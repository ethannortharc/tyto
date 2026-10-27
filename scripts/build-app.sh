#!/bin/bash
# 编译并打包成 .app：
#   scripts/build-app.sh             → build/Tyto.app
#   scripts/build-app.sh ShareCheck  → build/TytoShareCheck.app（共享屏幕验证程序）
# 系统权限（屏幕录制、系统录音、麦克风）是按 app 的签名记的：用固定的证书签名，重新编译后权限不会丢。
# 换证书：TYTO_SIGN_IDENTITY="Developer ID Application" scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

product="${1:-Tyto}"
case "$product" in
  Tyto) app="build/Tyto.app" ;;
  ShareCheck) app="build/TytoShareCheck.app" ;;
  *) echo "不认识的产品：$product（Tyto 或 ShareCheck）" >&2; exit 1 ;;
esac

swift build -c release --product "$product"
bin="$(swift build -c release --show-bin-path)/$product"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/$product"
cp "Resources/$product-Info.plist" "$app/Contents/Info.plist"

identity="${TYTO_SIGN_IDENTITY:-Apple Development}"
if ! codesign --force --sign "$identity" "$app" 2>/dev/null; then
  echo "找不到证书「$identity」，改用临时签名（每次重新编译都要重新授权）" >&2
  codesign --force --sign - "$app"
fi
echo "$app"
