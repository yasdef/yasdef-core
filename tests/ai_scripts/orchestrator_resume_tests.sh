#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
WORKER_UUID_DEFAULT="11111111-1111-1111-1111-111111111111"
PROJECT_ID_DEFAULT="project-resume"
FEATURE_ID_DEFAULT="feature-resume"

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

assert_not_equal() {
  local a="$1"
  local b="$2"
  if [[ "$a" == "$b" ]]; then
    echo "Assertion failed: values must differ" >&2
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

assert_file_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "Assertion failed: expected file $file to contain: $needle" >&2
    echo "Actual file content:" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_file_not_exists() {
  local file="$1"
  if [[ -e "$file" ]]; then
    echo "Assertion failed: expected file to be absent: $file" >&2
    exit 1
  fi
}

source_root_for_repo() {
  local repo_dir="$1"
  printf '%s' "${repo_dir}-source"
}

feature_dir_for_repo() {
  local repo_dir="$1"
  printf '%s/%s' "$(source_root_for_repo "$repo_dir")" "$FEATURE_ID_DEFAULT"
}

setup_repo() {
  local repo_dir="$1"
  local source_dir=""
  local feature_dir=""
  local remote_dir="${repo_dir}-remote.git"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/setup" "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/step_review_results" "$repo_dir/.asdlc_worker/overmind"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"

  cp "$ORCH_SRC" "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  chmod +x "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"

  cat >"$repo_dir/.asdlc_worker/scripts/ai_design.sh" <<'EOF'
#!/usr/bin/env bash
echo "design"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_plan.sh" <<'EOF'
#!/usr/bin/env bash
echo "planning"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_implementation.sh" <<'EOF'
#!/usr/bin/env bash
echo "implementation"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_user_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "user_review"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_audit.sh" <<'EOF'
#!/usr/bin/env bash
echo "review"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post_review"
EOF
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_design.sh" "$repo_dir/.asdlc_worker/scripts/ai_plan.sh" \
    "$repo_dir/.asdlc_worker/scripts/ai_implementation.sh" "$repo_dir/.asdlc_worker/scripts/ai_user_review.sh" "$repo_dir/.asdlc_worker/scripts/ai_audit.sh" \
    "$repo_dir/.asdlc_worker/scripts/post_review.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
design | echo | mock-model
planning | echo | mock-model
implementation | echo | mock-model
user_review | echo | mock-model
ai_audit | echo | mock-model
EOF

  source_dir="$(source_root_for_repo "$repo_dir")"
  feature_dir="$(feature_dir_for_repo "$repo_dir")"
  local source_remote_dir="${source_dir}-remote.git"
  mkdir -p "$source_dir" "$feature_dir"
  cat >"$source_dir/workers.yaml" <<EOF
workers:
  - uuid: "$WORKER_UUID_DEFAULT"
    class: "platform"
    status: "ready"
EOF
  cat >"$source_dir/init_progress_definition.yaml" <<EOF
meta_info:
  project_id: '$PROJECT_ID_DEFAULT'
steps: []
EOF
  cat >"$feature_dir/implementation_plan.md" <<EOF
### Step 1.1 Demo
#### Assigned: $WORKER_UUID_DEFAULT
- [ ] Plan and discuss the step (SP=1)
- [ ] Implement part A (SP=2)
- [ ] Implement part B (SP=1)
- [ ] Review step implementation (SP=1)
EOF
  cat >"$feature_dir/requirements_ears.md" <<'EOF'
### Requirement 1 Demo
- The system SHALL support demo behavior.
EOF
  cat >"$repo_dir/ai/project_overmind.yaml" <<EOF
overmind_source_path: '$source_dir'
project_id: '$PROJECT_ID_DEFAULT'
worker_uuid: '$WORKER_UUID_DEFAULT'
class: 'platform'
status: 'ready'
EOF

  (
    cd "$source_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed source"
    git init -q --bare "$source_remote_dir"
    git remote add origin "$source_remote_dir"
    git push -q -u origin master
  )

  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
    git init -q --bare "$remote_dir"
    git --git-dir "$remote_dir" symbolic-ref HEAD refs/heads/master
    git remote add origin "$remote_dir"
    git push -q -u origin master
  )
}

create_user_review_branch_marker() {
  local repo_dir="$1"
  local step="$2"
  (
    cd "$repo_dir"
    git branch "step-$step-$FEATURE_ID_DEFAULT-user-review"
  )
}

create_implementation_branch_marker() {
  local repo_dir="$1"
  local step="$2"
  (
    cd "$repo_dir"
    git branch "step-$step-$FEATURE_ID_DEFAULT-implementation"
  )
}

write_design_and_plan_artifacts() {
  local repo_dir="$1"
  local step="$2"
  local ordered_mode="${3:-all_checked}"
  local design_mode="${4:-complete}"

  local ordered_block=""
  local include_ordered_section=1
  local functional_block='### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL complete demo A.
- Plan Links: 1
- Verification: demo
- Status: done
### FR-1.1-02
- Source EARS Block: REQ-1
- Requirement: The system SHALL complete demo B.
- Plan Links: 2
- Verification: demo
- Status: done'
  case "$ordered_mode" in
    all_checked)
      ordered_block='- [x] 1. demo A
- [x] 2. demo B'
      ;;
    partial)
      ordered_block='- [x] 1. demo A
- [ ] 2. demo B'
      ;;
    all_unchecked)
      ordered_block='- [ ] 1. demo A
- [ ] 2. demo B'
      ;;
    no_checklist_items)
      ordered_block='No checklist bullets yet.'
      ;;
    missing_section)
      include_ordered_section=0
      ;;
    *)
      echo "Unknown ordered_mode: $ordered_mode" >&2
      exit 1
      ;;
  esac

  case "$design_mode" in
    complete)
      cat >"$repo_dir/.asdlc_worker/step_designs/step-$step-$FEATURE_ID_DEFAULT-design.md" <<'EOF'
## Goal
test
## In Scope
test
## Out of Scope
test
EOF
      ;;
    missing_sections)
      cat >"$repo_dir/.asdlc_worker/step_designs/step-$step-$FEATURE_ID_DEFAULT-design.md" <<'EOF'
## Goal
test
EOF
      ;;
    *)
      echo "Unknown design_mode: $design_mode" >&2
      exit 1
      ;;
  esac
  if [[ "$include_ordered_section" -eq 1 ]]; then
    cat >"$repo_dir/.asdlc_worker/step_plans/step-$step-$FEATURE_ID_DEFAULT.md" <<EOF
# Step Plan: 1.1 - Demo
## Plan (ordered)
$ordered_block
## Functional Requirements (translated from design EARS)
$functional_block
EOF
  else
    cat >"$repo_dir/.asdlc_worker/step_plans/step-$step-$FEATURE_ID_DEFAULT.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL complete demo A.
- Plan Links: 1
- Verification: demo
- Status: done
EOF
  fi
}

write_impl_plan() {
  local repo_dir="$1"
  local plan_checked="$2"
  local impl_a_checked="$3"
  local impl_b_checked="$4"
  local review_checked="$5"
  local gate_prefix="${6:-}"
  local feature_dir=""

  local plan_box=" "
  local impl_a_box=" "
  local impl_b_box=" "
  local review_box=" "

  [[ "$plan_checked" == "1" ]] && plan_box="x"
  [[ "$impl_a_checked" == "1" ]] && impl_a_box="x"
  [[ "$impl_b_checked" == "1" ]] && impl_b_box="x"
  [[ "$review_checked" == "1" ]] && review_box="x"

  local source_dir=""
  source_dir="$(source_root_for_repo "$repo_dir")"
  feature_dir="$(feature_dir_for_repo "$repo_dir")"
  cat >"$feature_dir/implementation_plan.md" <<EOF
### Step 1.1 Demo
#### Assigned: $WORKER_UUID_DEFAULT
Est. step total: 5 SP
- [$plan_box] ${gate_prefix}Plan and discuss the step (SP=1)
- [$impl_a_box] Implement part A (SP=2)
- [$impl_b_box] Implement part B (SP=1)
- [$review_box] ${gate_prefix}Review step implementation (SP=1)
EOF
  (
    cd "$source_dir"
    git add "$feature_dir/implementation_plan.md"
    git commit -qm "update impl plan"
    git push -q origin master
  )
}

write_feature_meta_sync() {
  local repo_dir="$1"
  local feature_id="$2"
  local selected_step="$3"

  cat >"$repo_dir/.asdlc_worker/feature_meta_sync.yaml" <<EOF
project_id: '$PROJECT_ID_DEFAULT'
worker_uuid: '$WORKER_UUID_DEFAULT'
feature_id: '$feature_id'
selected_step: '$selected_step'
EOF
}

write_review_result() {
  local repo_dir="$1"
  local step="$2"
  local mode="$3"

  mkdir -p "$repo_dir/ai/step_review_results"
  case "$mode" in
    missing_disposition)
      cat >"$repo_dir/.asdlc_worker/step_review_results/review_result-$step-$FEATURE_ID_DEFAULT.md" <<'EOF'
## Critical
- Missing null validation on review handoff.

## High
- (none)
EOF
      ;;
    insufficient_dispositions)
      cat >"$repo_dir/.asdlc_worker/step_review_results/review_result-$step-$FEATURE_ID_DEFAULT.md" <<'EOF'
## Critical
- Missing null validation on review handoff.

## High
- Cleanup path is not documented.

## Medium
- (none)

## Low
- (none)

## Disposition (per issue)
- **Accepted**: Track the validation gap in follow-up work.
EOF
      ;;
    complete)
      cat >"$repo_dir/.asdlc_worker/step_review_results/review_result-$step-$FEATURE_ID_DEFAULT.md" <<'EOF'
## Critical
- Missing null validation on review handoff.

## High
- Cleanup path is not documented.

## Medium
- (none)

## Low
- (none)

## Disposition (per issue)
- **Accepted**: Track the validation gap in follow-up work.
- **Rejected**: Cleanup note is informational and does not require action.
EOF
      ;;
    *)
      echo "Unknown review result mode: $mode" >&2
      exit 1
      ;;
  esac
}

test_resume_starts_at_planning() {
  local repo_dir="$TMP_ROOT/repo-planning"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 0 0 0 0

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "Selected start phase: planning"
  assert_contains "$out" "Executed phases: planning implementation user_review ai_audit post_review"
}

test_resume_starts_at_planning_when_design_sections_missing() {
  local repo_dir="$TMP_ROOT/repo-planning-missing-design-sections"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1" "all_checked" "missing_sections"
  write_impl_plan "$repo_dir" 0 0 0 0

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "design: complete (design artifact present)"
  assert_contains "$out" "Selected start phase: planning"
  assert_not_contains "$out" "missing required sections"
}

test_resume_starts_at_planning_when_step_plan_missing() {
  local repo_dir="$TMP_ROOT/repo-planning-missing-step-plan"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-$FEATURE_ID_DEFAULT-design.md" <<'EOF'
## Goal
test
## In Scope
test
## Out of Scope
test
EOF
  write_impl_plan "$repo_dir" 0 0 0 0

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run 2>&1)"
  status=$?
  set -e
  assert_not_equal "$status" "0"
  assert_contains "$out" "planning: incomplete (later-phase execution has not started yet)"
  assert_contains "$out" "implementation: invalid (missing .asdlc_worker/step_plans/step-1.1-$FEATURE_ID_DEFAULT.md)"
  assert_contains "$out" "Selected start phase: planning"
  assert_not_contains "$out" "Resume blocked:"
}

test_resume_starts_at_implementation_when_planning_gate_closed() {
  local repo_dir="$TMP_ROOT/repo-implementation-ready-after-planning"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 0 0 0

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "planning: complete (planning markers detected (step plan present and implementation-plan planning gate closed))"
  assert_contains "$out" "implementation: incomplete (missing implementation marker (expected branch step-1.1-feature-resume-implementation))"
  assert_contains "$out" "Selected start phase: implementation"
}

test_resume_starts_at_implementation_when_planning_gate_unchecked_but_work_started() {
  local repo_dir="$TMP_ROOT/repo-implementation-unchecked-planning-gate"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1" "partial"
  write_impl_plan "$repo_dir" 0 1 0 0

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "planning: complete (later-phase execution markers detected (1/2 implementation bullets checked))"
  assert_contains "$out" "implementation: incomplete (missing implementation marker (expected branch step-1.1-feature-resume-implementation))"
  assert_contains "$out" "Selected start phase: implementation"
  assert_not_contains "$out" "planning gate not checked"
}

test_partial_markers_rerun_implementation() {
  local repo_dir="$TMP_ROOT/repo-implementation"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1" "partial"
  write_impl_plan "$repo_dir" 1 1 0 0

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "implementation: incomplete (missing implementation marker (expected branch step-1.1-feature-resume-implementation))"
  assert_contains "$out" "Selected start phase: implementation"
}

test_resume_starts_at_user_review() {
  local repo_dir="$TMP_ROOT/repo-review"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0
  create_implementation_branch_marker "$repo_dir" "1.1"

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "implementation: complete (implementation marker detected (branch step-1.1-feature-resume-implementation or later-phase artifact present))"
  assert_contains "$out" "user_review: incomplete (missing user_review marker (expected branch step-1.1-feature-resume-user-review))"
  assert_contains "$out" "Selected start phase: user_review"
  assert_contains "$out" "Executed phases: user_review ai_audit post_review"
}

test_resume_starts_at_ai_audit_after_user_review_complete() {
  local repo_dir="$TMP_ROOT/repo-review-after-user-review"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0
  create_user_review_branch_marker "$repo_dir" "1.1"

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "implementation: complete (implementation marker detected (branch step-1.1-feature-resume-implementation or later-phase artifact present))"
  assert_contains "$out" "ai_audit: incomplete (missing .asdlc_worker/step_review_results/review_result-1.1-$FEATURE_ID_DEFAULT.md)"
  assert_contains "$out" "Selected start phase: ai_audit"
  assert_contains "$out" "Executed phases: ai_audit post_review"
}

test_resume_starts_at_ai_audit_with_prefixed_gates() {
  local repo_dir="$TMP_ROOT/repo-review-prefixed-gates"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0 "[REQ-1] "
  create_user_review_branch_marker "$repo_dir" "1.1"

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "implementation: complete (implementation marker detected (branch step-1.1-feature-resume-implementation or later-phase artifact present))"
  assert_contains "$out" "ai_audit: incomplete (missing .asdlc_worker/step_review_results/review_result-1.1-$FEATURE_ID_DEFAULT.md)"
  assert_contains "$out" "Selected start phase: ai_audit"
  assert_contains "$out" "Executed phases: ai_audit post_review"
}

test_resume_starts_at_post_review_when_disposition_section_is_missing() {
  local repo_dir="$TMP_ROOT/repo-post-review-missing-disposition-section"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0
  create_user_review_branch_marker "$repo_dir" "1.1"
  write_review_result "$repo_dir" "1.1" "missing_disposition"

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "ai_audit: complete (review artifact present (disposition semantics enforced by ai_audit/post_review helper))"
  assert_contains "$out" "post_review: incomplete (review gate 'Review step implementation' is not [x])"
  assert_contains "$out" "Selected start phase: post_review"
  assert_contains "$out" "Executed phases: post_review"
  assert_not_contains "$out" "missing '## Disposition (per issue)' section"
}

test_resume_starts_at_post_review_when_disposition_count_is_insufficient() {
  local repo_dir="$TMP_ROOT/repo-post-review-insufficient-dispositions"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0
  create_user_review_branch_marker "$repo_dir" "1.1"
  write_review_result "$repo_dir" "1.1" "insufficient_dispositions"

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "ai_audit: complete (review artifact present (disposition semantics enforced by ai_audit/post_review helper))"
  assert_contains "$out" "post_review: incomplete (review gate 'Review step implementation' is not [x])"
  assert_contains "$out" "Selected start phase: post_review"
  assert_contains "$out" "Executed phases: post_review"
  assert_not_contains "$out" "review dispositions incomplete"
}

test_missing_step_error() {
  local repo_dir="$TMP_ROOT/repo-missing-step"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_impl_plan "$repo_dir" 0 0 0 0

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 9.9 --dry-run 2>&1)"
  status=$?
  set -e
  assert_not_equal "$status" "0"
  assert_contains "$out" "No candidate features under project '$PROJECT_ID_DEFAULT' contain requested step '9.9' assigned to worker '$WORKER_UUID_DEFAULT'."
}

test_dry_run_is_deterministic() {
  local repo_dir="$TMP_ROOT/repo-deterministic"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0

  local out1 out2
  out1="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  out2="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  if [[ "$out1" != "$out2" ]]; then
    echo "Assertion failed: dry-run output must be deterministic for unchanged repo state" >&2
    echo "Output 1:" >&2
    echo "$out1" >&2
    echo "Output 2:" >&2
    echo "$out2" >&2
    exit 1
  fi
}

test_resume_does_not_require_evidence_before_ai_audit() {
  local repo_dir="$TMP_ROOT/repo-no-evidence-required"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0
  create_user_review_branch_marker "$repo_dir" "1.1"

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "implementation: complete (implementation marker detected (branch step-1.1-feature-resume-implementation or later-phase artifact present))"
  assert_contains "$out" "Selected start phase: ai_audit"
  assert_contains "$out" "Executed phases: ai_audit post_review"
}

test_resume_allows_implementation_when_ordered_plan_section_missing() {
  local repo_dir="$TMP_ROOT/repo-missing-ordered-section"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1" "missing_section"
  write_impl_plan "$repo_dir" 1 0 0 0

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "planning: complete (planning markers detected (step plan present and implementation-plan planning gate closed))"
  assert_contains "$out" "implementation: incomplete (missing implementation marker (expected branch step-1.1-feature-resume-implementation))"
  assert_contains "$out" "Selected start phase: implementation"
  assert_not_contains "$out" "Resume blocked:"
}

test_resume_allows_implementation_when_ordered_plan_has_no_checklist_items() {
  local repo_dir="$TMP_ROOT/repo-no-ordered-checklist-items"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_design_and_plan_artifacts "$repo_dir" "1.1" "no_checklist_items"
  write_impl_plan "$repo_dir" 1 0 0 0

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run)"
  assert_contains "$out" "planning: complete (planning markers detected (step plan present and implementation-plan planning gate closed))"
  assert_contains "$out" "implementation: incomplete (missing implementation marker (expected branch step-1.1-feature-resume-implementation))"
  assert_contains "$out" "Selected start phase: implementation"
  assert_not_contains "$out" "Resume blocked:"
}

test_resume_reuses_valid_feature_meta_sync_metadata() {
  local repo_dir="$TMP_ROOT/repo-resume-feature-sync-reuse"
  local source_dir=""
  local feature_primary=""
  local feature_secondary=""
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  source_dir="$(source_root_for_repo "$repo_dir")"
  feature_primary="$(feature_dir_for_repo "$repo_dir")"
  feature_secondary="$source_dir/feature-second"

  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0

  mkdir -p "$feature_secondary"
  cat >"$feature_secondary/implementation_plan.md" <<EOF
### Step 1.1 Demo secondary
#### Assigned: $WORKER_UUID_DEFAULT
- [x] Plan and discuss the step (SP=1)
- [x] Implement part A (SP=2)
- [x] Implement part B (SP=1)
- [ ] Review step implementation (SP=1)
EOF
  cat >"$feature_secondary/requirements_ears.md" <<'EOF'
### Requirement 1 Demo secondary
- The system SHALL support secondary demo behavior.
EOF

  write_feature_meta_sync "$repo_dir" "$FEATURE_ID_DEFAULT" "1.1"

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run 2>&1)"
  assert_contains "$out" "Resume dry-run for step 1.1"
  assert_not_contains "$out" "Multiple candidate features found under project"
  assert_file_contains "$repo_dir/.asdlc_worker/feature_meta_sync.yaml" "feature_id: '$FEATURE_ID_DEFAULT'"
  assert_file_contains "$repo_dir/.asdlc_worker/feature_meta_sync.yaml" "selected_step: '1.1'"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
  assert_file_not_exists "$repo_dir/.asdlc_worker/overmind/implementation_plan.md"
  assert_file_not_exists "$repo_dir/.asdlc_worker/overmind/reqirements_ears.md"
}

test_resume_invalidates_stale_feature_meta_sync_metadata() {
  local repo_dir="$TMP_ROOT/repo-resume-feature-sync-stale"
  local source_dir=""
  local feature_secondary=""
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  source_dir="$(source_root_for_repo "$repo_dir")"
  feature_secondary="$source_dir/feature-second"

  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0

  mkdir -p "$feature_secondary"
  cat >"$feature_secondary/implementation_plan.md" <<EOF
### Step 1.1 Demo secondary
#### Assigned: $WORKER_UUID_DEFAULT
- [x] Plan and discuss the step (SP=1)
- [x] Implement part A (SP=2)
- [x] Implement part B (SP=1)
- [ ] Review step implementation (SP=1)
EOF
  cat >"$feature_secondary/requirements_ears.md" <<'EOF'
### Requirement 1 Demo secondary
- The system SHALL support secondary demo behavior.
EOF

  write_feature_meta_sync "$repo_dir" "feature-missing" "1.1"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run 2>&1)"
  status=$?
  set -e
  assert_not_equal "$status" "0"
  assert_contains "$out" "Multiple candidate features were found for worker '$WORKER_UUID_DEFAULT'. Run in an interactive terminal to choose a feature."
}

test_resume_falls_through_when_meta_sync_has_mismatched_project_id() {
  local repo_dir="$TMP_ROOT/repo-resume-project-mismatch"
  local source_dir=""
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  source_dir="$(source_root_for_repo "$repo_dir")"

  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0

  cat >"$repo_dir/.asdlc_worker/feature_meta_sync.yaml" <<EOF
project_id: 'wrong-project-id'
worker_uuid: '$WORKER_UUID_DEFAULT'
feature_id: '$FEATURE_ID_DEFAULT'
selected_step: '1.1'
EOF

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run 2>&1)"
  assert_contains "$out" "Resume dry-run for step 1.1"
  assert_not_contains "$out" "wrong-project-id"
}

test_resume_falls_through_when_bound_plan_is_missing() {
  local repo_dir="$TMP_ROOT/repo-resume-plan-missing"
  local source_dir=""
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  source_dir="$(source_root_for_repo "$repo_dir")"

  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0

  write_feature_meta_sync "$repo_dir" "feature-nonexistent" "1.1"

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run 2>&1)"
  assert_contains "$out" "Resume dry-run for step 1.1"
  assert_not_contains "$out" "feature-nonexistent"
}

test_resume_ignores_legacy_feature_sync_yaml() {
  local repo_dir="$TMP_ROOT/repo-resume-legacy-ignored"
  local source_dir=""
  local feature_dir=""
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  source_dir="$(source_root_for_repo "$repo_dir")"
  feature_dir="$(feature_dir_for_repo "$repo_dir")"

  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0

  cat >"$repo_dir/.asdlc_worker/feature_sync.yaml" <<EOF
project_id: '$PROJECT_ID_DEFAULT'
feature_id: 'feature-nonexistent'
worker_uuid: '$WORKER_UUID_DEFAULT'
source_implementation_plan_path: '$source_dir/feature-nonexistent/implementation_plan.md'
source_requirements_ears_path: '$source_dir/feature-nonexistent/requirements_ears.md'
runtime_branch: 'overmind'
selection_mode: 'auto_single'
selected_step: '1.1'
EOF

  write_feature_meta_sync "$repo_dir" "$FEATURE_ID_DEFAULT" "1.1"

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run 2>&1)"
  assert_contains "$out" "Resume dry-run for step 1.1"
  assert_contains "$out" "feature '$FEATURE_ID_DEFAULT'"
}

test_resume_reuses_feature_meta_sync_without_forcing_runtime_branch_checkout_from_non_master_branch() {
  local repo_dir="$TMP_ROOT/repo-resume-no-forced-overmind-checkout-non-master"
  local source_dir=""
  local feature_dir=""
  local branch_name="resume-current-branch"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  source_dir="$(source_root_for_repo "$repo_dir")"
  feature_dir="$(feature_dir_for_repo "$repo_dir")"

  write_design_and_plan_artifacts "$repo_dir" "1.1"
  write_impl_plan "$repo_dir" 1 1 1 0
  create_implementation_branch_marker "$repo_dir" "1.1"
  write_feature_meta_sync "$repo_dir" "$FEATURE_ID_DEFAULT" "1.1"

  (
    cd "$repo_dir"
    git checkout -q -b "$branch_name"
  )

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run 2>&1)"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: expected resume dry-run to succeed without forced overmind checkout" >&2
    echo "Actual output:" >&2
    echo "$out" >&2
    exit 1
  fi
  assert_not_contains "$out" "Failed to checkout runtime branch 'overmind'."
  assert_contains "$out" "Selected start phase: user_review"
  assert_not_contains "$out" "Selected start phase: planning"
  assert_equal "$branch_name" "$(git -C "$repo_dir" branch --show-current)"
}

test_resume_starts_at_planning
test_resume_starts_at_planning_when_design_sections_missing
test_resume_starts_at_planning_when_step_plan_missing
test_resume_starts_at_implementation_when_planning_gate_closed
test_resume_starts_at_implementation_when_planning_gate_unchecked_but_work_started
test_partial_markers_rerun_implementation
test_resume_starts_at_user_review
test_resume_starts_at_ai_audit_after_user_review_complete
test_resume_starts_at_ai_audit_with_prefixed_gates
test_resume_starts_at_post_review_when_disposition_section_is_missing
test_resume_starts_at_post_review_when_disposition_count_is_insufficient
test_resume_does_not_require_evidence_before_ai_audit
test_resume_allows_implementation_when_ordered_plan_section_missing
test_resume_allows_implementation_when_ordered_plan_has_no_checklist_items
test_resume_reuses_valid_feature_meta_sync_metadata
test_resume_invalidates_stale_feature_meta_sync_metadata
test_resume_falls_through_when_meta_sync_has_mismatched_project_id
test_resume_falls_through_when_bound_plan_is_missing
test_resume_ignores_legacy_feature_sync_yaml
test_resume_reuses_feature_meta_sync_without_forcing_runtime_branch_checkout_from_non_master_branch
test_missing_step_error
test_dry_run_is_deterministic

echo "All orchestrator resume tests passed."
