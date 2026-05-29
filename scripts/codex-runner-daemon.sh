#!/usr/bin/env bash
# codex-runner-daemon.sh — 周期运行 codex-runner.sh 的常驻守护
#
# 每 INTERVAL 秒扫描一次 atelier 的 codex:go Issue 并自动实现。
# codex-runner.sh 内部用 flock 防并发,跑完一个再睡,天然串行。
#
# 用法:
#   nohup bash scripts/codex-runner-daemon.sh > .codex-runner-logs/daemon.log 2>&1 &
#
# 停止:
#   pkill -f codex-runner-daemon.sh
#
# 或用 systemd(见 deploy/atelier-codex-runner.service.example)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL="${ATELIER_RUNNER_INTERVAL:-120}"

echo "[daemon] codex-runner 守护启动,每 ${INTERVAL}s 扫描一次。Ctrl+C / pkill 停止。"

while true; do
  bash "$SCRIPT_DIR/codex-runner.sh" || echo "[daemon] runner 本轮异常退出(已记录),继续。"
  sleep "$INTERVAL"
done
