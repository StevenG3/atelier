#!/usr/bin/env bats
# test_autonomy_hardening.bats — orchestrator/codex-runner 自主闭环加固回归测试

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
ORCH="$REPO_ROOT/scripts/orchestrator.sh"
RUNNER="$REPO_ROOT/scripts/codex-runner.sh"

setup() {
  TMP_ATELIER="$(mktemp -d)"
  MOCK_BIN="$TMP_ATELIER/bin"
  TARGET_REPO="$TMP_ATELIER/target"
  STATE_DIR="$TMP_ATELIER/state"
  mkdir -p "$MOCK_BIN" "$TARGET_REPO" "$STATE_DIR"
  export TMP_ATELIER
  export PATH="$MOCK_BIN:$PATH"
  export ATELIER_REPO="StevenG3/atelier"
  export ATELIER_STATE_DIR="$STATE_DIR"
  export ATELIER_LOG_DIR="$TMP_ATELIER/logs"
}

teardown() {
  [[ -n "${TEST_PROJECT:-}" ]] && rm -f "$REPO_ROOT/projects/$TEST_PROJECT.yml"
  [[ -n "${TMP_ATELIER:-}" ]] && rm -rf "$TMP_ATELIER"
}

write_project() {
  TEST_PROJECT="$1"
  export TEST_PROJECT
  local current_phase="${2:-23}"
  cat > "$REPO_ROOT/projects/$TEST_PROJECT.yml" <<YAML
name: test
repos:
  - id: app
    github: "StevenG3/app"
    local_path: "$TARGET_REPO"
test_command: "true"
lint_command: "true"
current_phase: $current_phase
autonomy:
  enabled: true
  auto_merge: true
  auto_codex_go: true
  max_phases_per_day: 10
  max_consecutive_failures: 5
  max_ci_fixes_per_pr: 3
  max_review_iterations: 3
  kill_switch_file: ".atelier-stop"
  review_focus:
    - "schema"
YAML
}

write_mock_git() {
  cat > "$MOCK_BIN/git" <<'SH'
#!/usr/bin/env bash
echo "git $*" >> "$TMP_ATELIER/git.log"
case "$*" in
  "symbolic-ref --short refs/remotes/origin/HEAD") echo "origin/main" ;;
  "diff --cached --quiet") exit 1 ;;
esac
exit 0
SH
  chmod +x "$MOCK_BIN/git"
}

write_mock_git_commit_fails() {
  cat > "$MOCK_BIN/git" <<'SH'
#!/usr/bin/env bash
echo "git $*" >> "$TMP_ATELIER/git.log"
case "$*" in
  "commit -m "*) exit 1 ;;
esac
exit 0
SH
  chmod +x "$MOCK_BIN/git"
}

write_mock_codex() {
  cat > "$MOCK_BIN/codex" <<'SH'
#!/usr/bin/env bash
echo "codex $*" >> "$TMP_ATELIER/codex.args"
cat > "$TMP_ATELIER/codex.stdin"
exit 0
SH
  chmod +x "$MOCK_BIN/codex"
}

write_mock_claude_changes() {
  cat > "$MOCK_BIN/claude" <<'SH'
#!/usr/bin/env bash
echo "claude $*" >> "$TMP_ATELIER/claude.log"
echo "reviewed"
echo "VERDICT=CHANGES"
SH
  chmod +x "$MOCK_BIN/claude"
}

write_mock_claude_planned() {
  cat > "$MOCK_BIN/claude" <<'SH'
#!/usr/bin/env bash
echo "claude $*" >> "$TMP_ATELIER/claude.log"
echo "PLANNED=Phase24"
SH
  chmod +x "$MOCK_BIN/claude"
}

write_mock_claude_approve() {
  cat > "$MOCK_BIN/claude" <<'SH'
#!/usr/bin/env bash
echo "claude $*" >> "$TMP_ATELIER/claude.log"
echo "reviewed"
echo "VERDICT=APPROVE"
SH
  chmod +x "$MOCK_BIN/claude"
}

write_mock_gh_changes() {
  cat > "$MOCK_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$TMP_ATELIER/gh.log"
args="$*"
case "$args" in
  "pr list"*"--json number --jq .[].number"*) echo "7" ;;
  "pr list"*"--label claude:review"*) echo "7" ;;
  "pr checks 7"*) echo "unit pass" ;;
  "pr view 7"*"--json headRefName"*) echo "feature/existing-pr" ;;
  "pr view 7"*"--json reviews"*) echo "please fix review feedback" ;;
  "api repos/"*"--method DELETE"*) exit 0 ;;
  "api repos/"*) cat >> "$TMP_ATELIER/gh.log"; exit 0 ;;
  "pr comment 7"*) exit 0 ;;
  *) echo "" ;;
esac
SH
  chmod +x "$MOCK_BIN/gh"
}

write_mock_gh_approve() {
  cat > "$MOCK_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$TMP_ATELIER/gh.log"
args="$*"
case "$args" in
  "api repos/"*) exit 0 ;;
  "pr list"*"--json number --jq .[].number"*) echo "" ;;
  "pr list"*"--label claude:review"*) echo "7" ;;
  "pr checks 7"*) echo "unit pass" ;;
  "pr merge 7"*) exit 0 ;;
  "pr view 7"*"--json body,title"*) printf 'Auto-implemented from StevenG3/atelier#5.\nfeat: thing (atelier#5)\n' ;;
  "issue view 5"*"--json body"*) printf 'project: %s\nphase: 24\n' "$TEST_PROJECT" ;;
  *) echo "" ;;
esac
SH
  chmod +x "$MOCK_BIN/gh"
}

write_mock_gh_idle() {
  cat > "$MOCK_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$TMP_ATELIER/gh.log"
args="$*"
case "$args" in
  "api repos/"*) exit 0 ;;
  "pr list"*"--json number --jq .[].number"*) echo "" ;;
  "pr list"*"--label claude:review"*) echo "" ;;
  "issue list"*"needs-response"*) echo "" ;;
  "issue list"*"codex:go"*) echo "" ;;
  "issue list"*"--json labels"*) echo "0" ;;
  "pr list"*"--json number --jq length"*) echo "0" ;;
  *) echo "" ;;
esac
SH
  chmod +x "$MOCK_BIN/gh"
}

write_mock_gh_api_down() {
  cat > "$MOCK_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$TMP_ATELIER/gh.log"
args="$*"
case "$args" in
  "api repos/"*) exit 1 ;;
  *) echo "" ;;
esac
SH
  chmod +x "$MOCK_BIN/gh"
}

write_mock_gh_runner() {
  cat > "$MOCK_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$TMP_ATELIER/gh.log"
args="$*"
case "$args" in
  "issue list"*"codex:go"*) echo "5" ;;
  "issue view 5"*"--json body"*) printf 'project: %s\n\nDo the thing.\n' "$TEST_PROJECT" ;;
  "issue view 5"*"--json title"*) echo "Implement gate" ;;
  "api repos/"*"--method DELETE"*) exit 0 ;;
  "api repos/"*) cat >> "$TMP_ATELIER/gh.log"; exit 0 ;;
  "issue comment 5"*) exit 0 ;;
  "pr create"*) echo "https://github.com/StevenG3/app/pull/99" ;;
  *) echo "" ;;
esac
SH
  chmod +x "$MOCK_BIN/gh"
}

@test "CHANGES iterates on original PR branch without re-labeling Issue codex:go" {
  write_project "autonomy-changes"
  write_mock_git
  write_mock_codex
  write_mock_claude_changes
  write_mock_gh_changes

  run bash "$ORCH" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  grep -q "git checkout feature/existing-pr" "$TMP_ATELIER/git.log"
  grep -q "不要新建分支" "$TMP_ATELIER/codex.stdin"
  grep -q "please fix review feedback" "$TMP_ATELIER/codex.stdin"
  grep -q "运行 lint:true" "$STATE_DIR/audit.log"
  grep -q "运行测试:true" "$STATE_DIR/audit.log"
  ! grep -q "codex:go" "$TMP_ATELIER/gh.log"
  [ "$(cat "$STATE_DIR/review_iters_7")" = "1" ]
}

@test "APPROVE merge bumps current_phase from linked atelier issue" {
  write_project "autonomy-approve" 23
  write_mock_git
  write_mock_codex
  write_mock_claude_approve
  write_mock_gh_approve

  run bash "$ORCH" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  grep -q "pr merge 7" "$TMP_ATELIER/gh.log"
  grep -q "current_phase: 24" "$REPO_ROOT/projects/$TEST_PROJECT.yml"
  grep -q "git add projects/$TEST_PROJECT.yml" "$TMP_ATELIER/git.log"
  grep -q "git commit -m chore: bump current_phase → 24" "$TMP_ATELIER/git.log"
  grep -q "current_phase → 24(来自 PR #7)" "$STATE_DIR/audit.log"
}

@test "CHANGES escalates after max_review_iterations" {
  write_project "autonomy-review-limit"
  write_mock_git
  write_mock_codex
  write_mock_claude_changes
  write_mock_gh_changes
  echo 3 > "$STATE_DIR/review_iters_7"

  run bash "$ORCH" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  [ ! -f "$TMP_ATELIER/codex.stdin" ]
  grep -q "needs-human" "$TMP_ATELIER/gh.log"
}

@test "planning commits and pushes current_phase bump" {
  write_project "autonomy-planning" 23
  write_mock_git
  write_mock_codex
  write_mock_claude_planned
  write_mock_gh_idle

  run bash "$ORCH" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  grep -q "current_phase: 24" "$REPO_ROOT/projects/$TEST_PROJECT.yml"
  grep -q "git add projects/$TEST_PROJECT.yml" "$TMP_ATELIER/git.log"
  grep -q "git commit -m chore: bump current_phase → 24" "$TMP_ATELIER/git.log"
  grep -q "git push" "$TMP_ATELIER/git.log"
}

@test "planning records failure when current_phase bump cannot commit" {
  write_project "autonomy-planning-commit-fail" 23
  write_mock_git_commit_fails
  write_mock_codex
  write_mock_claude_planned
  write_mock_gh_idle

  run bash "$ORCH" "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  grep -q "current_phase: 24" "$REPO_ROOT/projects/$TEST_PROJECT.yml"
  grep -q "current_phase 提交/推送失败" "$STATE_DIR/audit.log"
  [ "$(cat "$STATE_DIR/consecutive_failures")" = "1" ]
}

@test "GitHub API failure stops before idle planning" {
  write_project "autonomy-gh-down" 23
  write_mock_git
  write_mock_codex
  write_mock_claude_planned
  write_mock_gh_api_down

  run bash "$ORCH" "$TEST_PROJECT"
  [ "$status" -eq 1 ]

  grep -q "GitHub API 不可用" "$STATE_DIR/audit.log"
  grep -q "current_phase: 23" "$REPO_ROOT/projects/$TEST_PROJECT.yml"
  [ ! -f "$TMP_ATELIER/claude.log" ]
  [ "$(cat "$STATE_DIR/consecutive_failures")" = "1" ]
}

@test "codex-runner cleans branch, prompts for lint, and gates draft PR on lint failure" {
  write_project "autonomy-runner"
  sed -i 's|lint_command: "true"|lint_command: "false"|' "$REPO_ROOT/projects/$TEST_PROJECT.yml"
  write_mock_git
  write_mock_codex
  write_mock_gh_runner

  run bash "$RUNNER"
  [ "$status" -eq 0 ]

  grep -q "git reset --hard HEAD" "$TMP_ATELIER/git.log"
  grep -q "git clean -fd" "$TMP_ATELIER/git.log"
  grep -q "lint 门禁 \`false\`" "$TMP_ATELIER/codex.args"
  grep -q "pr create" "$TMP_ATELIER/gh.log"
  grep -q -- "--draft" "$TMP_ATELIER/gh.log"
  grep -q "needs-human" "$TMP_ATELIER/gh.log"
}
