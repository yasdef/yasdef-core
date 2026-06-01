#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_PHASE_CMD_SRC="$SOURCE_ROOT/ai/scripts/helpers/build_phase_cmd.sh"

. "$BUILD_PHASE_CMD_SRC"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed${msg:+ ($msg)}: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_array_equal() {
  local label="$1"
  shift
  local -a expected=()
  while [[ "$1" != "--" ]]; do
    expected+=("$1")
    shift
  done
  shift
  local -a actual=("$@")

  assert_equal "${#expected[@]}" "${#actual[@]}" "$label length"
  local i
  for ((i = 0; i < ${#expected[@]}; i++)); do
    assert_equal "${expected[$i]}" "${actual[$i]}" "$label[$i]"
  done
}

test_build_codex_cmd_with_extras() {
  MODEL_CMD="codex"
  MODEL_MODEL="gpt-5.5"
  MODEL_ARGS=(--config "model_reasoning_effort='high'")

  build_phase_cmd "SAMPLE PROMPT"

  assert_array_equal "codex_with_extras" \
    codex -m gpt-5.5 --config "model_reasoning_effort='high'" "SAMPLE PROMPT" \
    -- "${BUILD_PHASE_CMD[@]}"
}

test_build_codex_cmd_no_extras() {
  MODEL_CMD="codex"
  MODEL_MODEL="gpt-5.5"
  MODEL_ARGS=()

  build_phase_cmd "SAMPLE PROMPT"

  assert_array_equal "codex_no_extras" \
    codex -m gpt-5.5 "SAMPLE PROMPT" \
    -- "${BUILD_PHASE_CMD[@]}"
}

test_build_claude_cmd_minimal() {
  MODEL_CMD="claude"
  MODEL_MODEL="claude-opus-4-7"
  MODEL_ARGS=()

  build_phase_cmd "SAMPLE PROMPT"

  assert_array_equal "claude_minimal" \
    claude --model claude-opus-4-7 --permission-mode acceptEdits -p "SAMPLE PROMPT" \
    -- "${BUILD_PHASE_CMD[@]}"
}

test_build_claude_cmd_drops_extras() {
  MODEL_CMD="claude"
  MODEL_MODEL="claude-opus-4-7"
  MODEL_ARGS=(--config "model_reasoning_effort='high'")

  build_phase_cmd "SAMPLE PROMPT"

  assert_array_equal "claude_drops_extras" \
    claude --model claude-opus-4-7 --permission-mode acceptEdits -p "SAMPLE PROMPT" \
    -- "${BUILD_PHASE_CMD[@]}"
}

test_build_phase_cmd_non_claude_falls_back_to_codex_shape() {
  MODEL_CMD=".asdlc_worker/scripts/fake_model.sh"
  MODEL_MODEL="mock-model"
  MODEL_ARGS=()

  build_phase_cmd "SAMPLE PROMPT"

  assert_array_equal "non_claude_fallback" \
    .asdlc_worker/scripts/fake_model.sh -m mock-model "SAMPLE PROMPT" \
    -- "${BUILD_PHASE_CMD[@]}"
}

test_build_codex_cmd_with_extras
test_build_codex_cmd_no_extras
test_build_claude_cmd_minimal
test_build_claude_cmd_drops_extras
test_build_phase_cmd_non_claude_falls_back_to_codex_shape

echo "model_runner_tests: PASS"
