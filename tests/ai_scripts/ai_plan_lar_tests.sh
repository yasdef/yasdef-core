#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_PLAN_SRC="$SOURCE_ROOT/ai/scripts/ai_plan.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"
PLANNING_READINESS_SRC="$SOURCE_ROOT/ai/scripts/helpers/check_planning_readiness.sh"
SYNC_LARS_SRC="$SOURCE_ROOT/ai/scripts/helpers/sync_step_lars.sh"
PROCESS_SRC="$SOURCE_ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
STEP_PLAN_TEMPLATE_SRC="$SOURCE_ROOT/ai/templates/step_plan_TEMPLATE.md"

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

setup_plan_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/templates" \
    "$repo_dir/.asdlc_worker/golden_examples" "$repo_dir/.asdlc_worker/overmind"
  cp "$AI_PLAN_SRC" "$repo_dir/.asdlc_worker/scripts/ai_plan.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp "$PLANNING_READINESS_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/check_planning_readiness.sh"
  cp "$SYNC_LARS_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/sync_step_lars.sh"
  cp "$PROCESS_SRC" "$repo_dir/.asdlc_worker/AI_DEVELOPMENT_PROCESS.md"
  cp "$STEP_PLAN_TEMPLATE_SRC" "$repo_dir/.asdlc_worker/templates/step_plan_TEMPLATE.md"
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_plan.sh" \
    "$repo_dir/.asdlc_worker/scripts/helpers/check_planning_readiness.sh" \
    "$repo_dir/.asdlc_worker/scripts/helpers/sync_step_lars.sh"

  cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [x] Plan and discuss the step. [REQ-1]
- [ ] Implement the feature. [REQ-1]
- [ ] Review step implementation.
EOF

  touch "$repo_dir/.asdlc_worker/decisions.md"
  touch "$repo_dir/.asdlc_worker/blocker_log.md"
  touch "$repo_dir/.asdlc_worker/open_questions.md"
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

make_step_plan() {
  local dir="$1"
  cat >"$dir/.asdlc_worker/step_plans/step-1.1.md" <<'EOF'
## Applicable UR Shortlist
- None.

## Plan (ordered)
- [ ] 1. Do the thing.

## Functional Requirements (translated from design EARS)
- [ ] FR-1.1-001 The system SHALL do the thing. EARS[REQ-1]
EOF
}

make_design_with_lar() {
  local dir="$1"
  cat >"$dir/.asdlc_worker/step_designs/step-1.1-design.md" <<'EOF'
## Target Bullets
- Implement the feature.

## Selected EARS Requirements (for planning translation)
- REQ-1 detail.

## Applicable UR Shortlist
- None.

## Linked Artifacts (in scope)
- LAR-003 | Figma | Feature Mockup | https://figma.com/file/abc/feature

## Applicable ADR Shortlist
- None.

## Applicable AGENTS.md Constraints
- Follow AGENTS.md.
EOF
}

make_design_without_lar() {
  local dir="$1"
  cat >"$dir/.asdlc_worker/step_designs/step-1.1-design.md" <<'EOF'
## Target Bullets
- Implement the feature.

## Selected EARS Requirements (for planning translation)
- REQ-1 detail.

## Applicable UR Shortlist
- None.

## Applicable ADR Shortlist
- None.

## Applicable AGENTS.md Constraints
- Follow AGENTS.md.
EOF
}

# Test 1: non-empty LAR shortlist in design — prompt contains LAR block and sync instruction
TEST_DIR="$TMP_ROOT/test_lar_present"
mkdir -p "$TEST_DIR"
setup_plan_repo "$TEST_DIR"
make_step_plan "$TEST_DIR"
make_design_with_lar "$TEST_DIR"

OUTPUT="$(bash "$TEST_DIR/.asdlc_worker/scripts/ai_plan.sh" --step 1.1 2>/dev/null)"
assert_contains "$OUTPUT" "LAR-003"
assert_contains "$OUTPUT" "Figma"
assert_contains "$OUTPUT" "Feature Mockup"
assert_contains "$OUTPUT" "sync_step_lars.sh"
assert_contains "$OUTPUT" "Fetch rule (planning):"
echo "PASS: non-empty LAR shortlist produces LAR block, sync instruction, and fetch rule in prompt"

# Test 2: empty/absent LAR shortlist in design — fetch rule and block suppressed
TEST_DIR="$TMP_ROOT/test_no_lar"
mkdir -p "$TEST_DIR"
setup_plan_repo "$TEST_DIR"
make_step_plan "$TEST_DIR"
make_design_without_lar "$TEST_DIR"

OUTPUT="$(bash "$TEST_DIR/.asdlc_worker/scripts/ai_plan.sh" --step 1.1 2>/dev/null)"
assert_not_contains "$OUTPUT" "Fetch rule (planning):"
echo "PASS: absent LAR shortlist suppresses fetch rule"

# Test 3: planning prompt sources LAR section from design artifact, not from reqirements_ears.md
TEST_DIR="$TMP_ROOT/test_no_rederive"
mkdir -p "$TEST_DIR"
setup_plan_repo "$TEST_DIR"
make_step_plan "$TEST_DIR"
make_design_with_lar "$TEST_DIR"

# Provide reqirements_ears.md with different LAR data
cat >"$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" <<'EOF'
### Requirement 1 Feature
- The system SHALL work.
**Linked Artifacts:** LAR-099

## Linked Artifacts
- LAR-099 | Confluence | Schema | https://confluence.example.com/should-not-appear
EOF

OUTPUT="$(bash "$TEST_DIR/.asdlc_worker/scripts/ai_plan.sh" --step 1.1 2>/dev/null)"
# Should contain design's LAR-003, not registry's LAR-099
assert_contains "$OUTPUT" "LAR-003"
assert_not_contains "$OUTPUT" "LAR-099"
echo "PASS: planning prompt sources LAR block from design artifact, not reqirements_ears.md"

echo ""
echo "All ai_plan LAR tests passed."
