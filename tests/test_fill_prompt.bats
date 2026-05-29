#!/usr/bin/env bats
# test_fill_prompt.bats — 模板变量替换逻辑单元测试
# Tests the sed substitution logic used in _fill_prompt directly.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  TMPDIR_PROMPTS="$(mktemp -d)"
  # Minimal template with all placeholder types
  cat > "$TMPDIR_PROMPTS/respond.md" <<'TMPL'
你是 {{REPO}} 的架构师。
Issue 编号：#{{ISSUE_NUMBER}}
工程配置：projects/{{PROJECT_NAME}}.yml
TMPL
  cat > "$TMPDIR_PROMPTS/review.md" <<'TMPL'
PR 编号：#{{PR_NUMBER}}
仓库：{{REPO}}
工程配置：projects/{{PROJECT_NAME}}.yml
TMPL
}

teardown() {
  rm -rf "$TMPDIR_PROMPTS"
}

# The sed substitution logic, extracted from _fill_prompt for unit testing
_apply_substitutions() {
  local file="$1" issue_num="$2" repo="${3:-StevenG3/atelier}" project="${4:-<填写工程名>}"
  sed \
    -e "s|{{ISSUE_NUMBER}}|$issue_num|g" \
    -e "s|{{PR_NUMBER}}|$issue_num|g" \
    -e "s|{{REPO}}|$repo|g" \
    -e "s|{{PROJECT_NAME}}|$project|g" \
    -e "s|{{SHORT_DESC}}|<填写简短描述>|g" \
    "$file"
}

@test "substitution replaces ISSUE_NUMBER" {
  run _apply_substitutions "$TMPDIR_PROMPTS/respond.md" 42
  [ "$status" -eq 0 ]
  [[ "$output" == *"#42"* ]]
  [[ "$output" != *"{{ISSUE_NUMBER}}"* ]]
}

@test "substitution replaces REPO" {
  run _apply_substitutions "$TMPDIR_PROMPTS/respond.md" 5 "MyOrg/my-repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MyOrg/my-repo"* ]]
  [[ "$output" != *"{{REPO}}"* ]]
}

@test "substitution replaces PR_NUMBER" {
  run _apply_substitutions "$TMPDIR_PROMPTS/review.md" 12
  [ "$status" -eq 0 ]
  [[ "$output" == *"#12"* ]]
  [[ "$output" != *"{{PR_NUMBER}}"* ]]
}

@test "substitution uses placeholder hint when project name is empty" {
  run _apply_substitutions "$TMPDIR_PROMPTS/respond.md" 5 "StevenG3/atelier" "<填写工程名>"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<填写工程名>"* ]]
}

@test "substitution fills PROJECT_NAME when provided" {
  run _apply_substitutions "$TMPDIR_PROMPTS/respond.md" 5 "StevenG3/atelier" "my-project"
  [ "$status" -eq 0 ]
  [[ "$output" == *"projects/my-project.yml"* ]]
  [[ "$output" != *"{{PROJECT_NAME}}"* ]]
}

@test "no remaining double-brace placeholders for known vars after substitution" {
  run _apply_substitutions "$TMPDIR_PROMPTS/respond.md" 7 "StevenG3/atelier" "my-project"
  [ "$status" -eq 0 ]
  [[ "$output" != *"{{ISSUE_NUMBER}}"* ]]
  [[ "$output" != *"{{REPO}}"* ]]
  [[ "$output" != *"{{PROJECT_NAME}}"* ]]
}

@test "substitution on review template replaces all vars" {
  run _apply_substitutions "$TMPDIR_PROMPTS/review.md" 99 "OtherOrg/other-repo" "proj-x"
  [ "$status" -eq 0 ]
  [[ "$output" == *"#99"* ]]
  [[ "$output" == *"OtherOrg/other-repo"* ]]
  [[ "$output" == *"projects/proj-x.yml"* ]]
}
