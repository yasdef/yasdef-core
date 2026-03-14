#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_IMPL_SRC="$SOURCE_ROOT/ai/scripts/ai_implementation.sh"
PLANNING_HELPER_SRC="$SOURCE_ROOT/ai/scripts/helpers/check_planning_readiness.sh"
IMPLEMENTATION_HELPER_SRC="$SOURCE_ROOT/ai/scripts/helpers/check_implementation_readiness.sh"
AI_AUDIT_SRC="$SOURCE_ROOT/ai/scripts/ai_audit.sh"
AI_AUDIT_DISPOSITION_HELPER_SRC="$SOURCE_ROOT/ai/scripts/helpers/check_ai_audit_disposition_readiness.sh"
POST_REVIEW_SRC="$SOURCE_ROOT/ai/scripts/post_review.sh"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"

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
    echo "Assertion failed: expected output to not contain: $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_not_heading() {
  local haystack="$1"
  local heading="$2"
  if printf '%s\n' "$haystack" | grep -Eq "^##[[:space:]]+${heading}([[:space:]]|$)"; then
    echo "Assertion failed: expected output to not contain heading: ## $heading" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_line_before() {
  local haystack="$1"
  local first="$2"
  local second="$3"
  local first_line second_line

  first_line="$(printf '%s\n' "$haystack" | grep -nF "$first" | head -n 1 | cut -d: -f1 || true)"
  second_line="$(printf '%s\n' "$haystack" | grep -nF "$second" | head -n 1 | cut -d: -f1 || true)"

  if [[ -z "$first_line" || -z "$second_line" ]]; then
    echo "Assertion failed: missing line markers: '$first' or '$second'" >&2
    exit 1
  fi
  if (( first_line >= second_line )); then
    echo "Assertion failed: expected '$first' before '$second'" >&2
    exit 1
  fi
}

setup_impl_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/step_plans" "$repo_dir/ai/step_designs" \
    "$repo_dir/ai/scripts/helpers" "$repo_dir/ai/templates" "$repo_dir/ai/golden_examples" "$repo_dir/overmind"

  cp "$AI_IMPL_SRC" "$repo_dir/ai/scripts/ai_implementation.sh"
  cp "$PLANNING_HELPER_SRC" "$repo_dir/ai/scripts/helpers/check_planning_readiness.sh"
  cp "$IMPLEMENTATION_HELPER_SRC" "$repo_dir/ai/scripts/helpers/check_implementation_readiness.sh"
  chmod +x "$repo_dir/ai/scripts/ai_implementation.sh" \
    "$repo_dir/ai/scripts/helpers/check_planning_readiness.sh" \
    "$repo_dir/ai/scripts/helpers/check_implementation_readiness.sh"

  cat >"$repo_dir/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1)
- [ ] Implement part A (SP=2)
- [ ] Implement part B (SP=1)
- [ ] Review step implementation (SP=1)
EOF

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Design Anchor (scope source of truth)
- ai/step_designs/step-1.1-design.md
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL implement part A behavior.
- Plan Links: 1
- Verification: Add/update tests.
- Status: pending
### FR-1.1-02
- Source EARS Block: NFR-2
- Requirement: The system SHALL enforce non-functional constraint for part B path.
- Plan Links: 2
- Verification: Add/update tests.
- Status: done
## Applicable UR Shortlist
- UR-0100 - Validate JWT auth boundary handling.
- UR-0101 - Keep endpoint contract assertions stable.
## Plan (ordered)
- [ ] 1. Implement part A [REQ-1] [NFR-2].
- [x] 2. Implement part B [REQ-1].
## Implementation Notes / Constraints
- Follow AGENTS.md.
- Keep diffs minimal.
## Tests
- Add/update tests.
## Docs / Artifacts
- Update docs.
## Risks / Edge Cases
- Risk 1.
- Risk 2.
## Decisions Needed
- Config strategy: Accepted (option 1).
- Fallback strategy: Deferred.
EOF

  cat >"$repo_dir/ai/step_designs/step-1.1-design.md" <<'EOF'
## Goal
- Keep implementation prompt deterministic and concise.
## In Scope
- Deterministic prompt ordering.
- UR-based anti-regression checklist.
## Out of Scope
- Runtime service behavior changes.
## Non-goals
- Add new orchestrator phases.
## Proposal / Design Details
- Extract mandatory sections from step plan and design.
- Keep prompt generation deterministic.
## Risks and Mitigations
- Over-slimming can remove needed context -> keep mandatory fields.
## Applicable AGENTS.md Constraints
- follow constraints
## Applicable User Review Rules
- UR-0101 - Keep endpoint contract assertions stable.
- UR-0102 - Validate requirement mapping in tests.
## Applicable UR Shortlist
- UR-9999 - Design fallback only.
## Applicable ADR Shortlist
- ADR-1
## References in Current Codebase
- `ai/scripts/ai_implementation.sh` - prompt generation.
- `tests/ai_scripts/implementation_evidence_tests.sh` - prompt assertions.
## Things to Decide (for final planning discussion)
- none
EOF

  cat >"$repo_dir/ai/AI_DEVELOPMENT_PROCESS.md" <<'EOF'
### 3) Implement ordered plan (batch execution)
- demo
### 4) Verification gates (required before Section 5)
- demo
### 5) User review (required before moving to the next step)
- demo
EOF

  cat >"$repo_dir/ai/blocker_log.md" <<'EOF'
## Step 1.1 Demo
- No blockers.
EOF
  cat >"$repo_dir/ai/open_questions.md" <<'EOF'
## Step 1.1 Demo
- No open questions.
EOF
  cat >"$repo_dir/overmind/reqirements_ears.md" <<'EOF'
### Requirement 1 Demo
- req 1 details
### Requirement 2 Non-target
- req 2 details
### NFR 2 Demo NFR
- nfr 2 details
EOF
  cat >"$repo_dir/AGENTS.md" <<'EOF'
Constraints.
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

setup_orchestrator_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/setup" "$repo_dir/ai/step_designs" "$repo_dir/ai/step_plans" "$repo_dir/overmind"
  cp "$ORCH_SRC" "$repo_dir/ai/scripts/orchestrator.sh"
  chmod +x "$repo_dir/ai/scripts/orchestrator.sh"

  cat >"$repo_dir/ai/scripts/ai_design.sh" <<'EOF'
#!/usr/bin/env bash
echo "design"
EOF
  cat >"$repo_dir/ai/scripts/ai_plan.sh" <<'EOF'
#!/usr/bin/env bash
echo "planning"
EOF
  cat >"$repo_dir/ai/scripts/ai_implementation.sh" <<'EOF'
#!/usr/bin/env bash
echo "implementation"
EOF
  cat >"$repo_dir/ai/scripts/ai_user_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "user_review"
EOF
  cat >"$repo_dir/ai/scripts/ai_audit.sh" <<'EOF'
#!/usr/bin/env bash
echo "review"
EOF
  cat >"$repo_dir/ai/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post_review"
EOF
  chmod +x "$repo_dir/ai/scripts/ai_design.sh" "$repo_dir/ai/scripts/ai_plan.sh" \
    "$repo_dir/ai/scripts/ai_implementation.sh" "$repo_dir/ai/scripts/ai_user_review.sh" "$repo_dir/ai/scripts/ai_audit.sh" \
    "$repo_dir/ai/scripts/post_review.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
design | echo | mock-model
planning | echo | mock-model
implementation | echo | mock-model
user_review | echo | mock-model
ai_audit | echo | mock-model
EOF

  cat >"$repo_dir/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1) [REQ-1]
- [x] Implement part A (SP=2) [REQ-1]
- [x] Implement part B (SP=1) [REQ-1]
- [ ] Review step implementation (SP=1)
EOF
  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- 1. demo
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL support demo behavior.
- Plan Links: 1
- Verification: demo
- Status: done
EOF
  cat >"$repo_dir/ai/step_designs/step-1.1-design.md" <<'EOF'
## Goal
test
## In Scope
test
## Out of Scope
test
EOF

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
    git branch step-1.1-user-review
  )
}

set_single_phase_model() {
  local repo_dir="$1"
  local phase="$2"
  cat >"$repo_dir/ai/setup/models.md" <<EOF
$phase | echo | mock-model
EOF
}

seed_review_result_artifact() {
  local repo_dir="$1"
  local step="$2"
  mkdir -p "$repo_dir/ai/step_review_results"
  cat >"$repo_dir/ai/step_review_results/review_result-$step.md" <<EOF
# Review Result: Step $step
## Disposition (per issue)
- None.
EOF
}

test_ai_implementation_prompt_has_deterministic_structure() {
  local repo_dir="$TMP_ROOT/repo-ai-impl"
  setup_impl_repo "$repo_dir"

  (
    cd "$repo_dir"
    ai/scripts/ai_implementation.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/impl_prompts/test.prompt.txt --no-branch
  )

  local prompt
  prompt="$(cat "$repo_dir/ai/prompts/impl_prompts/test.prompt.txt")"
  assert_contains "$prompt" "Phase contract (read first)"
  assert_contains "$prompt" "Anti-regression checklist (max 8)"
  assert_contains "$prompt" "Execution list (step plan \`## Plan (ordered)\`)"
  assert_contains "$prompt" "Step-plan execution context"
  assert_contains "$prompt" "Scope contract (design)"
  assert_contains "$prompt" "Key design details (excerpt)"
  assert_contains "$prompt" "Codebase entrypoints (design references)"
  assert_contains "$prompt" "## Functional Requirements (translated from design EARS)"
  assert_contains "$prompt" "### FR-1.1-01"
  assert_contains "$prompt" "- [ ] 1. Implement part A [REQ-1] [NFR-2]."
  assert_contains "$prompt" "- [x] 2. Implement part B [REQ-1]."
  assert_contains "$prompt" "## Applicable UR Shortlist"
  assert_contains "$prompt" "UR-0100 - Validate JWT auth boundary handling."
  assert_contains "$prompt" 'Before ending the implementation phase, run `ai/scripts/helpers/check_implementation_readiness.sh 1.1`.'
  assert_contains "$prompt" 'If that readiness check fails, do not emit the final completion line. Follow the Implementation Readiness Gate rules in `ai/AI_DEVELOPMENT_PROCESS.md`.'
  assert_line_before "$prompt" "Phase contract (read first)" "Anti-regression checklist (max 8)"
  assert_line_before "$prompt" "Anti-regression checklist (max 8)" "Execution list (step plan \`## Plan (ordered)\`)"
  assert_line_before "$prompt" "Execution list (step plan \`## Plan (ordered)\`)" "Step-plan execution context"
  assert_line_before "$prompt" "Step-plan execution context" "Scope contract (design)"
  assert_line_before "$prompt" "Scope contract (design)" "Key design details (excerpt)"
  assert_line_before "$prompt" "Key design details (excerpt)" "Codebase entrypoints (design references)"
  assert_line_before "$prompt" "Codebase entrypoints (design references)" "Process pointers"
  assert_not_contains "$prompt" "== estimation summary =="
  assert_not_contains "$prompt" "== repo snapshot =="
}

test_implementation_readiness_helper_fails_on_unchecked_ordered_items() {
  local repo_dir="$TMP_ROOT/repo-impl-readiness-ordered-unchecked"
  setup_impl_repo "$repo_dir"

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. demo A
- [ ] 2. demo B
## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 The system SHALL support demo A. EARS[REQ-1]
- [x] FR-1.1-002 The system SHALL support demo B. EARS[REQ-1]
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/helpers/check_implementation_readiness.sh 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: implementation readiness helper should fail when ordered-plan checklist has unchecked items" >&2
    exit 1
  fi
  assert_contains "$out" "Implementation readiness failed for step 1.1."
  assert_contains "$out" "All items in step plan '## Plan (ordered)' must be [x] before handing off implementation."
}

test_implementation_readiness_helper_fails_on_unchecked_functional_requirements() {
  local repo_dir="$TMP_ROOT/repo-impl-readiness-fr-unchecked"
  setup_impl_repo "$repo_dir"

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. demo A
- [x] 2. demo B
## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 The system SHALL support demo A. EARS[REQ-1]
- [ ] FR-1.1-002 The system SHALL support demo B. EARS[REQ-1]
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/helpers/check_implementation_readiness.sh 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: implementation readiness helper should fail when translated functional requirements are unchecked" >&2
    exit 1
  fi
  assert_contains "$out" "Implementation readiness failed for step 1.1."
  assert_contains "$out" "All items in step plan '## Functional Requirements (translated from design EARS)' must be [x] before handing off implementation."
}

test_ai_implementation_allows_non_executable_planning_helper() {
  local repo_dir="$TMP_ROOT/repo-impl-planning-helper-no-exec"
  setup_impl_repo "$repo_dir"
  chmod -x "$repo_dir/ai/scripts/helpers/check_planning_readiness.sh"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/ai_implementation.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/impl.prompt.txt --no-branch 2>&1)"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: ai_implementation should allow a readable planning helper without execute bit" >&2
    echo "$out" >&2
    exit 1
  fi
  assert_not_contains "$out" "Planning readiness helper not found or not readable:"
}

test_ai_implementation_prompt_builds_deduped_anti_regression_checklist() {
  local repo_dir="$TMP_ROOT/repo-ai-impl-step-plan-shortlist"
  setup_impl_repo "$repo_dir"

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Design Anchor (scope source of truth)
- ai/step_designs/step-1.1-design.md
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL implement part A behavior.
- Plan Links: 1
- Verification: Add/update tests.
- Status: pending
### FR-1.1-02
- Source EARS Block: REQ-1
- Requirement: The system SHALL implement part B behavior.
- Plan Links: 2
- Verification: Add/update tests.
- Status: pending
## Applicable UR Shortlist
- UR-0001 - Step-plan rule one.
- UR-0002 - Step-plan rule two.
## Plan (ordered)
- [ ] 1. Implement part A [REQ-1].
- [ ] 2. Implement part B [REQ-1].
## Implementation Notes / Constraints
- Follow AGENTS.md.
## Tests
- Add/update tests.
## Docs / Artifacts
- Update docs.
## Risks / Edge Cases
- None.
## Decisions Needed
- None.
EOF
  cat >"$repo_dir/ai/step_designs/step-1.1-design.md" <<'EOF'
## Goal
- Goal.
## In Scope
- Scope.
## Out of Scope
- Out.
## Non-goals
- Non-goal.
## Proposal / Design Details
- details
## Risks and Mitigations
- risk
## Applicable AGENTS.md Constraints
- constraints
## Applicable User Review Rules
- UR-0002 - Duplicate in design should be deduped.
- UR-0003 - Design-only rule should be retained.
## Applicable ADR Shortlist
- ADR-1
## References in Current Codebase
- `a` - a
EOF

  (
    cd "$repo_dir"
    ai/scripts/ai_implementation.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/impl_prompts/test.prompt.txt --no-branch
  )

  local prompt anti_block
  prompt="$(cat "$repo_dir/ai/prompts/impl_prompts/test.prompt.txt")"
  anti_block="$(printf '%s\n' "$prompt" | awk '
    /^Anti-regression checklist \(max 8\)$/ { in_section=1; next }
    in_section && /^Execution list \(step plan `## Plan \(ordered\)`\)$/ { exit }
    in_section { print }
  ')"

  assert_contains "$anti_block" "UR-0001 - Step-plan rule one."
  assert_contains "$anti_block" "UR-0002 - Step-plan rule two."
  assert_contains "$anti_block" "UR-0003 - Design-only rule should be retained."
  local ur2_count
  ur2_count="$(printf '%s\n' "$anti_block" | grep -c 'UR-0002' || true)"
  if [[ "$ur2_count" -ne 1 ]]; then
    echo "Assertion failed: expected UR-0002 exactly once in anti-regression checklist" >&2
    echo "$anti_block" >&2
    exit 1
  fi
  local anti_count
  anti_count="$(printf '%s\n' "$anti_block" | grep -c '^- ' || true)"
  if (( anti_count > 8 )); then
    echo "Assertion failed: anti-regression checklist must be capped at 8 bullets" >&2
    echo "$anti_block" >&2
    exit 1
  fi
}

test_ai_implementation_prompt_caps_and_requirement_filtering() {
  local repo_dir="$TMP_ROOT/repo-ai-impl-caps"
  setup_impl_repo "$repo_dir"

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Design Anchor (scope source of truth)
- ai/step_designs/step-1.1-design.md
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL implement part A behavior.
- Plan Links: 1
- Verification: test-1
- Status: pending
## Applicable UR Shortlist
- UR-0001 - one
## Plan (ordered)
- [ ] 1. Implement part A [REQ-1] [NFR-2].
## Implementation Notes / Constraints
- note-01
- note-02
- note-03
- note-04
- note-05
- note-06
- note-07
- note-08
- note-09
- note-10
- note-11
- note-12
- note-13-should-not-appear
## Tests
- test-1
## Docs / Artifacts
- docs
## Risks / Edge Cases
- risk-1
- risk-2
- risk-3
- risk-4
- risk-5
- risk-6
- risk-7
- risk-8
- risk-9-should-not-appear
## Decisions Needed
- Choice: Accepted.
EOF

  cat >"$repo_dir/ai/step_designs/step-1.1-design.md" <<'EOF'
## Goal
- goal-1
- goal-2
## In Scope
- scope-1
## Out of Scope
- out-1
## Non-goals
- non-goal-1
## Proposal / Design Details
- proposal-01
- proposal-02
- proposal-03
- proposal-04
- proposal-05
- proposal-06
- proposal-07
- proposal-08
- proposal-09
- proposal-10
- proposal-11
- proposal-12
- proposal-13
- proposal-14
- proposal-15
- proposal-16
- proposal-17
- proposal-18
- proposal-19
- proposal-20
- proposal-21-should-not-appear
## Risks and Mitigations
- drisk-1
- drisk-2
- drisk-3
- drisk-4
- drisk-5
- drisk-6
- drisk-7
- drisk-8
- drisk-9
- drisk-10
- drisk-11-should-not-appear
## Applicable AGENTS.md Constraints
- constraint-1
## Applicable User Review Rules
- UR-0001 - one
## Applicable ADR Shortlist
- ADR-1
## References in Current Codebase
- `src/main/a` - a
EOF

  (
    cd "$repo_dir"
    ai/scripts/ai_implementation.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/impl_prompts/test.prompt.txt --no-branch
  )

  local prompt
  prompt="$(cat "$repo_dir/ai/prompts/impl_prompts/test.prompt.txt")"
  assert_contains "$prompt" "note-12"
  assert_not_contains "$prompt" "note-13-should-not-appear"
  assert_contains "$prompt" "risk-8"
  assert_not_contains "$prompt" "risk-9-should-not-appear"
  assert_contains "$prompt" "proposal-20"
  assert_not_contains "$prompt" "proposal-21-should-not-appear"
  assert_contains "$prompt" "drisk-10"
  assert_not_contains "$prompt" "drisk-11-should-not-appear"
  assert_contains "$prompt" "## Functional Requirements (translated from design EARS)"
  assert_contains "$prompt" "### FR-1.1-01"
  assert_contains "$prompt" "Source EARS Block: REQ-1"
}

test_ai_implementation_prompt_is_deterministic_and_compact() {
  local repo_dir="$TMP_ROOT/repo-ai-impl-determinism"
  setup_impl_repo "$repo_dir"

  (
    cd "$repo_dir"
    ai/scripts/ai_implementation.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/impl_prompts/test-1.prompt.txt --no-branch
    ai/scripts/ai_implementation.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/impl_prompts/test-2.prompt.txt --no-branch
  )

  if ! cmp -s "$repo_dir/ai/prompts/impl_prompts/test-1.prompt.txt" "$repo_dir/ai/prompts/impl_prompts/test-2.prompt.txt"; then
    echo "Assertion failed: prompt output is not byte-deterministic for identical inputs" >&2
    exit 1
  fi

  local prompt
  local prompt_bytes
  prompt="$(cat "$repo_dir/ai/prompts/impl_prompts/test-1.prompt.txt")"
  prompt_bytes="$(printf '%s' "$prompt" | wc -c | tr -d '[:space:]')"
  if (( prompt_bytes > 7000 )); then
    echo "Assertion failed: implementation prompt too large, expected <= 7000 bytes, got $prompt_bytes" >&2
    exit 1
  fi
}

test_ai_implementation_prompt_normalizes_plain_ordered_bullets() {
  local repo_dir="$TMP_ROOT/repo-ai-impl-normalized-ordered"
  setup_impl_repo "$repo_dir"

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Design Anchor (scope source of truth)
- ai/step_designs/step-1.1-design.md
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL implement part A behavior.
- Plan Links: 1, 2
- Verification: Add/update tests.
- Status: pending
## Applicable UR Shortlist
- None.
## Plan (ordered)
- 1. Implement part A [REQ-1].
- 2. Implement part B [REQ-1].
## Implementation Notes / Constraints
- Follow AGENTS.md.
## Tests
- Add/update tests.
## Docs / Artifacts
- Update docs.
## Risks / Edge Cases
- None.
## Decisions Needed
- None.
EOF

  (
    cd "$repo_dir"
    ai/scripts/ai_implementation.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/impl_prompts/test.prompt.txt --no-branch
  )

  local prompt
  prompt="$(cat "$repo_dir/ai/prompts/impl_prompts/test.prompt.txt")"
  assert_contains "$prompt" "- [ ] 1. Implement part A [REQ-1]."
  assert_contains "$prompt" "- [ ] 2. Implement part B [REQ-1]."
}

test_orchestrator_does_not_gate_implementation_when_ordered_items_unchecked() {
  local repo_dir="$TMP_ROOT/repo-orch-impl-ordered-unchecked"
  setup_orchestrator_repo "$repo_dir"
  seed_review_result_artifact "$repo_dir" "1.1"

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. demo A
- [ ] 2. demo B
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL support demo A and B.
- Plan Links: 1, 2
- Verification: demo
- Status: done
EOF

  local out
  out="$(
    cd "$repo_dir" &&
    set_single_phase_model "$repo_dir" "implementation" &&
    ai/scripts/orchestrator.sh -- --step 1.1 2>&1
  )"
  assert_not_contains "$out" "Implementation exit gate failed for step 1.1."
}

test_orchestrator_implementation_runs_when_all_ordered_items_checked() {
  local repo_dir="$TMP_ROOT/repo-orch-impl-gate-pass"
  setup_orchestrator_repo "$repo_dir"
  seed_review_result_artifact "$repo_dir" "1.1"

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. demo A
- [x] 2. demo B
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL support demo A and B.
- Plan Links: 1, 2
- Verification: demo
- Status: done
EOF

  (
    cd "$repo_dir"
    set_single_phase_model "$repo_dir" "implementation"
    ai/scripts/orchestrator.sh -- --step 1.1 >/tmp/orch-impl-gate-pass.out 2>/tmp/orch-impl-gate-pass.err
  )
}

test_orchestrator_does_not_gate_implementation_when_functional_requirements_unchecked() {
  local repo_dir="$TMP_ROOT/repo-orch-impl-functional-incomplete"
  setup_orchestrator_repo "$repo_dir"
  seed_review_result_artifact "$repo_dir" "1.1"

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. demo A
- [x] 2. demo B
## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 The system SHALL support demo A. EARS[REQ-1]
- [ ] FR-1.1-002 The system SHALL support demo B. EARS[REQ-1]
EOF

  local out
  out="$(
    cd "$repo_dir" &&
    set_single_phase_model "$repo_dir" "implementation" &&
    ai/scripts/orchestrator.sh -- --step 1.1 2>&1
  )"
  assert_not_contains "$out" "Implementation exit gate failed for step 1.1."
}

test_step_plan_template_enforces_functional_requirement_contract() {
  local template="$SOURCE_ROOT/ai/templates/step_plan_TEMPLATE.md"
  local golden="$SOURCE_ROOT/ai/golden_examples/step_plan_GOLDEN_EXAMPLE.md"
  local template_content golden_content

  template_content="$(cat "$template")"
  golden_content="$(cat "$golden")"

  assert_not_heading "$template_content" "Target Bullets"
  assert_not_heading "$template_content" "Requirement Tags"
  assert_contains "$template_content" "## Functional Requirements (translated from design EARS)"
  assert_contains "$template_content" "- [ ] FR-<step-id>-001 The system SHALL"
  assert_contains "$template_content" "EARS[REQ-<id>]"

  assert_not_heading "$golden_content" "Target Bullets"
  assert_not_heading "$golden_content" "Requirement Tags"
  assert_contains "$golden_content" "## Functional Requirements (translated from design EARS)"
  assert_contains "$golden_content" "- [x] FR-1.6b-001 The system SHALL"
  assert_contains "$golden_content" "EARS[REQ-12.1]"
}

test_process_doc_defines_evidence_reasoning_summary_gate() {
  local process_doc="$SOURCE_ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
  local content
  content="$(cat "$process_doc")"
  assert_contains "$content" "#### 6.0) Entry proof-check against implementation_plan target bullets (required first gate)"
  assert_contains "$content" "Evidence Reasoning Summary output (required at ai_audit entry):"
  assert_contains "$content" 'For every `PROVEN` bullet, include code refs, reachability, and test evidence/mapping.'
  assert_contains "$content" 'If any target bullet is `NOT_PROVEN`, fail/flag ai_audit entry and stop before deeper Section 6.1 analysis.'
  assert_contains "$content" "#### 6.1) Analyse TODOs and convert them to findings (required second gate)"
  assert_contains "$content" "#### 6.4) AI Audit Disposition Gate (required before completion and before post_review)"
  assert_contains "$content" 'Before emitting the ai_audit completion line, run `ai/scripts/helpers/check_ai_audit_disposition_readiness.sh <current_step>`.'
  assert_contains "$content" 'Treat Section 6 as a closure loop, not a single pass: after every user decision and every artifact update, re-check the ai_audit completion gates and keep iterating until they pass.'
  assert_contains "$content" 'All bullets in the current step section of `overmind/implementation_plan.md` must be checklist bullets and marked `[x]` (including `Review step implementation`).'
}

setup_ai_audit_prompt_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/scripts/helpers" "$repo_dir/ai/step_plans" "$repo_dir/ai/step_designs" "$repo_dir/overmind"

  cp "$AI_AUDIT_SRC" "$repo_dir/ai/scripts/ai_audit.sh"
  cp "$AI_AUDIT_DISPOSITION_HELPER_SRC" "$repo_dir/ai/scripts/helpers/check_ai_audit_disposition_readiness.sh"
  chmod +x "$repo_dir/ai/scripts/ai_audit.sh" "$repo_dir/ai/scripts/helpers/check_ai_audit_disposition_readiness.sh"

  cat >"$repo_dir/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1) [REQ-1]
- [x] Implement part A (SP=2) [REQ-1]
- [x] Implement part B (SP=1) [REQ-1]
- [ ] Review step implementation (SP=1)
EOF

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. Implement part A.
- [x] 2. Implement part B.
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL implement part A.
- Plan Links: 1
- Verification: demo
- Status: done
### FR-1.1-02
- Source EARS Block: REQ-1
- Requirement: The system SHALL implement part B.
- Plan Links: 2
- Verification: demo
- Status: done
EOF

  cat >"$repo_dir/ai/step_designs/step-1.1-design.md" <<'EOF'
# Feature Design: preamble should not leak
Date: 2099-01-01
Designer model/session: preamble-should-not-leak

## Target Bullets
- Implement part A
- Implement part B
## Proposal / Design Details
- demo
## Risks and Mitigations
- none
## Applicable AGENTS.md Constraints
- follow constraints
## Applicable UR Shortlist
- UR-1
## Applicable ADR Shortlist
- ADR-1
## Things to Decide (for final planning discussion)
- none
EOF

  cat >"$repo_dir/ai/AI_DEVELOPMENT_PROCESS.md" <<'EOF'
### 6) Post-step ai_audit/review (required before moving to the next step)
#### 6.0) Entry proof-check against implementation_plan target bullets (required first gate)
- gate
#### 6.1) Analyse TODOs and convert them to findings (required second gate)
- todos
#### 6.2) Audit review and findings
- review
#### 6.3) Per-finding issue disposition workflow
- disposition
EOF

  cat >"$repo_dir/ai/blocker_log.md" <<'EOF'
## Step 1.1 Demo
- none
EOF

  cat >"$repo_dir/ai/open_questions.md" <<'EOF'
## Step 1.1 Demo
- none
EOF

  cat >"$repo_dir/overmind/reqirements_ears.md" <<'EOF'
### Requirement 1 Demo
- demo
EOF

  cat >"$repo_dir/AGENTS.md" <<'EOF'
Constraints.
EOF

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
    git checkout -qb step-1.1-implementation
    git checkout -qb step-1.1-user-review
  )
}

write_review_result_fixture() {
  local repo_dir="$1"
  local mode="$2"

  mkdir -p "$repo_dir/ai/step_review_results"
  case "$mode" in
    missing_disposition)
      cat >"$repo_dir/ai/step_review_results/review_result-1.1.md" <<'EOF'
## Critical
- Missing null validation on review handoff.

## High
- (none)
EOF
      ;;
    insufficient_dispositions)
      cat >"$repo_dir/ai/step_review_results/review_result-1.1.md" <<'EOF'
## Critical
- Missing null validation on review handoff.

## High
- Follow-up branch cleanup is undocumented.

## Medium
- (none)

## Low
- (none)

## Disposition (per issue)
- **Accepted**: Track the validation gap in a follow-up step.
EOF
      ;;
    complete)
      cat >"$repo_dir/ai/step_review_results/review_result-1.1.md" <<'EOF'
## Critical
- Missing null validation on review handoff.

## High
- Follow-up branch cleanup is undocumented.

## Medium
- (none)

## Low
- (none)

## Disposition (per issue)
- **Accepted**: Track the validation gap in a follow-up step.
- **Rejected**: Cleanup note is informational and does not require action.
EOF
      ;;
    *)
      echo "Unknown review fixture mode: $mode" >&2
      exit 1
      ;;
  esac
}

setup_post_review_repo() {
  local repo_dir="$1"
  local review_mode="$2"
  local review_checked="${3:-1}"
  local impl_checked="${4:-1}"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/scripts/helpers" "$repo_dir/ai/step_plans" \
    "$repo_dir/ai/step_review_results" "$repo_dir/overmind"

  cp "$POST_REVIEW_SRC" "$repo_dir/ai/scripts/post_review.sh"
  cp "$AI_AUDIT_DISPOSITION_HELPER_SRC" "$repo_dir/ai/scripts/helpers/check_ai_audit_disposition_readiness.sh"
  chmod +x "$repo_dir/ai/scripts/post_review.sh" "$repo_dir/ai/scripts/helpers/check_ai_audit_disposition_readiness.sh"

  local review_box=" "
  [[ "$review_checked" == "1" ]] && review_box="x"
  local impl_box=" "
  [[ "$impl_checked" == "1" ]] && impl_box="x"

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
EOF

  cat >"$repo_dir/overmind/implementation_plan.md" <<EOF
### Step 1.1 Demo
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1)
- [$impl_box] Implement part A (SP=2)
- [$review_box] Review step implementation (SP=1)
EOF

  write_review_result_fixture "$repo_dir" "$review_mode"

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
    git branch overmind
    git checkout -qb step-1.1-implementation
    git checkout -qb step-1.1-review
  )
}

test_ai_audit_prompt_requires_entry_proof_gate() {
  local repo_dir="$TMP_ROOT/repo-ai-audit-prompt"
  setup_ai_audit_prompt_repo "$repo_dir"

  echo "- changed during review" >>"$repo_dir/ai/open_questions.md"

  (
    cd "$repo_dir"
    ai/scripts/ai_audit.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/ai_audit_prompts/test.prompt.txt >/dev/null
  )

  local prompt
  prompt="$(cat "$repo_dir/ai/prompts/ai_audit_prompts/test.prompt.txt")"
  assert_contains "$prompt" 'ai_audit phase for Step 1.1 - Demo'
  assert_contains "$prompt" 'Follow `ai/AI_DEVELOPMENT_PROCESS.md` (Sections 6.0-6.4, Prompt governance) and `AGENTS.md` as the authoritative rules for this phase.'
  assert_contains "$prompt" 'Primary context is the inline audit context below.'
  assert_contains "$prompt" 'Read these artifacts directly from the repo:'
  assert_contains "$prompt" '- Step plan: ai/step_plans/step-1.1.md'
  assert_contains "$prompt" '- Feature design: ai/step_designs/step-1.1-design.md'
  assert_contains "$prompt" '- Review result artifact: '
  assert_contains "$prompt" 'Optional references (open only if needed):'
  assert_contains "$prompt" '- Implementation plan: '
  assert_contains "$prompt" '- Requirements: '
  assert_contains "$prompt" '- Blocker log: '
  assert_contains "$prompt" '- Open questions: '
  assert_contains "$prompt" '- Decisions: '
  assert_contains "$prompt" 'Run Section 6.0 first as the mandatory ai_audit entry proof-gate against `overmind/implementation_plan.md` target bullets, then continue Sections 6.1-6.4.'
  assert_contains "$prompt" 'Audit-loop rule: after each disposition or plan update, continue Sections 6.2-6.4 until every ai_audit gate passes; do not stop early because the user approved a follow-up bullet change.'
  assert_contains "$prompt" 'Before ending the ai_audit phase, ensure all bullets in the current step section of `overmind/implementation_plan.md` are checklist bullets and marked `[x]`, then run `ai/scripts/helpers/check_ai_audit_disposition_readiness.sh 1.1`.'
  assert_contains "$prompt" 'If that readiness check fails, keep iterating Section 6: finish dispositions and/or close remaining current-step bullets in `overmind/implementation_plan.md`, then rerun the helper.'
  assert_contains "$prompt" 'Extended completion-line gate: output the ai_audit completion line only after all current-step bullets are `[x]` in `overmind/implementation_plan.md`, the readiness helper passes, and the commit gate is satisfied (clean working tree).'
  assert_contains "$prompt" 'Only after the commit gate, current-step bullet closure, and readiness helper pass, end your final response with this exact last line: "ai_audit phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase."'
  assert_contains "$prompt" "== Target bullets (from overmind/implementation_plan.md) =="
  assert_contains "$prompt" "- Implement part A (SP=2)"
  assert_contains "$prompt" "- Implement part B (SP=1)"
  assert_contains "$prompt" "== Linked EARS requirement blocks =="
  assert_contains "$prompt" "### Requirement 1 Demo"
  assert_contains "$prompt" "== Design shortlist: Risks and mitigations =="
  assert_contains "$prompt" "- none"
  assert_contains "$prompt" "== Design shortlist: AGENTS constraints =="
  assert_contains "$prompt" "- follow constraints"
  assert_contains "$prompt" "== Design shortlist: UR shortlist =="
  assert_contains "$prompt" "- UR-1"
  assert_contains "$prompt" "== Design shortlist: ADR shortlist =="
  assert_contains "$prompt" "- ADR-1"
  assert_contains "$prompt" "== Step delta file list =="
  assert_contains "$prompt" " M ai/open_questions.md"
  assert_not_contains "$prompt" "## Plan (ordered)"
  assert_not_contains "$prompt" "== ai/AI_DEVELOPMENT_PROCESS.md (Sections 6.0-6.4) =="
  assert_not_contains "$prompt" 'Run the ai_audit flow in this exact order: Section 6.0 proof-check, Section 6.1 TODO scan, Section 6.2 audit review, Section 6.3 per-finding disposition, Section 6.4 disposition gate.'
  assert_not_contains "$prompt" "# Feature Design: preamble should not leak"
  assert_not_contains "$prompt" "Designer model/session: preamble-should-not-leak"
}

test_ai_audit_disposition_helper_fails_when_section_missing() {
  local repo_dir="$TMP_ROOT/repo-ai-audit-disposition-helper-missing-section"
  setup_post_review_repo "$repo_dir" "missing_disposition"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/helpers/check_ai_audit_disposition_readiness.sh 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: ai_audit disposition helper should fail when disposition section is missing" >&2
    exit 1
  fi
  assert_contains "$out" "AI audit disposition readiness failed for step 1.1."
  assert_contains "$out" "Review artifact is missing required section '## Disposition (per issue)'."
}

test_ai_audit_disposition_helper_fails_when_dispositions_are_insufficient() {
  local repo_dir="$TMP_ROOT/repo-ai-audit-disposition-helper-insufficient"
  setup_post_review_repo "$repo_dir" "insufficient_dispositions"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/helpers/check_ai_audit_disposition_readiness.sh 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: ai_audit disposition helper should fail when per-issue dispositions are incomplete" >&2
    exit 1
  fi
  assert_contains "$out" "AI audit disposition readiness failed for step 1.1."
  assert_contains "$out" "Review artifact lists 2 issue(s) but only 1 Accepted/Rejected disposition entry(ies)."
}

test_ai_audit_disposition_helper_fails_when_review_gate_is_open() {
  local repo_dir="$TMP_ROOT/repo-ai-audit-disposition-helper-review-open"
  setup_post_review_repo "$repo_dir" "complete" 0

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/helpers/check_ai_audit_disposition_readiness.sh 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: ai_audit disposition helper should fail when the implementation-plan review gate is still open" >&2
    exit 1
  fi
  assert_contains "$out" "AI audit disposition readiness failed for step 1.1."
  assert_contains "$out" "Current step review gate in overmind/implementation_plan.md is not [x]."
  assert_contains "$out" "Mark 'Review step implementation' complete before handing off ai_audit."
}

test_ai_audit_disposition_helper_fails_when_non_review_bullet_is_open() {
  local repo_dir="$TMP_ROOT/repo-ai-audit-disposition-helper-non-review-open"
  setup_post_review_repo "$repo_dir" "complete" 1 0

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/helpers/check_ai_audit_disposition_readiness.sh 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: ai_audit disposition helper should fail when a non-review current-step checklist bullet is unchecked" >&2
    exit 1
  fi
  assert_contains "$out" "AI audit disposition readiness failed for step 1.1."
  assert_contains "$out" "Current step has 1 unchecked checklist bullet(s) in overmind/implementation_plan.md."
  assert_contains "$out" "Mark all current-step checklist bullets [x] before handing off ai_audit."
}

test_post_review_fails_when_disposition_section_is_missing() {
  local repo_dir="$TMP_ROOT/repo-post-review-disposition-missing-section"
  setup_post_review_repo "$repo_dir" "missing_disposition"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/post_review.sh --step 1.1 --dry-run 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: post_review should fail when ai_audit disposition section is missing" >&2
    exit 1
  fi
  assert_contains "$out" "Post-review readiness failed for step 1.1."
  assert_contains "$out" "Review artifact is missing required section '## Disposition (per issue)'."
  assert_contains "$out" "ai_audit dispositions were not finished correctly. Complete the review artifact and rerun post_review."
}

test_post_review_fails_when_dispositions_are_insufficient() {
  local repo_dir="$TMP_ROOT/repo-post-review-disposition-insufficient"
  setup_post_review_repo "$repo_dir" "insufficient_dispositions"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/post_review.sh --step 1.1 --dry-run 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: post_review should fail when ai_audit per-issue dispositions are incomplete" >&2
    exit 1
  fi
  assert_contains "$out" "Post-review readiness failed for step 1.1."
  assert_contains "$out" "Review artifact lists 2 issue(s) but only 1 Accepted/Rejected disposition entry(ies)."
  assert_contains "$out" "ai_audit dispositions were not finished correctly. Complete the review artifact and rerun post_review."
}

test_post_review_fails_when_review_gate_is_open() {
  local repo_dir="$TMP_ROOT/repo-post-review-review-gate-open"
  setup_post_review_repo "$repo_dir" "complete" 0

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/post_review.sh --step 1.1 --dry-run 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: post_review should fail while the implementation-plan review gate is still open" >&2
    exit 1
  fi
  assert_contains "$out" "Post-review readiness failed for step 1.1."
  assert_contains "$out" "Current step review gate in overmind/implementation_plan.md is not [x]."
  assert_contains "$out" "ai_audit dispositions were not finished correctly. Complete the review artifact and rerun post_review."
}

test_post_review_fails_when_non_review_bullet_is_open() {
  local repo_dir="$TMP_ROOT/repo-post-review-non-review-open"
  setup_post_review_repo "$repo_dir" "complete" 1 0

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/post_review.sh --step 1.1 --dry-run 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: post_review should fail while any current-step checklist bullet is still open" >&2
    exit 1
  fi
  assert_contains "$out" "Post-review readiness failed for step 1.1."
  assert_contains "$out" "Current step has 1 unchecked checklist bullet(s) in overmind/implementation_plan.md."
  assert_contains "$out" "ai_audit dispositions were not finished correctly. Complete the review artifact and rerun post_review."
}

test_post_review_allows_non_executable_disposition_helper() {
  local repo_dir="$TMP_ROOT/repo-post-review-helper-no-exec"
  setup_post_review_repo "$repo_dir" "complete"
  chmod -x "$repo_dir/ai/scripts/helpers/check_ai_audit_disposition_readiness.sh"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/post_review.sh --step 1.1 --dry-run 2>&1)"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: post_review should allow a readable ai_audit helper without execute bit" >&2
    echo "$out" >&2
    exit 1
  fi
  assert_not_contains "$out" "AI audit disposition helper is missing or not readable:"
}

test_post_review_syncs_implementation_plan_to_overmind_branch() {
  local repo_dir="$TMP_ROOT/repo-post-review-overmind-sync"
  setup_post_review_repo "$repo_dir" "complete"

  cat >"$repo_dir/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
Est. step total: 6 SP
- [x] Plan and discuss the step (SP=1)
- [x] Implement part A (SP=2)
- [x] Review step implementation (SP=1)
- [x] Audit closure marker (SP=2)
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/post_review.sh --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: post_review should sync implementation plan into overmind branch" >&2
    echo "$out" >&2
    exit 1
  fi

  local current_branch
  current_branch="$(git -C "$repo_dir" branch --show-current)"
  if [[ "$current_branch" != "step-1.1-review" ]]; then
    echo "Assertion failed: post_review should return to review branch, got '$current_branch'" >&2
    exit 1
  fi

  local review_plan overmind_plan overmind_head_files
  review_plan="$(git -C "$repo_dir" show step-1.1-review:overmind/implementation_plan.md)"
  overmind_plan="$(git -C "$repo_dir" show overmind:overmind/implementation_plan.md)"
  if [[ "$review_plan" != "$overmind_plan" ]]; then
    echo "Assertion failed: overmind implementation plan must match review branch after sync" >&2
    exit 1
  fi
  assert_contains "$overmind_plan" "Audit closure marker"

  overmind_head_files="$(git -C "$repo_dir" show --name-only --pretty=format: refs/heads/overmind --)"
  assert_contains "$overmind_head_files" "overmind/implementation_plan.md"
  assert_not_contains "$overmind_head_files" "ai/history.md"
}

test_process_doc_defines_review_brief_mode() {
  local process_doc="$SOURCE_ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
  local content
  content="$(cat "$process_doc")"
  assert_contains "$content" 'Before asking for review feedback, provide a concise `Review Brief` (plain language, product-level) covering exactly:'
  assert_contains "$content" "what was changed and how"
  assert_contains "$content" "how to start code review"
  assert_contains "$content" "what should be checked first"
  assert_contains "$content" "Do not narrate artifact creation; focus on reviewer onboarding."
  assert_contains "$content" "Do not guess review ordering/entrypoints. If specific entrypoints are unclear, use cautious non-speculative guidance."
  assert_contains "$content" 'Use `ai/golden_examples/review_brief_GOLDEN_EXAMPLE.md` as the tone/structure anchor.'
}

test_review_brief_golden_example_exists() {
  local golden="$SOURCE_ROOT/ai/golden_examples/review_brief_GOLDEN_EXAMPLE.md"
  if [[ ! -f "$golden" ]]; then
    echo "Assertion failed: missing Review Brief golden example file: $golden" >&2
    exit 1
  fi

  local content
  content="$(cat "$golden")"
  assert_contains "$content" "What changed:"
  assert_contains "$content" "Start review:"
  assert_contains "$content" "Check first:"
}

test_orchestrator_does_not_block_ai_audit_without_evidence() {
  local repo_dir="$TMP_ROOT/repo-orch-review-no-evidence-gate"
  setup_orchestrator_repo "$repo_dir"
  seed_review_result_artifact "$repo_dir" "1.1"

  local status=0
  local out=""
  set +e
  out="$(
    cd "$repo_dir" &&
    set_single_phase_model "$repo_dir" "ai_audit" &&
    ai/scripts/orchestrator.sh -- --step 1.1 2>&1
  )"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: ai_audit should not fail when implementation evidence file is absent" >&2
    echo "$out" >&2
    exit 1
  fi
  if [[ "$out" == *"Implementation evidence missing for step"* ]]; then
    echo "Assertion failed: ai_audit output must not require implementation evidence file" >&2
    echo "$out" >&2
    exit 1
  fi
}

test_orchestrator_blocks_ai_audit_when_user_review_incomplete() {
  local repo_dir="$TMP_ROOT/repo-orch-review-blocked-no-user-review"
  setup_orchestrator_repo "$repo_dir"

  (
    cd "$repo_dir"
    git branch -D step-1.1-user-review >/dev/null
  )

  local status=0
  local out=""
  set +e
  out="$(
    cd "$repo_dir" &&
    set_single_phase_model "$repo_dir" "ai_audit" &&
    ai/scripts/orchestrator.sh -- --step 1.1 2>&1
  )"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: ai_audit should fail when user_review is incomplete" >&2
    exit 1
  fi
  assert_contains "$out" "Cannot start ai_audit for step 1.1: user_review phase is incomplete."
}

test_orchestrator_post_review_requires_ai_audit_artifact() {
  local repo_dir="$TMP_ROOT/repo-orch-post-review-requires-audit"
  setup_orchestrator_repo "$repo_dir"

  local status=0
  local out=""
  set +e
  out="$(
    cd "$repo_dir" &&
    set_single_phase_model "$repo_dir" "post_review" &&
    ai/scripts/orchestrator.sh -- --step 1.1 2>&1
  )"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: post_review should fail when ai_audit artifact is missing" >&2
    exit 1
  fi
  assert_contains "$out" "Cannot start post_review for step 1.1: ai_audit phase is incomplete."
}

test_ai_implementation_prompt_has_deterministic_structure
test_implementation_readiness_helper_fails_on_unchecked_ordered_items
test_implementation_readiness_helper_fails_on_unchecked_functional_requirements
test_ai_implementation_allows_non_executable_planning_helper
test_ai_implementation_prompt_builds_deduped_anti_regression_checklist
test_ai_implementation_prompt_caps_and_requirement_filtering
test_ai_implementation_prompt_is_deterministic_and_compact
test_ai_implementation_prompt_normalizes_plain_ordered_bullets
test_orchestrator_does_not_gate_implementation_when_ordered_items_unchecked
test_orchestrator_implementation_runs_when_all_ordered_items_checked
test_orchestrator_does_not_gate_implementation_when_functional_requirements_unchecked
test_step_plan_template_enforces_functional_requirement_contract
test_process_doc_defines_evidence_reasoning_summary_gate
test_process_doc_defines_review_brief_mode
test_review_brief_golden_example_exists
test_ai_audit_prompt_requires_entry_proof_gate
test_ai_audit_disposition_helper_fails_when_section_missing
test_ai_audit_disposition_helper_fails_when_dispositions_are_insufficient
test_ai_audit_disposition_helper_fails_when_review_gate_is_open
test_ai_audit_disposition_helper_fails_when_non_review_bullet_is_open
test_post_review_fails_when_disposition_section_is_missing
test_post_review_fails_when_dispositions_are_insufficient
test_post_review_fails_when_review_gate_is_open
test_post_review_fails_when_non_review_bullet_is_open
test_post_review_allows_non_executable_disposition_helper
test_post_review_syncs_implementation_plan_to_overmind_branch
test_orchestrator_does_not_block_ai_audit_without_evidence
test_orchestrator_blocks_ai_audit_when_user_review_incomplete
test_orchestrator_post_review_requires_ai_audit_artifact

echo "All implementation evidence tests passed."
