#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
executable="$repo_root/ios/DerivedData-Mac/Build/Products/Debug-maccatalyst/XiaodongwuYetanhui.app/Contents/MacOS/XiaodongwuYetanhui"
duration="${N2_SOAK_SECONDS:-30}"
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
  echo "Catalyst app is not built. Run scripts/run_mac.sh first." >&2
  exit 1
}

"$executable" >"$log_file" 2>&1 &
pid=$!

for ((second = 1; second <= duration; second += 1)); do
  kill -0 "$pid" 2>/dev/null || {
    echo "Catalyst app exited during soak at second $second" >&2
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
if len(samples) < 20:
    raise SystemExit(f"expected at least 20 RSS samples, got {len(samples)}")

window = min(5, max(2, len(samples) // 4))
peak_mb = max(samples) / 1024
early_mb = statistics.mean(samples[2 : 2 + window]) / 1024
late_mb = statistics.mean(samples[-window:]) / 1024
growth_mb = late_mb - early_mb

print(
    f"Catalyst N2 RSS samples={len(samples)} peak={peak_mb:.1f}MB "
    f"early={early_mb:.1f}MB late={late_mb:.1f}MB growth={growth_mb:.1f}MB"
)
if peak_mb > 700:
    raise SystemExit("peak RSS exceeded 700MB")
if growth_mb > 150:
    raise SystemExit("RSS growth exceeded 150MB during idle soak")
PY
