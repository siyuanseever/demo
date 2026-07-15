#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
binary="${TMPDIR:-/tmp}/sensen-native-deepseek-smoke"
module_cache="${TMPDIR:-/tmp}/sensen-native-deepseek-smoke-module-cache"

cleanup() {
  rm -f "$binary"
  rm -rf "$module_cache"
}
trap cleanup EXIT

if [[ -z "${DEEPSEEK_API_KEY:-}" && -f "$repo_root/.env" ]]; then
  key_line="$(grep -E '^DEEPSEEK_API_KEY=' "$repo_root/.env" | tail -n 1 || true)"
  if [[ -n "$key_line" ]]; then
    export DEEPSEEK_API_KEY="${key_line#DEEPSEEK_API_KEY=}"
    DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY#\"}"
    DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY%\"}"
    DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY#\'}"
    DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY%\'}"
    export DEEPSEEK_API_KEY
  fi
fi

[[ -n "${DEEPSEEK_API_KEY:-}" ]] || {
  echo "DEEPSEEK_API_KEY is missing from the environment and .env" >&2
  exit 1
}

xcrun swiftc \
  -parse-as-library \
  -module-cache-path "$module_cache" \
  "$repo_root/ios/XiaodongwuYetanhui/Models/CompanionModels.swift" \
  "$repo_root/ios/XiaodongwuYetanhui/Services/ChatService.swift" \
  "$repo_root/ios/XiaodongwuYetanhui/Services/SendInstrumentation.swift" \
  "$repo_root/ios/XiaodongwuYetanhui/Services/LocalDeepSeekService.swift" \
  "$repo_root/ios/XiaodongwuYetanhui/Services/SQLiteDatabase.swift" \
  "$repo_root/ios/Tests/NativeDeepSeekSmoke.swift" \
  -lsqlite3 \
  -o "$binary"

"$binary"
