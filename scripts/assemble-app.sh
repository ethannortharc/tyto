#!/bin/bash
# 把编译好的 Tyto 装成 .app 并签名（build-app.sh 和 release.sh 共用）：
#   scripts/assemble-app.sh <输出的 .app> <签名证书> [--release]
# --release：强化运行时 + 时间戳（公证要求）；不加就是日常开发用的签名。
# 里面带上 Sparkle.framework（自动更新）。Tyto 没开沙盒，用不到 Sparkle 的两个 XPC 服务，去掉；
# 剩下的从里往外逐个签（Sparkle 的说明里明确不要用 --deep）。
set -euo pipefail
cd "$(dirname "$0")/.."

app="$1"
identity="$2"
release="${3:-}"
bin="$(swift build -c release --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin/Tyto" "$app/Contents/MacOS/Tyto"
cp Resources/Tyto-Info.plist "$app/Contents/Info.plist"
cp -R Resources/*.lproj "$app/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$app/Contents/Resources/"
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
# 用到的开源库的许可证随 App 一起发
licenses="$app/Contents/Resources/Licenses"
mkdir -p "$licenses"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$licenses/Sparkle.txt"
cp .build/checkouts/swift-markdown/LICENSE.txt "$licenses/swift-markdown.txt"
cp .build/checkouts/swift-markdown/NOTICE.txt "$licenses/swift-markdown-NOTICE.txt"
cp .build/checkouts/swift-cmark/COPYING "$licenses/cmark-gfm.txt"
framework="$app/Contents/Frameworks/Sparkle.framework"
rm -rf "$framework/Versions/B/XPCServices" "$framework/XPCServices"

flags=(--force --sign "$identity")
[ "$release" = --release ] && flags+=(--options runtime --timestamp)
codesign "${flags[@]}" "$framework/Versions/B/Autoupdate"
codesign "${flags[@]}" "$framework/Versions/B/Updater.app"
codesign "${flags[@]}" "$framework"
codesign "${flags[@]}" --entitlements Resources/Tyto.entitlements "$app"
