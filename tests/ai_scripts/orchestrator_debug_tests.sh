#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Assertion failed: expected file to exist: $path" >&2
    exit 1
  fi
}

assert_contains_file() {
  local path="$1"
  local needle="$2"
  if ! grep -q "$needle" "$path"; then
    echo "Assertion failed: expected file $path to contain: $needle" >&2
    cat "$path" >&2 || true
    exit 1
  fi
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Assertion failed: expected output to contain: $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/setup" "$repo_dir/ai/step_designs" \
    "$repo_dir/ai/step_plans" "$repo_dir/ai/step_review_results" "$repo_dir/ai/prompts"

  cp "$ORCH_SRC" "$repo_dir/ai/scripts/orchestrator.sh"
  chmod +x "$repo_dir/ai/scripts/orchestrator.sh"

  cat >"$repo_dir/ai/scripts/ai_design.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROMPT_MARKER=${PROMPT_MARKER:-default-design}"
EOF
  cat >"$repo_dir/ai/scripts/ai_plan.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROMPT_MARKER=${PROMPT_MARKER:-default-planning}"
EOF
  cat >"$repo_dir/ai/scripts/ai_implementation.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROMPT_MARKER=${PROMPT_MARKER:-default-implementation}"
EOF
  cat >"$repo_dir/ai/scripts/ai_user_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROMPT_MARKER=${PROMPT_MARKER:-default-user-review}"
EOF
  cat >"$repo_dir/ai/scripts/ai_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROMPT_MARKER=${PROMPT_MARKER:-default-review}"
EOF
  cat >"$repo_dir/ai/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post_review"
EOF
  cat >"$repo_dir/ai/scripts/fake_model.sh" <<'EOF'
#!/usr/bin/env bash
echo "MODEL_MARKER=${MODEL_MARKER:-default-model}"
echo "Token usage: input=1 output=1 total=2"
EOF
  chmod +x "$repo_dir/ai/scripts/ai_design.sh" "$repo_dir/ai/scripts/ai_plan.sh" \
    "$repo_dir/ai/scripts/ai_implementation.sh" "$repo_dir/ai/scripts/ai_user_review.sh" "$repo_dir/ai/scripts/ai_review.sh" \
    "$repo_dir/ai/scripts/post_review.sh" "$repo_dir/ai/scripts/fake_model.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
design | ai/scripts/fake_model.sh | mock-model
planning | ai/scripts/fake_model.sh | mock-model
implementation | ai/scripts/fake_model.sh | mock-model
user_review | ai/scripts/fake_model.sh | mock-model
review | ai/scripts/fake_model.sh | mock-model
EOF

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Target Bullets
- demo
## Plan (ordered)
- 1. demo
EOF
}

run_non_debug_design_writes_latest_only() {
  local repo_dir="$TMP_ROOT/repo-non-debug"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  (
    cd "$repo_dir"
    PROMPT_MARKER=first MODEL_MARKER=first ai/scripts/orchestrator.sh --phase design -- --step 1.1 >/tmp/orch-test.out 2>/tmp/orch-test.err
  )

  local latest_prompt="$repo_dir/ai/prompts/design_prompts/repo-non-debug-latest-design-prompt.txt"
  local latest_log="$repo_dir/ai/logs/repo-non-debug-design-latest-log"
  assert_file_exists "$latest_prompt"
  assert_file_exists "$latest_log"
  assert_contains_file "$latest_prompt" "PROMPT_MARKER=first"
  assert_contains_file "$latest_log" "MODEL_MARKER=first"
}

run_debug_design_writes_step_specific() {
  local repo_dir="$TMP_ROOT/repo-debug"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  (
    cd "$repo_dir"
    PROMPT_MARKER=debug MODEL_MARKER=debug ai/scripts/orchestrator.sh --debug --phase design -- --step 1.1 >/tmp/orch-test.out 2>/tmp/orch-test.err
  )

  local step_prompt="$repo_dir/ai/prompts/design_prompts/repo-debug-step-1.1.design.prompt.txt"
  local step_log="$repo_dir/ai/logs/repo-debug-design-1-1-log"
  assert_file_exists "$step_prompt"
  assert_file_exists "$step_log"
  assert_contains_file "$step_prompt" "PROMPT_MARKER=debug"
  assert_contains_file "$step_log" "MODEL_MARKER=debug"
}

run_latest_overwrite_and_legacy_preserved() {
  local repo_dir="$TMP_ROOT/repo-overwrite"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  (
    cd "$repo_dir"
    PROMPT_MARKER=seed MODEL_MARKER=seed ai/scripts/orchestrator.sh --debug --phase design -- --step 1.1 >/tmp/orch-test.out 2>/tmp/orch-test.err
  )

  local step_prompt="$repo_dir/ai/prompts/design_prompts/repo-overwrite-step-1.1.design.prompt.txt"
  local step_before
  step_before="$(cat "$step_prompt")"

  (
    cd "$repo_dir"
    PROMPT_MARKER=first MODEL_MARKER=first ai/scripts/orchestrator.sh --phase design -- --step 1.1 >/tmp/orch-test.out 2>/tmp/orch-test.err
    PROMPT_MARKER=second MODEL_MARKER=second ai/scripts/orchestrator.sh --phase design -- --step 1.1 >/tmp/orch-test.out 2>/tmp/orch-test.err
  )

  local latest_prompt="$repo_dir/ai/prompts/design_prompts/repo-overwrite-latest-design-prompt.txt"
  local latest_log="$repo_dir/ai/logs/repo-overwrite-design-latest-log"
  assert_file_exists "$latest_prompt"
  assert_file_exists "$latest_log"
  assert_contains_file "$latest_prompt" "PROMPT_MARKER=second"
  assert_contains_file "$latest_log" "MODEL_MARKER=second"

  local step_after
  step_after="$(cat "$step_prompt")"
  assert_equal "$step_before" "$step_after"
}

run_user_review_dry_run_reports_prompt_and_log_paths() {
  local repo_dir="$TMP_ROOT/repo-user-review-latest"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  local out
  out="$(
    cd "$repo_dir" &&
    PROMPT_MARKER=ur MODEL_MARKER=ur ai/scripts/orchestrator.sh --dry-run --phase user_review
  )"

  local latest_prompt="$repo_dir/ai/prompts/user_review_prompts/repo-user-review-latest-latest-user-review-prompt.txt"
  assert_contains "$out" "dry-run prompt: ai/prompts/user_review_prompts/repo-user-review-latest-latest-user-review-prompt.txt"
  assert_contains "$out" "dry-run log: ai/logs/repo-user-review-latest-user-review-latest-log"
  assert_contains "$out" "$latest_prompt"
}

run_source_includes_user_review_interactive_confirmation() {
  local repo_dir="$TMP_ROOT/repo-confirmation-check"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  local out
  out="$(grep -n "planning|implementation|user_review|review" "$repo_dir/ai/scripts/orchestrator.sh" || true)"
  assert_contains "$out" "planning|implementation|user_review|review"
}

run_non_debug_design_writes_latest_only
run_debug_design_writes_step_specific
run_latest_overwrite_and_legacy_preserved
run_user_review_dry_run_reports_prompt_and_log_paths
run_source_includes_user_review_interactive_confirmation

echo "All orchestrator debug tests passed."
