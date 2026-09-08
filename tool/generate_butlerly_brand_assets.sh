#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_root="$repo_root/apps/butlerly"
source_svg="$app_root/assets/branding/app_icon_burgundy.svg"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

qlmanage -t -s 1024 -o "$tmp_dir" "$source_svg" >/dev/null 2>&1
rendered="$tmp_dir/app_icon_burgundy.svg.png"

resize() {
  local size="$1"
  local destination="$2"
  mkdir -p "$(dirname "$destination")"
  sips -z "$size" "$size" "$rendered" --out "$destination" >/dev/null
}

ios_dir="$app_root/ios/Runner/Assets.xcassets/AppIcon.appiconset"
resize 40 "$ios_dir/Icon-App-20x20@2x.png"
resize 60 "$ios_dir/Icon-App-20x20@3x.png"
resize 29 "$ios_dir/Icon-App-29x29@1x.png"
resize 58 "$ios_dir/Icon-App-29x29@2x.png"
resize 87 "$ios_dir/Icon-App-29x29@3x.png"
resize 80 "$ios_dir/Icon-App-40x40@2x.png"
resize 120 "$ios_dir/Icon-App-40x40@3x.png"
resize 120 "$ios_dir/Icon-App-60x60@2x.png"
resize 180 "$ios_dir/Icon-App-60x60@3x.png"
resize 20 "$ios_dir/Icon-App-20x20@1x.png"
resize 40 "$ios_dir/Icon-App-20x20@2x.png"
resize 29 "$ios_dir/Icon-App-29x29@1x.png"
resize 58 "$ios_dir/Icon-App-29x29@2x.png"
resize 40 "$ios_dir/Icon-App-40x40@1x.png"
resize 80 "$ios_dir/Icon-App-40x40@2x.png"
resize 76 "$ios_dir/Icon-App-76x76@1x.png"
resize 152 "$ios_dir/Icon-App-76x76@2x.png"
resize 167 "$ios_dir/Icon-App-83.5x83.5@2x.png"
resize 1024 "$ios_dir/Icon-App-1024x1024@1x.png"

android_dir="$app_root/android/app/src/main/res"
resize 48 "$android_dir/mipmap-mdpi/ic_launcher.png"
resize 72 "$android_dir/mipmap-hdpi/ic_launcher.png"
resize 96 "$android_dir/mipmap-xhdpi/ic_launcher.png"
resize 144 "$android_dir/mipmap-xxhdpi/ic_launcher.png"
resize 192 "$android_dir/mipmap-xxxhdpi/ic_launcher.png"
