#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"
PLAN_SKILL_DIR="$SOURCE_ROOT/ai/codex/skills/yasdef-worker-plan"
IMPLEMENTATION_SKILL_DIR="$SOURCE_ROOT/ai/codex/skills/yasdef-worker-implementation"
USER_REVIEW_SKILL_DIR="$SOURCE_ROOT/ai/codex/skills/yasdef-worker-user-review"
AI_AUDIT_SKILL_DIR="$SOURCE_ROOT/ai/codex/skills/yasdef-worker-ai-audit"

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

run_orchestrator_with_tty_input() {
  local repo_dir="$1"
  local input_text="$2"
  local expect_script="$TMP_ROOT/orchestrator-expect-$$.tcl"
  shift 2
  cat >"$expect_script" <<EOF
log_user 1
set timeout 20
set responses [split [string trim \$env(EXPECT_INPUT)] "\n"]
set idx 0
proc send_next {} {
  global responses idx
  if {\$idx >= [llength \$responses]} {
    return
  }
  send -- "[lindex \$responses \$idx]\r"
  incr idx
}
cd "$repo_dir"
spawn .asdlc_worker/scripts/orchestrator.sh $(printf ' %q' "$@")
expect {
  -re {Choose 1 or 2: $} {
    send_next
    exp_continue
  }
  -re {Proceed\\? \\[y/n\\] $} {
    send_next
    exp_continue
  }
  -re {Select feature number: $} {
    send_next
    exp_continue
  }
  eof
}
catch wait result
exit [lindex \$result 3]
EOF
  EXPECT_INPUT="$input_text" expect "$expect_script" 2>&1
}

setup_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/setup" "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/step_review_results" "$repo_dir/.asdlc_worker/overmind" "$repo_dir/.codex/skills"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"

  cp "$ORCH_SRC" "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp -R "$PLAN_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-plan"
  cp -R "$IMPLEMENTATION_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-implementation"
  cp -R "$USER_REVIEW_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-user-review"
  cp -R "$AI_AUDIT_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-ai-audit"
  chmod +x "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"
  cat >"$repo_dir/.asdlc_worker/scripts/ai_user_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "user_review"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_audit.sh" <<'EOF'
#!/usr/bin/env bash
echo "ai_audit"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post_review"
EOF
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_user_review.sh" \
    "$repo_dir/.asdlc_worker/scripts/ai_audit.sh" "$repo_dir/.asdlc_worker/scripts/post_review.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'MODELS'
design | echo | mock-model
MODELS
  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. demo
## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 Demo requirement.
EOF
  mkdir -p "$repo_dir/.asdlc_worker/step_designs"
  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-feature-a-design.md" <<'EOF'
## Goal
- Demo goal.

## In Scope
- Demo scope.

## Out of Scope
- Later work.
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
    git add README.md .asdlc_worker ai overmind
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
  local remote_dir="${source_dir}-remote.git"

  mkdir -p "$source_dir"
  (
    cd "$source_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
  )
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
  (
    cd "$source_dir"
    git add workers.yaml init_progress_definition.yaml
    git commit -qm "init project repo"
    git init -q --bare "$remote_dir"
    git --git-dir "$remote_dir" symbolic-ref HEAD refs/heads/master
    git remote add origin "$remote_dir"
    git push -q -u origin master
  )
}

commit_project_repo_changes() {
  local source_dir="$1"
  local message="$2"
  (
    cd "$source_dir"
    git add -A
    git commit -qm "$message"
    git push -q
  )
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
  commit_project_repo_changes "$source_dir" "add feature $feature_id"
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

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "orchestrator: default mode active; reading and writing plan/ears directly at bound-source paths."
  assert_contains "$out" "orchestrator: selected feature 'feature-a' (mode=auto_single, project=project-alpha, step=2.2)."
  assert_contains "$out" "orchestrator: resolved routed step '2.2' for design skill prompt."
  assert_contains "$out" "dry-run log: .asdlc_worker/logs/repo-single-feature-design-2-2-log"
  assert_contains "$out" "write yasdef-worker-design prompt for step 2.2"
  assert_contains "$out" "yasdef-worker-design"
  assert_not_contains "$out" "design-1-1-log"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
  assert_file_contains "$repo_dir/.asdlc_worker/feature_meta_sync.yaml" "feature_id: 'feature-a'"
  assert_file_contains "$repo_dir/.asdlc_worker/feature_meta_sync.yaml" "project_id: 'project-alpha'"
  assert_file_not_exists "$repo_dir/.asdlc_worker/feature_sync.yaml"
  assert_file_not_exists "$repo_dir/.asdlc_worker/overmind/implementation_plan.md"
  assert_file_not_exists "$repo_dir/.asdlc_worker/overmind/requirements_ears.md"
  assert_file_contains "$source_dir/feature-a/implementation_plan.md" "### Step 2.2 Worker step"
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

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --debug --dry-run 2>&1)"
  assert_contains "$out" "selected feature 'feature-x'"
  assert_contains "$out" "step=1.5"
  assert_file_contains "$repo_dir/.asdlc_worker/feature_meta_sync.yaml" "feature_id: 'feature-x'"
  assert_file_contains "$repo_dir/.asdlc_worker/feature_meta_sync.yaml" "project_id: 'project-direct'"
  assert_file_not_exists "$repo_dir/.asdlc_worker/feature_sync.yaml"
  assert_file_not_exists "$repo_dir/.asdlc_worker/overmind/implementation_plan.md"
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
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --debug --dry-run 2>&1)"
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
  commit_project_repo_changes "$source_dir" "add docs folder"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --debug --dry-run 2>&1)"
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

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --debug --dry-run -- --step 2.2 2>&1)"
  assert_contains "$out" "dry-run log: .asdlc_worker/logs/repo-step-filter-design-2-2-log"
  assert_file_contains "$repo_dir/.asdlc_worker/feature_meta_sync.yaml" "feature_id: 'feature-b'"
  assert_file_contains "$repo_dir/.asdlc_worker/feature_meta_sync.yaml" "selected_step: '2.2'"
  assert_file_not_exists "$repo_dir/.asdlc_worker/feature_sync.yaml"
  assert_file_not_exists "$repo_dir/.asdlc_worker/overmind/implementation_plan.md"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --debug --dry-run -- --step 1.1 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
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
  commit_project_repo_changes "$source_dir" "add feature without ears"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "does not match meta_info.project_id"
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
  mkdir -p "$repo_dir/.asdlc_worker/step_designs"
  cat >"$repo_dir/.asdlc_worker/step_designs/step-3.4-feature-routing-design.md" <<'EOF'
## Selected EARS Requirements (for planning translation)
### Requirement 1 Demo
- The system SHALL support routed planning.
EOF
  set_single_phase_model "$repo_dir" "planning"

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
  assert_contains "$out" "write yasdef-worker-plan prompt for step 3.4"
  assert_contains "$out" "dry-run prompt: .asdlc_worker/prompts/plan_prompts/repo-planning-step-injection-latest-planning-prompt.txt"
  assert_contains "$out" "dry-run log: .asdlc_worker/logs/repo-planning-step-injection-planning-latest-log"
}

test_non_master_start_can_cancel_before_switching_to_overmind() {
  local repo_dir="$TMP_ROOT/repo-non-master-cancel"
  local source_dir="$TMP_ROOT/source-non-master-cancel"
  local project_id="project-non-master-cancel"
  local worker_uuid="99999999-9999-9999-9999-999999999998"
  local out=""
  local current_branch=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-routing" "### Step 3.4 Planned step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  (
    cd "$repo_dir"
    git checkout -q -b feature-start
  )

  set +e
  out="$(run_orchestrator_with_tty_input "$repo_dir" $'2\n' --dry-run)"
  local status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "⚠️ overmind will merge (rebase) last master state and start work, but you start orchestrator NOT from master branch. Are you sure?"
  assert_contains "$out" "1. Yes I am sure, start from current branch"
  assert_contains "$out" "2. No, dont start I'll switch to master first (manually)"
  assert_contains "$out" "Execution stopped: switch to 'master' manually and rerun orchestrator."
  current_branch="$(git -C "$repo_dir" branch --show-current)"
  assert_equal "feature-start" "$current_branch"
}

test_runtime_branch_rebases_master_before_feature_routing() {
  local repo_dir="$TMP_ROOT/repo-overmind-rebase-master"
  local source_dir="$TMP_ROOT/source-overmind-rebase-master"
  local project_id="project-overmind-rebase-master"
  local worker_uuid="99999999-9999-9999-9999-999999999997"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-routing" "### Step 3.4 Planned step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  (
    cd "$repo_dir"
    git checkout -q -b overmind
    git checkout -q master
    echo "master freshness" >MASTER_FRESHNESS.txt
    git add MASTER_FRESHNESS.txt
    git commit -qm "add master freshness marker"
  )

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
  assert_contains "$out" "selected feature 'feature-routing'"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
  assert_file_contains "$repo_dir/MASTER_FRESHNESS.txt" "master freshness"
  assert_contains "$(git -C "$repo_dir" merge-base --is-ancestor master overmind; printf '%s' "$?")" "0"
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

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --debug --dry-run 2>&1)"
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

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --debug --dry-run 2>&1)"
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

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --debug --dry-run 2>&1)"
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

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --debug --dry-run 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
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

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --debug --dry-run 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "blocked by step '1.2'"
}

test_exits_nonzero_when_bound_source_plan_has_uncommitted_changes() {
  local repo_dir="$TMP_ROOT/repo-dirty-plan"
  local source_dir="$TMP_ROOT/source-dirty-plan"
  local project_id="project-dirty-plan"
  local worker_uuid="e0000000-0000-0000-0000-000000000001"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-dirty" "### Step 1.1 Dirty plan step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  printf '\n# uncommitted-change\n' >>"$source_dir/feature-dirty/implementation_plan.md"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Bound-source plan is dirty: $source_dir/feature-dirty/implementation_plan.md"
  assert_contains "$out" "git -C '$source_dir'"
}

assert_zero_status() {
  local status="$1"
  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: expected zero status, got $status" >&2
    exit 1
  fi
}

write_feature_meta_sync() {
  local repo_dir="$1"
  local project_id="$2"
  local worker_uuid="$3"
  local feature_id="$4"
  local selected_step="$5"

  cat >"$repo_dir/.asdlc_worker/feature_meta_sync.yaml" <<EOF
project_id: '$project_id'
worker_uuid: '$worker_uuid'
feature_id: '$feature_id'
selected_step: '$selected_step'
EOF
}

test_fast_path_blocked_feature_exits_with_blocker_message() {
  local repo_dir="$TMP_ROOT/repo-fast-path-blocked"
  local source_dir="$TMP_ROOT/source-fast-path-blocked"
  local project_id="project-fast-path-blocked"
  local worker_uuid="f0000000-0000-0000-0000-000000000001"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-fp-blocked" "### Step 1.1 Upstream step
#### Assigned: other-worker
- [ ] Do upstream work (SP=2)

### Step 2.1 Blocked worker step
#### Depends on: 1.1
#### Assigned: $worker_uuid
- [ ] Implement something (SP=3)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  write_feature_meta_sync "$repo_dir" "$project_id" "$worker_uuid" "feature-fp-blocked" "2.1"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "feature-fp-blocked"
  assert_contains "$out" "blocked"
  assert_contains "$out" "1.1"
  assert_not_contains "$out" "candidate features"
  assert_not_contains "$out" "Proceed with current feature"
}

test_fast_path_exhausted_feature_noninteractive_exits_with_exhausted_message() {
  local repo_dir="$TMP_ROOT/repo-fast-path-exhausted"
  local source_dir="$TMP_ROOT/source-fast-path-exhausted"
  local project_id="project-fast-path-exhausted"
  local worker_uuid="f0000000-0000-0000-0000-000000000002"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-fp-exhausted" "### Step 1.1 Completed step
#### Assigned: $worker_uuid
- [x] All done (SP=2)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  write_feature_meta_sync "$repo_dir" "$project_id" "$worker_uuid" "feature-fp-exhausted" "1.1"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "feature-fp-exhausted"
  assert_contains "$out" "exhausted"
  assert_contains "$out" "feature_meta_sync.yaml"
  assert_not_contains "$out" "candidate features"
  assert_not_contains "$out" "Proceed with current feature"
}

test_fast_path_exhausted_feature_interactive_choice1_deletes_file() {
  local repo_dir="$TMP_ROOT/repo-fast-path-exhausted-choice1"
  local source_dir="$TMP_ROOT/source-fast-path-exhausted-choice1"
  local project_id="project-fp-exhausted-choice1"
  local worker_uuid="f0000000-0000-0000-0000-000000000003"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-fp-done" "### Step 1.1 Completed step
#### Assigned: $worker_uuid
- [x] All done (SP=2)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  write_feature_meta_sync "$repo_dir" "$project_id" "$worker_uuid" "feature-fp-done" "1.1"

  set +e
  out="$(run_orchestrator_with_tty_input "$repo_dir" $'1\n' --dry-run 2>&1)"
  status=$?
  set -e
  assert_zero_status "$status"
  assert_contains "$out" "deleted"
  assert_file_not_exists "$repo_dir/.asdlc_worker/feature_meta_sync.yaml"
}

test_fast_path_exhausted_feature_interactive_choice2_keeps_file() {
  local repo_dir="$TMP_ROOT/repo-fast-path-exhausted-choice2"
  local source_dir="$TMP_ROOT/source-fast-path-exhausted-choice2"
  local project_id="project-fp-exhausted-choice2"
  local worker_uuid="f0000000-0000-0000-0000-000000000004"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-fp-done2" "### Step 1.1 Completed step
#### Assigned: $worker_uuid
- [x] All done (SP=2)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  write_feature_meta_sync "$repo_dir" "$project_id" "$worker_uuid" "feature-fp-done2" "1.1"

  set +e
  out="$(run_orchestrator_with_tty_input "$repo_dir" $'2\n' --dry-run 2>&1)"
  status=$?
  set -e
  assert_zero_status "$status"
  assert_contains "$out" "feature_meta_sync.yaml"
  assert_file_contains "$repo_dir/.asdlc_worker/feature_meta_sync.yaml" "feature-fp-done2"
}

test_startup_prompt_interactive_proceed_reuses_current_feature() {
  local repo_dir="$TMP_ROOT/repo-startup-prompt-proceed"
  local source_dir="$TMP_ROOT/source-startup-prompt-proceed"
  local project_id="project-startup-prompt-proceed"
  local worker_uuid="b0000000-0000-0000-0000-000000000001"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-prompt-a" "### Step 2.1 Demo step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  write_feature_meta_sync "$repo_dir" "$project_id" "$worker_uuid" "feature-prompt-a" "2.1"

  set +e
  out="$(run_orchestrator_with_tty_input "$repo_dir" $'1\n' --dry-run)"
  status=$?
  set -e

  assert_zero_status "$status"
  assert_contains "$out" "Proceed with current feature"
  assert_contains "$out" "selected feature 'feature-prompt-a'"
  assert_not_contains "$out" "Multiple candidate features"
  assert_file_contains "$repo_dir/.asdlc_worker/feature_meta_sync.yaml" "feature_id: 'feature-prompt-a'"
}

test_startup_prompt_interactive_change_selects_new_feature_with_current_label() {
  local repo_dir="$TMP_ROOT/repo-startup-prompt-change"
  local source_dir="$TMP_ROOT/source-startup-prompt-change"
  local project_id="project-startup-prompt-change"
  local worker_uuid="b0000000-0000-0000-0000-000000000002"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-chg-a" "### Step 1.1 Feature A step
#### Assigned: $worker_uuid
- [ ] Do work A (SP=1)
"
  create_feature "$source_dir" "feature-chg-b" "### Step 2.2 Feature B step
#### Assigned: $worker_uuid
- [ ] Do work B (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  write_feature_meta_sync "$repo_dir" "$project_id" "$worker_uuid" "feature-chg-a" "1.1"

  # feature-chg-a is sorted first alphabetically; picker shows: 1) feature-chg-a (CURRENT), 2) feature-chg-b
  # input: 2 (Change), 2 (select feature-chg-b)
  set +e
  out="$(run_orchestrator_with_tty_input "$repo_dir" $'2\n2\n' --dry-run)"
  status=$?
  set -e

  assert_zero_status "$status"
  assert_contains "$out" "Change feature"
  assert_contains "$out" "(CURRENT)"
  assert_contains "$out" "selected feature 'feature-chg-b'"
  assert_file_contains "$repo_dir/.asdlc_worker/feature_meta_sync.yaml" "feature_id: 'feature-chg-b'"
  # Task 7.1: verify feature_meta_sync.yaml has exactly 4 fields (no routing-signal field)
  local yaml_line_count
  yaml_line_count="$(grep -c '' "$repo_dir/.asdlc_worker/feature_meta_sync.yaml")"
  assert_equal "4" "$yaml_line_count"
  assert_not_contains "$(cat "$repo_dir/.asdlc_worker/feature_meta_sync.yaml")" "CURRENT_FEATURE_SWITCH_FROM_ID"
}

test_startup_prompt_skipped_when_noninteractive() {
  local repo_dir="$TMP_ROOT/repo-startup-prompt-noninteractive"
  local source_dir="$TMP_ROOT/source-startup-prompt-noninteractive"
  local project_id="project-startup-prompt-noninteractive"
  local worker_uuid="b0000000-0000-0000-0000-000000000003"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-noninteractive" "### Step 1.1 Demo step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  write_feature_meta_sync "$repo_dir" "$project_id" "$worker_uuid" "feature-noninteractive" "1.1"

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
  assert_contains "$out" "selected feature 'feature-noninteractive'"
  assert_not_contains "$out" "Proceed with current feature"
  assert_not_contains "$out" "Change feature"
}

test_startup_prompt_skipped_in_resume_mode() {
  local repo_dir="$TMP_ROOT/repo-startup-prompt-resume"
  local source_dir="$TMP_ROOT/source-startup-prompt-resume"
  local project_id="project-startup-prompt-resume"
  local worker_uuid="b0000000-0000-0000-0000-000000000004"
  local out=""

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-resume-skip" "### Step 1.1 Demo step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  write_feature_meta_sync "$repo_dir" "$project_id" "$worker_uuid" "feature-resume-skip" "1.1"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run 2>&1)"
  set -e
  assert_contains "$out" "Resume dry-run for step 1.1"
  assert_not_contains "$out" "Proceed with current feature"
  assert_not_contains "$out" "Change feature"
}

test_picker_no_current_label_when_current_id_not_in_candidates() {
  local repo_dir="$TMP_ROOT/repo-picker-no-current-label"
  local source_dir="$TMP_ROOT/source-picker-no-current-label"
  local project_id="project-picker-no-current-label"
  local worker_uuid="b0000000-0000-0000-0000-000000000006"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-ncl-a" "### Step 1.1 Feature A
#### Assigned: $worker_uuid
- [ ] Do work A (SP=1)
"
  create_feature "$source_dir" "feature-ncl-b" "### Step 2.1 Feature B
#### Assigned: $worker_uuid
- [ ] Do work B (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  # Stale feature_meta_sync.yaml pointing to a non-existent feature: fast path fails,
  # CURRENT_FEATURE_SWITCH_FROM_ID is never set, picker shows candidates without (CURRENT).
  write_feature_meta_sync "$repo_dir" "$project_id" "$worker_uuid" "feature-nonexistent" "1.1"

  set +e
  out="$(run_orchestrator_with_tty_input "$repo_dir" $'1\n' --dry-run)"
  status=$?
  set -e

  assert_zero_status "$status"
  assert_contains "$out" "Multiple candidate features found"
  assert_not_contains "$out" "(CURRENT)"
}

test_startup_prompt_change_single_candidate_auto_selects() {
  local repo_dir="$TMP_ROOT/repo-startup-prompt-single-auto"
  local source_dir="$TMP_ROOT/source-startup-prompt-single-auto"
  local project_id="project-startup-prompt-single-auto"
  local worker_uuid="b0000000-0000-0000-0000-000000000007"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-single-auto" "### Step 3.1 Demo step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  write_feature_meta_sync "$repo_dir" "$project_id" "$worker_uuid" "feature-single-auto" "3.1"

  # User chooses Change (2), slow-path finds only feature-single-auto → auto-selects without picker
  set +e
  out="$(run_orchestrator_with_tty_input "$repo_dir" $'2\n' --dry-run)"
  status=$?
  set -e

  assert_zero_status "$status"
  assert_contains "$out" "Change feature"
  assert_contains "$out" "selected feature 'feature-single-auto'"
  assert_not_contains "$out" "Select feature number"
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
test_planning_dry_run_injects_resolved_step_when_not_explicit
test_non_master_start_can_cancel_before_switching_to_overmind
test_runtime_branch_rebases_master_before_feature_routing
test_dep_none_step_is_selected
test_dep_missing_line_step_is_selected
test_dep_satisfied_step_is_selected
test_dep_not_satisfied_skips_step_selects_next
test_all_assigned_steps_blocked_exits_nonzero_with_blocked_message
test_dep_nonexistent_step_id_is_plan_error
test_dep_zero_bullet_step_is_plan_error
test_multi_dep_all_satisfied_step_selected
test_multi_dep_one_unsatisfied_step_skipped
test_exits_nonzero_when_bound_source_plan_has_uncommitted_changes
test_fast_path_blocked_feature_exits_with_blocker_message
test_fast_path_exhausted_feature_noninteractive_exits_with_exhausted_message
test_fast_path_exhausted_feature_interactive_choice1_deletes_file
test_fast_path_exhausted_feature_interactive_choice2_keeps_file
test_startup_prompt_interactive_proceed_reuses_current_feature
test_startup_prompt_interactive_change_selects_new_feature_with_current_label
test_startup_prompt_skipped_when_noninteractive
test_startup_prompt_skipped_in_resume_mode
test_picker_no_current_label_when_current_id_not_in_candidates
test_startup_prompt_change_single_candidate_auto_selects

echo "All orchestrator assignment tests passed."
