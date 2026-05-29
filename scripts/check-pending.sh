#!/usr/bin/env bash
# check-pending.sh
#
# 检测 atelier 仓库里待处理的 Claude 任务。
# Claude Code 定时任务调用此脚本，按输出列表逐项处理。
#
# 使用方式：
#   bash scripts/check-pending.sh
#
# 前置条件：已安装 gh CLI 并 gh auth login

set -euo pipefail

REPO="${ATELIER_REPO:-StevenG3/atelier}"

echo "======================================================"
echo "atelier 待处理任务检查  $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "======================================================"

echo ""
echo "--- needs-response（Codex 等待 Claude 回复）---"
gh issue list \
  --repo "$REPO" \
  --label "needs-response" \
  --json number,title,url,updatedAt \
  --template '{{range .}}#{{.number}}  {{.title}}  {{.url}}{{"\n"}}{{end}}'

echo ""
echo "--- claude:design（等待 Claude 写规格）---"
gh issue list \
  --repo "$REPO" \
  --label "claude:design" \
  --json number,title,url,updatedAt \
  --template '{{range .}}#{{.number}}  {{.title}}  {{.url}}{{"\n"}}{{end}}'

echo ""
echo "--- claude:review（等待 Claude 评审 PR）---"
gh pr list \
  --repo "$REPO" \
  --label "claude:review" \
  --json number,title,url,updatedAt \
  --template '{{range .}}#{{.number}}  {{.title}}  {{.url}}{{"\n"}}{{end}}'

echo ""
echo "======================================================"
echo "将上述列表粘贴给 Claude Code，并使用对应的 prompts/*.md.example 模板处理。"
echo "======================================================"
