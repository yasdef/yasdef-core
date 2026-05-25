#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLAN_SKILL_DIR="$SOURCE_ROOT/ai/codex/skills/yasdef-worker-plan"

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

setup_repo() {
  local repo_dir="$1"
  mkdir -p \
    "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" \
    "$repo_dir/.asdlc_worker/step_open_questions" \
    "$repo_dir/.asdlc_worker/step_blockers" \
    "$repo_dir/.codex/skills"
  cp -R "$PLAN_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-plan"

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-demo-design.md" <<'EOF'
## Selected EARS Requirements (for planning translation)
### Requirement 1 Demo
- The system SHALL implement demo behavior.

## Things to Decide (for final planning discussion)
- Adapter strategy: keep adapter A or switch to adapter B.
EOF
}

run_validator() {
  local repo_dir="$1"
  uv run python "$repo_dir/.codex/skills/yasdef-worker-plan/scripts/check_planning_readiness.py" \
    --design "$repo_dir/.asdlc_worker/step_designs/step-1.1-demo-design.md" \
    --step-plan "$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" \
    --open-questions "$repo_dir/.asdlc_worker/step_open_questions/step-1.1-demo-open-questions.md" \
    --blockers "$repo_dir/.asdlc_worker/step_blockers/step-1.1-demo-blockers.md"
}

test_helper_ready_exit_code() {
  local repo_dir="$TMP_ROOT/helper-ready"
  setup_repo "$repo_dir"

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Applicable UR Shortlist
- None.
## Plan (ordered)
- [ ] 1. Implement demo behavior.
## Functional Requirements (translated from design EARS)
- [ ] FR-1.1-001 The system SHALL implement demo behavior. EARS[REQ-1]
## Decisions Needed
- Adapter strategy | Accepted | Keep adapter A for now.
EOF

  local out
  out="$(cd "$repo_dir" && run_validator "$repo_dir")"
  assert_contains "$out" '"ready": true'
}

test_helper_missing_fr_section_fails() {
  local repo_dir="$TMP_ROOT/helper-missing-fr"
  setup_repo "$repo_dir"

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Applicable UR Shortlist
- None.
## Plan (ordered)
- [ ] 1. Implement demo behavior.
## Decisions Needed
- Adapter strategy | Accepted | Keep adapter A for now.
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && run_validator "$repo_dir" 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || exit 1
  assert_contains "$out" "missing required section: ## Functional Requirements (translated from design EARS)"
}

test_helper_bootstrap_requires_scaffold_section() {
  local repo_dir="$TMP_ROOT/helper-bootstrap"
  setup_repo "$repo_dir"

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-demo-design.md" <<'EOF'
## Selected EARS Requirements (for planning translation)
### Requirement 1 Demo
- The system SHALL implement demo behavior.

## Things to Decide (for final planning discussion)
- Adapter strategy: keep adapter A or switch to adapter B.

## First-Feature Bootstrap (only if needed)
- Bootstrap required: yes
EOF

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Applicable UR Shortlist
- None.
## Plan (ordered)
- [ ] 1. Implement demo behavior.
## Functional Requirements (translated from design EARS)
- [ ] FR-1.1-001 The system SHALL implement demo behavior. EARS[REQ-1]
## Decisions Needed
- Adapter strategy | Accepted | Keep adapter A for now.
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && run_validator "$repo_dir" 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || exit 1
  assert_contains "$out" "bootstrap-required design needs section: ## Scaffold Bootstrap Plan"
}

test_helper_ready_exit_code
test_helper_missing_fr_section_fails
test_helper_bootstrap_requires_scaffold_section

echo "All planning readiness tests passed."
