#!/bin/zsh

set -euo pipefail

base_url="${TTS_BASE_URL:-http://127.0.0.1:8768}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/sensen-tts-cancel.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

python3 - "$work_dir/request.json" <<'PY'
import json
import sys
import time
from pathlib import Path

nonce = f"{time.time_ns()}"
text = (
    "这是一次语音取消测试。为了确保后台模型正在真实生成，这段文字会稍微长一些。"
    "当停止按钮被点击以后，当前推理应该尽快结束，而不是继续占用内存并阻塞下一条回复。"
    "取消完成后，语音服务仍然需要保持健康，下一次朗读可以正常开始。"
    f"测试标识是{nonce}。"
)
Path(sys.argv[1]).write_text(
    json.dumps(
        {
            "model": "qwen3-tts-0.6b-customvoice-4bit",
            "input": text,
            "voice": "Serena",
            "instruct": (
                "平静、克制、自然地说，像一位年轻女孩在安静地陪伴朋友。"
                "保持稳定音量和清晰发音，情绪起伏小。"
            ),
        },
        ensure_ascii=False,
    ),
    encoding="utf-8",
)
PY

set +e
curl --noproxy '*' -fsS --max-time 300 \
  -H 'Content-Type: application/json' \
  --data-binary "@$work_dir/request.json" \
  "$base_url/v1/audio/speech/stream" \
  -o "$work_dir/cancelled.wav" \
  2>"$work_dir/request.log" &
request_pid=$!
sleep 1
cancel_response="$(curl --noproxy '*' -fsS --max-time 5 -X POST "$base_url/v1/audio/speech/cancel")"
wait "$request_pid"
request_status=$?
set -e

[[ "$cancel_response" == *'"cancelled"'* ]] || {
  echo "TTS cancel endpoint returned an unexpected response: $cancel_response" >&2
  exit 1
}
[[ "$request_status" -ne 0 ]] || {
  echo "TTS streaming request completed instead of being cancelled" >&2
  exit 1
}

health_response="$(curl --noproxy '*' -fsS --max-time 5 "$base_url/health")"
[[ "$health_response" == *'"status": "ok"'* ]] || {
  echo "TTS service did not recover after cancellation: $health_response" >&2
  exit 1
}

echo "TTS in-flight cancellation smoke passed (curl_status=$request_status)"
