#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"
USER_REVIEW_SRC="$SOURCE_ROOT/ai/scripts/ai_user_review.sh"
IMPLEMENTATION_HELPER_SRC="$SOURCE_ROOT/ai/scripts/helpers/check_implementation_readiness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "Assertion failed: expected output to not contain: $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Assertion failed: expected file to exist: $path" >&2
    exit 1
  fi
}

assert_file_not_exists() {
  local path="$1"
  if [[ -f "$path" ]]; then
    echo "Assertion failed: expected file to not exist: $path" >&2
    exit 1
  fi
}

assert_branch_equals() {
  local repo_dir="$1"
  local expected="$2"
  local actual
  actual="$(git -C "$repo_dir" branch --show-current)"
  if [[ "$actual" != "$expected" ]]; then
    echo "Assertion failed: expected branch '$expected', got '$actual'" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"
  local impl_checked="$2"
  local ordered_mode="$3"

  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/scripts/helpers" "$repo_dir/ai/setup" "$repo_dir/ai/step_designs" \
    "$repo_dir/ai/step_plans" "$repo_dir/ai/step_review_results" "$repo_dir/overmind"

  cp "$ORCH_SRC" "$repo_dir/ai/scripts/orchestrator.sh"
  cp "$USER_REVIEW_SRC" "$repo_dir/ai/scripts/ai_user_review.sh"
  cp "$IMPLEMENTATION_HELPER_SRC" "$repo_dir/ai/scripts/helpers/check_implementation_readiness.sh"
  chmod +x "$repo_dir/ai/scripts/orchestrator.sh" "$repo_dir/ai/scripts/ai_user_review.sh" \
    "$repo_dir/ai/scripts/helpers/check_implementation_readiness.sh"

  cat >"$repo_dir/ai/scripts/ai_design.sh" <<'EOF'
#!/usr/bin/env bash
echo "design"
EOF
  cat >"$repo_dir/ai/scripts/ai_plan.sh" <<'EOF'
#!/usr/bin/env bash
echo "planning"
EOF
  cat >"$repo_dir/ai/scripts/ai_implementation.sh" <<'EOF'
#!/usr/bin/env bash
echo "implementation"
EOF
  cat >"$repo_dir/ai/scripts/ai_audit.sh" <<'EOF'
#!/usr/bin/env bash
echo "review"
EOF
  cat >"$repo_dir/ai/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post_review"
EOF
  cat >"$repo_dir/ai/scripts/fake_model.sh" <<EOF
#!/usr/bin/env bash
touch "$repo_dir/model-ran.flag"
echo "model-ran"
EOF
  chmod +x "$repo_dir/ai/scripts/ai_design.sh" "$repo_dir/ai/scripts/ai_plan.sh" \
    "$repo_dir/ai/scripts/ai_implementation.sh" "$repo_dir/ai/scripts/ai_audit.sh" \
    "$repo_dir/ai/scripts/post_review.sh" "$repo_dir/ai/scripts/fake_model.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
user_review | ai/scripts/fake_model.sh | mock-model
EOF

  local impl_box=" "
  if [[ "$impl_checked" == "1" ]]; then
    impl_box="x"
  fi

  cat >"$repo_dir/overmind/implementation_plan.md" <<EOF
### Step 1.1 Demo
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1)
- [$impl_box] Implement part A (SP=3)
- [ ] Review step implementation (SP=1)
EOF

  local ordered_block=""
  case "$ordered_mode" in
    checked)
      ordered_block='- [x] 1. Implement part A.'
      ;;
    unchecked)
      ordered_block='- [ ] 1. Implement part A.'
      ;;
    plain)
      ordered_block='- 1. Implement part A.'
      ;;
    missing)
      ordered_block=''
      ;;
    *)
      echo "Unknown ordered_mode: $ordered_mode" >&2
      exit 1
      ;;
  esac

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<EOF
# Step Plan: 1.1 - Demo
## Plan (ordered)
$ordered_block
## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 The system SHALL implement part A behavior. EARS[REQ-1]
EOF

  cat >"$repo_dir/ai/step_designs/step-1.1-design.md" <<'EOF'
## Proposal / Design Details
- demo
EOF

  cat >"$repo_dir/ai/step_review_results/review_result-1.1.md" <<'EOF'
# Review Result: Step 1.1
## Disposition (per issue)
- None.
EOF

  cat >"$repo_dir/ai/AI_DEVELOPMENT_PROCESS.md" <<'EOF'
### 5) User review (required before moving to the next step)
1. Ask user for feedback.
EOF

  cat >"$repo_dir/ai/blocker_log.md" <<'EOF'
## Step 1.1 Demo
- none
EOF

  cat >"$repo_dir/ai/open_questions.md" <<'EOF'
## Step 1.1 Demo
- none
EOF

  cat >"$repo_dir/ai/user_review.md" <<'EOF'
# User review rules
EOF

  cat >"$repo_dir/AGENTS.md" <<'EOF'
# AGENTS
EOF

  cat >"$repo_dir/overmind/reqirements_ears.md" <<'EOF'
### Requirement 1 Demo
- demo
EOF

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
    git checkout -qb step-1.1-implementation
  )
}

test_user_review_fails_fast_when_ordered_plan_unchecked() {
  local repo_dir="$TMP_ROOT/repo-fail-fast-ordered-unchecked"
  setup_repo "$repo_dir" 1 unchecked

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: user_review phase must fail when ordered-plan items are unchecked" >&2
    echo "$out" >&2
    exit 1
  fi
  assert_contains "$out" "User review precheck failed for step 1.1."
  assert_contains "$out" "Unchecked ordered-plan items (normalized):"
  assert_contains "$out" "- [ ] 1. Implement part A."
  assert_contains "$out" "Implementation was not finished correctly."
  assert_file_not_exists "$repo_dir/model-ran.flag"
}

test_user_review_normalizes_plain_ordered_bullets_to_unchecked() {
  local repo_dir="$TMP_ROOT/repo-normalize-plain-ordered"
  setup_repo "$repo_dir" 1 plain

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: plain ordered-plan bullets must be treated as unchecked and block user_review" >&2
    exit 1
  fi
  assert_contains "$out" "Unchecked ordered-plan items (normalized):"
  assert_contains "$out" "- [ ] 1. Implement part A."
  assert_contains "$out" "Implementation was not finished correctly."
  assert_file_not_exists "$repo_dir/model-ran.flag"
}

test_user_review_runs_model_when_ordered_plan_checked_even_if_impl_unchecked() {
  local repo_dir="$TMP_ROOT/repo-pass-ordered-checked"
  setup_repo "$repo_dir" 0 checked

  (
    cd "$repo_dir"
    ai/scripts/orchestrator.sh -- --step 1.1 >/tmp/user-review-tests.out 2>/tmp/user-review-tests.err
  )

  assert_file_exists "$repo_dir/model-ran.flag"
  assert_branch_equals "$repo_dir" "step-1.1-user-review"
}

test_user_review_branch_handoff_fails_on_unsafe_dirty_state() {
  local repo_dir="$TMP_ROOT/repo-unsafe-state"
  setup_repo "$repo_dir" 1 checked

  (
    cd "$repo_dir"
    git checkout -qb scratch-branch
    echo "# dirty" >>AGENTS.md
  )

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: user_review must fail when branch handoff is unsafe" >&2
    exit 1
  fi
  assert_contains "$out" "User review branch must be created from step-1.1-implementation"
  assert_file_not_exists "$repo_dir/model-ran.flag"
}

test_user_review_prompt_uses_ordered_plan_state_only() {
  local repo_dir="$TMP_ROOT/repo-user-review-prompt-ordered-only"
  setup_repo "$repo_dir" 0 checked

  (
    cd "$repo_dir"
    ai/scripts/ai_user_review.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/user_review_prompts/test.prompt.txt >/dev/null
  )

  local prompt
  prompt="$(cat "$repo_dir/ai/prompts/user_review_prompts/test.prompt.txt")"
  assert_contains "$prompt" 'Entry gate already verified by script: `ai/scripts/helpers/check_implementation_readiness.sh 1.1` passed.'
  assert_contains "$prompt" 'User review phase-state source is step plan `## Plan (ordered)` only.'
  assert_contains "$prompt" 'User review functional-requirement source is step plan `## Functional Requirements (translated from design EARS)`.'
  assert_not_contains "$prompt" "== overmind/implementation_plan.md"
  assert_not_contains "$prompt" 'User review checklist (`## Target Bullets`)'
}

test_user_review_fails_when_functional_requirements_unchecked() {
  local repo_dir="$TMP_ROOT/repo-functional-requirements-incomplete"
  setup_repo "$repo_dir" 1 checked

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. Implement part A.
## Functional Requirements (translated from design EARS)
- [ ] FR-1.1-001 The system SHALL implement part A behavior. EARS[REQ-1]
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: user_review phase must fail when translated functional requirements are unchecked" >&2
    exit 1
  fi
  assert_contains "$out" "User review precheck failed for step 1.1."
  assert_contains "$out" "All items in step plan '## Functional Requirements (translated from design EARS)' must be [x] before handing off implementation."
  assert_contains "$out" "Implementation was not finished correctly."
  assert_file_not_exists "$repo_dir/model-ran.flag"
}

test_user_review_does_not_block_on_invalid_user_review_update() {
  local repo_dir="$TMP_ROOT/repo-user-review-invalid-ur-allowed"
  setup_repo "$repo_dir" 1 checked

  cat >"$repo_dir/ai/scripts/fake_model.sh" <<'EOF'
#!/usr/bin/env bash
touch "model-ran.flag"
cat >>"ai/user_review.md" <<'UR'

- **ID**: UR-0002
- **Status**: Accepted
- **Date**: 2026-03-03
- **Context**: Test
- **Trigger**: Invalid update
- **Rule**: Missing required fields should fail.
- **Example(s)**: Missing How to verify and References.
UR
echo "model-ran"
EOF
  chmod +x "$repo_dir/ai/scripts/fake_model.sh"

  local status=0
  set +e
  (cd "$repo_dir" && ai/scripts/orchestrator.sh -- --step 1.1 >/tmp/user-review-invalid-ur.out 2>/tmp/user-review-invalid-ur.err)
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: user_review should not fail due to invalid ai/user_review.md content" >&2
    exit 1
  fi
  assert_file_exists "$repo_dir/model-ran.flag"
  assert_branch_equals "$repo_dir" "step-1.1-user-review"
}

test_user_review_fails_fast_when_ordered_plan_unchecked
test_user_review_normalizes_plain_ordered_bullets_to_unchecked
test_user_review_runs_model_when_ordered_plan_checked_even_if_impl_unchecked
test_user_review_branch_handoff_fails_on_unsafe_dirty_state
test_user_review_prompt_uses_ordered_plan_state_only
test_user_review_fails_when_functional_requirements_unchecked
test_user_review_does_not_block_on_invalid_user_review_update

echo "All user review phase tests passed."
