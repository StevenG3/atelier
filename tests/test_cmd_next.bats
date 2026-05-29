#!/usr/bin/env bats
# test_cmd_next.bats — cmd_next 优先级路由逻辑单元测试

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
ATELIER_SH="$REPO_ROOT/scripts/atelier.sh"

setup() {
  load helpers/mock_gh
  export REPO="StevenG3/atelier"
  export ATELIER_REPO="StevenG3/atelier"
}

teardown() {
  teardown_mock_gh
}

# ── 无待处理项 ────────────────────────────────────────────────────────────

@test "next prints no-pending message when nothing to do" {
  setup_mock_gh  # default mock: all queues empty
  run bash /home/gggqqy/archives/atelier/scripts/atelier.sh next
  [ "$status" -eq 0 ]
  [[ "$output" == *"无待处理项"* ]]
}

# ── 优先级路由 ─────────────────────────────────────────────────────────────

@test "next picks needs-response over claude:review" {
  setup_mock_gh_with_pending
  run bash /home/gggqqy/archives/atelier/scripts/atelier.sh next
  [ "$status" -eq 0 ]
  # Should mention Issue #5 (needs-response) not PR #12 (claude:review)
  [[ "$output" == *"needs-response"* || "$output" == *"respond"* ]]
  # The highest-priority item (#5) should appear before review
  [[ "$output" == *"5"* ]]
}

@test "next picks claude:review when no needs-response" {
  setup_mock_gh
  # Override: has review but no needs-response
  cat > "$MOCK_GH_TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in
  "--version") echo "gh version 2.49.0" ;;
  "auth status"*) echo "  ✓ Logged in to github.com as testuser" ;;
  "repo view"*"--json name"*) echo '{"name":"atelier"}' ;;
  "api repos/"*"/labels?per_page=100"*)
    printf '%s\n' "claude:design" "claude:spec-ready" "claude:review" \
      "codex:implement" "codex:go" "needs-response" "needs-human" "on-hold" "blocked"
    ;;
  "issue list"*"needs-response"*) echo "" ;;
  "pr list"*"claude:review"*)
    echo "12|PR: add endpoint|https://github.com/test/repo/pull/12"
    ;;
  "issue list"*"claude:design"*) echo "" ;;
  "issue list"*) echo "" ;;
  "pr list"*) echo "" ;;
  *) echo "UNHANDLED: $args" >&2; exit 1 ;;
esac
SH
  chmod +x "$MOCK_GH_TMPDIR/gh"

  run bash /home/gggqqy/archives/atelier/scripts/atelier.sh next
  [ "$status" -eq 0 ]
  [[ "$output" == *"12"* || "$output" == *"review"* ]]
}

@test "next picks claude:design when no higher priority pending" {
  setup_mock_gh
  # Override: only design pending
  cat > "$MOCK_GH_TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in
  "--version") echo "gh version 2.49.0" ;;
  "auth status"*) echo "  ✓ Logged in to github.com as testuser" ;;
  "repo view"*"--json name"*) echo '{"name":"atelier"}' ;;
  "api repos/"*"/labels?per_page=100"*)
    printf '%s\n' "claude:design" "claude:spec-ready" "claude:review" \
      "codex:implement" "codex:go" "needs-response" "needs-human" "on-hold" "blocked"
    ;;
  "issue list"*"needs-response"*) echo "" ;;
  "pr list"*"claude:review"*) echo "" ;;
  "issue list"*"claude:design"*)
    echo "8|Phase 25 planning|https://github.com/test/repo/issues/8"
    ;;
  "issue list"*) echo "" ;;
  "pr list"*) echo "" ;;
  "issue view"*"--json number"*)
    echo "8" ;;
  *) echo "UNHANDLED: $args" >&2; exit 1 ;;
esac
SH
  chmod +x "$MOCK_GH_TMPDIR/gh"

  run bash /home/gggqqy/archives/atelier/scripts/atelier.sh next
  [ "$status" -eq 0 ]
  [[ "$output" == *"8"* || "$output" == *"design"* ]]
}

# ── 命令路由 ──────────────────────────────────────────────────────────────

@test "status command completes successfully with no pending items" {
  setup_mock_gh
  run bash /home/gggqqy/archives/atelier/scripts/atelier.sh status
  [ "$status" -eq 0 ]
  [[ "$output" == *"atelier"* ]]
}

@test "go command adds codex:go label" {
  setup_mock_gh
  # Override gh to capture the label edit call
  cat > "$MOCK_GH_TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in
  "--version") echo "gh version 2.49.0" ;;
  "auth status"*) echo "  ✓ Logged in to github.com as testuser" ;;
  "repo view"*"--json name"*) echo '{"name":"atelier"}' ;;
  "api repos/"*"/labels?per_page=100"*)
    printf '%s\n' "claude:design" "claude:spec-ready" "claude:review" \
      "codex:implement" "codex:go" "needs-response" "needs-human" "on-hold" "blocked"
    ;;
  "issue edit"*"--add-label"*"codex:go"*)
    echo "LABEL_ADDED"
    ;;
  *) echo "UNHANDLED: $args" >&2; exit 1 ;;
esac
SH
  chmod +x "$MOCK_GH_TMPDIR/gh"

  run bash /home/gggqqy/archives/atelier/scripts/atelier.sh go 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex:go"* ]]
}

@test "help command skips preflight and shows usage" {
  # help should NOT require gh to be available
  setup_mock_no_gh
  run bash /home/gggqqy/archives/atelier/scripts/atelier.sh help
  [ "$status" -eq 0 ]
  [[ "$output" == *"status"* ]]
  [[ "$output" == *"next"* ]]
  [[ "$output" == *"prompt"* ]]
}
