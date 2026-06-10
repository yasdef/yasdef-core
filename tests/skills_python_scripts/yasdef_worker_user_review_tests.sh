#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_DIR="$SOURCE_ROOT/src/yasdef_worker/_data/skills/yasdef-worker-user-review"
BUILD_CONTEXT="$SKILL_DIR/scripts/build_user_review_context.py"

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
- [x] Implement demo behavior. [REQ-1]
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
- This text must not reach user review context.

## Proposal / Design Details
- Forbidden proposal detail.

## Risks and Mitigations
- Forbidden design risk.

## Applicable ADR Shortlist
- Forbidden ADR.

## Applicable UR Shortlist
- UR-9999 - Forbidden design UR.
EOF

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-test.md" <<'EOF'
# Step Plan: 1.1 - Demo feature
## Plan (ordered)
- Create demo service.
- [x] Wire demo endpoint.

## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 The system SHALL implement demo behavior. EARS[REQ-1]

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

## Decisions Needed
- Adapter strategy | Accepted | Keep the existing adapter.
- Follow-up strategy | Deferred | Later step.
EOF

  cat >"$repo_dir/.asdlc_worker/blocker_log.md" <<'EOF'
## Step 1.1 Demo feature
- No blockers.
EOF

  cat >"$repo_dir/.asdlc_worker/open_questions.md" <<'EOF'
## Step 1.1 Demo feature
- No open questions.
EOF

  cat >"$repo_dir/.asdlc_worker/user_review.md" <<'EOF'
# User review rules

## UR-0001
- Keep behavior deterministic.
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
        --design .asdlc_worker/step_designs/missing.md \
        --runtime-plan "$repo_dir/source-feature/implementation_plan.md" 2>&1
  )"
  status=$?
  set -e

  assert_status "1" "$status"
  assert_contains "$out" "design artifact not found or empty"
}

test_context_builder_prints_review_contract_and_allowed_scope_only() {
  local repo_dir="$TMP_ROOT/repo-context"
  local out=""
  local ur_shortlist=""
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

  assert_contains "$out" "# YASDEF User Review Context: Step 1.1"
  assert_contains "$out" "## Review Contract"
  assert_contains "$out" "- [ ] Create demo service."
  assert_contains "$out" "FR-1.1-001"
  assert_contains "$out" "Adapter strategy | Accepted | Keep the existing adapter."
  assert_contains "$out" "### Goal"
  assert_contains "$out" "Implement scoped demo behavior."
  assert_contains "$out" "### In Scope"
  assert_contains "$out" "Demo API behavior."
  assert_contains "$out" "### Out of Scope"
  assert_contains "$out" "Later reporting."
  assert_contains "$out" "## Step 1.1 Demo feature"
  assert_contains "$out" "No blockers."
  assert_contains "$out" "No open questions."
  assert_contains "$out" ".asdlc_worker/user_review.md"
  assert_contains "$out" ".codex/skills/yasdef-worker-user-review/assets/user_review_TEMPLATE.md"
  assert_contains "$out" ".codex/skills/yasdef-worker-user-review/assets/review_brief_TEMPLATE.md"
  assert_contains "$out" ".codex/skills/yasdef-worker-user-review/assets/review_brief_GOLDEN_EXAMPLE.md"
  assert_contains "$out" ".codex/skills/yasdef-worker-user-review/assets/user_review_GOLDEN_EXAMPLE.md"

  ur_shortlist="$(printf '%s\n' "$out" | awk 'f && /^## Scope Contract/ { exit } f { print } /^### Applicable UR Shortlist/ { f=1 }')"
  assert_contains "$ur_shortlist" "- UR-0008 - Rule 8."
  assert_not_contains "$ur_shortlist" "- UR-0009 - Rule 9."
  assert_not_contains "$out" "UR-9999"
  assert_not_contains "$out" "This text must not reach user review context."
  assert_not_contains "$out" "Forbidden proposal detail."
  assert_not_contains "$out" "Forbidden design risk."
  assert_not_contains "$out" "Forbidden ADR."
}

test_context_builder_requires_step_plan
test_context_builder_requires_design
test_context_builder_prints_review_contract_and_allowed_scope_only

echo "yasdef_worker_user_review_tests: PASS"
