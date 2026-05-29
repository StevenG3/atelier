#!/usr/bin/env bash
# atelier.sh — 用户侧操作 CLI
#
# 用法：
#   ./scripts/atelier.sh status              # 查看所有待处理项
#   ./scripts/atelier.sh next                # 最高优先级项 → 输出填好的 Claude prompt
#   ./scripts/atelier.sh prompt respond <N>  # Issue #N 的 Claude 回复 prompt
#   ./scripts/atelier.sh prompt review  <N>  # PR #N 的 Claude 评审 prompt
#   ./scripts/atelier.sh prompt design  <N>  # Issue #N 的 Claude 写规格 prompt
#   ./scripts/atelier.sh go   <N>            # 给 Issue #N 加 codex:go（启动 Codex）
#   ./scripts/atelier.sh done <N>            # 给 Issue #N 移除 codex:go（停止 Codex）

set -euo pipefail

REPO="${ATELIER_REPO:-StevenG3/atelier}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPTS_DIR="$REPO_ROOT/prompts"

# ── ANSI 颜色 ──────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── 工具函数 ────────────────────────────────────────────────────────────────

_copy_to_clipboard() {
    local text="$1"
    if command -v pbcopy &>/dev/null; then
        printf '%s' "$text" | pbcopy && echo -e "${GREEN}✓ 已复制到剪贴板${RESET}"
    elif command -v xclip &>/dev/null; then
        printf '%s' "$text" | xclip -selection clipboard && echo -e "${GREEN}✓ 已复制到剪贴板${RESET}"
    elif command -v xsel &>/dev/null; then
        printf '%s' "$text" | xsel --clipboard --input && echo -e "${GREEN}✓ 已复制到剪贴板${RESET}"
    else
        echo -e "${YELLOW}提示：未检测到剪贴板工具（pbcopy/xclip/xsel），请手动复制上方内容。${RESET}"
    fi
}

_get_project_from_issue() {
    local issue_number="$1"
    gh issue view "$issue_number" --repo "$REPO" --json body -q '.body' 2>/dev/null \
        | grep -i '^project:' | head -1 | sed 's/^project:[[:space:]]*//' || true
}

_fill_prompt() {
    local template_file="$1"
    local number="$2"
    local is_pr="${3:-false}"

    if [[ ! -f "$template_file" ]]; then
        echo -e "${RED}错误：找不到模板文件 $template_file${RESET}" >&2
        exit 1
    fi

    local project=""
    if [[ "$is_pr" == "true" ]]; then
        # 从 PR 关联的 Issue 里提取 project
        local closes
        closes=$(gh pr view "$number" --repo "$REPO" --json body -q '.body' 2>/dev/null \
            | grep -oE '#[0-9]+' | head -1 | tr -d '#' || true)
        [[ -n "$closes" ]] && project=$(_get_project_from_issue "$closes")
    else
        project=$(_get_project_from_issue "$number")
    fi

    local filled
    filled=$(sed \
        -e "s|{{ISSUE_NUMBER}}|$number|g" \
        -e "s|{{PR_NUMBER}}|$number|g" \
        -e "s|{{REPO}}|$REPO|g" \
        -e "s|{{PROJECT_NAME}}|${project:-<填写工程名>}|g" \
        -e "s|{{SHORT_DESC}}|<填写简短描述>|g" \
        "$template_file")

    printf '%s\n' "$filled"
}

# ── status 命令 ─────────────────────────────────────────────────────────────

cmd_status() {
    echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  atelier  $(date -u '+%Y-%m-%d %H:%M UTC')${RESET}"
    echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"

    local found=0

    # needs-response（最高优先级）
    local resp_issues
    resp_issues=$(gh issue list --repo "$REPO" --label "needs-response" \
        --json number,title --template '{{range .}}{{.number}}|{{.title}}{{"\n"}}{{end}}' 2>/dev/null || true)
    if [[ -n "$resp_issues" ]]; then
        found=1
        echo -e "\n${RED}🔴 needs-response（Codex 等 Claude 回复）${RESET}"
        while IFS='|' read -r num title; do
            printf "   %-5s  %s\n" "#$num" "$title"
            printf "        ${CYAN}→ ./scripts/atelier.sh prompt respond %s${RESET}\n" "$num"
        done <<< "$resp_issues"
    fi

    # claude:review
    local review_prs
    review_prs=$(gh pr list --repo "$REPO" --label "claude:review" \
        --json number,title --template '{{range .}}{{.number}}|{{.title}}{{"\n"}}{{end}}' 2>/dev/null || true)
    if [[ -n "$review_prs" ]]; then
        found=1
        echo -e "\n${YELLOW}🟡 claude:review（PR 等 Claude 评审）${RESET}"
        while IFS='|' read -r num title; do
            printf "   %-5s  %s\n" "PR#$num" "$title"
            printf "        ${CYAN}→ ./scripts/atelier.sh prompt review %s${RESET}\n" "$num"
        done <<< "$review_prs"
    fi

    # claude:design
    local design_issues
    design_issues=$(gh issue list --repo "$REPO" --label "claude:design" \
        --json number,title --template '{{range .}}{{.number}}|{{.title}}{{"\n"}}{{end}}' 2>/dev/null || true)
    if [[ -n "$design_issues" ]]; then
        found=1
        echo -e "\n${GREEN}🟢 claude:design（Issue 等 Claude 写规格）${RESET}"
        while IFS='|' read -r num title; do
            printf "   %-5s  %s\n" "#$num" "$title"
            printf "        ${CYAN}→ ./scripts/atelier.sh prompt design %s${RESET}\n" "$num"
        done <<< "$design_issues"
    fi

    # needs-human
    local human_issues
    human_issues=$(gh issue list --repo "$REPO" --label "needs-human" \
        --json number,title --template '{{range .}}{{.number}}|{{.title}}{{"\n"}}{{end}}' 2>/dev/null || true)
    if [[ -n "$human_issues" ]]; then
        found=1
        echo -e "\n${RED}🚨 needs-human（需要你介入决策）${RESET}"
        while IFS='|' read -r num title; do
            printf "   %-5s  %s\n" "#$num" "$title"
            printf "        ${CYAN}→ gh issue view %s --repo %s --comments${RESET}\n" "$num" "$REPO"
        done <<< "$human_issues"
    fi

    if [[ "$found" -eq 0 ]]; then
        echo -e "\n${GREEN}✓ 无待处理项。${RESET}"
    fi

    echo -e "\n${BOLD}══════════════════════════════════════════════════════${RESET}"
}

# ── next 命令 ───────────────────────────────────────────────────────────────

cmd_next() {
    # 优先级：needs-response > claude:review > claude:design
    local issue_num pr_num

    issue_num=$(gh issue list --repo "$REPO" --label "needs-response" \
        --json number --jq '.[0].number' 2>/dev/null || true)
    if [[ -n "$issue_num" && "$issue_num" != "null" ]]; then
        echo -e "${BOLD}最高优先级：Issue #${issue_num}（needs-response）${RESET}\n"
        cmd_prompt "respond" "$issue_num"
        return
    fi

    pr_num=$(gh pr list --repo "$REPO" --label "claude:review" \
        --json number --jq '.[0].number' 2>/dev/null || true)
    if [[ -n "$pr_num" && "$pr_num" != "null" ]]; then
        echo -e "${BOLD}最高优先级：PR #${pr_num}（claude:review）${RESET}\n"
        cmd_prompt "review" "$pr_num"
        return
    fi

    issue_num=$(gh issue list --repo "$REPO" --label "claude:design" \
        --json number --jq '.[0].number' 2>/dev/null || true)
    if [[ -n "$issue_num" && "$issue_num" != "null" ]]; then
        echo -e "${BOLD}最高优先级：Issue #${issue_num}（claude:design）${RESET}\n"
        cmd_prompt "design" "$issue_num"
        return
    fi

    echo -e "${GREEN}✓ 无待处理项。${RESET}"
}

# ── prompt 命令 ─────────────────────────────────────────────────────────────

cmd_prompt() {
    local action="${1:-}"
    local number="${2:-}"

    if [[ -z "$action" || -z "$number" ]]; then
        echo "用法：./scripts/atelier.sh prompt <respond|review|design> <编号>" >&2
        exit 1
    fi

    local template_file is_pr="false"
    case "$action" in
        respond) template_file="$PROMPTS_DIR/claude-respond.md.example" ;;
        review)  template_file="$PROMPTS_DIR/claude-review.md.example"; is_pr="true" ;;
        design)  template_file="$PROMPTS_DIR/claude-design.md.example" ;;
        *)
            echo -e "${RED}未知动作：$action（可选：respond / review / design）${RESET}" >&2
            exit 1
            ;;
    esac

    local filled
    filled=$(_fill_prompt "$template_file" "$number" "$is_pr")

    echo -e "${BOLD}────────── 粘贴到 Claude Code ──────────${RESET}"
    printf '%s\n' "$filled"
    echo -e "${BOLD}────────────────────────────────────────${RESET}"

    _copy_to_clipboard "$filled"
}

# ── go / done 命令 ──────────────────────────────────────────────────────────

cmd_go() {
    local number="${1:-}"
    [[ -z "$number" ]] && { echo "用法：./scripts/atelier.sh go <Issue编号>" >&2; exit 1; }
    gh issue edit "$number" --repo "$REPO" --add-label "codex:go"
    echo -e "${GREEN}✓ Issue #${number} 已打 codex:go 标签，Codex 即将启动。${RESET}"
}

cmd_done() {
    local number="${1:-}"
    [[ -z "$number" ]] && { echo "用法：./scripts/atelier.sh done <Issue编号>" >&2; exit 1; }
    gh issue edit "$number" --repo "$REPO" --remove-label "codex:go" 2>/dev/null || true
    echo -e "${YELLOW}✓ Issue #${number} 已移除 codex:go 标签。${RESET}"
}

# ── 帮助 ────────────────────────────────────────────────────────────────────

cmd_help() {
    cat <<'HELP'
atelier.sh — 用户侧操作 CLI

命令：
  status                      查看所有待处理项（彩色表格）
  next                        找最高优先级项，输出已填好的 Claude prompt
  prompt respond <N>          输出 Issue #N 的 Claude 回复 prompt
  prompt review  <N>          输出 PR #N 的 Claude 评审 prompt
  prompt design  <N>          输出 Issue #N 的 Claude 写规格 prompt
  go   <N>                    给 Issue #N 加 codex:go（启动 Codex）
  done <N>                    给 Issue #N 移除 codex:go（停止 Codex）
  help                        显示此帮助

环境变量：
  ATELIER_REPO                仓库名（默认 StevenG3/atelier）
HELP
}

# ── 入口 ────────────────────────────────────────────────────────────────────

CMD="${1:-help}"
shift || true

case "$CMD" in
    status)  cmd_status ;;
    next)    cmd_next ;;
    prompt)  cmd_prompt "$@" ;;
    go)      cmd_go "$@" ;;
    done)    cmd_done "$@" ;;
    help|-h|--help) cmd_help ;;
    *)
        echo -e "${RED}未知命令：$CMD${RESET}" >&2
        cmd_help
        exit 1
        ;;
esac
