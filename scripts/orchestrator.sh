#!/usr/bin/env bash
# orchestrator.sh — 自主开发循环大脑(单次 tick)
#
# 你只启动它(经 orchestrator-daemon.sh 周期跑)。每个 tick 按优先级处理
# 一件最高优先级事项,靠 daemon 循环推进整条链路:
#
#   ⓪ CI failing PR      → codex 读失败日志自修 → push → CI 重跑(上限N次)
#   ① claude:review PR   → CI 通过才评审;claude -p:
#                            禁区命中 → needs-human(强制人类合并)
#                            approve  → 自动合并 → 更新 current_phase
#                            改动请求 → request-changes,重打 codex:go
#   ② needs-response Issue → claude -p 回答 codex 提问
#   ③ codex:go Issue      → 调 codex-runner.sh 实现 → 开 PR(打 claude:review)
#   ④ 全部空闲            → claude -p 读 north_star+进度 → 规划下一 Phase
#                            → 生成 Issue → 打 codex:go
#
# 护栏(projects/<project>.yml 的 autonomy 段):kill switch、每日 Phase 上限、
# 连续失败熔断、禁区强制人类合并。全程写 audit log。
#
# 用法:bash scripts/orchestrator.sh [project]   (默认 hermes-aegis)

set -uo pipefail

PROJECT="${1:-hermes-aegis}"
ATELIER_REPO="${ATELIER_REPO:-StevenG3/atelier}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CFG="$REPO_ROOT/projects/$PROJECT.yml"
STATE_DIR="${ATELIER_STATE_DIR:-$REPO_ROOT/.orchestrator-state}"
AUDIT_LOG="$STATE_DIR/audit.log"
LOCK_FILE="/tmp/atelier-orchestrator-$PROJECT.lock"

mkdir -p "$STATE_DIR"

# flock 防并发(claude/codex 调用很慢)
exec 9>"$LOCK_FILE"
if ! flock -n 9; then exit 0; fi

audit() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$AUDIT_LOG"; }

[[ -f "$CFG" ]] || { audit "FATAL: 配置不存在 $CFG"; exit 1; }

# ── YAML 取值(去行尾 # 注释 + 去引号)───────────────────────────────────
yget() { grep -m1 "^[[:space:]]*$1:" "$CFG" | sed "s/^[[:space:]]*$1:[[:space:]]*//; s/[[:space:]]*#.*//; s/[[:space:]]*$//; s/\"//g; s/^'//; s/'$//"; }
yget_repo() { awk -v f="$1:" '/^repos:/{r=1;next} r&&$1==f{sub(/^[^:]*:[[:space:]]*/,"");sub(/[[:space:]]*#.*/,"");gsub(/"/,"");print;exit}' "$CFG"; }

AUTONOMY_ENABLED=$(yget "enabled")
AUTO_MERGE=$(yget "auto_merge")
AUTO_CODEX_GO=$(yget "auto_codex_go")
MAX_PHASES_DAY=$(yget "max_phases_per_day"); MAX_PHASES_DAY=${MAX_PHASES_DAY:-3}
MAX_FAILS=$(yget "max_consecutive_failures"); MAX_FAILS=${MAX_FAILS:-2}
MAX_CI_FIXES=$(yget "max_ci_fixes_per_pr"); MAX_CI_FIXES=${MAX_CI_FIXES:-3}
KILL_FILE=$(yget "kill_switch_file"); KILL_FILE=${KILL_FILE:-.atelier-stop}
REPO_PATH=$(yget_repo "local_path")
REPO_GH=$(yget_repo "github")
TEST_CMD=$(yget "test_command")
CURRENT_PHASE=$(yget "current_phase")

# 重点审查清单(autonomy.review_focus 列表项)— 注入 Claude 评审 prompt
mapfile -t REVIEW_FOCUS < <(awk '
  /review_focus:/{f=1;next}
  f && /^[[:space:]]*-/ {
    line=$0
    sub(/^[[:space:]]*-[[:space:]]*/,"",line)
    sub(/[[:space:]]*#.*/,"",line)
    gsub(/"/,"",line)
    gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
    if(line!="") print line
    next
  }
  f && /^[^[:space:]#]/ {exit}
' "$CFG")

# ── 护栏:总开关 / kill switch / 熔断 ───────────────────────────────────
[[ "$AUTONOMY_ENABLED" == "true" ]] || { audit "autonomy.enabled != true,退出"; exit 0; }

if [[ -f "$REPO_ROOT/$KILL_FILE" || -f "$STATE_DIR/$KILL_FILE" ]]; then
  audit "🛑 kill switch ($KILL_FILE) 存在,暂停整个循环。删除该文件以恢复。"
  exit 0
fi

FAIL_FILE="$STATE_DIR/consecutive_failures"
fails=$(cat "$FAIL_FILE" 2>/dev/null || echo 0)
if (( fails >= MAX_FAILS )); then
  audit "🛑 连续失败 $fails 次 (上限 $MAX_FAILS),熔断暂停。修复后清零:rm $FAIL_FILE"
  gh issue list --repo "$ATELIER_REPO" --label "needs-human" --state open --limit 1 >/dev/null 2>&1
  exit 0
fi

# 每日 Phase 上限
DAY=$(date -u +%Y-%m-%d)
DAY_FILE="$STATE_DIR/phases_$DAY"
phases_today=$(cat "$DAY_FILE" 2>/dev/null || echo 0)

record_fail() { echo $(( $(cat "$FAIL_FILE" 2>/dev/null || echo 0) + 1 )) > "$FAIL_FILE"; }
record_ok()   { echo 0 > "$FAIL_FILE"; }

# claude -p 封装(headless,允许 Bash 跑 gh/git)
run_claude() {
  local prompt="$1"
  claude -p "$prompt" --permission-mode acceptEdits --allowedTools "Bash" 2>&1
}

# PR 的 GitHub CI 汇总状态:pass / fail / pending / none
ci_state() {
  local pr="$1" states
  states=$(gh pr checks "$pr" --repo "$REPO_GH" --json state --jq '[.[].state]|join(",")' 2>/dev/null || echo "")
  if [[ -z "$states" || "$states" == "[]" ]]; then echo "none"; return; fi
  if grep -qiE "FAILURE|ERROR|CANCELLED|TIMED_OUT" <<<"$states"; then echo "fail"; return; fi
  if grep -qiE "PENDING|IN_PROGRESS|QUEUED|WAITING|REQUESTED" <<<"$states"; then echo "pending"; return; fi
  echo "pass"
}

# ════════════════════════════════════════════════════════════════════════
# ⓪ CI failing 的 PR → codex 自主读失败日志修复(带次数上限)
# ════════════════════════════════════════════════════════════════════════
for cipr in $(gh pr list --repo "$REPO_GH" --state open --json number --jq '.[].number' 2>/dev/null); do
  st=$(ci_state "$cipr")
  [[ "$st" == "fail" ]] || continue
  CI_FIX_FILE="$STATE_DIR/ci_fixes_${cipr}"
  fixes=$(cat "$CI_FIX_FILE" 2>/dev/null || echo 0)
  if (( fixes >= MAX_CI_FIXES )); then
    audit "⓪ PR #$cipr CI 已修 $fixes 次仍失败(上限 $MAX_CI_FIXES)→ ESCALATE needs-human"
    gh pr edit "$cipr" --repo "$REPO_GH" --remove-label "claude:review" --add-label "needs-human" 2>/dev/null || true
    gh pr comment "$cipr" --repo "$REPO_GH" --body "🚨 CI 连续 $fixes 次自动修复仍失败,需你介入。" 2>/dev/null || true
    record_fail; exit 0
  fi
  audit "⓪ PR #$cipr CI 失败 → codex 第 $((fixes+1)) 次修复"
  # checkout PR 分支
  pr_branch=$(gh pr view "$cipr" --repo "$REPO_GH" --json headRefName --jq '.headRefName' 2>/dev/null)
  cd "$REPO_PATH"
  git fetch origin >>"$AUDIT_LOG" 2>&1 || true
  git checkout "$pr_branch" >>"$AUDIT_LOG" 2>&1 && git pull --ff-only >>"$AUDIT_LOG" 2>&1 || { audit "  ❌ checkout $pr_branch 失败"; record_fail; exit 1; }
  # codex 读 CI 失败日志并修复(它自己用 gh 抓日志)
  printf '%s' "PR #${cipr} 的 GitHub CI 失败了。请用 \`gh pr checks ${cipr} --repo ${REPO_GH}\` 和 \`gh run view --log-failed\` 查看失败的具体原因(lint/类型/测试等),然后在当前已 checkout 的 PR 分支上修复代码使 CI 能通过。只改工作区文件,不要 git commit/push(外层处理)。" \
    | codex exec -s workspace-write -C "$REPO_PATH" --skip-git-repo-check \
        -o "$STATE_DIR/ci-fix-${cipr}-last.md" >>"$AUDIT_LOG" 2>&1 || { audit "  ❌ codex 修复异常"; record_fail; exit 1; }
  git add -A >>"$AUDIT_LOG" 2>&1 || true
  if git diff --cached --quiet; then
    audit "  ⚠️ codex 未产生修复改动 → ESCALATE needs-human"
    gh pr edit "$cipr" --repo "$REPO_GH" --remove-label "claude:review" --add-label "needs-human" 2>/dev/null || true
    record_fail; exit 0
  fi
  git commit -m "fix: CI repair attempt $((fixes+1)) for ${ATELIER_REPO}#? (PR #${cipr})" >>"$AUDIT_LOG" 2>&1 || true
  git push >>"$AUDIT_LOG" 2>&1 || { audit "  ❌ push 失败"; record_fail; exit 1; }
  echo $(( fixes + 1 )) > "$CI_FIX_FILE"
  audit "  ✓ 已推送 CI 修复,等 CI 重跑(下个 tick 复检)"
  record_ok; exit 0
done

# ════════════════════════════════════════════════════════════════════════
# ① claude:review 的 PR → 评审 + (CI 门禁 / 自动合并 / 打回)
# ════════════════════════════════════════════════════════════════════════
pr_num=$(gh pr list --repo "$REPO_GH" --label "claude:review" --state open \
  --json number --jq 'sort_by(.number)|.[0].number // empty' 2>/dev/null || true)

if [[ -n "$pr_num" ]]; then
  # CI 门禁:只评审 CI 通过(或无 CI)的 PR;pending 等待,fail 交给 ⓪
  ci=$(ci_state "$pr_num")
  if [[ "$ci" == "pending" ]]; then
    audit "① PR #$pr_num CI 运行中,本 tick 等待。"; exit 0
  elif [[ "$ci" == "fail" ]]; then
    audit "① PR #$pr_num CI 失败,交由 ⓪ 修复(下个 tick)。"; exit 0
  fi
  audit "① 评审 PR $REPO_GH#$pr_num(CI=$ci)"
  # 禁区关键词降级为「给 Claude 的重点审查清单」,决定权完全交给 Claude。
  checklist=$(printf '%s; ' "${REVIEW_FOCUS[@]}")

  # Claude 评审(headless),三态判定。是否需要人介入由 Claude 自己判断。
  verdict=$(run_claude "你是 Atelier 架构师(见 StevenG3/atelier CLAUDE.md)。评审 PR ${REPO_GH}#${pr_num}。

这是**全自动开发循环**:你 APPROVE 会被自动 --squash 合并进 main 并触发下一 Phase,合并不易撤销。人类不做代码评审(你比他强),只在你主动 ESCALATE 时介入。

步骤:
1. gh pr view ${pr_num} --repo ${REPO_GH};gh pr diff ${pr_num} --repo ${REPO_GH}
2. 按 CLAUDE.md 评审清单查:验收标准、安全不变量、测试覆盖。
3. 重点审查清单(命中这些的改动尤其谨慎,但不是硬性否决):${checklist}
4. gh pr review ${pr_num} --repo ${REPO_GH} 提交 --approve 或 --request-changes --body。PR 评论写简短结论。

判定(最后一行**必须**单独输出以下机器标记之一):
  VERDICT=APPROVE   代码正确、安全、达标 → 自动合并进 main
  VERDICT=CHANGES   有可修问题 → 打回 codex 重做
  VERDICT=ESCALATE  涉及不可逆操作 / 动真钱 / 你无法确信安全的高危改动 → 需人类最终拍板" | tail -25)

  if grep -q "VERDICT=APPROVE" <<<"$verdict"; then
    if [[ "$AUTO_MERGE" == "true" ]]; then
      audit "  ✅ Claude approve → 自动合并 PR #$pr_num"
      if gh pr merge "$pr_num" --repo "$REPO_GH" --squash --delete-branch 2>>"$AUDIT_LOG"; then
        audit "  🎉 PR #$pr_num 已合并到 main"; record_ok
      else
        audit "  ❌ 自动合并失败(冲突/未过 CI)→ needs-human"
        gh pr edit "$pr_num" --repo "$REPO_GH" --add-label "needs-human" 2>/dev/null || true
        record_fail
      fi
    else
      audit "  ✅ approve(auto_merge 关闭)→ 等人类合并"
    fi
  elif grep -q "VERDICT=CHANGES" <<<"$verdict"; then
    audit "  🔁 Claude 要求修改 → 关联 Issue 重打 codex:go"
    iss=$(gh pr view "$pr_num" --repo "$REPO_GH" --json body --jq '.body' 2>/dev/null | grep -oE "atelier#[0-9]+" | head -1 | grep -oE "[0-9]+" || true)
    [[ -n "$iss" ]] && gh issue edit "$iss" --repo "$ATELIER_REPO" --add-label "codex:go" 2>/dev/null || true
    gh pr edit "$pr_num" --repo "$REPO_GH" --remove-label "claude:review" 2>/dev/null || true
    record_ok
  elif grep -q "VERDICT=ESCALATE" <<<"$verdict"; then
    audit "  🚨 Claude 主动 ESCALATE(高危/不可逆/涉真钱)→ needs-human + 通知"
    gh pr edit "$pr_num" --repo "$REPO_GH" --remove-label "claude:review" --add-label "needs-human" 2>/dev/null || true
    gh pr comment "$pr_num" --repo "$REPO_GH" --body "🚨 Claude 主动上报:此 PR 涉及不可逆/真钱/高危,需你最终拍板(回复 approve 即合并,或说明顾虑)。" 2>/dev/null || true
    record_ok   # ESCALATE 是正常决策,不计失败
  else
    audit "  ⚠️ 评审无明确 VERDICT → needs-human"
    gh pr edit "$pr_num" --repo "$REPO_GH" --add-label "needs-human" 2>/dev/null || true
    record_fail
  fi
  exit 0
fi

# ════════════════════════════════════════════════════════════════════════
# ② needs-response 的 Issue → claude 回答
# ════════════════════════════════════════════════════════════════════════
resp_iss=$(gh issue list --repo "$ATELIER_REPO" --label "needs-response" --state open \
  --json number --jq 'sort_by(.number)|.[0].number // empty' 2>/dev/null || true)
if [[ -n "$resp_iss" ]]; then
  audit "② 回答 Issue #$resp_iss 的 codex 提问"
  run_claude "你是 Atelier 架构师。读 Issue ${ATELIER_REPO}#${resp_iss} 全部评论(gh issue view --comments),
用决策格式回复 codex 最新的 @claude 提问(gh issue comment):**决策:** / **理由:** / **行动:** 继续|等人类|停止。
若决策导致规格变更,gh issue edit 更新 body。完成后 gh issue edit 移除 needs-response 标签。" >>"$AUDIT_LOG" 2>&1 \
    && { audit "  ✓ 已回复"; record_ok; } || { audit "  ❌ 回复失败"; record_fail; }
  exit 0
fi

# ════════════════════════════════════════════════════════════════════════
# ③ codex:go 的 Issue → 调 codex-runner 实现
# ════════════════════════════════════════════════════════════════════════
go_iss=$(gh issue list --repo "$ATELIER_REPO" --label "codex:go" --state open \
  --json number,labels \
  --jq '[.[]|select(([.labels[].name]|index("codex:working"))|not)]|sort_by(.number)|.[0].number // empty' 2>/dev/null || true)
if [[ -n "$go_iss" ]]; then
  audit "③ codex 实现 Issue #$go_iss(调 codex-runner)"
  if bash "$SCRIPT_DIR/codex-runner.sh" >>"$AUDIT_LOG" 2>&1; then
    audit "  ✓ codex-runner 完成,PR 待下一 tick 评审"; record_ok
  else
    audit "  ❌ codex-runner 失败"; record_fail
  fi
  exit 0
fi

# ════════════════════════════════════════════════════════════════════════
# ④ 全部空闲 → 规划下一 Phase(目标驱动)
# ════════════════════════════════════════════════════════════════════════
# 空闲定义:无 codex:go / codex:working / claude:review / needs-response / needs-human
busy=$(gh issue list --repo "$ATELIER_REPO" --state open \
  --json labels --jq '[.[]|.labels[].name]|map(select(.=="codex:go" or .=="codex:working" or .=="claude:design" or .=="needs-response" or .=="needs-human"))|length' 2>/dev/null || echo 0)
busy_pr=$(gh pr list --repo "$REPO_GH" --state open --json number --jq 'length' 2>/dev/null || echo 0)

if (( busy > 0 || busy_pr > 0 )); then
  audit "④ 有进行中事项(issues=$busy prs=$busy_pr),不规划新 Phase。"
  exit 0
fi

if (( phases_today >= MAX_PHASES_DAY )); then
  audit "④ 今日已自动启动 $phases_today 个 Phase (上限 $MAX_PHASES_DAY),今日不再规划。"
  exit 0
fi

if [[ "$AUTO_CODEX_GO" != "true" ]]; then
  audit "④ auto_codex_go 关闭,跳过自动规划(改用 'atelier next-phase')。"
  exit 0
fi

NEXT=$(( CURRENT_PHASE + 1 ))
audit "④ 空闲 → 规划 Phase $NEXT(north_star 驱动)"

plan_out=$(run_claude "你是 Atelier 架构师(StevenG3/atelier CLAUDE.md)。为 $PROJECT 规划并发布 Phase $NEXT。
1. 读 north_star 与进度:cat $CFG;读 Phase $CURRENT_PHASE 的 Design Notes:cat /home/gggqqy/docs/CODEX_PHASE${CURRENT_PHASE}_PROMPT.md;git -C $REPO_PATH log --oneline -15
2. 基于 Phase $CURRENT_PHASE 的 DESIGN NOTES FOR FUTURE PHASES 中关于 Phase $NEXT 的描述,生成完整 Phase $NEXT 规格(格式同既有 Phase prompt:ROLE/CONTEXT/GOAL/SAFETY INVARIANTS/§/ALLOWED FILES/FORBIDDEN SCOPE/ACCEPTANCE CRITERIA/STOP-AND-ASK/DESIGN NOTES)
3. 保存:tee /home/gggqqy/docs/CODEX_PHASE${NEXT}_PROMPT.md
4. 创建 Issue 并立即打 codex:go(全自主):
   gh issue create --repo ${ATELIER_REPO} --title '[${PROJECT}] Phase ${NEXT} — <一行>' --body \"\$(printf 'project: ${PROJECT}\\nphase: ${NEXT}\\n\\n---\\n\\n'; cat /home/gggqqy/docs/CODEX_PHASE${NEXT}_PROMPT.md)\" --label 'codex:implement,codex:go'
5. 最后一行单独输出:PLANNED=Phase${NEXT}")

if grep -q "PLANNED=Phase${NEXT}" <<<"$plan_out"; then
  # 更新 current_phase + 计数
  sed -i "s/^current_phase:.*/current_phase: $NEXT/" "$CFG"
  echo $(( phases_today + 1 )) > "$DAY_FILE"
  audit "  ✓ Phase $NEXT 已发布并打 codex:go;current_phase → $NEXT(今日第 $((phases_today+1)) 个)"
  record_ok
else
  audit "  ❌ Phase $NEXT 规划失败(无 PLANNED 标记)"
  record_fail
fi
