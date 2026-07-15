#!/bin/zsh

set -euo pipefail

base_url="${TTS_BASE_URL:-http://127.0.0.1:8768}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/sensen-tts-smoke.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

health_file="$work_dir/health.json"
short_file="$work_dir/short.wav"
long_file="$work_dir/long.wav"
long_cached_file="$work_dir/long-cached.wav"
instruction="平静、克制、自然地说，像一位年轻女孩在安静地陪伴朋友。保持稳定音量和清晰发音，情绪起伏小，不使用哭腔、气声、播音腔或撒娇语气。"

curl --noproxy '*' -fsS --max-time 5 "$base_url/health" -o "$health_file"

python3 - "$work_dir" "$instruction" <<'PY'
import json
import sys
from pathlib import Path

directory = Path(sys.argv[1])
instruction = sys.argv[2]
payloads = {
    "short.json": "晚上好呀，我是忧忧兔。你可以慢慢说，我会安静地听着。",
    "long.json": (
        "我听见你说，今天有很多事情挤在一起，让你既疲惫又有些不知所措。"
        "我们先不用急着把全部问题解决，可以先找出此刻最让身体紧绷的那一件事。"
        "等这一小块被看清以后，再决定下一步要不要继续。"
        "你已经在认真照顾自己了，现在可以慢一点。"
    ),
}
for filename, text in payloads.items():
    (directory / filename).write_text(
        json.dumps(
            {
                "model": "qwen3-tts-0.6b-customvoice-4bit",
                "input": text,
                "voice": "Serena",
                "instruct": instruction,
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
PY

curl --noproxy '*' -fsS --max-time 180 \
  -H 'Content-Type: application/json' \
  --data-binary "@$work_dir/short.json" \
  "$base_url/v1/audio/speech/stream" \
  -o "$short_file"

curl --noproxy '*' -fsS --max-time 300 \
  -H 'Content-Type: application/json' \
  --data-binary "@$work_dir/long.json" \
  "$base_url/v1/audio/speech" \
  -o "$long_file"

cached_seconds="$(curl --noproxy '*' -fsS --max-time 30 \
  -H 'Content-Type: application/json' \
  --data-binary "@$work_dir/long.json" \
  -w '%{time_total}' \
  "$base_url/v1/audio/speech" \
  -o "$long_cached_file")"

python3 - "$health_file" "$short_file" "$long_file" "$long_cached_file" "$cached_seconds" <<'PY'
import json
import struct
import sys
from pathlib import Path

health_path, short_path, long_path, cached_path = map(Path, sys.argv[1:5])
cached_seconds = float(sys.argv[5])
health = json.loads(health_path.read_text(encoding="utf-8"))
assert health.get("status") == "ok", health
assert health.get("voice") == "Serena", health
assert "4bit" in str(health.get("model", "")), health

def inspect(path: Path) -> tuple[int, float]:
    data = path.read_bytes()
    assert len(data) > 44, f"{path.name}: empty audio"
    assert data[:4] == b"RIFF" and data[8:12] == b"WAVE", f"{path.name}: invalid WAV"
    channels = struct.unpack_from("<H", data, 22)[0]
    sample_rate = struct.unpack_from("<I", data, 24)[0]
    bits_per_sample = struct.unpack_from("<H", data, 34)[0]
    assert channels == 1 and sample_rate == 24_000 and bits_per_sample == 16
    duration = (len(data) - 44) / (sample_rate * channels * bits_per_sample / 8)
    return len(data), duration

short_size, short_duration = inspect(short_path)
long_size, long_duration = inspect(long_path)
cached_size, cached_duration = inspect(cached_path)
assert 1.0 <= short_duration <= 30.0, short_duration
assert 8.0 <= long_duration <= 90.0, long_duration
assert long_size == cached_size, (long_size, cached_size)
assert abs(long_duration - cached_duration) < 0.01
assert cached_seconds < 2.0, cached_seconds
print(
    "TTS service smoke passed "
    f"short={short_duration:.1f}s long={long_duration:.1f}s cache={cached_seconds:.3f}s"
)
PY
