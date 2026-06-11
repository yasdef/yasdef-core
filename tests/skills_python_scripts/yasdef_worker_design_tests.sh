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

test_context_builder_initializes_design_and_prints_context
test_context_builder_requires_explicit_paths
test_readiness_gate_exit_codes
test_readiness_gate_blocks_unresolved_bootstrap

echo "yasdef_worker_design_tests: PASS"
