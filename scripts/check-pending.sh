#!/usr/bin/env bash
# check-pending.sh
#
# 检测 atelier 仓库里待处理的 Claude 任务，输出结构化列表供 Claude 定时任务处理。
#
# Claude 定时任务调用此脚本时，按以下优先级处理输出：
#   1. needs-response  → atelier respond <N>（回复 Codex 问题）
#   2. claude:review   → atelier review <N>（评审 PR）
#   3. claude:design   → atelier design <N>（写规格，写完自动打 codex:go）
#
# 使用方式（用户手动查看）：
#   bash scripts/check-pending.sh
#
# 前置条件：已安装 gh CLI 并 gh auth login

set -euo pipefail

REPO="${ATELIER_REPO:-StevenG3/atelier}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Preflight 依赖检查 ────────────────────────────────────────────────────
# shellcheck source=preflight.sh
source "$SCRIPT_DIR/preflight.sh"
run_preflight

timestamp() { date -u '+%Y-%m-%d %H:%M UTC'; }

echo "======================================================"
echo "  atelier 待处理任务  $(timestamp)"
echo "======================================================"

# ── 1. needs-response（最高优先级）──────────────────────────────────────

RESP=$(gh issue list \
  --repo "$REPO" \
  --label "needs-response" \
  --json number,title,url \
  --template '{{range .}}{{.number}}|{{.title}}|{{.url}}{{"\n"}}{{end}}' 2>/dev/null || true)

if [[ -n "$RESP" ]]; then
  echo ""
  echo "PRIORITY=1 TYPE=respond"
  echo "--- Codex 等 Claude 回复 ---"
  while IFS='|' read -r num title url; do
    echo "ACTION=respond NUMBER=$num TITLE=$title URL=$url"
  done <<< "$RESP"
fi

# ── 2. claude:review（PR 评审）──────────────────────────────────────────

REVIEW=$(gh pr list \
  --repo "$REPO" \
  --label "claude:review" \
  --json number,title,url \
  --template '{{range .}}{{.number}}|{{.title}}|{{.url}}{{"\n"}}{{end}}' 2>/dev/null || true)

if [[ -n "$REVIEW" ]]; then
  echo ""
  echo "PRIORITY=2 TYPE=review"
  echo "--- PR 等 Claude 评审 ---"
  while IFS='|' read -r num title url; do
    echo "ACTION=review NUMBER=$num TITLE=$title URL=$url"
  done <<< "$REVIEW"
fi

# ── 3. claude:design（写规格）──────────────────────────────────────────

DESIGN=$(gh issue list \
  --repo "$REPO" \
  --label "claude:design" \
  --json number,title,url \
  --template '{{range .}}{{.number}}|{{.title}}|{{.url}}{{"\n"}}{{end}}' 2>/dev/null || true)

if [[ -n "$DESIGN" ]]; then
  echo ""
  echo "PRIORITY=3 TYPE=design"
  echo "--- Issue 等 Claude 写规格 ---"
  while IFS='|' read -r num title url; do
    echo "ACTION=design NUMBER=$num TITLE=$title URL=$url"
  done <<< "$DESIGN"
fi

# ── 4. needs-human（人类决策，Claude 无法处理）─────────────────────────

HUMAN=$(gh issue list \
  --repo "$REPO" \
  --label "needs-human" \
  --json number,title,url \
  --template '{{range .}}{{.number}}|{{.title}}|{{.url}}{{"\n"}}{{end}}' 2>/dev/null || true)

if [[ -n "$HUMAN" ]]; then
  echo ""
  echo "PRIORITY=0 TYPE=human"
  echo "--- 需要人类决策（Claude 跳过）---"
  while IFS='|' read -r num title url; do
    echo "ACTION=human NUMBER=$num TITLE=$title URL=$url"
  done <<< "$HUMAN"
fi

echo ""
echo "======================================================"

# ── 总结（Claude 定时任务读取此段） ────────────────────────────────────

HAS_RESP=$(  [[ -n "$RESP"   ]] && echo "yes" || echo "no")
HAS_REVIEW=$([ -n "$REVIEW" ] && echo "yes" || echo "no")
HAS_DESIGN=$([ -n "$DESIGN" ] && echo "yes" || echo "no")
HAS_HUMAN=$( [ -n "$HUMAN"  ] && echo "yes" || echo "no")

echo "SUMMARY has_response=$HAS_RESP has_review=$HAS_REVIEW has_design=$HAS_DESIGN has_human=$HAS_HUMAN"
echo "======================================================"
