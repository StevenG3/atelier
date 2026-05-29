#!/usr/bin/env bash
# preflight.sh — 启动前依赖检查
#
# 被其他脚本 source，不直接执行。
# 调用方式：
#   source "$(dirname "$0")/preflight.sh"
#   run_preflight   # 失败则 exit 1

# ── 颜色（在被 source 时继承父脚本的颜色变量，或重新定义）──────────────
_PF_RED='\033[0;31m'; _PF_GREEN='\033[0;32m'
_PF_YELLOW='\033[0;33m'; _PF_BOLD='\033[1m'; _PF_RESET='\033[0m'

_pf_ok()   { echo -e "  ${_PF_GREEN}✓${_PF_RESET} $*"; }
_pf_fail() { echo -e "  ${_PF_RED}✗${_PF_RESET} $*"; }
_pf_hint() { echo -e "    ${_PF_YELLOW}→${_PF_RESET} $*"; }

# 必需标签列表（与 .github/labels.yml 保持一致）
REQUIRED_LABELS=(
  "claude:design"
  "claude:spec-ready"
  "claude:review"
  "codex:implement"
  "codex:go"
  "needs-response"
  "needs-human"
  "on-hold"
  "blocked"
)

run_preflight() {
  local _repo="${REPO:-StevenG3/atelier}"
  local _script_dir
  _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local _repo_root
  _repo_root="$(cd "$_script_dir/.." && pwd)"

  local _failed=0

  echo -e "${_PF_BOLD}── preflight 依赖检查 ──────────────────────────────${_PF_RESET}"

  # ── 1. gh CLI 已安装 ───────────────────────────────────────────────────
  if command -v gh &>/dev/null; then
    local _gh_ver
    _gh_ver=$(gh --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    _pf_ok "gh CLI 已安装 (${_gh_ver:-unknown})"
  else
    _pf_fail "gh CLI 未安装"
    _pf_hint "安装：https://cli.github.com  或  brew install gh  或  apt install gh"
    _failed=1
  fi

  # ── 2. GitHub 已认证 ───────────────────────────────────────────────────
  if command -v gh &>/dev/null; then
    local _auth_out _auth_user
    _auth_out=$(gh auth status 2>&1 || true)
    # 支持两种格式：
    #   "Logged in to github.com as USERNAME"
    #   "Logged in to github.com account USERNAME"
    _auth_user=$(echo "$_auth_out" | grep -oE 'Logged in to github\.com (as|account) \S+' \
                 | awk '{print $NF}' | tr -d '()' || true)
    if [[ -n "$_auth_user" ]]; then
      _pf_ok "GitHub 已认证 (${_auth_user})"
    else
      _pf_fail "GitHub 未认证"
      _pf_hint "运行：gh auth login"
      _failed=1
    fi
  fi

  # ── 3. 目标仓库可访问 ──────────────────────────────────────────────────
  if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    if gh repo view "$_repo" --json name -q '.name' &>/dev/null; then
      _pf_ok "仓库可访问 ($_repo)"
    else
      _pf_fail "仓库不可访问：$_repo"
      _pf_hint "检查 ATELIER_REPO 环境变量（当前值：${REPO:-未设置，默认 StevenG3/atelier}）"
      _pf_hint "或检查网络连接与仓库权限"
      _failed=1
    fi
  fi

  # ── 4. 必需标签全部存在 ────────────────────────────────────────────────
  if command -v gh &>/dev/null && gh auth status &>/dev/null && \
     gh repo view "$_repo" --json name -q '.name' &>/dev/null; then
    local _existing_labels
    _existing_labels=$(gh api "repos/$_repo/labels?per_page=100" --jq '.[].name' 2>/dev/null || true)
    local _missing=()
    for label in "${REQUIRED_LABELS[@]}"; do
      if ! echo "$_existing_labels" | grep -qxF "$label" 2>/dev/null; then
        _missing+=("$label")
      fi
    done
    local _total=${#REQUIRED_LABELS[@]}
    local _found=$(( _total - ${#_missing[@]} ))
    if [[ ${#_missing[@]} -eq 0 ]]; then
      _pf_ok "所有必需标签存在 (${_found}/${_total})"
    else
      _pf_fail "缺失标签 (${_found}/${_total} 存在)：${_missing[*]}"
      _pf_hint "修复：bash $_script_dir/sync-labels.sh"
      _failed=1
    fi
  fi

  # ── 5. prompts/ 目录存在 ──────────────────────────────────────────────
  if [[ -d "$_repo_root/prompts" ]]; then
    _pf_ok "prompts/ 目录存在"
  else
    _pf_fail "prompts/ 目录不存在（$_repo_root/prompts）"
    _pf_hint "请重新 clone 仓库或检查本地路径是否正确"
    _failed=1
  fi

  echo -e "${_PF_BOLD}────────────────────────────────────────────────────${_PF_RESET}"

  # ── 汇总 ──────────────────────────────────────────────────────────────
  if [[ $_failed -eq 0 ]]; then
    echo -e "  ${_PF_GREEN}${_PF_BOLD}✓ 所有依赖满足，继续执行${_PF_RESET}"
    echo ""
    return 0
  else
    echo -e "  ${_PF_RED}${_PF_BOLD}✗ 检查未通过，请修复以上问题后重试${_PF_RESET}"
    echo ""
    exit 1
  fi
}
