#!/usr/bin/env bash
# sync-labels.sh — 同步 .github/labels.yml 到 GitHub 仓库
#
# 当 preflight 报告缺失标签时运行此脚本修复。
# 会创建缺失的标签，已存在的标签跳过（不更新颜色/描述）。
#
# 使用方式：
#   bash scripts/sync-labels.sh
#
# 前置条件：已安装 gh CLI 并 gh auth login

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="${ATELIER_REPO:-StevenG3/atelier}"
LABELS_FILE="$REPO_ROOT/.github/labels.yml"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BOLD='\033[1m'; RESET='\033[0m'

echo -e "${BOLD}── 同步标签到 $REPO ────────────────────────────${RESET}"

if [[ ! -f "$LABELS_FILE" ]]; then
  echo -e "${RED}✗ 找不到标签文件：$LABELS_FILE${RESET}"
  exit 1
fi

# 解析 .github/labels.yml（不依赖 yq，用 awk 手工解析）
# 格式：每个标签块以 "- name:" 开头，后跟 "  color:" 和 "  description:"
parse_labels() {
  awk '
    /^- name:/ {
      if (name != "") print name "|" color "|" desc
      name = $0; sub(/^- name: *"?/, "", name); sub(/"?$/, "", name)
      color = ""; desc = ""
    }
    /^  color:/ {
      color = $0; sub(/^  color: *"?/, "", color); sub(/"?$/, "", color)
    }
    /^  description:/ {
      desc = $0; sub(/^  description: *"?/, "", desc); sub(/"?$/, "", desc)
    }
    END { if (name != "") print name "|" color "|" desc }
  ' "$LABELS_FILE"
}

created=0; skipped=0; failed=0

while IFS='|' read -r name color description; do
  [[ -z "$name" ]] && continue
  # 先检查是否已存在
  if gh api "repos/$REPO/labels/$name" --silent 2>/dev/null; then
    echo -e "  ${YELLOW}↷${RESET} $name（已存在，跳过）"
    (( skipped++ )) || true
  else
    # 创建新标签（去掉颜色前缀 #）
    local_color="${color#\#}"
    if gh api "repos/$REPO/labels" \
         --method POST \
         --field name="$name" \
         --field color="$local_color" \
         --field description="$description" \
         --silent 2>/dev/null; then
      echo -e "  ${GREEN}✓${RESET} $name"
      (( created++ )) || true
    else
      echo -e "  ${RED}✗${RESET} $name（创建失败）"
      (( failed++ )) || true
    fi
  fi
done < <(parse_labels)

echo -e "${BOLD}────────────────────────────────────────────────────${RESET}"
echo -e "  新建 ${GREEN}${created}${RESET}  跳过 ${YELLOW}${skipped}${RESET}  失败 ${RED}${failed}${RESET}"
echo ""
echo -e "运行 ${BOLD}./scripts/atelier.sh status${RESET} 验证。"
