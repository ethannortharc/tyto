#!/bin/bash
# 真的走一遍自动更新：旧版（0.0.1）从本机的 appcast 找到新版（9.9.9），下载、验 EdDSA 签名和开发者签名、替换自己。
# 两份都改成单独的 bundle id（com.giomni.tyto.updatetest），不碰真实设置；测完全部删掉。
#   scripts/test-update.sh
# 要钥匙串里有 Developer ID 证书，和 Sparkle 私钥文件（见 release.sh）。
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${TYTO_RELEASE_IDENTITY:-Developer ID Application}"
key="${SPARKLE_KEY_FILE:-$HOME/.config/tyto-release/sparkle-ed25519-private.key}"
sparkle_bin=".build/artifacts/sparkle/Sparkle/bin"
test_id="com.giomni.tyto.updatetest"
work="$(mktemp -d)"
cleanup() {
  [ -n "${server:-}" ] && kill "$server" 2>/dev/null || true
  rm -rf "$work" "$HOME/Library/Caches/$test_id" "$HOME/Library/HTTPStorages/$test_id" "$HOME/Library/HTTPStorages/$test_id.binarycookies"
  defaults delete "$test_id" >/dev/null 2>&1 || true
}
trap cleanup EXIT

swift build -c release --product Tyto >/dev/null
# <目录> <版本> <build 号>
make_app() {
  scripts/assemble-app.sh "$1/Tyto.app" "$identity" --release >/dev/null 2>&1
  /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $test_id" -c "Set CFBundleShortVersionString $2" \
    -c "Set CFBundleVersion $3" -c "Add NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" \
    "$1/Tyto.app/Contents/Info.plist"
  codesign --force --sign "$identity" --options runtime --entitlements Resources/Tyto.entitlements "$1/Tyto.app" 2>/dev/null
}
mkdir -p "$work/old" "$work/new" "$work/feed"
make_app "$work/old" 0.0.1 1
make_app "$work/new" 9.9.9 999
ditto -c -k --keepParent "$work/new/Tyto.app" "$work/feed/Tyto-new.zip"

port=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
signature=$("$sparkle_bin/sign_update" --ed-key-file "$key" "$work/feed/Tyto-new.zip")
cat > "$work/feed/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>Tyto update test</title>
<item>
<title>9.9.9</title>
<sparkle:version>999</sparkle:version>
<sparkle:shortVersionString>9.9.9</sparkle:shortVersionString>
<pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
<enclosure url="http://127.0.0.1:$port/Tyto-new.zip" type="application/octet-stream" $signature/>
</item>
</channel></rss>
XML
python3 -I -m http.server "$port" --bind 127.0.0.1 --directory "$work/feed" >/dev/null 2>&1 &
server=$!
sleep 1

echo "==> 旧版 0.0.1 检查更新"
"$work/old/Tyto.app/Contents/MacOS/Tyto" --selftest-update "http://127.0.0.1:$port/appcast.xml" 2>/dev/null | grep '^update:' || true
for _ in $(seq 1 60); do
  version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$work/old/Tyto.app/Contents/Info.plist" 2>/dev/null || true)
  [ "$version" = 9.9.9 ] && break
  sleep 1
done
echo "==> 替换后的版本：${version:-?}"
[ "$version" = 9.9.9 ] || { echo "❌ 没有换成新版"; exit 1; }
codesign --verify --strict "$work/old/Tyto.app" && echo "==> 签名完好"

echo "==> 被篡改的更新包不能装"
make_app "$work/old" 0.0.1 1
echo tampered >> "$work/feed/Tyto-new.zip"
"$work/old/Tyto.app/Contents/MacOS/Tyto" --selftest-update "http://127.0.0.1:$port/appcast.xml" 2>/dev/null | grep '^update:' || true
sleep 3
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$work/old/Tyto.app/Contents/Info.plist")
[ "$version" = 0.0.1 ] || { echo "❌ 篡改过的包也装上了"; exit 1; }
echo "✅ 自动更新：能装新版，拒绝篡改的包"
