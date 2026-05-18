#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_LARS_SRC="$SOURCE_ROOT/ai/scripts/helpers/sync_step_lars.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Assertion failed: expected content to contain: $needle" >&2
    echo "Actual content:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "Assertion failed: expected content NOT to contain: $needle" >&2
    echo "Actual content:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/step_plans" \
    "$repo_dir/.asdlc_worker/step_designs" "$repo_dir/.asdlc_worker/overmind"
  cp "$SYNC_LARS_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/sync_step_lars.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  chmod +x "$repo_dir/.asdlc_worker/scripts/helpers/sync_step_lars.sh"
}

make_plan() {
  local dir="$1"
  cat >"$dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Feature with LAR
- [ ] Plan and discuss the step.
- [ ] Implement the menu. [REQ-5]
- [ ] Review step implementation.
EOF
}

make_requirements() {
  local dir="$1"
  cat >"$dir/.asdlc_worker/overmind/reqirements_ears.md" <<'EOF'
### Requirement 5 Menu
- The system SHALL render the menu.
**Linked Artifacts:**
- LAR-002

## Linked Artifacts
- id: LAR-002
  title: Menu Mockup
  type: Figma
  locator: https://figma.com/file/abc/menu
EOF
}

make_requirements_multiple_yaml() {
  local dir="$1"
  cat >"$dir/.asdlc_worker/overmind/reqirements_ears.md" <<'EOF'
### Requirement 5 Menu
- The system SHALL render the menu.
**Linked Artifacts:**
- LAR-002
- LAR-010

## Linked Artifacts
- id: LAR-002
  title: Menu Mockup
  type: Figma
  locator: https://figma.com/file/abc/menu
- id: LAR-010
  title: Menu Schema
  type: Schema
  locator: https://example.com/menu-schema
EOF
}

# Test 1: helper appends section when artifact lacks it
TEST_DIR="$TMP_ROOT/test_append"
mkdir -p "$TEST_DIR"
setup_repo "$TEST_DIR"
make_plan "$TEST_DIR"
make_requirements "$TEST_DIR"

cat >"$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md" <<'EOF'
## Goal
- Render the menu.
EOF

ASDLC_RUNTIME_PLAN_PATH="$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" \
  ASDLC_RUNTIME_EARS_PATH="$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" \
  bash "$TEST_DIR/.asdlc_worker/scripts/helpers/sync_step_lars.sh" 1.1 \
  "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md"

CONTENT="$(cat "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md")"
assert_contains "$CONTENT" "## Linked Artifacts (in scope)"
assert_contains "$CONTENT" "LAR-002"
assert_contains "$CONTENT" "Figma"
assert_contains "$CONTENT" "Menu Mockup"
assert_contains "$CONTENT" "https://figma.com/file/abc/menu"
echo "PASS: helper appends ## Linked Artifacts (in scope) section to artifact lacking it"

# Test 2: helper supports multiline requirement links and YAML-like registry entries
TEST_DIR="$TMP_ROOT/test_yaml_registry"
mkdir -p "$TEST_DIR"
setup_repo "$TEST_DIR"
make_plan "$TEST_DIR"
make_requirements_multiple_yaml "$TEST_DIR"

cat >"$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md" <<'EOF'
## Goal
- Render the menu.
EOF

ASDLC_RUNTIME_PLAN_PATH="$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" \
  ASDLC_RUNTIME_EARS_PATH="$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" \
  bash "$TEST_DIR/.asdlc_worker/scripts/helpers/sync_step_lars.sh" 1.1 \
  "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md"

CONTENT="$(cat "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md")"
assert_contains "$CONTENT" "- LAR-002 | Figma | Menu Mockup | https://figma.com/file/abc/menu"
assert_contains "$CONTENT" "- LAR-010 | Schema | Menu Schema | https://example.com/menu-schema"
echo "PASS: helper flattens YAML-like LAR registry entries referenced from multiline requirement blocks"

# Test 3: helper replaces existing section idempotently
TEST_DIR="$TMP_ROOT/test_replace"
mkdir -p "$TEST_DIR"
setup_repo "$TEST_DIR"
make_plan "$TEST_DIR"
make_requirements "$TEST_DIR"

cat >"$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md" <<'EOF'
## Goal
- Render the menu.

## Linked Artifacts (in scope)
- LAR-999 | Stale | Old Entry | https://old.example.com

## Non-goals
- No old entries.
EOF

ASDLC_RUNTIME_PLAN_PATH="$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" \
  ASDLC_RUNTIME_EARS_PATH="$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" \
  bash "$TEST_DIR/.asdlc_worker/scripts/helpers/sync_step_lars.sh" 1.1 \
  "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md"

CONTENT="$(cat "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md")"
assert_contains "$CONTENT" "LAR-002"
assert_not_contains "$CONTENT" "LAR-999"
assert_contains "$CONTENT" "## Non-goals"
echo "PASS: helper replaces existing section idempotently, preserves rest of file"

# Test 4: running helper twice produces byte-equivalent output
TEST_DIR="$TMP_ROOT/test_idempotent"
mkdir -p "$TEST_DIR"
setup_repo "$TEST_DIR"
make_plan "$TEST_DIR"
make_requirements "$TEST_DIR"

cat >"$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md" <<'EOF'
## Goal
- Render the menu.
EOF

ASDLC_RUNTIME_PLAN_PATH="$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" \
  ASDLC_RUNTIME_EARS_PATH="$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" \
  bash "$TEST_DIR/.asdlc_worker/scripts/helpers/sync_step_lars.sh" 1.1 \
  "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md"
FIRST_RUN="$(cat "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md")"

ASDLC_RUNTIME_PLAN_PATH="$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" \
  ASDLC_RUNTIME_EARS_PATH="$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" \
  bash "$TEST_DIR/.asdlc_worker/scripts/helpers/sync_step_lars.sh" 1.1 \
  "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md"
SECOND_RUN="$(cat "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md")"

if [[ "$FIRST_RUN" != "$SECOND_RUN" ]]; then
  echo "Assertion failed: repeated invocations should produce byte-equivalent output" >&2
  echo "First run:" >&2
  echo "$FIRST_RUN" >&2
  echo "Second run:" >&2
  echo "$SECOND_RUN" >&2
  exit 1
fi
echo "PASS: repeated invocations produce byte-equivalent output"

# Test 5: step with no LARs — no-op, leaves artifact unchanged
TEST_DIR="$TMP_ROOT/test_noop"
mkdir -p "$TEST_DIR"
setup_repo "$TEST_DIR"

cat >"$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Feature without LAR
- [ ] Plan and discuss the step.
- [ ] Implement something. [REQ-3]
- [ ] Review step implementation.
EOF

cat >"$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" <<'EOF'
### Requirement 3 Basic
- The system SHALL respond.

## Linked Artifacts
- id: LAR-001
  title: Unrelated
  type: Figma
  locator: https://figma.com/file/unrelated
EOF

cat >"$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md" <<'EOF'
## Goal
- Respond to requests.
EOF
ORIGINAL_CONTENT="$(cat "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md")"

ASDLC_RUNTIME_PLAN_PATH="$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" \
  ASDLC_RUNTIME_EARS_PATH="$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" \
  bash "$TEST_DIR/.asdlc_worker/scripts/helpers/sync_step_lars.sh" 1.1 \
  "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md"

AFTER_CONTENT="$(cat "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md")"
if [[ "$ORIGINAL_CONTENT" != "$AFTER_CONTENT" ]]; then
  echo "Assertion failed: no-LAR step should leave artifact unchanged" >&2
  echo "Before:" >&2
  echo "$ORIGINAL_CONTENT" >&2
  echo "After:" >&2
  echo "$AFTER_CONTENT" >&2
  exit 1
fi
echo "PASS: no-LAR step is a no-op that leaves the artifact unchanged"

# Test 6: missing step plan exits non-zero
TEST_DIR="$TMP_ROOT/test_missing_plan"
mkdir -p "$TEST_DIR"
setup_repo "$TEST_DIR"
cp /dev/null "$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md"
echo "### Step 1.1 Missing Plan" > "$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md"

cat >"$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md" <<'EOF'
## Goal
- Test.
EOF

# Step doesn't exist in plan
RC=0
ASDLC_RUNTIME_PLAN_PATH="$TEST_DIR/.asdlc_worker/overmind/implementation_plan.md" \
  ASDLC_RUNTIME_EARS_PATH="$TEST_DIR/.asdlc_worker/overmind/reqirements_ears.md" \
  bash "$TEST_DIR/.asdlc_worker/scripts/helpers/sync_step_lars.sh" 1.9 \
  "$TEST_DIR/.asdlc_worker/step_designs/step-1.1-design.md" 2>/dev/null || RC=$?
if [[ "$RC" -eq 0 ]]; then
  echo "Assertion failed: missing step should exit non-zero" >&2
  exit 1
fi
echo "PASS: missing step in implementation plan exits non-zero"

echo ""
echo "All sync_step_lars tests passed."
