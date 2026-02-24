#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"

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

assert_not_equal() {
  local a="$1"
  local b="$2"
  if [[ "$a" == "$b" ]]; then
    echo "Assertion failed: values must differ" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/setup" "$repo_dir/ai/step_designs" \
    "$repo_dir/ai/step_plans" "$repo_dir/ai/step_review_results"

  cp "$ORCH_SRC" "$repo_dir/ai/scripts/orchestrator.sh"
  chmod +x "$repo_dir/ai/scripts/orchestrator.sh"

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
  cat >"$repo_dir/ai/scripts/ai_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "review"
EOF
  cat >"$repo_dir/ai/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post_review"
EOF
  chmod +x "$repo_dir/ai/scripts/ai_design.sh" "$repo_dir/ai/scripts/ai_plan.sh" \
    "$repo_dir/ai/scripts/ai_implementation.sh" "$repo_dir/ai/scripts/ai_review.sh" \
    "$repo_dir/ai/scripts/post_review.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
design | echo | mock-model
planning | echo | mock-model
implementation | echo | mock-model
review | echo | mock-model
EOF
}

write_design_and_plan_artifacts() {
  local repo_dir="$1"
  local step="$2"
  cat >"$repo_dir/ai/step_designs/step-$step-design.md" <<'EOF'
## Goal
test
## In Scope
test
## Out of Scope
test
EOF
  cat >"$repo_dir/ai/step_plans/step-$step.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Target Bullets
- demo
## Plan (ordered)
- 1. demo
EOF
}

write_impl_plan() {
  local repo_dir="$1"
  local plan_checked="$2"
  local impl_a_checked="$3"
  local impl_b_checked="$4"
  local review_checked="$5"
  local gate_prefix="${6:-}"

  local plan_box=" "
  local impl_a_box=" "
  local impl_b_box=" "
  local review_box=" "

  [[ "$plan_checked" == "1" ]] && plan_box="x"
  [[ "$impl_a_checked" == "1" ]] && impl_a_box="x"
  [[ "$impl_b_checked" == "1" ]] && impl_b_box="x"
  [[ "$review_checked" == "1" ]] && review_box="x"

  cat >"$repo_dir/ai/implementation_plan.md" <<EOF
### Step 1.1 Demo
Est. step total: 5 SP
- [$plan_box] ${gate_prefix}Plan and discuss the step (SP=1)
- [$impl_a_box] Implement part A (SP=2)
- [$impl_b_box] Implement part B (SP=1)
- [$review_box] ${gate_prefix}Review step implementation (SP=1)
EOF
}

test_resume_starts_at_planning() {
  local repo_dir="$TMP_ROOT/repo-planning"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 0 0 0 0

  local out
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "Selected start phase: planning"
  assert_contains "$out" "Executed phases: planning implementation review post_review"
}

test_partial_markers_rerun_implementation() {
  local repo_dir="$TMP_ROOT/repo-implementation"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 0 0

  local out
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "implementation: invalid (partial implementation markers (1/2 checked))"
  assert_contains "$out" "Selected start phase: implementation"
}

test_resume_starts_at_review() {
  local repo_dir="$TMP_ROOT/repo-review"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0

  local out
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "review: incomplete (missing ai/step_review_results/review_result-1.1.md)"
  assert_contains "$out" "Selected start phase: review"
  assert_contains "$out" "Executed phases: review post_review"
}

test_resume_starts_at_review_with_prefixed_gates() {
  local repo_dir="$TMP_ROOT/repo-review-prefixed-gates"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0 "[REQ-1] "

  local out
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "review: incomplete (missing ai/step_review_results/review_result-1.1.md)"
  assert_contains "$out" "Selected start phase: review"
  assert_contains "$out" "Executed phases: review post_review"
}

test_cli_validation() {
  local repo_dir="$TMP_ROOT/repo-cli-validation"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_impl_plan "$repo_dir" 0 0 0 0

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --resume 1.1 --phase review --dry-run 2>&1)"
  status=$?
  set -e
  assert_not_equal "$status" "0"
  assert_contains "$out" "--resume cannot be combined with explicit --phase"
}

test_missing_step_error() {
  local repo_dir="$TMP_ROOT/repo-missing-step"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_impl_plan "$repo_dir" 0 0 0 0

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --resume 9.9 --dry-run 2>&1)"
  status=$?
  set -e
  assert_not_equal "$status" "0"
  assert_contains "$out" "Unknown step '9.9'"
}

test_dry_run_is_deterministic() {
  local repo_dir="$TMP_ROOT/repo-deterministic"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0

  local out1 out2
  out1="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  out2="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  if [[ "$out1" != "$out2" ]]; then
    echo "Assertion failed: dry-run output must be deterministic for unchanged repo state" >&2
    echo "Output 1:" >&2
    echo "$out1" >&2
    echo "Output 2:" >&2
    echo "$out2" >&2
    exit 1
  fi
}

test_resume_does_not_require_evidence_before_review() {
  local repo_dir="$TMP_ROOT/repo-no-evidence-required"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0

  local out
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "implementation: complete (all implementation bullets are [x])"
  assert_contains "$out" "Selected start phase: review"
  assert_contains "$out" "Executed phases: review post_review"
}

test_resume_starts_at_planning
test_partial_markers_rerun_implementation
test_resume_starts_at_review
test_resume_starts_at_review_with_prefixed_gates
test_resume_does_not_require_evidence_before_review
test_cli_validation
test_missing_step_error
test_dry_run_is_deterministic

echo "All orchestrator resume tests passed."
