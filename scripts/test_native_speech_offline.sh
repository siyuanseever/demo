#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output="${TMPDIR:-/tmp}/native-speech-offline-smoke"
module_cache="${TMPDIR:-/tmp}/native-speech-module-cache"
test_home="${TMPDIR:-/tmp}/native-speech-home"

cd "$repo_root"

swiftc \
  -D DEBUG \
  -module-cache-path "$module_cache" \
  ios/XiaodongwuYetanhui/Services/SpeechService.swift \
  ios/Tests/NativeSpeechOfflineSmoke.swift \
  -o "$output"

mkdir -p "$test_home/Library/Caches"
CFFIXED_USER_HOME="$test_home" \
  SENSEN_TTS_BASE_URL="http://127.0.0.1:9" \
  "$output"
