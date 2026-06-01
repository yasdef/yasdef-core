#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"
IMPLEMENTATION_SKILL_DIR="$SOURCE_ROOT/ai/codex/skills/yasdef-worker-implementation"
USER_REVIEW_SKILL_DIR="$SOURCE_ROOT/ai/codex/skills/yasdef-worker-user-review"
AI_AUDIT_SKILL_DIR="$SOURCE_ROOT/ai/codex/skills/yasdef-worker-ai-audit"

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

assert_nonzero_status() {
  local status="$1"
  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: expected non-zero status" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"
  local worker_uuid="11111111-1111-1111-1111-111111111111"
  local source_dir="$TMP_ROOT/source-debug-${repo_dir##*/}"
  local remote_dir="${source_dir}-remote.git"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/setup" "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/step_review_results" \
    "$repo_dir/.asdlc_worker/overmind" "$repo_dir/.codex/skills"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"

  cp "$ORCH_SRC" "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp -R "$IMPLEMENTATION_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-implementation"
  cp -R "$USER_REVIEW_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-user-review"
  cp -R "$AI_AUDIT_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-ai-audit"
  chmod +x "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"

  cat >"$repo_dir/.asdlc_worker/scripts/ai_user_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROMPT_MARKER=${PROMPT_MARKER:-default-user-review}"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_audit.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROMPT_MARKER=${PROMPT_MARKER:-default-review}"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post_review"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/fake_model.sh" <<'EOF'
#!/usr/bin/env bash
echo "MODEL_MARKER=${MODEL_MARKER:-default-model}"
echo "Token usage: input=1 output=1 total=2"
EOF
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_user_review.sh" "$repo_dir/.asdlc_worker/scripts/ai_audit.sh" \
    "$repo_dir/.asdlc_worker/scripts/post_review.sh" "$repo_dir/.asdlc_worker/scripts/fake_model.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
design | .asdlc_worker/scripts/fake_model.sh | mock-model
planning | .asdlc_worker/scripts/fake_model.sh | mock-model
implementation | .asdlc_worker/scripts/fake_model.sh | mock-model
user_review | .asdlc_worker/scripts/fake_model.sh | mock-model
ai_audit | .asdlc_worker/scripts/fake_model.sh | mock-model
EOF

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-one.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- 1. demo
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL execute demo behavior.
- Plan Links: 1
- Verification: demo
- Status: done
EOF
  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-feature-one-design.md" <<'EOF'
## Goal
- Demo goal.

## In Scope
- Demo scope.

## Out of Scope
- Later work.
EOF

  cat >"$repo_dir/.asdlc_worker/step_review_results/review_result-1.1-feature-one.md" <<'EOF'
# Review Result: Step 1.1
## Disposition (per issue)
- None.
EOF

  mkdir -p "$source_dir/feature-one"
  cat >"$source_dir/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF
  cat >"$source_dir/init_progress_definition.yaml" <<'EOF'
meta_info:
  project_id: 'project-debug'
steps: []
EOF
  cat >"$source_dir/feature-one/implementation_plan.md" <<EOF
### Step 1.1 Demo
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
- [ ] Implement demo behavior (SP=1)
EOF
  cat >"$source_dir/feature-one/requirements_ears.md" <<'EOF'
### Requirement 1 Demo
- The system SHALL support demo behavior.
EOF

  (
    cd "$source_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add -A
    git commit -qm "init source repo"
    git init -q --bare "$remote_dir"
    git --git-dir "$remote_dir" symbolic-ref HEAD refs/heads/master
    git remote add origin "$remote_dir"
    git push -q -u origin master
  )

  cat >"$repo_dir/ai/project_overmind.yaml" <<EOF
overmind_source_path: '$source_dir'
project_id: 'project-debug'
worker_uuid: '$worker_uuid'
class: 'platform'
status: 'ready'
EOF

  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
  )
}

set_single_phase_model() {
  local repo_dir="$1"
  local phase="$2"
  cat >"$repo_dir/ai/setup/models.md" <<EOF
$phase | .asdlc_worker/scripts/fake_model.sh | mock-model
EOF
}

run_non_debug_design_writes_latest_log_only() {
  local repo_dir="$TMP_ROOT/repo-non-debug"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  (
    cd "$repo_dir"
    set_single_phase_model "$repo_dir" "design"
    PROMPT_MARKER=first MODEL_MARKER=first .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 >/tmp/orch-test.out 2>/tmp/orch-test.err
  )

  local latest_log="$repo_dir/.asdlc_worker/logs/repo-non-debug-design-latest-log"
  assert_file_exists "$latest_log"
  assert_contains_file "$latest_log" "MODEL_MARKER=first"
}

run_debug_design_writes_step_specific_log() {
  local repo_dir="$TMP_ROOT/repo-debug"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  (
    cd "$repo_dir"
    set_single_phase_model "$repo_dir" "design"
    PROMPT_MARKER=debug MODEL_MARKER=debug .asdlc_worker/scripts/orchestrator.sh --debug -- --step 1.1 >/tmp/orch-test.out 2>/tmp/orch-test.err
  )

  local step_log="$repo_dir/.asdlc_worker/logs/repo-debug-design-1-1-log"
  assert_file_exists "$step_log"
  assert_contains_file "$step_log" "MODEL_MARKER=debug"
}

run_orchestrator_fails_when_uv_missing() {
  local repo_dir="$TMP_ROOT/repo-missing-uv"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  local out=""
  local status=0
  set +e
  out="$(
    cd "$repo_dir" &&
    set_single_phase_model "$repo_dir" "planning" &&
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" .asdlc_worker/scripts/orchestrator.sh --dry-run -- --step 1.1 2>&1
  )"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "ERROR: ASDLC orchestrator requires 'uv' to be installed and available in PATH."
}

run_latest_log_overwrite_and_legacy_preserved() {
  local repo_dir="$TMP_ROOT/repo-overwrite"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  (
    cd "$repo_dir"
    set_single_phase_model "$repo_dir" "design"
    PROMPT_MARKER=seed MODEL_MARKER=seed .asdlc_worker/scripts/orchestrator.sh --debug -- --step 1.1 >/tmp/orch-test.out 2>/tmp/orch-test.err
  )

  local step_log="$repo_dir/.asdlc_worker/logs/repo-overwrite-design-1-1-log"
  local step_log_before
  step_log_before="$(cat "$step_log")"

  (
    cd "$repo_dir"
    set_single_phase_model "$repo_dir" "design"
    PROMPT_MARKER=first MODEL_MARKER=first .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 >/tmp/orch-test.out 2>/tmp/orch-test.err
    PROMPT_MARKER=second MODEL_MARKER=second .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 >/tmp/orch-test.out 2>/tmp/orch-test.err
  )

  local latest_log="$repo_dir/.asdlc_worker/logs/repo-overwrite-design-latest-log"
  assert_file_exists "$latest_log"
  assert_contains_file "$latest_log" "MODEL_MARKER=second"

  local step_log_after
  step_log_after="$(cat "$step_log")"
  assert_equal "$step_log_before" "$step_log_after"
}

run_user_review_dry_run_reports_log_path() {
  local repo_dir="$TMP_ROOT/repo-user-review-latest"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  local out
  out="$(
    cd "$repo_dir" &&
    set_single_phase_model "$repo_dir" "user_review" &&
    PROMPT_MARKER=ur MODEL_MARKER=ur .asdlc_worker/scripts/orchestrator.sh --dry-run
  )"

  assert_contains "$out" "dry-run log: .asdlc_worker/logs/repo-user-review-latest-user-review-latest-log"
  assert_contains "$out" "run yasdef-worker-user-review for step"
}

run_ai_audit_dry_run_reports_log_path() {
  local repo_dir="$TMP_ROOT/repo-ai-audit-latest"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  local out
  out="$(
    cd "$repo_dir" &&
    set_single_phase_model "$repo_dir" "ai_audit" &&
    PROMPT_MARKER=audit MODEL_MARKER=audit .asdlc_worker/scripts/orchestrator.sh --dry-run
  )"

  assert_contains "$out" "dry-run log: .asdlc_worker/logs/repo-ai-audit-latest-ai-audit-latest-log"
  assert_contains "$out" "run yasdef-worker-ai-audit for step"
}

run_source_includes_user_review_interactive_confirmation() {
  local repo_dir="$TMP_ROOT/repo-confirmation-check"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  local out
  out="$(grep -n "planning|implementation|user_review|ai_audit" "$repo_dir/.asdlc_worker/scripts/orchestrator.sh" || true)"
  assert_contains "$out" "planning|implementation|user_review|ai_audit"
}

run_non_debug_design_writes_latest_log_only
run_debug_design_writes_step_specific_log
run_orchestrator_fails_when_uv_missing
run_latest_log_overwrite_and_legacy_preserved
run_user_review_dry_run_reports_log_path
run_ai_audit_dry_run_reports_log_path
run_source_includes_user_review_interactive_confirmation

echo "All orchestrator debug tests passed."
