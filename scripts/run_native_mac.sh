#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
project="$repo_root/ios/XiaodongwuYetanhui.xcodeproj"
derived_data="$repo_root/ios/DerivedData-Native"
app="$derived_data/Build/Products/Debug/SensenStoryNative.app"
executable="$app/Contents/MacOS/SensenStoryNative"
tts_log="$repo_root/logs/tts.log"

mkdir -p "$repo_root/logs"

if ! curl --noproxy '*' --silent --fail --max-time 1 http://127.0.0.1:8768/health >/dev/null 2>&1; then
  "$repo_root/scripts/run_tts.sh" >>"$tts_log" 2>&1 &
  echo "本地 Qwen3-TTS 正在启动，首次朗读可能需要等待模型加载。"
  echo "语音日志：$tts_log"
fi

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
