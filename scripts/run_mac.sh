#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
project="$repo_root/ios/XiaodongwuYetanhui.xcodeproj"
derived_data="$repo_root/ios/DerivedData-Mac"
app="$derived_data/Build/Products/Debug-maccatalyst/XiaodongwuYetanhui.app"
executable="$app/Contents/MacOS/XiaodongwuYetanhui"

xcodebuild \
  -quiet \
  -project "$project" \
  -scheme XiaodongwuYetanhui \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

SENSEN_REPO_ROOT="$repo_root" "$executable" &
