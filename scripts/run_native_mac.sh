#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
project="$repo_root/ios/XiaodongwuYetanhui.xcodeproj"
derived_data="$repo_root/ios/DerivedData-Native"
app="$derived_data/Build/Products/Debug/SensenStoryNative.app"
executable="$app/Contents/MacOS/SensenStoryNative"

xcodebuild \
  -quiet \
  -project "$project" \
  -scheme SensenStoryNative \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

"$executable" &
