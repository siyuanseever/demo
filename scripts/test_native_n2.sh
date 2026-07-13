#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
binary="${TMPDIR:-/tmp}/sensen-native-n2-contract-tests"
module_cache="${TMPDIR:-/tmp}/sensen-native-n2-module-cache"
port_file="$(mktemp)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
  fi
  rm -f "$port_file" "$binary"
  rm -rf "$module_cache"
}
trap cleanup EXIT

xcrun swiftc \
  -parse-as-library \
  -module-cache-path "$module_cache" \
  "$repo_root/ios/XiaodongwuYetanhui/Models/CompanionModels.swift" \
  "$repo_root/ios/XiaodongwuYetanhui/Services/ChatService.swift" \
  "$repo_root/ios/XiaodongwuYetanhui/Services/SendInstrumentation.swift" \
  "$repo_root/ios/XiaodongwuYetanhui/Services/LocalDeepSeekService.swift" \
  "$repo_root/ios/XiaodongwuYetanhui/Services/SQLiteDatabase.swift" \
  "$repo_root/ios/SensenStoryMac/NativeConversationTurn.swift" \
  "$repo_root/ios/Tests/NativeN2ContractTests.swift" \
  -lsqlite3 \
  -o "$binary"

python3 "$repo_root/ios/Tests/native_n2_fixture_server.py" "$port_file" &
server_pid=$!

for _ in {1..50}; do
  [[ -s "$port_file" ]] && break
  sleep 0.05
done

[[ -s "$port_file" ]] || { echo "fixture server did not start" >&2; exit 1; }
NATIVE_N2_FIXTURE_URL="http://127.0.0.1:$(cat "$port_file")" "$binary"
