#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_IMPL_SRC="$SOURCE_ROOT/ai/scripts/ai_implementation.sh"
AI_AUDIT_SRC="$SOURCE_ROOT/ai/scripts/ai_audit.sh"
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

setup_impl_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/step_plans" "$repo_dir/ai/step_designs" \
    "$repo_dir/ai/templates" "$repo_dir/ai/golden_examples"

  cp "$AI_IMPL_SRC" "$repo_dir/ai/scripts/ai_implementation.sh"
  chmod +x "$repo_dir/ai/scripts/ai_implementation.sh"

  cat >"$repo_dir/ai/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1)
- [ ] Implement part A (SP=2)
- [ ] Implement part B (SP=1)
- [ ] Review step implementation (SP=1)
EOF

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Target Bullets
- Implement part A
- Implement part B
## Design Anchor (scope source of truth)
- ai/step_designs/step-1.1-design.md
## Plan (ordered)
- 1. Implement part A.
- 2. Implement part B.
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
  cat >"$repo_dir/reqirements_ears.md" <<'EOF'
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
  )
}

setup_orchestrator_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/setup" "$repo_dir/ai/step_designs" "$repo_dir/ai/step_plans"
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

  cat >"$repo_dir/ai/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1)
- [x] Implement part A (SP=2)
- [x] Implement part B (SP=1)
- [ ] Review step implementation (SP=1)
EOF
  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Target Bullets
- demo
## Plan (ordered)
- 1. demo
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

test_ai_implementation_prompt_uses_concise_evidence_gate() {
  local repo_dir="$TMP_ROOT/repo-ai-impl"
  setup_impl_repo "$repo_dir"

  (
    cd "$repo_dir"
    ai/scripts/ai_implementation.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/impl_prompts/test.prompt.txt --no-branch
  )

  local prompt
  prompt="$(cat "$repo_dir/ai/prompts/impl_prompts/test.prompt.txt")"
  assert_contains "$prompt" 'First rule (execution state, required): use step plan `## Plan (ordered)` as the only implementation-phase execution checklist.'
  assert_contains "$prompt" 'Execution strategy is adaptive: implement in the most coherent order/batching needed, but update ordered-bullet checkbox state per ordered item and mark `[x]` only when that specific ordered bullet is proven complete.'
  assert_contains "$prompt" 'Targeted verification may run during implementation when needed (focused tests/lint/typecheck), but it does not replace the full step gate.'
  assert_contains "$prompt" 'Run the full end-of-step verification gate from AGENTS.md exactly once after all ordered bullets are `[x]` and before Section 5.'
  assert_contains "$prompt" 'Implementation progress and completion reporting in this phase must reference only `## Plan (ordered)` bullets.'
  assert_contains "$prompt" 'Do not use `ai/implementation_plan.md` target bullets as implementation-phase gating or completion state; explicit target-bullet proof-check is performed first in ai_audit.'
  assert_not_contains "$prompt" 'emit an "Evidence Reasoning Summary" before handoff'
  assert_contains "$prompt" 'Before ending this phase, emit the concise three-point `Review Brief` defined in ai/AI_DEVELOPMENT_PROCESS.md Section 5: what changed/how, how to start review (entrypoints/order), and what to check first (top risks), using concrete references when available and no guessing.'
  assert_contains "$prompt" 'Do not start Section 5 review exchange in this phase. Stop after Review Brief so orchestrator can enter the dedicated User Review phase.'
  if [[ "$prompt" == *"Implementation evidence artifact (required):"* ]]; then
    echo "Assertion failed: prompt must not require dedicated implementation evidence artifact" >&2
    exit 1
  fi
}

test_ai_implementation_prompt_uses_step_plan_shortlist_as_primary() {
  local repo_dir="$TMP_ROOT/repo-ai-impl-step-plan-shortlist"
  setup_impl_repo "$repo_dir"

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Target Bullets
- Implement part A
- Implement part B
## Design Anchor (scope source of truth)
- ai/step_designs/step-1.1-design.md
## Applicable UR Shortlist
- UR-0999 - Step-plan shortlist should be primary.
## Plan (ordered)
- 1. Implement part A.
- 2. Implement part B.
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

  local prompt impl_ur_block
  prompt="$(cat "$repo_dir/ai/prompts/impl_prompts/test.prompt.txt")"
  impl_ur_block="$(printf '%s\n' "$prompt" | awk '
    /^== Applicable UR shortlist for implementation \(primary \+ fallback\) ==$/ { in_section=1; next }
    in_section && /^== / { exit }
    in_section { print }
  ')"

  assert_contains "$impl_ur_block" 'Source: step-plan `## Applicable UR Shortlist`'
  assert_contains "$impl_ur_block" "UR-0999 - Step-plan shortlist should be primary."
  assert_not_contains "$impl_ur_block" "UR-1"
}

test_ai_implementation_prompt_falls_back_to_design_shortlist() {
  local repo_dir="$TMP_ROOT/repo-ai-impl-design-fallback"
  setup_impl_repo "$repo_dir"

  (
    cd "$repo_dir"
    ai/scripts/ai_implementation.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/impl_prompts/test.prompt.txt --no-branch
  )

  local prompt impl_ur_block
  prompt="$(cat "$repo_dir/ai/prompts/impl_prompts/test.prompt.txt")"
  impl_ur_block="$(printf '%s\n' "$prompt" | awk '
    /^== Applicable UR shortlist for implementation \(primary \+ fallback\) ==$/ { in_section=1; next }
    in_section && /^== / { exit }
    in_section { print }
  ')"

  assert_contains "$impl_ur_block" 'Source: design fallback (`## Applicable UR Shortlist`) because step-plan shortlist is missing'
  assert_contains "$impl_ur_block" "UR-1"
}

test_process_doc_defines_evidence_reasoning_summary_gate() {
  local process_doc="$SOURCE_ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
  local content
  content="$(cat "$process_doc")"
  assert_contains "$content" "#### 6.0) Entry proof-check against implementation_plan target bullets (required first gate)"
  assert_contains "$content" "Evidence Reasoning Summary output (required at ai_audit entry):"
  assert_contains "$content" 'For every `PROVEN` bullet, include code refs, reachability, and test evidence/mapping.'
  assert_contains "$content" 'If any target bullet is `NOT_PROVEN`, fail/flag ai_audit entry and stop before deeper Section 6.1 analysis.'
}

setup_ai_audit_prompt_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/step_plans" "$repo_dir/ai/step_designs"

  cp "$AI_AUDIT_SRC" "$repo_dir/ai/scripts/ai_audit.sh"
  chmod +x "$repo_dir/ai/scripts/ai_audit.sh"

  cat >"$repo_dir/ai/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1)
- [x] Implement part A (SP=2)
- [x] Implement part B (SP=1)
- [ ] Review step implementation (SP=1)
EOF

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Target Bullets
- Implement part A
- Implement part B
## Plan (ordered)
- [x] 1. Implement part A.
- [x] 2. Implement part B.
EOF

  cat >"$repo_dir/ai/step_designs/step-1.1-design.md" <<'EOF'
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
#### 6.1) Audit review and findings
- review
#### 6.2) Per-finding issue disposition workflow
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

  cat >"$repo_dir/reqirements_ears.md" <<'EOF'
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

test_ai_audit_prompt_requires_entry_proof_gate() {
  local repo_dir="$TMP_ROOT/repo-ai-audit-prompt"
  setup_ai_audit_prompt_repo "$repo_dir"

  (
    cd "$repo_dir"
    ai/scripts/ai_audit.sh --step 1.1 --step-plan ai/step_plans/step-1.1.md --design ai/step_designs/step-1.1-design.md --out ai/prompts/ai_audit_prompts/test.prompt.txt >/dev/null
  )

  local prompt
  prompt="$(cat "$repo_dir/ai/prompts/ai_audit_prompts/test.prompt.txt")"
  assert_contains "$prompt" 'Use ai/AI_DEVELOPMENT_PROCESS.md (Sections 6.0-6.2, Prompt governance) and AGENTS.md as the authoritative rules for this phase.'
  assert_contains "$prompt" 'Run Section 6.0 first as the mandatory ai_audit entry proof-gate against `ai/implementation_plan.md` target bullets, then continue Sections 6.1-6.2.'
  assert_contains "$prompt" "== ai_audit entry proof-check target bullets (from ai/implementation_plan.md) =="
  assert_contains "$prompt" "- Implement part A (SP=2)"
  assert_contains "$prompt" "- Implement part B (SP=1)"
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

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --phase ai_audit -- --step 1.1 2>&1)"
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
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --phase ai_audit -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: ai_audit should fail when user_review is incomplete" >&2
    exit 1
  fi
  assert_contains "$out" "Cannot start ai_audit for step 1.1: user_review phase is incomplete."
}

test_ai_implementation_prompt_uses_concise_evidence_gate
test_ai_implementation_prompt_uses_step_plan_shortlist_as_primary
test_ai_implementation_prompt_falls_back_to_design_shortlist
test_process_doc_defines_evidence_reasoning_summary_gate
test_process_doc_defines_review_brief_mode
test_review_brief_golden_example_exists
test_ai_audit_prompt_requires_entry_proof_gate
test_orchestrator_does_not_block_ai_audit_without_evidence
test_orchestrator_blocks_ai_audit_when_user_review_incomplete

echo "All implementation evidence tests passed."
