#!/bin/bash
# 发布给别人用：编译 → Developer ID 签名（强化运行时）→ 苹果公证 → 钉上公证票据 → 打包 dist/Tyto-<版本>.zip
# 公证用钥匙串里的 notarytool 配置（一次性：xcrun notarytool store-credentials notarytool --apple-id … --team-id …）
# 换证书 / 配置：TYTO_RELEASE_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=… scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Tyto-Info.plist)
identity="${TYTO_RELEASE_IDENTITY:-Developer ID Application}"
profile="${NOTARY_PROFILE:-notarytool}"

swift build -c release --product Tyto
bin="$(swift build -c release --show-bin-path)/Tyto"

rm -rf dist
app="dist/Tyto.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/Tyto"
cp Resources/Tyto-Info.plist "$app/Contents/Info.plist"

echo "==> 签名：$identity"
codesign --force --options runtime --timestamp --entitlements Resources/Tyto.entitlements --sign "$identity" "$app"
codesign --verify --strict --verbose=2 "$app"

echo "==> 公证（几分钟）"
ditto -c -k --keepParent "$app" dist/notarize.zip
xcrun notarytool submit dist/notarize.zip --keychain-profile "$profile" --wait
rm dist/notarize.zip
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"

ditto -c -k --keepParent "$app" "dist/Tyto-$version.zip"
echo "dist/Tyto-$version.zip"
