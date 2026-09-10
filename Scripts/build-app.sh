#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
output_dir="$project_dir/build"
app_path="$output_dir/Cinema Player.app"

cd "$project_dir"
swift build -c release

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$project_dir/.build/release/CinemaPlayer" "$app_path/Contents/MacOS/CinemaPlayer"
cp "$project_dir/AppBundle/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_dir/AppBundle/CinemaPlayer.icns" "$app_path/Contents/Resources/CinemaPlayer.icns"
codesign --force --sign - "$app_path"

echo "Built: $app_path"
