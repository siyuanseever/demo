#!/bin/zsh

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
python="$repo_root/.venv-tts/bin/python"

if [[ ! -x "$python" ]]; then
  echo "还没有安装本地语音环境，请先运行："
  echo "  uv venv .venv-tts --python 3.12"
  echo "  uv pip install --python .venv-tts/bin/python mlx-audio socksio"
  exit 1
fi

cd "$repo_root"

# 自动重启循环：TTS 服务在检测到 MLX Metal 状态损坏后会主动退出，
# 这里自动重启它。每次重启间隔 2 秒，让系统回收资源。
restart_count=0

cleanup() {
  echo "[run_tts] received interrupt signal, stopping"
  stop_requested=1
}
trap cleanup INT TERM

stop_requested=0

while true; do
  restart_count=$((restart_count + 1))
  echo "[run_tts] starting TTS server (attempt $restart_count)..."

  # 在后台启动，前台等待，这样 trap 可以正确捕获信号
  "$python" -m app.tts_server &
  server_pid=$!

  # 等待进程结束
  wait $server_pid
  exit_code=$?
  echo "[run_tts] TTS server exited with code $exit_code"

  # 如果是用户主动终止，不重启
  if [[ $stop_requested -eq 1 ]]; then
    echo "[run_tts] stop requested, not restarting"
    break
  fi

  # 如果退出码是 0 且不是自动重启信号，也不重启（正常退出）
  if [[ $exit_code -eq 0 ]]; then
    echo "[run_tts] server exited normally, not restarting"
    break
  fi

  echo "[run_tts] restarting in 2 seconds..."
  sleep 2
done

