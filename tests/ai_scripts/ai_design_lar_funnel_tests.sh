#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_DESIGN_SRC="$SOURCE_ROOT/ai/scripts/ai_design.sh"
SYNC_LARS_SRC="$SOURCE_ROOT/ai/scripts/helpers/sync_step_lars.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Assertion failed: expected output to contain:" >&2
    echo "  $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "Assertion failed: expected output NOT to contain:" >&2
    echo "  $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

setup_design_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/templates" \
    "$repo_dir/.asdlc_worker/golden_examples" "$repo_dir/.asdlc_worker/overmind"
  cp "$AI_DESIGN_SRC" "$repo_dir/.asdlc_worker/scripts/ai_design.sh"
  cp "$SYNC_LARS_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/sync_step_lars.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_design.sh" \
    "$repo_dir/.asdlc_worker/scripts/helpers/sync_step_lars.sh"

  cat >"$repo_dir/.asdlc_worker/templates/feature_design_TEMPLATE.md" <<'EOF'
---
# Feature Design: <step> - <step title>
Date: <YYYY-MM-DD>
Designer model/session: <fill>
EOF

  touch "$repo_dir/.asdlc_worker/AI_DEVELOPMENT_PROCESS.md"
  touch "$repo_dir/.asdlc_worker/decisions.md"
  touch "$repo_dir/.asdlc_worker/blocker_log.md"
  touch "$repo_dir/.asdlc_worker/open_questions.md"
  touch "$repo_dir/.asdlc_worker/user_review.md"
  touch "$repo_dir/AGENTS.md"
  touch "$repo_dir/.asdlc_worker/feature_sync.yaml"

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test"
    git config user.email "test@test.com"
    git add .
    git commit -qm "seed"
  )
}

# Test 1: step bullets reference LAR-tagged requirements — LAR block appears in prompt
TEST_DIR="$TMP_ROOT/test_lar_present"
mkdir -p "$TEST_DIR"
setup_design_repo "$TEST_DIR"

cat >"$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Feature with LAR
- [ ] Plan and discuss the step.
- [ ] Implement the main menu endpoint. [REQ-5]
- [ ] Review step implementation.
EOF

cat >"$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" <<'EOF'
### Requirement 5 Main menu
- The system SHALL render the main menu.
**Linked Artifacts:** LAR-002

## Linked Artifacts
- LAR-002 | Figma | Main Menu Mockup | https://figma.com/file/abc/main-menu
EOF

OUTPUT="$(bash "$TEST_DIR/.asdlc_worker/scripts/ai_design.sh" --step 1.1 2>/dev/null)"
assert_contains "$OUTPUT" "LAR-002"
assert_contains "$OUTPUT" "Figma"
assert_contains "$OUTPUT" "Main Menu Mockup"
assert_contains "$OUTPUT" "https://figma.com/file/abc/main-menu"
assert_contains "$OUTPUT" "Linked Artifacts (in scope)"
echo "PASS: LAR-tagged requirement produces LAR block in prompt"

# Test 2: step bullets reference no LAR-tagged requirements — block absent or empty
TEST_DIR="$TMP_ROOT/test_no_lar"
mkdir -p "$TEST_DIR"
setup_design_repo "$TEST_DIR"

cat >"$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Feature without LAR
- [ ] Plan and discuss the step.
- [ ] Implement the basic endpoint. [REQ-3]
- [ ] Review step implementation.
EOF

cat >"$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" <<'EOF'
### Requirement 3 Basic endpoint
- The system SHALL respond to requests.

## Linked Artifacts
- LAR-001 | Confluence | Schema Doc | https://confluence.example.com/schema
EOF

OUTPUT="$(bash "$TEST_DIR/.asdlc_worker/scripts/ai_design.sh" --step 1.1 2>/dev/null)"
assert_not_contains "$OUTPUT" "LAR-001"
assert_contains "$OUTPUT" "none"
echo "PASS: no LAR-tagged requirements produces empty/absent block"

# Test 3: multiple LARs are deduplicated and ordered by ascending numeric ID
TEST_DIR="$TMP_ROOT/test_dedup_order"
mkdir -p "$TEST_DIR"
setup_design_repo "$TEST_DIR"

cat >"$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Feature with multiple LARs
- [ ] Plan and discuss the step.
- [ ] Implement menu and schema. [REQ-7]
- [ ] Review step implementation.
EOF

cat >"$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" <<'EOF'
### Requirement 7 Menu and schema
- The system SHALL render the menu.
**Linked Artifacts:** LAR-005, LAR-001, LAR-005

## Linked Artifacts
- LAR-001 | Confluence | Schema | https://confluence.example.com/schema
- LAR-005 | Figma | Menu Mockup | https://figma.com/file/abc/menu
EOF

OUTPUT="$(bash "$TEST_DIR/.asdlc_worker/scripts/ai_design.sh" --step 1.1 2>/dev/null)"
# Check ordering within the LAR section using "LAR-NNN |" format unique to section entries
assert_contains "$OUTPUT" "LAR-001 |"
assert_contains "$OUTPUT" "LAR-005 |"
LAR001_POS="$(printf '%s\n' "$OUTPUT" | grep -n "LAR-001 |" | head -1 | cut -d: -f1)"
LAR005_POS="$(printf '%s\n' "$OUTPUT" | grep -n "LAR-005 |" | head -1 | cut -d: -f1)"
if [[ -z "$LAR001_POS" || -z "$LAR005_POS" || "$LAR001_POS" -ge "$LAR005_POS" ]]; then
  echo "Assertion failed: expected LAR-001 | before LAR-005 | in output" >&2
  exit 1
fi
# LAR-005 entry appears exactly once in the LAR section
LAR005_ENTRY_COUNT="$(printf '%s\n' "$OUTPUT" | grep -c "LAR-005 |" || true)"
if [[ "$LAR005_ENTRY_COUNT" -ne 1 ]]; then
  echo "Assertion failed: expected LAR-005 entry exactly once, got $LAR005_ENTRY_COUNT occurrences" >&2
  exit 1
fi
echo "PASS: multiple LARs deduplicated and ordered by ascending numeric ID"

# Test 4: referenced LAR missing from registry — omitted from block (not an error)
TEST_DIR="$TMP_ROOT/test_missing_lar"
mkdir -p "$TEST_DIR"
setup_design_repo "$TEST_DIR"

cat >"$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Feature with missing LAR
- [ ] Plan and discuss the step.
- [ ] Implement something. [REQ-9]
- [ ] Review step implementation.
EOF

cat >"$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" <<'EOF'
### Requirement 9 Missing LAR
- The system SHALL do something.
**Linked Artifacts:** LAR-099

## Linked Artifacts
- LAR-001 | Figma | Unrelated | https://figma.com/file/unrelated
EOF

OUTPUT="$(bash "$TEST_DIR/.asdlc_worker/scripts/ai_design.sh" --step 1.1 2>/dev/null)" || true
assert_not_contains "$OUTPUT" "LAR-099 |"
echo "PASS: LAR missing from registry is omitted from block without error"

# Test 5: prompt instructs model to invoke sync_step_lars.sh
TEST_DIR="$TMP_ROOT/test_sync_instruction"
mkdir -p "$TEST_DIR"
setup_design_repo "$TEST_DIR"

cat >"$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Feature with LAR
- [ ] Plan and discuss the step.
- [ ] Implement the menu. [REQ-5]
- [ ] Review step implementation.
EOF

cat >"$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" <<'EOF'
### Requirement 5 Menu
- The system SHALL render the menu.
**Linked Artifacts:** LAR-002

## Linked Artifacts
- LAR-002 | Figma | Menu | https://figma.com/file/abc/menu
EOF

OUTPUT="$(bash "$TEST_DIR/.asdlc_worker/scripts/ai_design.sh" --step 1.1 2>/dev/null)" || true
assert_contains "$OUTPUT" "sync_step_lars.sh"
assert_contains "$OUTPUT" "1.1"
echo "PASS: prompt contains sync_step_lars.sh invocation instruction"

echo ""
echo "All ai_design LAR funnel tests passed."
