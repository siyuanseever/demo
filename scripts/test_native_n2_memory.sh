#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
executable="$repo_root/ios/DerivedData-Native/Build/Products/Debug/SensenStoryNative.app/Contents/MacOS/SensenStoryNative"
sample_file="$(mktemp)"
log_file="$(mktemp)"
pid=""

cleanup() {
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$sample_file" "$log_file"
}
trap cleanup EXIT

[[ -x "$executable" ]] || {
  echo "Native app is not built. Run xcodebuild for SensenStoryNative first." >&2
  exit 1
}

"$executable" >"$log_file" 2>&1 &
pid=$!

for second in {1..20}; do
  kill -0 "$pid" 2>/dev/null || {
    echo "Native app exited during soak at second $second" >&2
    cat "$log_file" >&2
    exit 1
  }
  rss_kb="$(ps -o rss= -p "$pid" | tr -d ' ')"
  [[ -n "$rss_kb" ]] || { echo "Unable to sample RSS" >&2; exit 1; }
  echo "$rss_kb" >> "$sample_file"
  sleep 1
done

python3 - "$sample_file" <<'PY'
from pathlib import Path
import statistics
import sys

samples = [int(value) for value in Path(sys.argv[1]).read_text().splitlines()]
if len(samples) != 20:
    raise SystemExit(f"expected 20 RSS samples, got {len(samples)}")

peak_mb = max(samples) / 1024
early_mb = statistics.mean(samples[2:7]) / 1024
late_mb = statistics.mean(samples[-5:]) / 1024
growth_mb = late_mb - early_mb

print(f"Native N2 RSS peak={peak_mb:.1f}MB early={early_mb:.1f}MB late={late_mb:.1f}MB growth={growth_mb:.1f}MB")
if peak_mb > 500:
    raise SystemExit("peak RSS exceeded 500MB")
if growth_mb > 120:
    raise SystemExit("RSS growth exceeded 120MB during idle soak")
PY
