#!/usr/bin/env bats
# test_preflight.bats — preflight.sh 5 项依赖检查的单元测试

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PREFLIGHT="$REPO_ROOT/scripts/preflight.sh"

setup() {
  load helpers/mock_gh
  # preflight 使用 REPO 环境变量
  export REPO="StevenG3/atelier"
  export ATELIER_REPO="StevenG3/atelier"
}

teardown() {
  teardown_mock_gh
}

# ── 全绿路径 ──────────────────────────────────────────────────────────────

@test "preflight passes when all dependencies are satisfied" {
  setup_mock_gh
  run bash -c "source '$PREFLIGHT' && REPO=StevenG3/atelier run_preflight"
  [ "$status" -eq 0 ]
  [[ "$output" == *"所有依赖满足"* ]]
}

@test "preflight prints all 5 check items when passing" {
  setup_mock_gh
  run bash -c "source '$PREFLIGHT' && REPO=StevenG3/atelier run_preflight"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh CLI 已安装"* ]]
  [[ "$output" == *"GitHub 已认证"* ]]
  [[ "$output" == *"仓库可访问"* ]]
  [[ "$output" == *"所有必需标签存在"* ]]
  [[ "$output" == *"prompts/ 目录存在"* ]]
}

@test "preflight shows authenticated username" {
  setup_mock_gh
  run bash -c "source '$PREFLIGHT' && REPO=StevenG3/atelier run_preflight"
  [ "$status" -eq 0 ]
  [[ "$output" == *"testuser"* ]]
}

# ── gh 未安装 ─────────────────────────────────────────────────────────────

@test "preflight fails with clear message when gh not installed" {
  setup_mock_no_gh
  run bash -c "GH_CMD='$MOCK_GH_TMPDIR/nonexistent_gh' source '$PREFLIGHT' && REPO=StevenG3/atelier run_preflight"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh CLI 未安装"* ]]
}

@test "preflight shows install hint when gh missing" {
  setup_mock_no_gh
  run bash -c "GH_CMD='$MOCK_GH_TMPDIR/nonexistent_gh' source '$PREFLIGHT' && REPO=StevenG3/atelier run_preflight"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cli.github.com"* ]]
}

# ── 未认证 ────────────────────────────────────────────────────────────────

@test "preflight fails when not authenticated" {
  setup_mock_gh_unauthed
  run bash -c "source '$PREFLIGHT' && REPO=StevenG3/atelier run_preflight"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GitHub 未认证"* ]]
}

@test "preflight shows gh auth login hint when not authenticated" {
  setup_mock_gh_unauthed
  run bash -c "source '$PREFLIGHT' && REPO=StevenG3/atelier run_preflight"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh auth login"* ]]
}

# ── 标签缺失 ──────────────────────────────────────────────────────────────

@test "preflight fails when required labels are missing" {
  setup_mock_gh_missing_labels
  run bash -c "source '$PREFLIGHT' && REPO=StevenG3/atelier run_preflight"
  [ "$status" -eq 1 ]
  [[ "$output" == *"缺失标签"* ]]
}

@test "preflight lists specific missing labels" {
  setup_mock_gh_missing_labels
  run bash -c "source '$PREFLIGHT' && REPO=StevenG3/atelier run_preflight"
  [ "$status" -eq 1 ]
  # claude:design is in REQUIRED_LABELS but not in mock's 3-label response
  [[ "$output" == *"claude:design"* ]]
}

@test "preflight gives sync-labels.sh fix command for missing labels" {
  setup_mock_gh_missing_labels
  run bash -c "source '$PREFLIGHT' && REPO=StevenG3/atelier run_preflight"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sync-labels.sh"* ]]
}

# ── 所有失败项一次显示 ────────────────────────────────────────────────────

@test "preflight shows failure summary line on any failure" {
  setup_mock_gh_missing_labels
  run bash -c "source '$PREFLIGHT' && REPO=StevenG3/atelier run_preflight"
  [ "$status" -eq 1 ]
  [[ "$output" == *"检查未通过"* ]]
}
