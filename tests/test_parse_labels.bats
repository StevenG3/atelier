#!/usr/bin/env bats
# test_parse_labels.bats — sync-labels.sh 的 awk YAML 解析逻辑单元测试

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SYNC_SH="$REPO_ROOT/scripts/sync-labels.sh"
LABELS_YML="$REPO_ROOT/.github/labels.yml"

# The awk parse function, inlined for direct testing
PARSE_AWK='
/^- name:/ {
  if (name != "") print name "|" color "|" desc
  name = $0; sub(/^- name: *"?/, "", name); sub(/"? *$/, "", name)
  color = ""; desc = ""
}
/^  color:/ {
  color = $0; sub(/^  color: *"?/, "", color); sub(/"? *$/, "", color)
}
/^  description:/ {
  desc = $0; sub(/^  description: *"?/, "", desc); sub(/"? *$/, "", desc)
}
END { if (name != "") print name "|" color "|" desc }
'

setup() {
  TMPDIR_LABELS="$(mktemp -d)"
  cat > "$TMPDIR_LABELS/labels.yml" <<'YAML'
- name: "claude:design"
  color: "8B5CF6"
  description: "需要 Claude 出规格 / 拆解"

- name: "codex:go"
  color: "22C55E"
  description: "起停开关"

- name: "needs-response"
  color: "F97316"
  description: "Codex 等待 Claude 回复"
YAML
}

teardown() {
  rm -rf "$TMPDIR_LABELS"
}

@test "parse_labels extracts label names" {
  run awk "$PARSE_AWK" "$TMPDIR_LABELS/labels.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude:design"* ]]
  [[ "$output" == *"codex:go"* ]]
  [[ "$output" == *"needs-response"* ]]
}

@test "parse_labels produces pipe-separated output (name|color|desc)" {
  run awk "$PARSE_AWK" "$TMPDIR_LABELS/labels.yml"
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    pipe_count=$(echo "$line" | tr -cd '|' | wc -c)
    [ "$pipe_count" -ge 2 ]
  done <<< "$output"
}

@test "parse_labels strips quotes from label name" {
  run awk "$PARSE_AWK" "$TMPDIR_LABELS/labels.yml"
  [ "$status" -eq 0 ]
  # Should not contain literal double-quote in names
  [[ "$output" != *'"claude:design"'* ]]
  [[ "$output" == *"claude:design"* ]]
}

@test "parse_labels extracts hex color value" {
  run awk "$PARSE_AWK" "$TMPDIR_LABELS/labels.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"8B5CF6"* ]]
}

@test "parse_labels returns correct number of entries" {
  run awk "$PARSE_AWK" "$TMPDIR_LABELS/labels.yml"
  [ "$status" -eq 0 ]
  line_count=$(echo "$output" | grep -c '|' || true)
  [ "$line_count" -eq 3 ]
}

@test "parse_labels handles all 9 required labels in real labels.yml" {
  run awk "$PARSE_AWK" "$LABELS_YML"
  [ "$status" -eq 0 ]
  required=(
    "claude:design" "claude:spec-ready" "claude:review"
    "codex:implement" "codex:go"
    "needs-response" "needs-human" "on-hold" "blocked"
  )
  for label in "${required[@]}"; do
    [[ "$output" == *"$label"* ]] || {
      echo "Missing label in parse output: $label" >&2
      return 1
    }
  done
}

@test "parse_labels handles label with no description" {
  cat > "$TMPDIR_LABELS/nodesc.yml" <<'YAML'
- name: "simple"
  color: "AABBCC"
YAML
  run awk "$PARSE_AWK" "$TMPDIR_LABELS/nodesc.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"simple"* ]]
  [[ "$output" == *"AABBCC"* ]]
}
