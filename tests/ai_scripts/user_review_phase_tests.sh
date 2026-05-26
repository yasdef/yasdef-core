#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"
USER_REVIEW_SRC="$SOURCE_ROOT/ai/scripts/ai_user_review.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"
IMPLEMENTATION_SKILL_DIR="$SOURCE_ROOT/ai/codex/skills/yasdef-worker-implementation"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export UV_CACHE_DIR="$TMP_ROOT/uv-cache"

WORKER_UUID="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

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

# Creates an external ASDLC source project repo with workers.yaml, init_progress_definition.yaml,
# and a bare remote so the orchestrator's `git pull --rebase` succeeds.
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

# Creates a feature folder under the source repo with implementation_plan.md and
# requirements_ears.md, then commits and pushes to the bare remote.
create_feature() {
  local source_dir="$1"
  local feature_id="$2"
  local plan_content="$3"
  local ears_content="$4"

  mkdir -p "$source_dir/$feature_id"
  printf '%s' "$plan_content" >"$source_dir/$feature_id/implementation_plan.md"
  printf '%s' "$ears_content" >"$source_dir/$feature_id/requirements_ears.md"
  (
    cd "$source_dir"
    git add -A
    git commit -qm "add feature $feature_id"
    git push -q
  )
}

# Builds the implementation_plan body used by both the source feature and the local runtime mirror.
# The two must be byte-identical so that the orchestrator's mirror is a no-op against git status
# (otherwise the user_review branch handoff would see dirty state and reject the run).
build_runtime_plan() {
  local impl_box="$1"
  cat <<EOF
### Step 1.1 Demo
Est. step total: 5 SP
#### Assigned: $WORKER_UUID
- [x] Plan and discuss the step (SP=1)
- [$impl_box] Implement part A (SP=3)
- [ ] Review step implementation (SP=1)
EOF
}

build_runtime_ears() {
  cat <<'EOF'
### Requirement 1 Demo
- demo
EOF
}

setup_repo() {
  local repo_dir="$1"
  local impl_checked="$2"
  local ordered_mode="$3"
  local source_dir="$4"
  local project_id="$5"
  local feature_id="$6"

  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/setup" "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/step_review_results" "$repo_dir/.asdlc_worker/overmind" \
    "$repo_dir/.codex/skills"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"

  cp "$ORCH_SRC" "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"
  cp "$USER_REVIEW_SRC" "$repo_dir/.asdlc_worker/scripts/ai_user_review.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp -R "$IMPLEMENTATION_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-implementation"
  chmod +x "$repo_dir/.asdlc_worker/scripts/orchestrator.sh" "$repo_dir/.asdlc_worker/scripts/ai_user_review.sh"

  cat >"$repo_dir/.asdlc_worker/scripts/ai_audit.sh" <<'EOF'
#!/usr/bin/env bash
echo "review"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post_review"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/fake_model.sh" <<EOF
#!/usr/bin/env bash
touch "$repo_dir/model-ran.flag"
echo "model-ran"
EOF
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_audit.sh" \
    "$repo_dir/.asdlc_worker/scripts/post_review.sh" "$repo_dir/.asdlc_worker/scripts/fake_model.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
user_review | .asdlc_worker/scripts/fake_model.sh | mock-model
EOF

  local impl_box=" "
  if [[ "$impl_checked" == "1" ]]; then
    impl_box="x"
  fi

  local plan_body ears_body
  plan_body="$(build_runtime_plan "$impl_box")"
  ears_body="$(build_runtime_ears)"

  printf '%s' "$plan_body" >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md"
  printf '%s' "$ears_body" >"$repo_dir/.asdlc_worker/overmind/reqirements_ears.md"

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

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-${feature_id}.md" <<EOF
# Step Plan: 1.1 - Demo
## Plan (ordered)
$ordered_block
## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 The system SHALL implement part A behavior. EARS[REQ-1]
EOF

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-feature-demo-design.md" <<'EOF'
## Proposal / Design Details
- demo
EOF

  cat >"$repo_dir/.asdlc_worker/step_review_results/review_result-1.1-${feature_id}.md" <<'EOF'
# Review Result: Step 1.1
## Disposition (per issue)
- None.
EOF

  cat >"$repo_dir/.asdlc_worker/AI_DEVELOPMENT_PROCESS.md" <<'EOF'
### 5) User review (required before moving to the next step)
1. Ask user for feedback.
EOF

  cat >"$repo_dir/.asdlc_worker/blocker_log.md" <<'EOF'
## Step 1.1 Demo
- none
EOF

  cat >"$repo_dir/.asdlc_worker/open_questions.md" <<'EOF'
## Step 1.1 Demo
- none
EOF

  cat >"$repo_dir/.asdlc_worker/decisions.md" <<'EOF'
# ADRs
EOF

  cat >"$repo_dir/.asdlc_worker/history.md" <<'EOF'
# History
EOF

  cat >"$repo_dir/.asdlc_worker/user_review.md" <<'EOF'
# User review rules
EOF

  cat >"$repo_dir/.asdlc_worker/project_overmind.yaml" <<EOF
overmind_source_path: '$source_dir'
project_id: '$project_id'
worker_uuid: '$WORKER_UUID'
class: 'platform'
status: 'ready'
EOF

  cat >"$repo_dir/AGENTS.md" <<'EOF'
# AGENTS
EOF

  # Orchestrator writes .asdlc_worker/feature_meta_sync.yaml during runtime context
  # setup and emits log/prompt artifacts under .asdlc_worker/logs and
  # .asdlc_worker/prompts. Ignore them so the user_review branch handoff sees a
  # clean working tree on the runtime branch.
  cat >"$repo_dir/.gitignore" <<'EOF'
.asdlc_worker/feature_meta_sync.yaml
.asdlc_worker/logs/
.asdlc_worker/prompts/
model-ran.flag
EOF

  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
    # Create the implementation branch the user_review handoff forks from.
    git branch step-1.1-feature-demo-implementation
    # Pre-create the runtime branch so the orchestrator's slow-path checkout
    # finds it rather than creating it from a transient HEAD.
    git branch overmind
  )

  init_project_repo "$source_dir" "$project_id" "$WORKER_UUID"
  create_feature "$source_dir" "$feature_id" "$plan_body" "$ears_body"
}

test_user_review_fails_fast_when_ordered_plan_unchecked() {
  local repo_dir="$TMP_ROOT/repo-fail-fast-ordered-unchecked"
  local source_dir="$TMP_ROOT/source-fail-fast-ordered-unchecked"
  setup_repo "$repo_dir" 1 unchecked "$source_dir" "project-fail-unchecked" "feature-demo"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: user_review phase must fail when ordered-plan items are unchecked" >&2
    echo "$out" >&2
    exit 1
  fi
  assert_contains "$out" "User review precheck failed for step 1.1."
  assert_contains "$out" "unchecked_ordered_plan_items"
  assert_contains "$out" "- [ ] 1. Implement part A."
  assert_contains "$out" "Implementation was not finished correctly."
  assert_file_not_exists "$repo_dir/model-ran.flag"
}

test_user_review_normalizes_plain_ordered_bullets_to_unchecked() {
  local repo_dir="$TMP_ROOT/repo-normalize-plain-ordered"
  local source_dir="$TMP_ROOT/source-normalize-plain-ordered"
  setup_repo "$repo_dir" 1 plain "$source_dir" "project-normalize-plain" "feature-demo"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: plain ordered-plan bullets must be treated as unchecked and block user_review" >&2
    exit 1
  fi
  assert_contains "$out" "unchecked_ordered_plan_items"
  assert_contains "$out" "- [ ] 1. Implement part A."
  assert_contains "$out" "Implementation was not finished correctly."
  assert_file_not_exists "$repo_dir/model-ran.flag"
}

test_user_review_runs_model_when_ordered_plan_checked_even_if_impl_unchecked() {
  local repo_dir="$TMP_ROOT/repo-pass-ordered-checked"
  local source_dir="$TMP_ROOT/source-pass-ordered-checked"
  setup_repo "$repo_dir" 0 checked "$source_dir" "project-pass-checked" "feature-demo"

  (
    cd "$repo_dir"
    .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 >/tmp/user-review-tests.out 2>/tmp/user-review-tests.err
  )

  assert_file_exists "$repo_dir/model-ran.flag"
  assert_branch_equals "$repo_dir" "step-1.1-feature-demo-user-review"
}

test_user_review_branch_handoff_fails_on_unsafe_dirty_state() {
  local repo_dir="$TMP_ROOT/repo-unsafe-state"
  local source_dir="$TMP_ROOT/source-unsafe-state"
  setup_repo "$repo_dir" 1 checked "$source_dir" "project-unsafe-state" "feature-demo"

  # Start the orchestrator on the runtime branch with a dirty tracked file so
  # the user_review handoff sees uncommitted changes on a non-implementation
  # branch and refuses to fork the user-review branch.
  (
    cd "$repo_dir"
    git checkout -q overmind
    echo "# dirty" >>AGENTS.md
  )

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: user_review must fail when branch handoff is unsafe" >&2
    exit 1
  fi
  assert_contains "$out" "User review branch must be created from step-1.1-feature-demo-implementation"
  assert_file_not_exists "$repo_dir/model-ran.flag"
}

test_user_review_prompt_uses_ordered_plan_state_only() {
  local repo_dir="$TMP_ROOT/repo-user-review-prompt-ordered-only"
  local source_dir="$TMP_ROOT/source-user-review-prompt-ordered-only"
  setup_repo "$repo_dir" 0 checked "$source_dir" "project-prompt-ordered-only" "feature-demo"

  (
    cd "$repo_dir"
    ASDLC_RUNTIME_PLAN_PATH="$source_dir/feature-demo/implementation_plan.md" \
    ASDLC_RUNTIME_EARS_PATH="$source_dir/feature-demo/requirements_ears.md" \
    .asdlc_worker/scripts/ai_user_review.sh --step 1.1 --feature-id feature-demo --step-plan .asdlc_worker/step_plans/step-1.1-feature-demo.md --design .asdlc_worker/step_designs/step-1.1-feature-demo-design.md --out .asdlc_worker/prompts/user_review_prompts/test.prompt.txt >/dev/null
  )

  local prompt
  prompt="$(cat "$repo_dir/.asdlc_worker/prompts/user_review_prompts/test.prompt.txt")"
  assert_contains "$prompt" 'Entry gate already verified by script: `.codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py --step 1.1 --step-plan .asdlc_worker/step_plans/step-1.1-feature-demo.md` passed.'
  assert_contains "$prompt" 'User review phase-state source is step plan `## Plan (ordered)` only.'
  assert_contains "$prompt" 'User review functional-requirement source is step plan `## Functional Requirements (translated from design EARS)`.'
  assert_not_contains "$prompt" "== .asdlc_worker/overmind/implementation_plan.md"
  assert_not_contains "$prompt" 'User review checklist (`## Target Bullets`)'
}

test_user_review_fails_when_functional_requirements_unchecked() {
  local repo_dir="$TMP_ROOT/repo-functional-requirements-incomplete"
  local source_dir="$TMP_ROOT/source-functional-requirements-incomplete"
  setup_repo "$repo_dir" 1 checked "$source_dir" "project-functional-incomplete" "feature-demo"

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-demo.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. Implement part A.
## Functional Requirements (translated from design EARS)
- [ ] FR-1.1-001 The system SHALL implement part A behavior. EARS[REQ-1]
EOF
  (
    cd "$repo_dir"
    git add .asdlc_worker/step_plans/step-1.1-feature-demo.md
    git commit -qm "make functional requirements unchecked"
  )

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: user_review phase must fail when translated functional requirements are unchecked" >&2
    exit 1
  fi
  assert_contains "$out" "User review precheck failed for step 1.1."
  assert_contains "$out" "unchecked_functional_requirement_items"
  assert_contains "$out" "Implementation was not finished correctly."
  assert_file_not_exists "$repo_dir/model-ran.flag"
}

test_user_review_does_not_block_on_invalid_user_review_update() {
  local repo_dir="$TMP_ROOT/repo-user-review-invalid-ur-allowed"
  local source_dir="$TMP_ROOT/source-user-review-invalid-ur-allowed"
  setup_repo "$repo_dir" 1 checked "$source_dir" "project-invalid-ur" "feature-demo"

  cat >"$repo_dir/.asdlc_worker/scripts/fake_model.sh" <<'EOF'
#!/usr/bin/env bash
touch "model-ran.flag"
cat >>".asdlc_worker/user_review.md" <<'UR'

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
  chmod +x "$repo_dir/.asdlc_worker/scripts/fake_model.sh"
  (
    cd "$repo_dir"
    git add .asdlc_worker/scripts/fake_model.sh
    git commit -qm "override fake user review model"
  )

  local status=0
  set +e
  (cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 >/tmp/user-review-invalid-ur.out 2>/tmp/user-review-invalid-ur.err)
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: user_review should not fail due to invalid .asdlc_worker/user_review.md content" >&2
    exit 1
  fi
  assert_file_exists "$repo_dir/model-ran.flag"
  assert_branch_equals "$repo_dir" "step-1.1-feature-demo-user-review"
}

test_user_review_fails_fast_when_ordered_plan_unchecked
test_user_review_normalizes_plain_ordered_bullets_to_unchecked
test_user_review_runs_model_when_ordered_plan_checked_even_if_impl_unchecked
test_user_review_branch_handoff_fails_on_unsafe_dirty_state
test_user_review_prompt_uses_ordered_plan_state_only
test_user_review_fails_when_functional_requirements_unchecked
test_user_review_does_not_block_on_invalid_user_review_update

echo "All user review phase tests passed."
