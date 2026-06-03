#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_DIR="$SOURCE_ROOT/ai/skills/yasdef-worker-implementation"
BUILD_CONTEXT="$SKILL_DIR/scripts/build_implementation_context.py"
CHECK_READINESS="$SKILL_DIR/scripts/check_implementation_readiness.py"

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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "Assertion failed: expected output not to contain: $needle" >&2
    echo "$haystack" >&2
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
  mkdir -p "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/step_designs" "$repo_dir/source-feature"

  cat >"$repo_dir/source-feature/implementation_plan.md" <<'EOF'
### Step 1.1 Demo feature
- [x] Plan and discuss the step. [REQ-1]
- [ ] Implement demo behavior. [REQ-1]
- [ ] Review step implementation.
EOF

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-feature-test-design.md" <<'EOF'
## Goal
- Implement scoped demo behavior.

## In Scope
- Demo API behavior.

## Out of Scope
- Later reporting.

## Non-goals
- This text must not reach implementation context.

## Proposal / Design Details
- Forbidden proposal detail.

## Risks and Mitigations
- Forbidden design risk.

## Applicable ADR Shortlist
- Forbidden ADR.

## Applicable AGENTS.md Constraints
- Forbidden AGENTS detail.

## References in Current Codebase
- Forbidden code reference.

## Applicable UR Shortlist
- UR-9999 - Forbidden design UR.
EOF

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-test.md" <<'EOF'
# Step Plan: 1.1 - Demo feature
## Plan (ordered)
- Create demo service.
- [ ] Wire demo endpoint.

## Functional Requirements (translated from design EARS)
- [ ] FR-1.1-001 The system SHALL implement demo behavior. EARS[REQ-1]

## Applicable UR Shortlist
- UR-0001 - Preserve deterministic behavior.
- UR-0002 - Keep public output stable.
- UR-0003 - Rule 3.
- UR-0004 - Rule 4.
- UR-0005 - Rule 5.
- UR-0006 - Rule 6.
- UR-0007 - Rule 7.
- UR-0008 - Rule 8.
- UR-0009 - Rule 9.

## Architecture / Helper Flow
- Route calls through DemoService.

## Implementation Notes / Constraints
- Keep changes minimal.

## Tests
- Run demo tests.

## Risks / Edge Cases
- Missing data.

## Decisions Needed
- Adapter strategy | Accepted | Keep the existing adapter.
- Follow-up strategy | Deferred | Later step.

## Linked Artifacts (in scope)
- LAR-001 | api | Demo API | https://example.invalid/demo-api
EOF
}

test_context_builder_requires_step_plan() {
  local repo_dir="$TMP_ROOT/repo-missing-step-plan"
  local out=""
  local status=0
  setup_repo "$repo_dir"

  set +e
  out="$(
    cd "$repo_dir" && \
      uv run python "$BUILD_CONTEXT" \
        --step 1.1 \
        --feature-id feature-test \
        --step-plan .asdlc_worker/step_plans/missing.md \
        --design .asdlc_worker/step_designs/step-1.1-feature-test-design.md \
        --runtime-plan "$repo_dir/source-feature/implementation_plan.md" 2>&1
  )"
  status=$?
  set -e

  assert_status "1" "$status"
  assert_contains "$out" "step plan not found or empty"
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
        --step-plan .asdlc_worker/step_plans/step-1.1-feature-test.md \
        --design .asdlc_worker/step_designs/missing-design.md \
        --runtime-plan "$repo_dir/source-feature/implementation_plan.md" 2>&1
  )"
  status=$?
  set -e

  assert_status "1" "$status"
  assert_contains "$out" "design artifact not found or empty"
}

test_context_builder_prints_allowed_context_only() {
  local repo_dir="$TMP_ROOT/repo-context"
  local out=""
  local anti_regression=""
  setup_repo "$repo_dir"

  out="$(
    cd "$repo_dir" && \
      uv run python "$BUILD_CONTEXT" \
        --step 1.1 \
        --feature-id feature-test \
        --step-plan .asdlc_worker/step_plans/step-1.1-feature-test.md \
        --design .asdlc_worker/step_designs/step-1.1-feature-test-design.md \
        --runtime-plan "$repo_dir/source-feature/implementation_plan.md"
  )"

  assert_contains "$out" "# YASDEF Implementation Context: Step 1.1"
  assert_contains "$out" "## Anti-regression Checklist (from step-plan"
  assert_contains "$out" "- UR-0008 - Rule 8."
  anti_regression="$(printf '%s\n' "$out" | awk 'f && /^## Execution List/ { exit } f { print } /^## Anti-regression Checklist/ { f=1 }')"
  assert_not_contains "$anti_regression" "- UR-0009 - Rule 9."
  assert_not_contains "$out" "UR-9999"
  assert_contains "$out" "- [ ] Create demo service."
  assert_contains "$out" "### Goal"
  assert_contains "$out" "Implement scoped demo behavior."
  assert_contains "$out" "### In Scope"
  assert_contains "$out" "Demo API behavior."
  assert_contains "$out" "### Out of Scope"
  assert_contains "$out" "Later reporting."
  assert_not_contains "$out" "This text must not reach implementation context."
  assert_not_contains "$out" "Forbidden proposal detail."
  assert_not_contains "$out" "Forbidden design risk."
  assert_not_contains "$out" "Forbidden ADR."
  assert_not_contains "$out" "Forbidden AGENTS detail."
  assert_not_contains "$out" "Forbidden code reference."
}

test_readiness_rejects_unchecked_items() {
  local repo_dir="$TMP_ROOT/repo-not-ready"
  local out=""
  local status=0
  setup_repo "$repo_dir"

  set +e
  out="$(
    cd "$repo_dir" && \
      uv run python "$CHECK_READINESS" \
        --step 1.1 \
        --step-plan .asdlc_worker/step_plans/step-1.1-feature-test.md 2>&1
  )"
  status=$?
  set -e

  assert_status "1" "$status"
  assert_contains "$out" '"ready": false'
  assert_contains "$out" "unchecked_ordered_plan_items"
  assert_contains "$out" "unchecked_functional_requirement_items"
}

test_readiness_accepts_closed_checklists_and_status_done_frs() {
  local repo_dir="$TMP_ROOT/repo-ready"
  local out=""
  setup_repo "$repo_dir"

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-test.md" <<'EOF'
## Plan (ordered)
- [x] Create demo service.
- [x] Wire demo endpoint.

## Functional Requirements
### FR-1.1-001 The system SHALL implement demo behavior. EARS[REQ-1]
- Status: Done
EOF

  out="$(
    cd "$repo_dir" && \
      uv run python "$CHECK_READINESS" \
        --step 1.1 \
        --step-plan .asdlc_worker/step_plans/step-1.1-feature-test.md
  )"

  assert_contains "$out" '"ready": true'
  assert_contains "$out" '"functional_requirement_items": 1'
}

test_context_builder_requires_step_plan
test_context_builder_requires_design
test_context_builder_prints_allowed_context_only
test_readiness_rejects_unchecked_items
test_readiness_accepts_closed_checklists_and_status_done_frs

echo "yasdef_worker_implementation_tests: PASS"
