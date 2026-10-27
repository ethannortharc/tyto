#!/bin/bash
# 发布给别人用：编译 → Developer ID 签名（强化运行时）→ 苹果公证 → 钉上公证票据，产出
#   dist/Tyto-<版本>.dmg   安装包：打开后把 Tyto 拖进「应用程序」（也公证、钉票据）
#   dist/Tyto-<版本>.zip   自动更新用的包（Sparkle 下载这个）
#   dist/appcast.xml       自动更新的清单：上传到 GitHub Release，App 从 releases/latest/download/appcast.xml 读
#   scripts/release.sh [更新说明.md]
# 更新说明（英文，Markdown）会转成 HTML 写进 appcast，"检查更新"弹窗里显示。
# 公证用钥匙串里的 notarytool 配置（一次性：xcrun notarytool store-credentials notarytool --apple-id … --team-id …）
# 更新包用 Sparkle 的 EdDSA 私钥签名，默认读 ~/.config/tyto-release/sparkle-ed25519-private.key
# （公钥在 Info.plist 的 SUPublicEDKey；私钥丢了，已经装了的 Tyto 就收不到更新，要备份好）。
# 换证书 / 配置：TYTO_RELEASE_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=… SPARKLE_KEY_FILE=… scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

notes="${1:-}"
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Tyto-Info.plist)
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Tyto-Info.plist)
identity="${TYTO_RELEASE_IDENTITY:-Developer ID Application}"
profile="${NOTARY_PROFILE:-notarytool}"
key="${SPARKLE_KEY_FILE:-$HOME/.config/tyto-release/sparkle-ed25519-private.key}"
sparkle_bin=".build/artifacts/sparkle/Sparkle/bin"
repo="https://github.com/ethannortharc/tyto"
[ -f "$key" ] || { echo "找不到 Sparkle 私钥：$key" >&2; exit 1; }
[ -z "$notes" ] || [ -f "$notes" ] || { echo "找不到更新说明：$notes" >&2; exit 1; }

swift build -c release --product Tyto
rm -rf dist
mkdir -p dist
app="dist/Tyto.app"

echo "==> 签名：$identity"
scripts/assemble-app.sh "$app" "$identity" --release
codesign --verify --deep --strict --verbose=2 "$app"

echo "==> 公证 App（几分钟）"
ditto -c -k --keepParent "$app" dist/notarize.zip
xcrun notarytool submit dist/notarize.zip --keychain-profile "$profile" --wait
rm dist/notarize.zip
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"

zip="dist/Tyto-$version.zip"
ditto -c -k --keepParent "$app" "$zip"

echo "==> 安装包（DMG）"
dmg="dist/Tyto-$version.dmg"
stage="dist/dmg"
mkdir -p "$stage"
ditto "$app" "$stage/Tyto.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Tyto $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
rm -rf "$stage"
codesign --force --timestamp --sign "$identity" "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"

echo "==> 自动更新清单（appcast.xml）"
signature=$("$sparkle_bin/sign_update" --ed-key-file "$key" "$zip")
description=""
if [ -n "$notes" ]; then
  html=$("$app/Contents/MacOS/Tyto" --markdown-to-html "$notes")
  description="<description><![CDATA[$html]]></description>"
fi
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Tyto</title>
    <link>$repo</link>
    <item>
      <title>Tyto $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <link>$repo/releases/tag/v$version</link>
      $description
      <enclosure url="$repo/releases/download/v$version/Tyto-$version.zip" type="application/octet-stream" $signature/>
    </item>
  </channel>
</rss>
XML
xmllint --noout dist/appcast.xml

echo
shasum -a 256 "$dmg" "$zip"
echo "上传：gh release create v$version $dmg $zip dist/appcast.xml --notes-file <说明>"
