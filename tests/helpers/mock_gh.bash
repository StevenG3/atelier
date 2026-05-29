#!/usr/bin/env bash
# helpers/mock_gh.sh — 可配置的 gh mock 工厂
#
# 在 bats setup() 里调用：
#   load helpers/mock_gh
#   setup_mock_gh            # 创建默认的全绿 mock
#   setup_mock_gh_unauthed   # 模拟未登录状态
#   setup_mock_gh_no_labels  # 模拟标签缺失

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOCK_GH_TMPDIR=""

# 默认：全部依赖满足，所有 9 个标签存在，无待处理任务
setup_mock_gh() {
  MOCK_GH_TMPDIR="$(mktemp -d)"
  export GH_CMD="$MOCK_GH_TMPDIR/gh"
  export PATH="$MOCK_GH_TMPDIR:$PATH"
  cat > "$MOCK_GH_TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in
  "--version")
    echo "gh version 2.49.0 (2024-01-01)"
    ;;
  "auth status"*)
    echo "  ✓ Logged in to github.com as testuser (/home/user/.config/gh/hosts.yml)"
    ;;
  "repo view"*"--json name"*)
    echo '{"name":"atelier"}'
    ;;
  "api repos/"*"/labels?per_page=100"*)
    printf '%s\n' \
      "claude:design" "claude:spec-ready" "claude:review" \
      "codex:implement" "codex:go" \
      "needs-response" "needs-human" "on-hold" "blocked"
    ;;
  "api repos/"*"/labels/"*)
    # 存在性检查 — 默认返回成功（标签存在）
    echo '{"name":"label","color":"abcdef"}'
    ;;
  "issue list"*"needs-response"*)
    # 无待处理任务
    echo ""
    ;;
  "issue list"*"claude:review"*)
    echo ""
    ;;
  "issue list"*"claude:design"*)
    echo ""
    ;;
  "pr list"*"claude:review"*)
    echo ""
    ;;
  *)
    echo "MOCK_GH_UNHANDLED: $args" >&2
    exit 1
    ;;
esac
SH
  chmod +x "$MOCK_GH_TMPDIR/gh"
  export PATH="$MOCK_GH_TMPDIR:$PATH"
  export MOCK_GH_TMPDIR
}

# 模拟 gh 未安装（GH_CMD 指向不存在的路径）
setup_mock_no_gh() {
  MOCK_GH_TMPDIR="$(mktemp -d)"
  export MOCK_GH_TMPDIR
  # GH_CMD 指向不存在的路径 → command -v "$GH_CMD" 失败
  export GH_CMD="$MOCK_GH_TMPDIR/nonexistent_gh"
}

# 模拟 gh 已安装但未认证
setup_mock_gh_unauthed() {
  setup_mock_gh
  cat > "$MOCK_GH_TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in
  "--version") echo "gh version 2.49.0 (2024-01-01)" ;;
  "auth status"*)
    echo "You are not logged in to any GitHub hosts." >&2
    exit 1
    ;;
  *) echo "MOCK_GH_UNHANDLED: $args" >&2; exit 1 ;;
esac
SH
  chmod +x "$MOCK_GH_TMPDIR/gh"
}

# 模拟标签缺失
setup_mock_gh_missing_labels() {
  setup_mock_gh
  cat > "$MOCK_GH_TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in
  "--version") echo "gh version 2.49.0 (2024-01-01)" ;;
  "auth status"*)
    echo "  ✓ Logged in to github.com as testuser (/home/user/.config/gh/hosts.yml)"
    ;;
  "repo view"*"--json name"*) echo '{"name":"atelier"}' ;;
  "api repos/"*"/labels?per_page=100"*)
    # 只返回 3 个标签，缺少 6 个
    printf '%s\n' "bug" "documentation" "duplicate"
    ;;
  *) echo "MOCK_GH_UNHANDLED: $args" >&2; exit 1 ;;
esac
SH
  chmod +x "$MOCK_GH_TMPDIR/gh"
}

# 模拟有待处理任务
setup_mock_gh_with_pending() {
  setup_mock_gh
  cat > "$MOCK_GH_TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in
  "--version") echo "gh version 2.49.0 (2024-01-01)" ;;
  "auth status"*)
    echo "  ✓ Logged in to github.com as testuser (/home/user/.config/gh/hosts.yml)"
    ;;
  "repo view"*"--json name"*) echo '{"name":"atelier"}' ;;
  "api repos/"*"/labels?per_page=100"*)
    printf '%s\n' \
      "claude:design" "claude:spec-ready" "claude:review" \
      "codex:implement" "codex:go" \
      "needs-response" "needs-human" "on-hold" "blocked"
    ;;
  "issue list"*"needs-response"*)
    echo "5|Phase 24 implementation|https://github.com/test/repo/issues/5"
    ;;
  "issue list"*"claude:review"*)
    echo "12|PR: add endpoint|https://github.com/test/repo/pull/12"
    ;;
  "issue list"*"claude:design"*)
    echo "8|Phase 25 planning|https://github.com/test/repo/issues/8"
    ;;
  "pr list"*) echo "" ;;
  *) echo "MOCK_GH_UNHANDLED: $args" >&2; exit 1 ;;
esac
SH
  chmod +x "$MOCK_GH_TMPDIR/gh"
}

teardown_mock_gh() {
  [[ -n "$MOCK_GH_TMPDIR" ]] && rm -rf "$MOCK_GH_TMPDIR"
}
