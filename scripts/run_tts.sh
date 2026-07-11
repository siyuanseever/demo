#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
python="$repo_root/.venv-tts/bin/python"

if [[ ! -x "$python" ]]; then
  echo "还没有安装本地语音环境，请先运行："
  echo "  uv venv .venv-tts --python 3.12"
  echo "  uv pip install --python .venv-tts/bin/python mlx-audio socksio"
  exit 1
fi

cd "$repo_root"
exec "$python" -m app.tts_server
