#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"
USER_REVIEW_SRC="$SOURCE_ROOT/ai/scripts/ai_user_review.sh"

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

  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/setup" "$repo_dir/ai/step_designs" \
    "$repo_dir/ai/step_plans"

  cp "$ORCH_SRC" "$repo_dir/ai/scripts/orchestrator.sh"
  cp "$USER_REVIEW_SRC" "$repo_dir/ai/scripts/ai_user_review.sh"
  chmod +x "$repo_dir/ai/scripts/orchestrator.sh" "$repo_dir/ai/scripts/ai_user_review.sh"

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
design | ai/scripts/fake_model.sh | mock-model
planning | ai/scripts/fake_model.sh | mock-model
implementation | ai/scripts/fake_model.sh | mock-model
user_review | ai/scripts/fake_model.sh | mock-model
ai_audit | ai/scripts/fake_model.sh | mock-model
EOF

  local impl_box=" "
  if [[ "$impl_checked" == "1" ]]; then
    impl_box="x"
  fi

  cat >"$repo_dir/ai/implementation_plan.md" <<EOF
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
## Target Bullets
- Implement part A
## Plan (ordered)
$ordered_block
EOF

  cat >"$repo_dir/ai/step_designs/step-1.1-design.md" <<'EOF'
## Proposal / Design Details
- demo
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

  cat >"$repo_dir/reqirements_ears.md" <<'EOF'
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
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --phase user_review -- --step 1.1 2>&1)"
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
  assert_file_not_exists "$repo_dir/model-ran.flag"
}

test_user_review_normalizes_plain_ordered_bullets_to_unchecked() {
  local repo_dir="$TMP_ROOT/repo-normalize-plain-ordered"
  setup_repo "$repo_dir" 1 plain

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --phase user_review -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: plain ordered-plan bullets must be treated as unchecked and block user_review" >&2
    exit 1
  fi
  assert_contains "$out" "Unchecked ordered-plan items (normalized):"
  assert_contains "$out" "- [ ] 1. Implement part A."
  assert_file_not_exists "$repo_dir/model-ran.flag"
}

test_user_review_runs_model_when_ordered_plan_checked_even_if_impl_unchecked() {
  local repo_dir="$TMP_ROOT/repo-pass-ordered-checked"
  setup_repo "$repo_dir" 0 checked

  (
    cd "$repo_dir"
    ai/scripts/orchestrator.sh --phase user_review -- --step 1.1 >/tmp/user-review-tests.out 2>/tmp/user-review-tests.err
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
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --phase user_review -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: user_review must fail when branch handoff is unsafe" >&2
    exit 1
  fi
  assert_contains "$out" "User review branch must be created from step-1.1-implementation"
  assert_file_not_exists "$repo_dir/model-ran.flag"
}

test_user_review_fails_fast_when_ordered_plan_unchecked
test_user_review_normalizes_plain_ordered_bullets_to_unchecked
test_user_review_runs_model_when_ordered_plan_checked_even_if_impl_unchecked
test_user_review_branch_handoff_fails_on_unsafe_dirty_state

echo "All user review phase tests passed."
