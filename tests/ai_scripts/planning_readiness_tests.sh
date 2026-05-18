#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER_SRC="$SOURCE_ROOT/ai/scripts/helpers/check_planning_readiness.sh"
IMPLEMENTATION_HELPER_SRC="$SOURCE_ROOT/ai/scripts/helpers/check_implementation_readiness.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"
AI_PLAN_SRC="$SOURCE_ROOT/ai/scripts/ai_plan.sh"
AI_IMPL_SRC="$SOURCE_ROOT/ai/scripts/ai_implementation.sh"
PROCESS_SRC="$SOURCE_ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
STEP_PLAN_TEMPLATE_SRC="$SOURCE_ROOT/ai/templates/step_plan_TEMPLATE.md"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export ASDLC_RUNTIME_PLAN_PATH=".asdlc_worker/overmind/implementation_plan.md"
export ASDLC_RUNTIME_EARS_PATH=".asdlc_worker/overmind/reqirements_ears.md"

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
    echo "Assertion failed: expected output to not contain: $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_order() {
  local haystack="$1"
  local first="$2"
  local second="$3"
  local first_line second_line

  first_line="$(printf '%s\n' "$haystack" | grep -nF "$first" | head -n 1 | cut -d: -f1 || true)"
  second_line="$(printf '%s\n' "$haystack" | grep -nF "$second" | head -n 1 | cut -d: -f1 || true)"

  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    echo "Assertion failed: expected '$first' before '$second'" >&2
    exit 1
  fi
}

setup_helper_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/overmind"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"
  cp "$HELPER_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/check_planning_readiness.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  chmod +x "$repo_dir/.asdlc_worker/scripts/helpers/check_planning_readiness.sh"
}

setup_plan_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/.asdlc_worker/scripts" "$repo_dir/.asdlc_worker/step_designs" "$repo_dir/.asdlc_worker/step_plans" \
    "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/templates" "$repo_dir/.asdlc_worker/overmind"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"
  cp "$AI_PLAN_SRC" "$repo_dir/.asdlc_worker/scripts/ai_plan.sh"
  cp "$HELPER_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/check_planning_readiness.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp "$PROCESS_SRC" "$repo_dir/.asdlc_worker/AI_DEVELOPMENT_PROCESS.md"
  cp "$STEP_PLAN_TEMPLATE_SRC" "$repo_dir/ai/templates/step_plan_TEMPLATE.md"
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_plan.sh" "$repo_dir/.asdlc_worker/scripts/helpers/check_planning_readiness.sh"

  cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [ ] Plan and discuss the step. [REQ-1]
- [ ] Implement the feature endpoint. [REQ-1]
- [ ] Review step implementation.
EOF

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-demo-design.md" <<'EOF'
## Target Bullets
- Implement the feature endpoint.

## Selected EARS Requirements (for planning translation)
- REQ-1 - Deterministic response.

## Things to Decide (for final planning discussion)
- None.

## Applicable AGENTS.md Constraints
- Follow AGENTS.md constraints relevant to this step.

## Applicable UR Shortlist
- None.

## Applicable ADR Shortlist
- ADR-0001 - Preserve existing API contract.
EOF

  cat >"$repo_dir/.asdlc_worker/open_questions.md" <<'EOF'
## Step 1.1 Demo
- No open questions.
EOF

  cat >"$repo_dir/.asdlc_worker/blocker_log.md" <<'EOF'
## Step 1.1 Demo
- No blockers.
EOF

  cat >"$repo_dir/.asdlc_worker/decisions.md" <<'EOF'
## ADR-0001 - Baseline
- **Status**: Accepted
EOF

  cat >"$repo_dir/.asdlc_worker/overmind/reqirements_ears.md" <<'EOF'
### Requirement 1 API behavior
- Endpoint returns deterministic response.
EOF

  cat >"$repo_dir/AGENTS.md" <<'EOF'
Project constraints placeholder.
EOF

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
  )
}

setup_impl_repo() {
  local repo_dir="$1"
  local readiness_mode="${2:-ready}"
  mkdir -p "$repo_dir/.asdlc_worker/scripts" "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/overmind"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"
  cp "$AI_IMPL_SRC" "$repo_dir/.asdlc_worker/scripts/ai_implementation.sh"
  cp "$HELPER_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/check_planning_readiness.sh"
  cp "$IMPLEMENTATION_HELPER_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/check_implementation_readiness.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_implementation.sh" \
    "$repo_dir/.asdlc_worker/scripts/helpers/check_planning_readiness.sh" \
    "$repo_dir/.asdlc_worker/scripts/helpers/check_implementation_readiness.sh"

  cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [x] Plan and discuss the step. [REQ-1]
- [ ] Implement the feature endpoint. [REQ-1]
- [ ] Review step implementation.
EOF

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-design.md" <<'EOF'
## Goal
- Demo.
## In Scope
- Demo.
## Out of Scope
- Demo.
## Non-goals
- Demo.
## Proposal / Design Details
- Demo.
## Risks and Mitigations
- Demo risk.
## Applicable AGENTS.md Constraints
- Demo constraint.
## Applicable User Review Rules
- None.
## Applicable UR Shortlist
- None.
## Applicable ADR Shortlist
- ADR-1
## References in Current Codebase
- `.asdlc_worker/scripts/ai_implementation.sh`
EOF

  cat >"$repo_dir/.asdlc_worker/AI_DEVELOPMENT_PROCESS.md" <<'EOF'
### 3) Implement ordered plan (adaptive batch execution)
- demo
### 4) Verification gates (required before Section 5)
- demo
EOF

  cat >"$repo_dir/.asdlc_worker/blocker_log.md" <<'EOF'
## Step 1.1 Demo
- No blockers.
EOF

  cat >"$repo_dir/.asdlc_worker/open_questions.md" <<'EOF'
## Step 1.1 Demo
- No open questions.
EOF

  cat >"$repo_dir/AGENTS.md" <<'EOF'
Constraints.
EOF

  cat >"$repo_dir/.asdlc_worker/overmind/reqirements_ears.md" <<'EOF'
### Requirement 1 Demo
- Demo.
EOF

  case "$readiness_mode" in
    ready)
      cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [ ] 1. Implement the feature endpoint.
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL implement the feature endpoint.
- Plan Links: 1
- Verification: Add tests.
- Status: pending
## Applicable UR Shortlist
- None.
## Implementation Notes / Constraints
- Keep diffs minimal.
## Tests
- Add/update tests.
## Risks / Edge Cases
- Demo risk.
## Decisions Needed
- None.
EOF
      ;;
    missing_step_plan)
      ;;
    unchecked_gate)
      cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [ ] Plan and discuss the step. [REQ-1]
- [ ] Implement the feature endpoint. [REQ-1]
- [ ] Review step implementation.
EOF
      cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [ ] 1. Implement the feature endpoint.
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL implement the feature endpoint.
- Plan Links: 1
- Verification: Add tests.
- Status: pending
EOF
      ;;
    *)
      echo "Unknown readiness_mode: $readiness_mode" >&2
      exit 1
      ;;
  esac

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
  )
}

run_plan() {
  local repo_dir="$1"
  (
    cd "$repo_dir"
    .asdlc_worker/scripts/ai_plan.sh --step 1.1 --feature-id demo --out .asdlc_worker/step_plans/step-1.1-demo.md
  )
}

run_impl() {
  local repo_dir="$1"
  (
    cd "$repo_dir"
    .asdlc_worker/scripts/ai_implementation.sh --step 1.1 --step-plan .asdlc_worker/step_plans/step-1.1-demo.md --design .asdlc_worker/step_designs/step-1.1-design.md --out .asdlc_worker/prompts/impl.prompt.txt --no-branch
  )
}

test_helper_ready_exit_code() {
  local repo_dir="$TMP_ROOT/helper-ready"
  setup_helper_repo "$repo_dir"

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
# Step Plan
## Plan (ordered)
- [ ] Demo
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL demo.
- Plan Links: 1
- Verification: demo
- Status: pending
EOF

  cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [x] Plan and discuss the step. [REQ-1]
- [ ] Implement demo.
EOF

  local out
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_planning_readiness.sh 1.1)"
  assert_contains "$out" "Planning readiness check passed for step 1.1"
}

test_helper_missing_step_plan_fails() {
  local repo_dir="$TMP_ROOT/helper-missing-step-plan"
  setup_helper_repo "$repo_dir"
  mkdir -p "$repo_dir/overmind"
  cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [x] Plan and discuss the step. [REQ-1]
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_planning_readiness.sh 1.1 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || exit 1
  assert_contains "$out" "Planning readiness failed: step plan not found"
}

test_helper_missing_section_fails() {
  local repo_dir="$TMP_ROOT/helper-missing-section"
  setup_helper_repo "$repo_dir"
  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
# Step Plan
## Plan (ordered)
- [ ] Demo
EOF
  cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [x] Plan and discuss the step. [REQ-1]
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_planning_readiness.sh 1.1 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || exit 1
  assert_contains "$out" "Planning readiness failed: missing required section '## Functional Requirements (translated from design EARS)' in .asdlc_worker/step_plans/step-1.1.md"
}

test_helper_unchecked_gate_fails() {
  local repo_dir="$TMP_ROOT/helper-unchecked-gate"
  setup_helper_repo "$repo_dir"
  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
# Step Plan
## Plan (ordered)
- [ ] Demo
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL demo.
- Plan Links: 1
- Verification: demo
- Status: pending
EOF
  cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [ ] Plan and discuss the step. [REQ-1]
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_planning_readiness.sh 1.1 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || exit 1
  assert_contains "$out" "Planning readiness failed: 'Plan and discuss the step' is not marked [x] in .asdlc_worker/overmind/implementation_plan.md for step 1.1"
}

test_helper_bootstrap_requires_scaffold_section_and_first_plan_item() {
  local repo_dir="$TMP_ROOT/helper-bootstrap-gate"
  setup_helper_repo "$repo_dir"
  mkdir -p "$repo_dir/ai/step_designs"

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-demo-design.md" <<'EOF'
## First-Feature Bootstrap (only if needed)
- Bootstrap required: yes
- Repo state rationale: Empty backend repo.
- Blueprint result: relevant blueprint found
- Blueprint evidence: /tmp/project_stack_blueprint_back.md
- User stack decision: None
- Planning handoff: Scaffold creation must come before endpoint implementation.
EOF

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
# Step Plan
## Scaffold Bootstrap Plan
- Use the approved backend blueprint.
## Plan (ordered)
- [ ] 1. Implement the feature endpoint.
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL demo.
- Plan Links: 1
- Verification: demo
- Status: pending
EOF

  cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [x] Plan and discuss the step. [REQ-1]
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_planning_readiness.sh 1.1 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || exit 1
  assert_contains "$out" "Planning readiness failed: bootstrap-required planning must place scaffold creation first in '## Plan (ordered)'"
}

test_plan_prompt_includes_readiness_contract() {
  local repo_dir="$TMP_ROOT/plan-prompt"
  setup_plan_repo "$repo_dir"

  local out
  out="$(run_plan "$repo_dir")"
  assert_contains "$out" 'Before ending the planning phase, run `.asdlc_worker/scripts/helpers/check_planning_readiness.sh 1.1`.'
  assert_contains "$out" 'If the readiness check fails, do not emit the final completion line. Follow the Planning Readiness Gate rules in `.asdlc_worker/AI_DEVELOPMENT_PROCESS.md`.'
  assert_order "$out" 'Before ending the planning phase, run `.asdlc_worker/scripts/helpers/check_planning_readiness.sh 1.1`.' 'Only after the Planning Readiness Gate is satisfied, end your final response with this exact last line: "Planning phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase."'
}

test_implementation_prompt_includes_helper_contract() {
  local repo_dir="$TMP_ROOT/impl-ready"
  setup_impl_repo "$repo_dir" "ready"

  run_impl "$repo_dir"
  local out
  out="$(cat "$repo_dir/.asdlc_worker/prompts/impl.prompt.txt")"
  assert_contains "$out" 'Execution list (step plan `## Plan (ordered)`)'
  assert_contains "$out" 'Before ending the implementation phase, run `.asdlc_worker/scripts/helpers/check_implementation_readiness.sh 1.1`.'
  assert_contains "$out" 'If that readiness check fails, do not emit the final completion line. Follow the Implementation Readiness Gate rules in `.asdlc_worker/AI_DEVELOPMENT_PROCESS.md`.'
}

test_implementation_prompt_fails_fast_when_helper_fails() {
  local repo_dir="$TMP_ROOT/impl-failure"
  setup_impl_repo "$repo_dir" "missing_step_plan"

  local status=0
  local out
  set +e
  out="$(run_impl "$repo_dir" 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || exit 1
  assert_contains "$out" "Planning readiness failed: step plan not found"
  if [[ -f "$repo_dir/.asdlc_worker/prompts/impl.prompt.txt" ]]; then
    echo "Assertion failed: implementation prompt should not be written when readiness fails" >&2
    exit 1
  fi
}

test_helper_ready_exit_code
test_helper_missing_step_plan_fails
test_helper_missing_section_fails
test_helper_unchecked_gate_fails
test_helper_bootstrap_requires_scaffold_section_and_first_plan_item
test_plan_prompt_includes_readiness_contract
test_implementation_prompt_includes_helper_contract
test_implementation_prompt_fails_fast_when_helper_fails

echo "All planning readiness tests passed."
