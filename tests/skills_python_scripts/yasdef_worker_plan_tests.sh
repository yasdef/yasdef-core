#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_DIR="$SOURCE_ROOT/src/yasdef_worker/_data/skills/yasdef-worker-plan"
BUILD_CONTEXT="$SKILL_DIR/scripts/build_plan_context.py"
CHECK_READINESS="$SKILL_DIR/scripts/check_planning_readiness.py"
SYNC_LARS="$SKILL_DIR/scripts/sync_step_lars.py"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export UV_CACHE_DIR="$TMP_ROOT/uv-cache"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Assertion failed: expected output to contain: $needle" >&2
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

  cat >"$repo_dir/source-feature/reqirements_ears.md" <<'EOF'
### Requirement 1 Demo
- The system SHALL implement demo behavior.
EOF

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-feature-test-design.md" <<'EOF'
## Target Bullets (excluding planning/review)
- Implement demo behavior.

## Selected EARS Requirements (for planning translation)
### Requirement 1 Demo
- The system SHALL implement demo behavior.

## Things to Decide (for final planning discussion)
- Adapter strategy: keep adapter A or switch to adapter B.

## Applicable AGENTS.md Constraints
- Keep diffs minimal.

## Applicable UR Shortlist
- UR-0001 - Keep behavior deterministic.

## Applicable ADR Shortlist
- ADR-0001 - Preserve the existing contract.

## Linked Artifacts (in scope)
- LAR-001 | api | Demo API | https://example.invalid/demo-api
EOF
}

test_context_builder_requires_design() {
  local repo_dir="$TMP_ROOT/repo-missing-design"
  local out=""
  local status=0
  setup_repo "$repo_dir"

  set +e
  out="$(
    cd "$repo_dir" && \
      uv run python "$BUILD_CONTEXT" \
        --step 1.1 \
        --feature-id feature-test \
        --design .asdlc_worker/step_designs/missing-design.md \
        --plan-out .asdlc_worker/step_plans/step-1.1-feature-test.md \
        --runtime-plan "$repo_dir/source-feature/implementation_plan.md" \
        --open-questions .asdlc_worker/step_open_questions/step-1.1-feature-test-open-questions.md \
        --blockers .asdlc_worker/step_blockers/step-1.1-feature-test-blockers.md 2>&1
  )"
  status=$?
  set -e

  assert_status "1" "$status"
  assert_contains "$out" "design artifact not found or empty"
}

test_context_builder_initializes_files_and_prints_sections() {
  local repo_dir="$TMP_ROOT/repo-context"
  local out=""
  setup_repo "$repo_dir"

  out="$(
    cd "$repo_dir" && \
      uv run python "$BUILD_CONTEXT" \
        --step 1.1 \
        --feature-id feature-test \
        --design .asdlc_worker/step_designs/step-1.1-feature-test-design.md \
        --plan-out .asdlc_worker/step_plans/step-1.1-feature-test.md \
        --runtime-plan "$repo_dir/source-feature/implementation_plan.md" \
        --open-questions .asdlc_worker/step_open_questions/step-1.1-feature-test-open-questions.md \
        --blockers .asdlc_worker/step_blockers/step-1.1-feature-test-blockers.md
  )"

  assert_file_exists "$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-test.md"
  assert_file_exists "$repo_dir/.asdlc_worker/step_open_questions/step-1.1-feature-test-open-questions.md"
  assert_file_exists "$repo_dir/.asdlc_worker/step_blockers/step-1.1-feature-test-blockers.md"
  assert_contains "$out" "# YASDEF Planning Context: Step 1.1 - Demo feature"
  assert_contains "$out" "Requirements EARS path (pointer only): source-feature/reqirements_ears.md"
  assert_contains "$out" "## Design Target Bullets"
  assert_contains "$out" "## Design Selected EARS Requirements (for planning translation)"
  assert_contains "$out" "## Design Things to Decide (for final planning discussion)"
  assert_contains "$out" "## Current Open Questions Ledger"
  assert_contains "$out" "## Current Blockers Ledger"
  assert_contains "$out" "## Step Plan Golden Example"
  assert_contains "$(cat "$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-test.md")" "## Applicable UR Shortlist"
}

test_sync_step_lars_is_idempotent() {
  local repo_dir="$TMP_ROOT/repo-sync"
  setup_repo "$repo_dir"

  mkdir -p "$repo_dir/.asdlc_worker/step_plans"
  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-test.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [ ] 1. Implement demo behavior.
EOF

  (
    cd "$repo_dir"
    uv run python "$SYNC_LARS" \
      --design .asdlc_worker/step_designs/step-1.1-feature-test-design.md \
      --step-plan .asdlc_worker/step_plans/step-1.1-feature-test.md
  )
  local first_run
  first_run="$(cat "$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-test.md")"

  (
    cd "$repo_dir"
    uv run python "$SYNC_LARS" \
      --design .asdlc_worker/step_designs/step-1.1-feature-test-design.md \
      --step-plan .asdlc_worker/step_plans/step-1.1-feature-test.md
  )
  local second_run
  second_run="$(cat "$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-test.md")"

  assert_contains "$first_run" "## Linked Artifacts (in scope)"
  assert_contains "$first_run" "LAR-001 | api | Demo API | https://example.invalid/demo-api"
  if [[ "$first_run" != "$second_run" ]]; then
    echo "Assertion failed: sync_step_lars.py should be idempotent" >&2
    exit 1
  fi
}

test_readiness_rejects_malformed_plan_and_unresolved_decision() {
  local repo_dir="$TMP_ROOT/repo-not-ready"
  local out=""
  local status=0
  setup_repo "$repo_dir"

  cat >"$repo_dir/not-ready.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Applicable UR Shortlist
- None.
## Plan (ordered)
- [ ] 1. Implement demo behavior.
## Functional Requirements (translated from design EARS)
- [ ] FR-1.1-001 The system SHALL implement demo behavior. EARS[REQ-1]
## Decisions Needed
- Something else | Accepted | Not the same design decision.
EOF

  set +e
  out="$(
    cd "$repo_dir" && \
      uv run python "$CHECK_READINESS" \
        --design .asdlc_worker/step_designs/step-1.1-feature-test-design.md \
        --step-plan not-ready.md 2>&1
  )"
  status=$?
  set -e

  assert_status "1" "$status"
  assert_contains "$out" '"ready": false'
  assert_contains "$out" "design decision lacks explicit outcome in step plan: Adapter strategy"
}

test_readiness_accepts_complete_plan_and_missing_ledgers_as_clean() {
  local repo_dir="$TMP_ROOT/repo-ready"
  local out=""
  setup_repo "$repo_dir"

  cat >"$repo_dir/ready.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Applicable UR Shortlist
- None.
## Plan (ordered)
- [ ] 1. Implement demo behavior.
## Functional Requirements (translated from design EARS)
- [ ] FR-1.1-001 The system SHALL implement demo behavior. EARS[REQ-1]
## Architecture / Helper Flow
- Demo flow.
## Decisions Needed
- Adapter strategy | Accepted | Keep adapter A because it matches the current wiring.
EOF

  out="$(
    cd "$repo_dir" && \
      uv run python "$CHECK_READINESS" \
        --design .asdlc_worker/step_designs/step-1.1-feature-test-design.md \
        --step-plan ready.md \
        --open-questions missing-open-questions.md \
        --blockers missing-blockers.md
  )"

  assert_contains "$out" '"ready": true'
  assert_contains "$out" '"open_questions_dirty": false'
  assert_contains "$out" '"blockers_dirty": false'
}

test_context_builder_requires_design
test_context_builder_initializes_files_and_prints_sections
test_sync_step_lars_is_idempotent
test_readiness_rejects_malformed_plan_and_unresolved_decision
test_readiness_accepts_complete_plan_and_missing_ledgers_as_clean

echo "yasdef_worker_plan_tests: PASS"
