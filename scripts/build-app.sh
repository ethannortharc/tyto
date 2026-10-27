#!/bin/bash
# 编译验证程序并打包成 build/TytoShareCheck.app。
# 屏幕录制权限是按 app 的签名记的：用固定的证书签名，重新编译后权限不会丢。
# 换证书：TYTO_SIGN_IDENTITY="Developer ID Application" scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ShareCheck
bin="$(swift build -c release --show-bin-path)/ShareCheck"

app="build/TytoShareCheck.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/ShareCheck"
cp Resources/ShareCheck-Info.plist "$app/Contents/Info.plist"

identity="${TYTO_SIGN_IDENTITY:-Apple Development}"
if ! codesign --force --sign "$identity" "$app" 2>/dev/null; then
  echo "找不到证书「$identity」，改用临时签名（每次重新编译都要重新授权屏幕录制）" >&2
  codesign --force --sign - "$app"
fi
echo "$app"
