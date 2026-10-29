#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
raw=.demo-studio/capture/readme-2026-10
take=${1:?Pass the capture take directory, e.g. .demo-studio/capture/readme-2026-10/native-take2}
meeting_take=${2:-$take}
out=docs/media/readme-2026-10
mkdir -p "$out"
magick "$meeting_take/meeting.png" -strip -define png:compression-level=9 "$out/meeting.png"
magick "$take/screenshot-replies.png" -strip -define png:compression-level=9 "$out/screenshot-replies.png"
magick "$raw/prompter/prompter-dark-obsidian.png" -strip -define png:compression-level=9 "$out/prompter.png"
magick identify "$out"/*.png
