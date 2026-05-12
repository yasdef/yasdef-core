#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_IMPL_SRC="$SOURCE_ROOT/ai/scripts/ai_implementation.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"
PLANNING_READINESS_SRC="$SOURCE_ROOT/ai/scripts/helpers/check_planning_readiness.sh"
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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "Assertion failed: expected output NOT to contain: $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

setup_impl_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/prompts/impl_prompts" \
    "$repo_dir/.asdlc_worker/overmind"
  cp "$AI_IMPL_SRC" "$repo_dir/.asdlc_worker/scripts/ai_implementation.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp "$PLANNING_READINESS_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/check_planning_readiness.sh"
  cp "$IMPLEMENTATION_READINESS_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/check_implementation_readiness.sh"
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_implementation.sh" \
    "$repo_dir/.asdlc_worker/scripts/helpers/check_planning_readiness.sh" \
    "$repo_dir/.asdlc_worker/scripts/helpers/check_implementation_readiness.sh"

  cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [x] Plan and discuss the step. [REQ-1]
- [ ] Implement the feature. [REQ-1]
- [ ] Review step implementation.
EOF

  touch "$repo_dir/.asdlc_worker/AI_DEVELOPMENT_PROCESS.md"
  touch "$repo_dir/AGENTS.md"

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test"
    git config user.email "test@test.com"
    git add .
    git commit -qm "seed"
  )
}

make_ready_step_plan_with_lar() {
  local dir="$1"
  cat >"$dir/.asdlc_worker/step_plans/step-1.1.md" <<'EOF'
## Linked Artifacts (in scope)
- LAR-003 | Figma | Feature Mockup | http://example.com

## Applicable UR Shortlist
- None.

## Plan (ordered)
- [x] 1. Do the thing.

## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 The system SHALL do the thing. EARS[REQ-1]
EOF
}

make_ready_step_plan_without_lar() {
  local dir="$1"
  cat >"$dir/.asdlc_worker/step_plans/step-1.1.md" <<'EOF'
## Applicable UR Shortlist
- None.

## Plan (ordered)
- [x] 1. Do the thing.

## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 The system SHALL do the thing. EARS[REQ-1]
EOF
}

make_design() {
  local dir="$1"
  cat >"$dir/.asdlc_worker/step_designs/step-1.1-design.md" <<'EOF'
## Goal
- Do the thing.
## In Scope
- The thing.
## Out of Scope
- Other things.
## Non-goals
- Unrelated.
## Proposal / Design Details
- Implement the thing.
## Risks and Mitigations
- Risk -> mitigation.
## Applicable AGENTS.md Constraints
- Follow AGENTS.md.
## Applicable User Review Rules
- None.
## Applicable ADR Shortlist
- None.
## References in Current Codebase
- (none)
EOF
}

# Test 1: step plan with non-empty LAR shortlist — prompt contains block and fetch rule
TEST_DIR="$TMP_ROOT/test_lar_present"
mkdir -p "$TEST_DIR"
setup_impl_repo "$TEST_DIR"
make_design "$TEST_DIR"
make_ready_step_plan_with_lar "$TEST_DIR"

OUT_FILE="$TEST_DIR/out.txt"
bash "$TEST_DIR/.asdlc_worker/scripts/ai_implementation.sh" --step 1.1 --no-branch --out "$OUT_FILE" 2>/dev/null
OUTPUT="$(cat "$OUT_FILE")"
assert_contains "$OUTPUT" "LAR-003"
assert_contains "$OUTPUT" "Figma"
assert_contains "$OUTPUT" "Feature Mockup"
assert_contains "$OUTPUT" "Fetch rule (implementation)"
assert_contains "$OUTPUT" "whatever the artifact represents"
echo "PASS: non-empty LAR shortlist injects block and fetch rule into implementation prompt"

# Test 2: step plan with no LAR shortlist — block and fetch rule omitted
TEST_DIR="$TMP_ROOT/test_no_lar"
mkdir -p "$TEST_DIR"
setup_impl_repo "$TEST_DIR"
make_design "$TEST_DIR"
make_ready_step_plan_without_lar "$TEST_DIR"

OUT_FILE="$TEST_DIR/out.txt"
bash "$TEST_DIR/.asdlc_worker/scripts/ai_implementation.sh" --step 1.1 --no-branch --out "$OUT_FILE" 2>/dev/null
OUTPUT="$(cat "$OUT_FILE")"
assert_not_contains "$OUTPUT" "Fetch rule (implementation)"
assert_not_contains "$OUTPUT" "LAR-"
echo "PASS: absent LAR shortlist suppresses fetch rule and block from implementation prompt"

# Test 3: shortlist position is fixed (before Functional Requirements)
TEST_DIR="$TMP_ROOT/test_position"
mkdir -p "$TEST_DIR"
setup_impl_repo "$TEST_DIR"
make_design "$TEST_DIR"
make_ready_step_plan_with_lar "$TEST_DIR"

OUT_FILE="$TEST_DIR/out.txt"
bash "$TEST_DIR/.asdlc_worker/scripts/ai_implementation.sh" --step 1.1 --no-branch --out "$OUT_FILE" 2>/dev/null
OUTPUT="$(cat "$OUT_FILE")"
LAR_LINE="$(printf '%s\n' "$OUTPUT" | grep -n "^## Linked Artifacts" | head -1 | cut -d: -f1)"
FR_LINE="$(printf '%s\n' "$OUTPUT" | grep -n "^## Functional Requirements" | head -1 | cut -d: -f1)"
if [[ -z "$LAR_LINE" || -z "$FR_LINE" || "$LAR_LINE" -ge "$FR_LINE" ]]; then
  echo "Assertion failed: LAR shortlist should appear before Functional Requirements in prompt" >&2
  exit 1
fi
echo "PASS: LAR shortlist appears before Functional Requirements in implementation prompt"

# Test 4: byte-determinism — running twice produces identical output
TEST_DIR="$TMP_ROOT/test_determinism"
mkdir -p "$TEST_DIR"
setup_impl_repo "$TEST_DIR"
make_design "$TEST_DIR"
make_ready_step_plan_with_lar "$TEST_DIR"

OUT_FILE1="$TEST_DIR/run1.txt"
OUT_FILE2="$TEST_DIR/run2.txt"
bash "$TEST_DIR/.asdlc_worker/scripts/ai_implementation.sh" --step 1.1 --no-branch \
  --out "$OUT_FILE1" 2>/dev/null
bash "$TEST_DIR/.asdlc_worker/scripts/ai_implementation.sh" --step 1.1 --no-branch \
  --out "$OUT_FILE2" 2>/dev/null

if ! diff -q "$OUT_FILE1" "$OUT_FILE2" >/dev/null 2>&1; then
  echo "Assertion failed: two runs should produce byte-identical output" >&2
  diff "$OUT_FILE1" "$OUT_FILE2" >&2
  exit 1
fi
echo "PASS: implementation prompt is byte-deterministic across runs"

echo ""
echo "All ai_implementation LAR tests passed."
