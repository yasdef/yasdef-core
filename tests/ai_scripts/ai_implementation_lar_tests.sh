#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_IMPL_SRC="$SOURCE_ROOT/ai/scripts/ai_implementation.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"
IMPLEMENTATION_READINESS_SRC="$SOURCE_ROOT/ai/scripts/helpers/check_implementation_readiness.sh"

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

setup_impl_repo() {
  local repo_dir="$1"
  mkdir -p \
    "$repo_dir/.asdlc_worker/scripts/helpers" \
    "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" \
    "$repo_dir/.asdlc_worker/prompts/impl_prompts" \
    "$repo_dir/.asdlc_worker/overmind"

  cp "$AI_IMPL_SRC" "$repo_dir/.asdlc_worker/scripts/ai_implementation.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp "$IMPLEMENTATION_READINESS_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/check_implementation_readiness.sh"
  chmod +x \
    "$repo_dir/.asdlc_worker/scripts/ai_implementation.sh" \
    "$repo_dir/.asdlc_worker/scripts/helpers/check_implementation_readiness.sh"

  cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [x] Plan and discuss the step. [REQ-1]
- [ ] Implement the feature. [REQ-1]
- [ ] Review step implementation.
EOF

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
## Plan (ordered)
- [x] 1. Do the thing.

## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 The system SHALL do the thing. EARS[REQ-1]
EOF

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-demo-design.md" <<'EOF'
## Selected EARS Requirements (for planning translation)
### Requirement 1 Demo
- The system SHALL do the thing.

## Goal
- Do the thing.
EOF

  touch "$repo_dir/.asdlc_worker/AI_DEVELOPMENT_PROCESS.md"
}

test_ai_implementation_fails_fast_without_planning_readiness_script() {
  local repo_dir="$TMP_ROOT/repo-impl-fail-fast"
  setup_impl_repo "$repo_dir"

  local status=0
  local out=""
  set +e
  out="$(
    cd "$repo_dir" &&
    ASDLC_RUNTIME_PLAN_PATH=".asdlc_worker/overmind/implementation_plan.md" \
    ASDLC_RUNTIME_EARS_PATH=".asdlc_worker/overmind/reqirements_ears.md" \
    .asdlc_worker/scripts/ai_implementation.sh \
      --step 1.1 \
      --feature-id demo \
      --step-plan ".asdlc_worker/step_plans/step-1.1-demo.md" \
      --design ".asdlc_worker/step_designs/step-1.1-demo-design.md" \
      --out ".asdlc_worker/prompts/impl_prompts/out.txt" \
      --no-branch 2>&1
  )"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: ai_implementation should fail fast until the implementation phase is migrated to a skill." >&2
    exit 1
  fi
  assert_contains "$out" "no script to check planing readiness"
  if [[ -e "$repo_dir/.asdlc_worker/prompts/impl_prompts/out.txt" ]]; then
    echo "Assertion failed: ai_implementation should not write an implementation prompt after fail-fast exit." >&2
    exit 1
  fi
}

test_ai_implementation_fails_fast_without_planning_readiness_script

echo "All ai_implementation tests passed."
