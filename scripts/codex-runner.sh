#!/usr/bin/env bash
# codex-runner.sh — codex 实现环节(被 orchestrator.sh 调用,也可独立跑)
#
# 职责(单一):
#   codex:go 标签 → codex exec (ChatGPT OAuth) 实现 → 跑测试
#     → 推分支 → 开 PR → 打 claude:review 标签 → Issue 评论
#
# 评审 / 自动合并 / 规划下一 Phase 由 orchestrator.sh 统一负责。
# 本脚本只管"把一个 codex:go 变成一个待评审 PR"。
#
# 状态机(防重复触发):
#   codex:go            待处理
#   → codex:working     处理中(本脚本加,处理完移除;防止下轮重入)
#   → 成功:移除 working,产出 PR 打 claude:review,Issue 评论 PR 链接
#   → 失败:移除 working,Issue 打 needs-human + 评论错误
#
# 一次只处理一个 Issue。用 flock 防止并发重入。
# 不自动合并 PR(合并是人类的权力)。
#
# 用法:
#   bash scripts/codex-runner.sh            # 单次扫描处理一个
#   (周期运行见 scripts/codex-runner-daemon.sh)
#
# 前置:gh 已登录(StevenG3)、codex 已 ChatGPT 登录、各 repo 已 clone

set -euo pipefail

ATELIER_REPO="${ATELIER_REPO:-StevenG3/atelier}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECTS_DIR="$REPO_ROOT/projects"
LOG_DIR="${ATELIER_LOG_DIR:-$REPO_ROOT/.codex-runner-logs}"
LOCK_FILE="/tmp/atelier-codex-runner.lock"

mkdir -p "$LOG_DIR"

# ── flock 防并发(codex exec 可能跑很久,避免重叠)──────────────────────
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[$(date -u +%H:%M:%S)] 另一个 runner 正在运行,跳过本次。"
  exit 0
fi

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# ── YAML 取值(简易,projects/<name>.yml)──────────────────────────────
# 取第一个 repo 的 local_path / github
yaml_first_repo_field() {
  local file="$1" field="$2"
  awk -v f="$field:" '
    /^repos:/ {inrepos=1; next}
    inrepos && $1==f {sub(/^[^:]*:[[:space:]]*/,""); gsub(/"/,""); print; exit}
  ' "$file"
}
yaml_scalar() {
  local file="$1" key="$2"
  grep -m1 "^${key}:" "$file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//; s/\"//g; s/^'//; s/'$//"
}

# ── 1. 找一个 codex:go 且无 codex:working 的 Issue ──────────────────────
issue_num=$(gh issue list --repo "$ATELIER_REPO" --label "codex:go" --state open \
  --json number,labels \
  --jq '[.[] | select(([.labels[].name] | index("codex:working")) | not)] | sort_by(.number) | .[0].number // empty' 2>/dev/null || true)

if [[ -z "$issue_num" ]]; then
  log "无待处理的 codex:go Issue。"
  exit 0
fi

log "处理 Issue #$issue_num"
RUN_LOG="$LOG_DIR/issue-${issue_num}-$(date -u +%Y%m%dT%H%M%SZ).log"

# ── 2. 读 Issue body + 解析 project ─────────────────────────────────────
body=$(gh issue view "$issue_num" --repo "$ATELIER_REPO" --json body --jq '.body')
project=$(printf '%s\n' "$body" | grep -m1 -i '^project:' | sed 's/^[Pp]roject:[[:space:]]*//' | tr -d '\r' || true)

if [[ -z "$project" || ! -f "$PROJECTS_DIR/$project.yml" ]]; then
  log "Issue #$issue_num 缺少有效 project 字段(got: '$project')→ needs-human"
  gh issue edit "$issue_num" --repo "$ATELIER_REPO" --add-label "needs-human" 2>/dev/null || true
  gh issue comment "$issue_num" --repo "$ATELIER_REPO" \
    --body "⚠️ codex-runner 无法处理:Issue body 第一行需要 \`project: <name>\`,且 projects/<name>.yml 必须存在。当前解析到:\`$project\`" 2>/dev/null || true
  exit 1
fi

cfg="$PROJECTS_DIR/$project.yml"
repo_path=$(yaml_first_repo_field "$cfg" "local_path")
repo_github=$(yaml_first_repo_field "$cfg" "github")
test_cmd=$(yaml_scalar "$cfg" "test_command")

log "project=$project repo_path=$repo_path github=$repo_github"

if [[ -z "$repo_path" || ! -d "$repo_path" ]]; then
  log "repo 路径无效:$repo_path → needs-human"
  gh issue edit "$issue_num" --repo "$ATELIER_REPO" --add-label "needs-human" 2>/dev/null || true
  gh issue comment "$issue_num" --repo "$ATELIER_REPO" \
    --body "⚠️ codex-runner:projects/$project.yml 的首个 repo local_path 无效(\`$repo_path\`)。" 2>/dev/null || true
  exit 1
fi

# ── 3. 状态机:codex:go → codex:working(防重入)─────────────────────────
gh issue edit "$issue_num" --repo "$ATELIER_REPO" \
  --remove-label "codex:go" --add-label "codex:working" 2>/dev/null || true
log "标签 codex:go → codex:working"

# 失败兜底:任何提前退出都回滚为 needs-human
fail() {
  log "FAILED: $*"
  gh issue edit "$issue_num" --repo "$ATELIER_REPO" \
    --remove-label "codex:working" --add-label "needs-human" 2>/dev/null || true
  gh issue comment "$issue_num" --repo "$ATELIER_REPO" \
    --body "❌ codex-runner 失败:$1。日志:\`$RUN_LOG\`" 2>/dev/null || true
  exit 1
}

# ── 4. 准备干净分支 ─────────────────────────────────────────────────────
cd "$repo_path"
git fetch origin >>"$RUN_LOG" 2>&1 || true
default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || echo main)
git checkout "$default_branch" >>"$RUN_LOG" 2>&1 || fail "checkout $default_branch 失败"
git pull --ff-only >>"$RUN_LOG" 2>&1 || fail "pull 失败"
branch="feat/atelier-${issue_num}-$(date -u +%Y%m%d%H%M%S)"
git checkout -b "$branch" >>"$RUN_LOG" 2>&1 || fail "建分支失败"
log "分支:$branch (base $default_branch)"

# ── 5. 跑 codex exec 实现(非交互,workspace-write 沙箱)───────────────────
log "启动 codex exec(可能耗时数分钟)…"
CODEX_PROMPT="你是执行工程师 Codex。下面 <stdin> 是一个 GitHub Issue 的完整规格。
请在当前仓库实现它,严格遵守规格中的 ALLOWED FILES、FORBIDDEN SCOPE、SAFETY INVARIANTS、ACCEPTANCE CRITERIA。
补充并跑通测试。遇到规格里的 STOP-AND-ASK 条件时,在代码注释里标注 TODO(STOP-AND-ASK) 并实现最合理的默认方案,不要中断。
不要执行 git commit / git push / 创建 PR —— 这些由外层脚本完成。只修改工作区文件。"

if printf '%s' "$body" | codex exec \
      -s workspace-write \
      -C "$repo_path" \
      --skip-git-repo-check \
      -o "$LOG_DIR/issue-${issue_num}-last-message.md" \
      "$CODEX_PROMPT" >>"$RUN_LOG" 2>&1; then
  log "codex exec 完成"
else
  fail "codex exec 非零退出"
fi

# ── 6. 检查是否真有产出 ─────────────────────────────────────────────────
git add -A >>"$RUN_LOG" 2>&1 || true
if git diff --cached --quiet; then
  fail "codex 未产生任何文件改动"
fi

# ── 7. 跑测试(失败则开 draft PR + needs-human,不直接合并路径)──────────
test_passed=1
if [[ -n "$test_cmd" ]]; then
  log "运行测试:$test_cmd"
  if eval "$test_cmd" >>"$RUN_LOG" 2>&1; then
    log "测试通过"
  else
    test_passed=0
    log "测试失败"
  fi
fi

# ── 8. 提交 + 推送 ──────────────────────────────────────────────────────
issue_title=$(gh issue view "$issue_num" --repo "$ATELIER_REPO" --json title --jq '.title')
git commit -m "feat: implement ${ATELIER_REPO}#${issue_num} — ${issue_title}

Auto-implemented by codex-runner from Atelier Issue #${issue_num}.

Co-Authored-By: Codex <noreply@openai.com>" >>"$RUN_LOG" 2>&1 || fail "git commit 失败"
git push -u origin "$branch" >>"$RUN_LOG" 2>&1 || fail "git push 失败"
log "已推送分支 $branch"

# ── 9. 开 PR ────────────────────────────────────────────────────────────
pr_draft_flag=""
review_label="claude:review"
status_note="✅ 测试通过,待 Claude 评审"
if [[ "$test_passed" -eq 0 ]]; then
  pr_draft_flag="--draft"
  review_label="needs-human"
  status_note="⚠️ 测试未通过,已开 Draft PR,需人工/Claude 介入"
fi

pr_url=$(gh pr create --repo "$repo_github" \
  --title "feat: $issue_title (atelier#$issue_num)" \
  --body "$(printf 'Auto-implemented by codex-runner from Atelier Issue %s#%s.\n\n%s\n\n---\n🤖 codex exec (ChatGPT OAuth) · Atelier' "$ATELIER_REPO" "$issue_num" "$status_note")" \
  --head "$branch" \
  $pr_draft_flag 2>>"$RUN_LOG") || fail "gh pr create 失败"

log "PR: $pr_url"

# ── 10. 收尾:状态机 codex:working → 完成,Issue 评论 PR ────────────────
if [[ "$test_passed" -eq 1 ]]; then
  gh issue edit "$issue_num" --repo "$ATELIER_REPO" --remove-label "codex:working" 2>/dev/null || true
else
  gh issue edit "$issue_num" --repo "$ATELIER_REPO" \
    --remove-label "codex:working" --add-label "needs-human" 2>/dev/null || true
fi

# gh 2.4.0 的 gh pr edit --label 走 GraphQL 会失败,用 REST(PR 共用 issues/{n}/labels)
pr_number=$(printf '%s' "$pr_url" | grep -oE '[0-9]+$')
echo "{\"labels\":[\"$review_label\"]}" | gh api "repos/$repo_github/issues/$pr_number/labels" --method POST --input - --silent 2>/dev/null || true
gh issue comment "$issue_num" --repo "$ATELIER_REPO" \
  --body "$(printf '🤖 codex-runner 完成实现。\n- 分支:\`%s\`\n- PR:%s\n- %s' "$branch" "$pr_url" "$status_note")" 2>/dev/null || true

# 输出 PR URL 供 orchestrator 捕获(最后一行)
echo "PR_URL=$pr_url"
log "Issue #$issue_num 实现环节完成 → $pr_url(待 orchestrator 评审)"
