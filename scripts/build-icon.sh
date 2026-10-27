#!/bin/bash
# 把 1024×1024 的图标 PNG 转成 Resources/AppIcon.icns（各种尺寸都从它缩出来）
#   scripts/build-icon.sh <图标.png>
# 图标本身用 scripts/make-icon.swift 画。
set -euo pipefail
cd "$(dirname "$0")/.."
source="${1:?用法：scripts/build-icon.sh <1024×1024 的 PNG>}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
set="$work/AppIcon.iconset"
mkdir "$set"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source" --out "$set/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$source" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Resources/AppIcon.icns
echo Resources/AppIcon.icns
