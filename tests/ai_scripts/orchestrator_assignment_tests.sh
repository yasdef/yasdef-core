#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "Assertion failed: expected output to NOT contain: $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_nonzero_status() {
  local status="$1"
  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: expected non-zero status" >&2
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

setup_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/setup" "$repo_dir/ai/step_plans" "$repo_dir/ai/step_review_results"

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
  cat >"$repo_dir/ai/scripts/ai_user_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "user_review"
EOF
  cat >"$repo_dir/ai/scripts/ai_audit.sh" <<'EOF'
#!/usr/bin/env bash
echo "ai_audit"
EOF
  cat >"$repo_dir/ai/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post_review"
EOF
  chmod +x "$repo_dir/ai/scripts/ai_design.sh" "$repo_dir/ai/scripts/ai_plan.sh" \
    "$repo_dir/ai/scripts/ai_implementation.sh" "$repo_dir/ai/scripts/ai_user_review.sh" \
    "$repo_dir/ai/scripts/ai_audit.sh" "$repo_dir/ai/scripts/post_review.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'MODELS'
design | echo | mock-model
MODELS
  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. demo
## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 Demo requirement.
EOF
  cat >"$repo_dir/ai/step_review_results/review_result-1.1.md" <<'EOF'
# Review Result: Step 1.1
## Disposition (per issue)
- None.
EOF

  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "seed" >README.md
    git add README.md ai
    git commit -qm "seed"
  )
}

write_binding() {
  local repo_dir="$1"
  local source_dir="$2"
  local project_id="$3"
  local worker_uuid="$4"

  cat >"$repo_dir/ai/project_overmind.yaml" <<EOF
overmind_source_path: '$source_dir'
project_id: '$project_id'
worker_uuid: '$worker_uuid'
class: 'platform'
status: 'ready'
EOF
}

create_feature() {
  local source_dir="$1"
  local project_id="$2"
  local feature_id="$3"
  local plan_content="$4"

  mkdir -p "$source_dir/projects/$project_id/$feature_id"
  cat >"$source_dir/projects/$project_id/$feature_id/implementation_plan.md" <<EOF
$plan_content
EOF
  cat >"$source_dir/projects/$project_id/$feature_id/requirements_ears.md" <<'EOF'
### Requirement 1 Demo
- The system SHALL support demo behavior.
EOF
}

create_workers_registry() {
  local source_dir="$1"
  local project_id="$2"
  local worker_uuid="$3"

  mkdir -p "$source_dir/projects/$project_id"
  cat >"$source_dir/projects/$project_id/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF
}

set_single_phase_model() {
  local repo_dir="$1"
  local phase="$2"
  cat >"$repo_dir/ai/setup/models.md" <<EOF
$phase | echo | mock-model
EOF
}

test_bound_project_single_feature_auto_selected() {
  local repo_dir="$TMP_ROOT/repo-single-feature"
  local source_dir="$TMP_ROOT/source-single-feature"
  local project_id="project-alpha"
  local worker_uuid="11111111-1111-1111-1111-111111111111"
  local other_uuid="22222222-2222-2222-2222-222222222222"
  local out=""

  mkdir -p "$repo_dir" "$source_dir"
  setup_repo "$repo_dir"
  create_workers_registry "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "$project_id" "feature-a" "### Step 2.2 Worker step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  create_feature "$source_dir" "$project_id" "feature-b" "### Step 1.1 Other worker
#### Assigned: $other_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "orchestrator: selected feature 'feature-a' (mode=auto_single, project=project-alpha, step=2.2)."
  assert_contains "$out" "orchestrator: resolved routed step '2.2' for design; injecting --step into ai_design.sh."
  assert_contains "$out" "dry-run log: ai/logs/repo-single-feature-design-2-2-log"
  assert_contains "$out" "ai/scripts/ai_design.sh --step 2.2"
  assert_not_contains "$out" "design-1-1-log"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
  assert_file_contains "$repo_dir/ai/feature_sync.yaml" "feature_id: 'feature-a'"
  assert_file_contains "$repo_dir/ai/feature_sync.yaml" "selection_mode: 'auto_single'"
  assert_file_contains "$repo_dir/overmind/implementation_plan.md" "### Step 2.2 Worker step"
}

test_requested_step_filters_candidate_features() {
  local repo_dir="$TMP_ROOT/repo-step-filter"
  local source_dir="$TMP_ROOT/source-step-filter"
  local project_id="project-beta"
  local worker_uuid="33333333-3333-3333-3333-333333333333"
  local out=""

  mkdir -p "$repo_dir" "$source_dir"
  setup_repo "$repo_dir"
  create_workers_registry "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "$project_id" "feature-a" "### Step 1.1 Old step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  create_feature "$source_dir" "$project_id" "feature-b" "### Step 2.2 Requested step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run -- --step 2.2 2>&1)"
  assert_contains "$out" "dry-run log: ai/logs/repo-step-filter-design-2-2-log"
  assert_file_contains "$repo_dir/ai/feature_sync.yaml" "feature_id: 'feature-b'"
  assert_file_contains "$repo_dir/ai/feature_sync.yaml" "requested_step: '2.2'"
  assert_file_contains "$repo_dir/ai/feature_sync.yaml" "selected_step: '2.2'"
}

test_multiple_candidate_features_require_explicit_interactive_selection() {
  local repo_dir="$TMP_ROOT/repo-multi-prompt"
  local source_dir="$TMP_ROOT/source-multi-prompt"
  local project_id="project-gamma"
  local worker_uuid="44444444-4444-4444-4444-444444444444"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$source_dir"
  setup_repo "$repo_dir"
  create_workers_registry "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "$project_id" "feature-a" "### Step 1.1 Shared step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  create_feature "$source_dir" "$project_id" "feature-b" "### Step 1.1 Shared step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run -- --step 1.1 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Multiple candidate features were found for worker '$worker_uuid'. Run in an interactive terminal to choose a feature."
}

test_fails_when_no_assigned_worker_steps_exist() {
  local repo_dir="$TMP_ROOT/repo-no-assigned"
  local source_dir="$TMP_ROOT/source-no-assigned"
  local project_id="project-delta"
  local worker_uuid="55555555-5555-5555-5555-555555555555"
  local other_uuid="66666666-6666-6666-6666-666666666666"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$source_dir"
  setup_repo "$repo_dir"
  create_workers_registry "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "$project_id" "feature-z" "### Step 1.1 Other worker
#### Assigned: $other_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "No feature under bound project '$project_id' contains assigned steps for worker UUID '$worker_uuid'."
}

test_fails_when_selected_feature_requirements_ears_missing() {
  local repo_dir="$TMP_ROOT/repo-missing-ears"
  local source_dir="$TMP_ROOT/source-missing-ears"
  local project_id="project-epsilon"
  local worker_uuid="77777777-7777-7777-7777-777777777777"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$source_dir"
  setup_repo "$repo_dir"
  create_workers_registry "$source_dir" "$project_id" "$worker_uuid"
  mkdir -p "$source_dir/projects/$project_id/feature-no-ears"
  cat >"$source_dir/projects/$project_id/feature-no-ears/implementation_plan.md" <<EOF
### Step 1.1 Missing EARS
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
EOF
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Selected feature requirements_ears.md is missing"
}

test_planning_syncs_runtime_plan_back_to_selected_feature_source() {
  local repo_dir="$TMP_ROOT/repo-plan-sync-back"
  local source_dir="$TMP_ROOT/source-plan-sync-back"
  local project_id="project-zeta"
  local worker_uuid="88888888-8888-8888-8888-888888888888"
  local feature_plan=""

  mkdir -p "$repo_dir" "$source_dir"
  setup_repo "$repo_dir"
  create_workers_registry "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "$project_id" "feature-sync" "### Step 1.1 Sync candidate
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  feature_plan="$source_dir/projects/$project_id/feature-sync/implementation_plan.md"

  cat >"$repo_dir/ai/scripts/ai_plan.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "# planning prompt"
echo "# synced-by-planning" >> overmind/implementation_plan.md
EOF
  chmod +x "$repo_dir/ai/scripts/ai_plan.sh"
  set_single_phase_model "$repo_dir" "planning"
  cat >"$repo_dir/ai/step_review_results/review_result-1.1.md" <<'EOF'
# Review Result: Step 1.1
## Disposition (per issue)
- None.
EOF

  (cd "$repo_dir" && ai/scripts/orchestrator.sh -- --step 1.1 >/dev/null 2>/dev/null)
  assert_file_contains "$feature_plan" "# synced-by-planning"
}

test_planning_dry_run_injects_resolved_step_when_not_explicit() {
  local repo_dir="$TMP_ROOT/repo-planning-step-injection"
  local source_dir="$TMP_ROOT/source-planning-step-injection"
  local project_id="project-theta"
  local worker_uuid="99999999-9999-9999-9999-999999999999"
  local out=""

  mkdir -p "$repo_dir" "$source_dir"
  setup_repo "$repo_dir"
  create_workers_registry "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "$project_id" "feature-routing" "### Step 3.4 Planned step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  set_single_phase_model "$repo_dir" "planning"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  assert_contains "$out" "ai/scripts/ai_plan.sh --step 3.4"
  assert_contains "$out" "dry-run log: ai/logs/repo-planning-step-injection-planning-latest-log"
}

test_bound_project_single_feature_auto_selected
test_requested_step_filters_candidate_features
test_multiple_candidate_features_require_explicit_interactive_selection
test_fails_when_no_assigned_worker_steps_exist
test_fails_when_selected_feature_requirements_ears_missing
test_planning_syncs_runtime_plan_back_to_selected_feature_source
test_planning_dry_run_injects_resolved_step_when_not_explicit

echo "All orchestrator assignment tests passed."
