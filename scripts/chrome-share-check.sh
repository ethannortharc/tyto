#!/bin/bash
# 用 Chrome 的屏幕共享接口（getDisplayMedia）共享整个屏幕，看悬浮窗在不在画面里。
# Google Meet 网页版，以及 Zoom、Teams 的网页版，共享屏幕走的都是这条路。
#
# 用法：scripts/chrome-share-check.sh [--no-protect]
#   --no-protect  关掉共享保护再测，用来确认这个测试认得出"被截到"
#
# 会临时开一个独立的 Chrome（单独的用户目录，不碰你平时的 Chrome），跑完自动关掉。
# 需要从已经有屏幕录制权限的终端里运行。
set -euo pipefail
cd "$(dirname "$0")/.."

chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
app="build/TytoShareCheck.app/Contents/MacOS/ShareCheck"
data="$HOME/Library/Application Support/Tyto/share-check"
[ -x "$app" ] || scripts/build-app.sh >/dev/null

work="$(mktemp -d)"
cleanup() {
  [ -n "${chrome_pid:-}" ] && kill "$chrome_pid" 2>/dev/null || true
  [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null || true
  pkill -f "$app" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

# 1. 在主屏上开验证程序（Chrome 自动选的是主屏）
pkill -f "$app" 2>/dev/null || true
rm -f "$data/windows.json"
"$app" --screen 1 "$@" >/dev/null 2>&1 &
disown
for _ in $(seq 1 20); do [ -f "$data/windows.json" ] && break; sleep 0.5; done
[ -f "$data/windows.json" ] || { echo "验证程序没有写出 windows.json" >&2; exit 1; }
sleep 1

# 2. 本地服务：提供测试网页，接收结果
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
cp scripts/chrome-share-check.html "$work/index.html"
python3 -I - "$work" "$port" <<'EOF' &
import http.server, json, sys, threading
work, port = sys.argv[1], int(sys.argv[2])
class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=work, **k)
    def log_message(self, *a): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        open(f"{work}/result.json", "wb").write(body)
        self.send_response(200); self.end_headers()
        threading.Thread(target=self.server.shutdown).start()
http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
EOF
server_pid=$!
disown

query=$(python3 -I -c '
import json, sys, urllib.parse
f = json.load(open(sys.argv[1]))
print(urllib.parse.urlencode({"screenWidth": f["screenWidth"],
    "overlay": ",".join(map(str, f["overlay"])), "control": ",".join(map(str, f["control"]))}))
' "$data/windows.json")

# 3. 独立的 Chrome，自动同意共享整个屏幕；窗口放到右下角，不挡测试窗口
screen_w=$(python3 -I -c 'import json,sys; print(int(json.load(open(sys.argv[1]))["screenWidth"]))' "$data/windows.json")
screen_h=$(python3 -I -c 'import json,sys; print(int(json.load(open(sys.argv[1]))["screenHeight"]))' "$data/windows.json")
"$chrome" --user-data-dir="$work/profile" --no-first-run --no-default-browser-check \
  --use-fake-ui-for-media-stream \
  --window-position=$((screen_w - 520)),$((screen_h - 360)) --window-size=500,300 \
  "http://127.0.0.1:$port/index.html?$query" >/dev/null 2>&1 &
chrome_pid=$!
disown

for _ in $(seq 1 60); do [ -f "$work/result.json" ] && break; sleep 0.5; done
[ -f "$work/result.json" ] || { echo "30 秒内没收到 Chrome 的结果" >&2; exit 1; }

# 4. 结果
mkdir -p "$data"
python3 -I - "$work/result.json" "$data" "$data/windows.json" <<'EOF'
import base64, json, sys, time
report = json.load(open(sys.argv[1]))
frames = json.load(open(sys.argv[3]))
stamp = time.strftime("%Y%m%d-%H%M%S")
if "png" in report:
    path = f"{sys.argv[2]}/chrome-{stamp}.png"
    open(path, "wb").write(base64.b64decode(report.pop("png").split(",", 1)[1]))
    report["imagePath"] = path
report["overlayProtected"] = frames["overlayProtected"]
json.dump(report, open(f"{sys.argv[2]}/chrome-{stamp}.json", "w"), ensure_ascii=False, indent=2)
print("Chrome:", report["userAgent"].split("Chrome/")[-1].split(" ")[0])
print("共享保护:", "开" if frames["overlayProtected"] else "关")
if "error" in report:
    print("出错:", report["error"])
    if "NotReadableError" in report["error"]:
        print("多半是 Chrome 没有屏幕录制权限：系统设置 → 隐私与安全性 → 录屏与系统录音 → 打开 Google Chrome")
    sys.exit(1)
print("共享的屏幕:", report.get("trackLabel"), "画面", report["frameSize"])
need = report["expectedMarkerPixels"] / 4
control, overlay = report["controlHits"] >= need, report["overlayHits"] >= need
print(f"品红像素：对照窗口 {report['controlHits']}，悬浮窗 {report['overlayHits']}（标记应有 {report['expectedMarkerPixels']}）")
if not control:
    print("无效：画面里没有对照窗口（共享的可能不是这块屏幕）")
else:
    print("❌ 悬浮窗被截到了" if overlay else "✅ 悬浮窗被隐藏")
print("截图:", report.get("imagePath"))
EOF
