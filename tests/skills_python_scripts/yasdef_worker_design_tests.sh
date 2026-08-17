#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_DIR="$SOURCE_ROOT/src/yasdef_worker/_data/skills/yasdef-worker-design"
BUILD_CONTEXT="$SKILL_DIR/scripts/build_design_context.py"
CHECK_READINESS="$SKILL_DIR/scripts/check_design_readiness.py"

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

assert_status() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed: expected status $expected, got $actual" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/.asdlc_worker/step_designs" "$repo_dir/source-feature"

  cat >"$repo_dir/source-feature/implementation_plan.md" <<'EOF'
### Step 1.1 Demo feature
- [ ] Plan and discuss the step. [REQ-1]
- [ ] Implement demo behavior. [REQ-1]
- [ ] Review step implementation.
EOF

  cat >"$repo_dir/source-feature/requirements_ears.md" <<'EOF'
## Linked Artifacts
- id: LAR-001
  type: api
  title: Demo API
  locator: https://example.invalid/demo-api

### Requirement 1 Demo
**Linked Artifacts:**
- LAR-001

- The system SHALL implement demo behavior.
EOF

  cat >"$repo_dir/.asdlc_worker/blocker_log.md" <<'EOF'
## Step 1.1 Demo feature
- No blockers.
EOF

  cat >"$repo_dir/.asdlc_worker/open_questions.md" <<'EOF'
## Step 1.1 Demo feature
- No open questions.
EOF

  cat >"$repo_dir/.asdlc_worker/feature_meta_sync.yaml" <<'EOF'
project_id: 'project-test'
worker_uuid: '11111111-1111-1111-1111-111111111111'
feature_id: 'feature-test'
selected_step: '1.1'
EOF
}

test_context_builder_initializes_design_and_prints_context() {
  local repo_dir="$TMP_ROOT/repo-context"
  local out=""
  setup_repo "$repo_dir"

  out="$(
    cd "$repo_dir"
    python3 "$BUILD_CONTEXT" \
      --step 1.1 \
      --design-out .asdlc_worker/step_designs/step-1.1-feature-test-design.md \
      --plan "$repo_dir/source-feature/implementation_plan.md" \
      --ears "$repo_dir/source-feature/requirements_ears.md"
  )"

  assert_file_exists "$repo_dir/.asdlc_worker/step_designs/step-1.1-feature-test-design.md"
  assert_contains "$out" "# YASDEF Design Context: Step 1.1 - Demo feature"
  assert_contains "$out" "### Requirement 1 Demo"
  assert_contains "$out" "- LAR-001 | api | Demo API | https://example.invalid/demo-api"
  assert_contains "$out" "## Feature Design Golden Example"
  assert_contains "$out" "# Feature Design: 1.6x - Example feature title"
  assert_contains "$(cat "$repo_dir/.asdlc_worker/step_designs/step-1.1-feature-test-design.md")" "## Goal"
}

test_context_builder_requires_explicit_paths() {
  local repo_dir="$TMP_ROOT/repo-context-required-paths"
  local out=""
  local status=0
  setup_repo "$repo_dir"

  set +e
  out="$(cd "$repo_dir" && python3 "$BUILD_CONTEXT" --step 1.1 --design-out .asdlc_worker/step_designs/step-1.1-feature-test-design.md 2>&1)"
  status=$?
  set -e

  assert_status "2" "$status"
  assert_contains "$out" "the following arguments are required: --plan, --ears"
}

test_readiness_gate_exit_codes() {
  local repo_dir="$TMP_ROOT/repo-readiness"
  local out=""
  local status=0
  setup_repo "$repo_dir"

  cat >"$repo_dir/ready.md" <<'EOF'
## Goal
- Ready.
## In Scope
- Ready.
## Out of Scope
- Ready.
EOF

  out="$(cd "$repo_dir" && python3 "$CHECK_READINESS" ready.md)"
  assert_contains "$out" '"ready": true'

  cat >"$repo_dir/not-ready.md" <<'EOF'
## Goal
- Missing scope.
EOF

  set +e
  out="$(cd "$repo_dir" && python3 "$CHECK_READINESS" not-ready.md)"
  status=$?
  set -e
  assert_status "1" "$status"
  assert_contains "$out" "missing required sections: In Scope Out of Scope"
}

test_readiness_gate_blocks_unresolved_bootstrap() {
  local repo_dir="$TMP_ROOT/repo-bootstrap"
  local out=""
  local status=0
  setup_repo "$repo_dir"

  cat >"$repo_dir/bootstrap.md" <<'EOF'
## Goal
- Bootstrap.
## In Scope
- Bootstrap.
## Out of Scope
- Later implementation.
## First-Feature Bootstrap (only if needed)
- Bootstrap required: yes
- Planning handoff: Pending user direction.
EOF

  set +e
  out="$(cd "$repo_dir" && python3 "$CHECK_READINESS" bootstrap.md)"
  status=$?
  set -e
  assert_status "1" "$status"
  assert_contains "$out" "bootstrap-required design must include a concrete planning handoff"
}

write_bootstrap_design() {
  local path="$1"
  local agents_state="$2"
  local claude_state="$3"
  local disposition="$4"
  local source_line="${5:-}"

  {
    echo "## Goal"
    echo "- Bootstrap."
    echo "## In Scope"
    echo "- Bootstrap."
    echo "## Out of Scope"
    echo "- Later implementation."
    echo "## First-Feature Bootstrap (only if needed)"
    echo "- Bootstrap required: yes"
    echo "- Planning handoff: Create the runnable scaffold."
    echo "- Agents guidance lookup: found 1 class-matching candidate."
    echo "- Project AGENTS.md state: $agents_state"
    echo "- Project CLAUDE.md state: $claude_state"
    if [[ -n "$disposition" ]]; then
      echo "- Agent-guidance disposition: $disposition"
    fi
    if [[ -n "$source_line" ]]; then
      echo "- Agent-guidance source: $source_line"
    fi
  } >"$path"
}

READINESS_STATUS=0
READINESS_OUT=""

run_readiness() {
  local repo_dir="$1"
  local design="$2"
  set +e
  READINESS_OUT="$(cd "$repo_dir" && python3 "$CHECK_READINESS" "$design")"
  READINESS_STATUS=$?
  set -e
}

test_readiness_gate_accepts_valid_dispositions() {
  local repo_dir="$TMP_ROOT/repo-dispositions"
  local out=""
  setup_repo "$repo_dir"

  write_bootstrap_design "$repo_dir/both-present.md" "present" "present" "both-present-no-action"
  run_readiness "$repo_dir" both-present.md
  out="$READINESS_OUT"
  assert_status "0" "$READINESS_STATUS"
  assert_contains "$out" '"ready": true'

  write_bootstrap_design "$repo_dir/approved.md" "present" "absent" "regenerate-both-approved" \
    "project_agents_md_claude_md_backend.md"
  run_readiness "$repo_dir" approved.md
  out="$READINESS_OUT"
  assert_status "0" "$READINESS_STATUS"
  assert_contains "$out" '"ready": true'

  write_bootstrap_design "$repo_dir/declined.md" "absent" "absent" "leave-unchanged-declined"
  run_readiness "$repo_dir" declined.md
  out="$READINESS_OUT"
  assert_status "0" "$READINESS_STATUS"
  assert_contains "$out" '"ready": true'
}

test_readiness_gate_blocks_invalid_guidance_records() {
  local repo_dir="$TMP_ROOT/repo-guidance-blocked"
  local out=""
  setup_repo "$repo_dir"

  # A directory at a project-root guidance path blocks readiness.
  write_bootstrap_design "$repo_dir/invalid-dir.md" "invalid-directory" "absent" "regenerate-both-approved" \
    "project_agents_md_claude_md_backend.md"
  run_readiness "$repo_dir" invalid-dir.md
  out="$READINESS_OUT"
  assert_status "1" "$READINESS_STATUS"
  assert_contains "$out" "a project-root guidance path is a directory"

  # Missing file-state fields.
  cat >"$repo_dir/missing-states.md" <<'EOF'
## Goal
- Bootstrap.
## In Scope
- Bootstrap.
## Out of Scope
- Later implementation.
## First-Feature Bootstrap (only if needed)
- Bootstrap required: yes
- Planning handoff: Create the runnable scaffold.
- Agent-guidance disposition: leave-unchanged-declined
EOF
  run_readiness "$repo_dir" missing-states.md
  out="$READINESS_OUT"
  assert_status "1" "$READINESS_STATUS"
  assert_contains "$out" "must record 'Project AGENTS.md state'"
  assert_contains "$out" "must record 'Project CLAUDE.md state'"

  # Missing disposition.
  write_bootstrap_design "$repo_dir/no-disposition.md" "present" "absent" ""
  run_readiness "$repo_dir" no-disposition.md
  out="$READINESS_OUT"
  assert_status "1" "$READINESS_STATUS"
  assert_contains "$out" "must record 'Agent-guidance disposition'"

  # Disposition inconsistent with the recorded states.
  write_bootstrap_design "$repo_dir/inconsistent.md" "present" "present" "regenerate-both-approved" \
    "project_agents_md_claude_md_backend.md"
  run_readiness "$repo_dir" inconsistent.md
  out="$READINESS_OUT"
  assert_status "1" "$READINESS_STATUS"
  assert_contains "$out" "disposition must be both-present-no-action"

  write_bootstrap_design "$repo_dir/inconsistent-noop.md" "present" "absent" "both-present-no-action"
  run_readiness "$repo_dir" inconsistent-noop.md
  out="$READINESS_OUT"
  assert_status "1" "$READINESS_STATUS"
  assert_contains "$out" "both-present-no-action requires both project-root guidance files to be present"

  # Approved regeneration without a recorded source.
  write_bootstrap_design "$repo_dir/no-source.md" "absent" "absent" "regenerate-both-approved"
  run_readiness "$repo_dir" no-source.md
  out="$READINESS_OUT"
  assert_status "1" "$READINESS_STATUS"
  assert_contains "$out" "regenerate-both-approved requires one 'Agent-guidance source'"
}

test_skill_states_all_or_nothing_reconciliation_contract() {
  local skill=""
  skill="$(cat "$SKILL_DIR/SKILL.md")"

  assert_contains "$skill" '`Yes, regenerate both files`'
  assert_contains "$skill" '`No, leave the repository unchanged`'
  assert_contains "$skill" "Never offer a per-file choice, a merge, partial preservation, or creation of only the missing file."
  assert_contains "$skill" "never inspect or modify global/user-home guidance files"
  assert_contains "$skill" "invalid-directory"
}

test_context_builder_initializes_design_and_prints_context
test_context_builder_requires_explicit_paths
test_readiness_gate_exit_codes
test_readiness_gate_blocks_unresolved_bootstrap
test_readiness_gate_accepts_valid_dispositions
test_readiness_gate_blocks_invalid_guidance_records
test_skill_states_all_or_nothing_reconciliation_contract

echo "yasdef_worker_design_tests: PASS"
