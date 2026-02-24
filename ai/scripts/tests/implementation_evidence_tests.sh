#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
AI_IMPL_SRC="$SOURCE_ROOT/ai/scripts/ai_implementation.sh"
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
  cat >"$repo_dir/ai/scripts/ai_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "review"
EOF
  cat >"$repo_dir/ai/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post_review"
EOF
  chmod +x "$repo_dir/ai/scripts/ai_design.sh" "$repo_dir/ai/scripts/ai_plan.sh" \
    "$repo_dir/ai/scripts/ai_implementation.sh" "$repo_dir/ai/scripts/ai_review.sh" \
    "$repo_dir/ai/scripts/post_review.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
design | echo | mock-model
planning | echo | mock-model
implementation | echo | mock-model
review | echo | mock-model
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
  assert_contains "$prompt" 'Before any implementation bullet `[ ]` -> `[x]`, apply the proof gate in ai/AI_DEVELOPMENT_PROCESS.md Section 4.1 and keep bullets `[ ]` when proof is missing.'
  assert_contains "$prompt" 'Before the first Section 5 feedback request, emit the brief three-part human-review explanation mode defined in ai/AI_DEVELOPMENT_PROCESS.md Section 5.'
  if [[ "$prompt" == *"Implementation evidence artifact (required):"* ]]; then
    echo "Assertion failed: prompt must not require dedicated implementation evidence artifact" >&2
    exit 1
  fi
}

test_process_doc_defines_human_review_explanation_mode() {
  local process_doc="$SOURCE_ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
  local content
  content="$(cat "$process_doc")"
  assert_contains "$content" "Before asking for review feedback, provide a brief human-review explanation mode (plain language) covering exactly:"
  assert_contains "$content" "what was changed and how"
  assert_contains "$content" "how to start code review"
  assert_contains "$content" "what should be checked first"
  assert_contains "$content" "Keep it concise (short checklist-style summary; avoid long narrative)."
}

test_orchestrator_does_not_block_review_without_evidence() {
  local repo_dir="$TMP_ROOT/repo-orch-review-no-evidence-gate"
  setup_orchestrator_repo "$repo_dir"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --phase review -- --step 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: review should not fail when implementation evidence file is absent" >&2
    echo "$out" >&2
    exit 1
  fi
  if [[ "$out" == *"Implementation evidence missing for step"* ]]; then
    echo "Assertion failed: review output must not require implementation evidence file" >&2
    echo "$out" >&2
    exit 1
  fi
}

test_ai_implementation_prompt_uses_concise_evidence_gate
test_process_doc_defines_human_review_explanation_mode
test_orchestrator_does_not_block_review_without_evidence

echo "All implementation evidence tests passed."
