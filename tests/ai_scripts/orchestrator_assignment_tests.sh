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

assert_file_not_exists() {
  local file="$1"
  if [[ -e "$file" ]]; then
    echo "Assertion failed: expected file to be absent: $file" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/setup" "$repo_dir/ai/step_plans" "$repo_dir/ai/step_review_results" "$repo_dir/overmind"

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

# Creates a single ASDLC project repo at source_dir with workers.yaml and init_progress_definition.yaml at root.
init_project_repo() {
  local source_dir="$1"
  local project_id="$2"
  local worker_uuid="$3"

  mkdir -p "$source_dir"
  cat >"$source_dir/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF
  cat >"$source_dir/init_progress_definition.yaml" <<EOF
meta_info:
  project_id: '$project_id'
steps: []
EOF
}

# Creates a feature folder directly under the project repo root (not under projects/<id>/).
create_feature() {
  local source_dir="$1"
  local feature_id="$2"
  local plan_content="$3"

  mkdir -p "$source_dir/$feature_id"
  cat >"$source_dir/$feature_id/implementation_plan.md" <<EOF
$plan_content
EOF
  cat >"$source_dir/$feature_id/requirements_ears.md" <<'EOF'
### Requirement 1 Demo
- The system SHALL support demo behavior.
EOF
}

write_local_overmind_runtime() {
  local repo_dir="$1"
  local worker_uuid="$2"
  local step="${3:-1.7}"

  cat >"$repo_dir/overmind/implementation_plan.md" <<EOF
### Step $step Local runtime step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
EOF
  cat >"$repo_dir/overmind/reqirements_ears.md" <<'EOF'
### Requirement 1 Local runtime requirement
- The system SHALL support local standalone behavior.
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

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 2.2 Worker step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  create_feature "$source_dir" "feature-b" "### Step 1.1 Other worker
#### Assigned: $other_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "orchestrator: default mode active; ASDLC artifact read/copy flow is enabled"
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

test_bound_project_path_equals_overmind_source_path() {
  local repo_dir="$TMP_ROOT/repo-path-equals-source"
  local source_dir="$TMP_ROOT/source-path-equals-source"
  local project_id="project-direct"
  local worker_uuid="11111111-1111-1111-1111-111111111112"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-x" "### Step 1.5 Direct path step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "selected feature 'feature-x'"
  assert_contains "$out" "step=1.5"
  assert_file_contains "$repo_dir/ai/feature_sync.yaml" "bound_project_path: '$source_dir'"
  assert_file_contains "$repo_dir/ai/feature_sync.yaml" "overmind_source_path: '$source_dir'"
}

test_git_directory_is_skipped_during_feature_enumeration() {
  local repo_dir="$TMP_ROOT/repo-git-skip"
  local source_dir="$TMP_ROOT/source-git-skip"
  local project_id="project-gitskip"
  local worker_uuid="11111111-1111-1111-1111-111111111113"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-real" "### Step 3.1 Real feature step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  # Simulate a .git directory at the project repo root (as in a real git working tree)
  mkdir -p "$source_dir/.git/refs"
  echo "ref: refs/heads/main" >"$source_dir/.git/HEAD"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "selected feature 'feature-real'"
  assert_contains "$out" "step=3.1"
  assert_not_contains "$out" "feature '.git'"
}

test_non_feature_subdirectory_is_skipped() {
  local repo_dir="$TMP_ROOT/repo-non-feature-skip"
  local source_dir="$TMP_ROOT/source-non-feature-skip"
  local project_id="project-nonfeat"
  local worker_uuid="11111111-1111-1111-1111-111111111114"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-valid" "### Step 2.7 Valid feature
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  # Subdirectory without implementation_plan.md — should be skipped
  mkdir -p "$source_dir/docs"
  echo "documentation" >"$source_dir/docs/readme.md"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "selected feature 'feature-valid'"
  assert_not_contains "$out" "feature 'docs'"
}

test_requested_step_filters_candidate_features() {
  local repo_dir="$TMP_ROOT/repo-step-filter"
  local source_dir="$TMP_ROOT/source-step-filter"
  local project_id="project-beta"
  local worker_uuid="33333333-3333-3333-3333-333333333333"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Old step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  create_feature "$source_dir" "feature-b" "### Step 2.2 Requested step
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

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Shared step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  create_feature "$source_dir" "feature-b" "### Step 1.1 Shared step
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

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-z" "### Step 1.1 Other worker
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

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  mkdir -p "$source_dir/feature-no-ears"
  cat >"$source_dir/feature-no-ears/implementation_plan.md" <<EOF
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

test_fails_when_init_progress_definition_missing_in_project_repo() {
  local repo_dir="$TMP_ROOT/repo-missing-ipd"
  local source_dir="$TMP_ROOT/source-missing-ipd"
  local project_id="project-no-ipd"
  local worker_uuid="77777777-7777-7777-7777-777777777778"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  mkdir -p "$source_dir"
  cat >"$source_dir/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF
  # No init_progress_definition.yaml
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "init_progress_definition.yaml"
}

test_fails_when_project_id_mismatch_in_init_progress_definition() {
  local repo_dir="$TMP_ROOT/repo-id-mismatch"
  local source_dir="$TMP_ROOT/source-id-mismatch"
  local project_id="project-bound"
  local worker_uuid="77777777-7777-7777-7777-777777777779"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  # init_progress_definition.yaml says different project_id than binding
  init_project_repo "$source_dir" "project-actual" "$worker_uuid"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "does not match meta_info.project_id"
}

test_planning_syncs_runtime_plan_back_to_selected_feature_source() {
  local repo_dir="$TMP_ROOT/repo-plan-sync-back"
  local source_dir="$TMP_ROOT/source-plan-sync-back"
  local project_id="project-zeta"
  local worker_uuid="88888888-8888-8888-8888-888888888888"
  local feature_plan=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-sync" "### Step 1.1 Sync candidate
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  feature_plan="$source_dir/feature-sync/implementation_plan.md"

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

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-routing" "### Step 3.4 Planned step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  set_single_phase_model "$repo_dir" "planning"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  assert_contains "$out" "ai/scripts/ai_plan.sh --step 3.4"
  assert_contains "$out" "dry-run log: ai/logs/repo-planning-step-injection-planning-latest-log"
}

test_standalone_routes_from_local_overmind_runtime_and_skips_remote_validation() {
  local repo_dir="$TMP_ROOT/repo-standalone-local-routing"
  local source_dir="$TMP_ROOT/source-standalone-local-routing-does-not-exist"
  local project_id="project-iota"
  local worker_uuid="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  write_local_overmind_runtime "$repo_dir" "$worker_uuid" "7.3"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --standalone --debug --dry-run 2>&1)"
  assert_contains "$out" "orchestrator: standalone mode enabled; bypassing ASDLC feature discovery, remote validation, and artifact mirroring."
  assert_contains "$out" "orchestrator: standalone mode runtime inputs: overmind/implementation_plan.md, overmind/reqirements_ears.md."
  assert_contains "$out" "orchestrator: selected standalone step '7.3' for worker '$worker_uuid' from overmind/implementation_plan.md."
  assert_contains "$out" "ai/scripts/ai_design.sh --step 7.3"
  assert_contains "$out" "dry-run log: ai/logs/repo-standalone-local-routing-design-7-3-log"
  assert_file_not_exists "$repo_dir/ai/feature_sync.yaml"
}

test_standalone_fails_fast_when_local_runtime_ears_missing() {
  local repo_dir="$TMP_ROOT/repo-standalone-missing-ears"
  local source_dir="$TMP_ROOT/source-standalone-missing-ears-does-not-exist"
  local project_id="project-kappa"
  local worker_uuid="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  cat >"$repo_dir/overmind/implementation_plan.md" <<EOF
### Step 1.2 Missing local ears
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
EOF
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --standalone --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Standalone mode requires local runtime EARS: overmind/reqirements_ears.md."
}

test_dep_none_step_is_selected() {
  local repo_dir="$TMP_ROOT/repo-dep-none"
  local source_dir="$TMP_ROOT/source-dep-none"
  local project_id="project-dep-none"
  local worker_uuid="d0000000-0000-0000-0000-000000000001"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-dep-none" "### Step 1.1 Backend step
#### Assigned: other-worker
- [x] Done (SP=1)

### Step 2.1 Frontend step
#### Depends on: none
#### Assigned: $worker_uuid
- [ ] Implement frontend (SP=2)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "selected feature 'feature-dep-none'"
  assert_contains "$out" "step=2.1"
}

test_dep_missing_line_step_is_selected() {
  local repo_dir="$TMP_ROOT/repo-dep-missing"
  local source_dir="$TMP_ROOT/source-dep-missing"
  local project_id="project-dep-missing"
  local worker_uuid="d0000000-0000-0000-0000-000000000002"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-dep-missing" "### Step 3.1 Step without dep line
#### Assigned: $worker_uuid
- [ ] Do the work (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "step=3.1"
}

test_dep_satisfied_step_is_selected() {
  local repo_dir="$TMP_ROOT/repo-dep-sat"
  local source_dir="$TMP_ROOT/source-dep-sat"
  local project_id="project-dep-sat"
  local worker_uuid="d0000000-0000-0000-0000-000000000003"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-dep-sat" "### Step 1.1 OpenAPI step
#### Assigned: other-worker
- [x] Create OpenAPI spec (SP=2)

### Step 2.1 Frontend step
#### Depends on: 1.1
#### Assigned: $worker_uuid
- [ ] Implement frontend (SP=3)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "step=2.1"
}

test_dep_not_satisfied_skips_step_selects_next() {
  local repo_dir="$TMP_ROOT/repo-dep-skip"
  local source_dir="$TMP_ROOT/source-dep-skip"
  local project_id="project-dep-skip"
  local worker_uuid="d0000000-0000-0000-0000-000000000004"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-dep-skip" "### Step 1.1 OpenAPI step
#### Assigned: other-worker
- [ ] Create OpenAPI spec (SP=2)

### Step 2.1 Blocked frontend
#### Depends on: 1.1
#### Assigned: $worker_uuid
- [ ] Implement frontend (SP=3)

### Step 2.2 Unblocked frontend task
#### Assigned: $worker_uuid
- [ ] Add styling (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "step=2.2"
  assert_not_contains "$out" "step=2.1"
}

test_all_assigned_steps_blocked_exits_nonzero_with_blocked_message() {
  local repo_dir="$TMP_ROOT/repo-dep-all-blocked"
  local source_dir="$TMP_ROOT/source-dep-all-blocked"
  local project_id="project-dep-all-blocked"
  local worker_uuid="d0000000-0000-0000-0000-000000000005"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-all-blocked" "### Step 1.1 OpenAPI step
#### Assigned: other-worker
- [ ] Create OpenAPI spec (SP=2)

### Step 2.1 Blocked frontend
#### Depends on: 1.1
#### Assigned: $worker_uuid
- [ ] Implement frontend (SP=3)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "blocked by step '1.1'"
}

test_dep_nonexistent_step_id_is_plan_error() {
  local repo_dir="$TMP_ROOT/repo-dep-missing-id"
  local source_dir="$TMP_ROOT/source-dep-missing-id"
  local project_id="project-dep-missing-id"
  local worker_uuid="d0000000-0000-0000-0000-000000000006"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-bad-dep" "### Step 2.1 Step with bad dep
#### Depends on: 9.9
#### Assigned: $worker_uuid
- [ ] Implement something (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "plan error"
  assert_contains "$out" "9.9"
}

test_dep_zero_bullet_step_is_plan_error() {
  local repo_dir="$TMP_ROOT/repo-dep-zero-bullets"
  local source_dir="$TMP_ROOT/source-dep-zero-bullets"
  local project_id="project-dep-zero-bullets"
  local worker_uuid="d0000000-0000-0000-0000-000000000007"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-zero-bullets" "### Step 1.1 Empty dep step
#### Assigned: other-worker

### Step 2.1 Depends on empty step
#### Depends on: 1.1
#### Assigned: $worker_uuid
- [ ] Implement something (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "plan error"
  assert_contains "$out" "1.1"
}

test_multi_dep_all_satisfied_step_selected() {
  local repo_dir="$TMP_ROOT/repo-multi-dep-ok"
  local source_dir="$TMP_ROOT/source-multi-dep-ok"
  local project_id="project-multi-dep-ok"
  local worker_uuid="d0000000-0000-0000-0000-000000000008"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-multi-dep" "### Step 1.1 Backend step
#### Assigned: other-worker
- [x] Done (SP=1)

### Step 1.2 DB migration
#### Assigned: other-worker
- [x] Migrated (SP=1)

### Step 2.1 Frontend step
#### Depends on: 1.1, 1.2
#### Assigned: $worker_uuid
- [ ] Implement (SP=2)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "step=2.1"
}

test_multi_dep_one_unsatisfied_step_skipped() {
  local repo_dir="$TMP_ROOT/repo-multi-dep-block"
  local source_dir="$TMP_ROOT/source-multi-dep-block"
  local project_id="project-multi-dep-block"
  local worker_uuid="d0000000-0000-0000-0000-000000000009"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-multi-dep-block" "### Step 1.1 Backend step
#### Assigned: other-worker
- [x] Done (SP=1)

### Step 1.2 DB migration
#### Assigned: other-worker
- [ ] Not done yet (SP=1)

### Step 2.1 Frontend step
#### Depends on: 1.1, 1.2
#### Assigned: $worker_uuid
- [ ] Implement (SP=2)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "blocked by step '1.2'"
}

test_bound_project_single_feature_auto_selected
test_bound_project_path_equals_overmind_source_path
test_git_directory_is_skipped_during_feature_enumeration
test_non_feature_subdirectory_is_skipped
test_requested_step_filters_candidate_features
test_multiple_candidate_features_require_explicit_interactive_selection
test_fails_when_no_assigned_worker_steps_exist
test_fails_when_selected_feature_requirements_ears_missing
test_fails_when_init_progress_definition_missing_in_project_repo
test_fails_when_project_id_mismatch_in_init_progress_definition
test_planning_syncs_runtime_plan_back_to_selected_feature_source
test_planning_dry_run_injects_resolved_step_when_not_explicit
test_standalone_routes_from_local_overmind_runtime_and_skips_remote_validation
test_standalone_fails_fast_when_local_runtime_ears_missing
test_dep_none_step_is_selected
test_dep_missing_line_step_is_selected
test_dep_satisfied_step_is_selected
test_dep_not_satisfied_skips_step_selects_next
test_all_assigned_steps_blocked_exits_nonzero_with_blocked_message
test_dep_nonexistent_step_id_is_plan_error
test_dep_zero_bullet_step_is_plan_error
test_multi_dep_all_satisfied_step_selected
test_multi_dep_one_unsatisfied_step_skipped

echo "All orchestrator assignment tests passed."
