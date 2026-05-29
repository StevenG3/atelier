#!/usr/bin/env bash
# orchestrator-daemon.sh — 自主开发循环常驻守护(你只启动这一个)
#
# 每 INTERVAL 秒跑一次 orchestrator.sh(一个 tick 推进一步)。
# orchestrator 内部 flock 防并发,跑完一步再睡,天然串行。
#
# 启动:
#   cd /home/gggqqy/archives/atelier
#   nohup bash scripts/orchestrator-daemon.sh > .orchestrator-state/daemon.log 2>&1 &
#
# 停止(临时):pkill -f orchestrator-daemon.sh
# 暂停循环(保留进程):touch .atelier-stop      # 删除即恢复
# 熔断恢复:rm .orchestrator-state/consecutive_failures
#
# 默认每小时一 tick;要更快设 ATELIER_TICK=300(秒)。

set -uo pipefail

PROJECT="${1:-hermes-aegis}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL="${ATELIER_TICK:-3600}"

echo "[daemon] 自主开发循环启动:project=$PROJECT 每 ${INTERVAL}s 一 tick。"
echo "[daemon] 暂停:touch atelier 根目录下 .atelier-stop;停止:pkill -f orchestrator-daemon.sh"

while true; do
  bash "$SCRIPT_DIR/orchestrator.sh" "$PROJECT" || echo "[daemon] 本 tick 异常(已记录),继续。"
  sleep "$INTERVAL"
done
