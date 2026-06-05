#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLAN_SKILL_DIR="$SOURCE_ROOT/ai/skills/yasdef-worker-plan"
IMPLEMENTATION_SKILL_DIR="$SOURCE_ROOT/ai/skills/yasdef-worker-implementation"
AI_AUDIT_SRC="$SOURCE_ROOT/ai/scripts/ai_audit.sh"
AI_AUDIT_DISPOSITION_HELPER_SRC="$SOURCE_ROOT/ai/scripts/helpers/check_ai_audit_disposition_readiness.sh"
POST_REVIEW_SRC="$SOURCE_ROOT/ai/scripts/post_review.sh"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"
BUILD_PHASE_CMD_SRC="$SOURCE_ROOT/ai/scripts/helpers/build_phase_cmd.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export UV_CACHE_DIR="$TMP_ROOT/uv-cache"

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

setup_orchestrator_repo() {
  local repo_dir="$1"
  local worker_uuid="11111111-1111-1111-1111-111111111111"
  local source_dir="$TMP_ROOT/source-evidence-${repo_dir##*/}"
  local remote_dir="${source_dir}-remote.git"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/setup" "$repo_dir/.asdlc_worker/step_designs" "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/overmind" "$repo_dir/.codex/skills"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"
  cp "$ORCH_SRC" "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp "$BUILD_PHASE_CMD_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/build_phase_cmd.sh"
  cp -R "$PLAN_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-plan"
  cp -R "$IMPLEMENTATION_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-implementation"
  chmod +x "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"
  cat >"$repo_dir/ai/scripts/ai_user_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "user_review"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_audit.sh" <<'EOF'
#!/usr/bin/env bash
echo "review"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post_review"
EOF
  chmod +x "$repo_dir/ai/scripts/ai_user_review.sh" "$repo_dir/.asdlc_worker/scripts/ai_audit.sh" \
    "$repo_dir/.asdlc_worker/scripts/post_review.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
design | echo | mock-model
planning | echo | mock-model
implementation | echo | mock-model
user_review | echo | mock-model
ai_audit | echo | mock-model
EOF

  cat >"$repo_dir/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
#### Assigned: 11111111-1111-1111-1111-111111111111
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1) [REQ-1]
- [x] Implement part A (SP=2) [REQ-1]
- [x] Implement part B (SP=1) [REQ-1]
- [ ] Review step implementation (SP=1)
EOF
  mkdir -p "$source_dir/feature-one"
  cat >"$source_dir/init_progress_definition.yaml" <<'EOF'
meta_info:
  project_id: project-evidence
EOF
  cat >"$source_dir/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF
  cat >"$source_dir/feature-one/implementation_plan.md" <<EOF
### Step 1.1 Demo
#### Assigned: $worker_uuid
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1) [REQ-1]
- [x] Implement part A (SP=2) [REQ-1]
- [x] Implement part B (SP=1) [REQ-1]
- [ ] Review step implementation (SP=1)
EOF
  cat >"$source_dir/feature-one/requirements_ears.md" <<'EOF'
### Requirement 1 Demo
- The system SHALL support demo behavior.
EOF

  (
    cd "$source_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add -A
    git commit -qm "init source repo"
    git init -q --bare "$remote_dir"
    git --git-dir "$remote_dir" symbolic-ref HEAD refs/heads/master
    git remote add origin "$remote_dir"
    git push -q -u origin master
  )

  cat >"$repo_dir/ai/project_overmind.yaml" <<EOF
overmind_source_path: '$source_dir'
project_id: 'project-evidence'
worker_uuid: '$worker_uuid'
class: 'platform'
status: 'ready'
EOF
  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-one.md" <<'EOF'
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
  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-feature-one-design.md" <<'EOF'
## Goal
test
## Selected EARS Requirements (for planning translation)
### Requirement 1 Demo
- The system SHALL support demo behavior.
## In Scope
test
## Out of Scope
test
EOF

  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
    git branch step-1.1-feature-one-user-review
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
  cat >"$repo_dir/ai/step_review_results/review_result-$step-feature-one.md" <<EOF
# Review Result: Step $step
## Disposition (per issue)
- None.
EOF
}

test_orchestrator_does_not_gate_implementation_when_ordered_items_unchecked() {
  local repo_dir="$TMP_ROOT/repo-orch-impl-ordered-unchecked"
  setup_orchestrator_repo "$repo_dir"
  seed_review_result_artifact "$repo_dir" "1.1"

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-one.md" <<'EOF'
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
    .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 2>&1
  )"
  assert_not_contains "$out" "Implementation exit gate failed for step 1.1."
}

test_orchestrator_implementation_runs_when_all_ordered_items_checked() {
  local repo_dir="$TMP_ROOT/repo-orch-impl-gate-pass"
  setup_orchestrator_repo "$repo_dir"
  seed_review_result_artifact "$repo_dir" "1.1"

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-one.md" <<'EOF'
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
    .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 >/tmp/orch-impl-gate-pass.out 2>/tmp/orch-impl-gate-pass.err
  )

  local prompt
  prompt="$(cat "$repo_dir/.asdlc_worker/logs/repo-orch-impl-gate-pass-implementation-latest-log")"
  assert_contains "$prompt" 'Use the `yasdef-worker-implementation` skill to run the ASDLC worker implementation phase.'
  assert_contains "$prompt" "- Step: 1.1"
  assert_contains "$prompt" "- Feature id: feature-one"
  assert_contains "$prompt" "- Branch: step-1.1-feature-one-implementation"
  assert_contains "$prompt" "- Step plan: "
  assert_contains "$prompt" "- Design artifact: "
  assert_contains "$prompt" "- Runtime implementation plan: "
}

test_orchestrator_does_not_gate_implementation_when_functional_requirements_unchecked() {
  local repo_dir="$TMP_ROOT/repo-orch-impl-functional-incomplete"
  setup_orchestrator_repo "$repo_dir"
  seed_review_result_artifact "$repo_dir" "1.1"

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-one.md" <<'EOF'
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
    .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 2>&1
  )"
  assert_not_contains "$out" "Implementation exit gate failed for step 1.1."
}

test_step_plan_template_enforces_functional_requirement_contract() {
  local template="$SOURCE_ROOT/ai/skills/yasdef-worker-plan/assets/step_plan_TEMPLATE.md"
  local golden="$SOURCE_ROOT/ai/skills/yasdef-worker-plan/assets/step_plan_GOLDEN_EXAMPLE.md"
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

setup_ai_audit_prompt_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/step_designs" "$repo_dir/.asdlc_worker/overmind"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"

  cp "$AI_AUDIT_SRC" "$repo_dir/.asdlc_worker/scripts/ai_audit.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp "$BUILD_PHASE_CMD_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/build_phase_cmd.sh"
  cp "$AI_AUDIT_DISPOSITION_HELPER_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/check_ai_audit_disposition_readiness.sh"
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_audit.sh" "$repo_dir/.asdlc_worker/scripts/helpers/check_ai_audit_disposition_readiness.sh"

  cat >"$repo_dir/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1) [REQ-1]
- [x] Implement part A (SP=2) [REQ-1]
- [x] Implement part B (SP=1) [REQ-1]
- [ ] Review step implementation (SP=1)
EOF

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1.md" <<'EOF'
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

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-design.md" <<'EOF'
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

  cat >"$repo_dir/ai/blocker_log.md" <<'EOF'
## Step 1.1 Demo
- none
EOF

  cat >"$repo_dir/.asdlc_worker/open_questions.md" <<'EOF'
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
  export ASDLC_RUNTIME_PLAN_PATH=".asdlc_worker/overmind/implementation_plan.md"
  export ASDLC_RUNTIME_EARS_PATH=".asdlc_worker/overmind/reqirements_ears.md"

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
    git checkout -qb step-1.1-feature-one-implementation
    git checkout -qb step-1.1-feature-one-user-review
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
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/step_plans" \
    "$repo_dir/.asdlc_worker/step_review_results" "$repo_dir/.asdlc_worker/overmind"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"

  cp "$POST_REVIEW_SRC" "$repo_dir/.asdlc_worker/scripts/post_review.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp "$BUILD_PHASE_CMD_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/build_phase_cmd.sh"
  cp "$AI_AUDIT_DISPOSITION_HELPER_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/check_ai_audit_disposition_readiness.sh"
  chmod +x "$repo_dir/.asdlc_worker/scripts/post_review.sh" "$repo_dir/.asdlc_worker/scripts/helpers/check_ai_audit_disposition_readiness.sh"

  local review_box=" "
  [[ "$review_checked" == "1" ]] && review_box="x"
  local impl_box=" "
  [[ "$impl_checked" == "1" ]] && impl_box="x"

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1.md" <<'EOF'
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

  echo "- changed during review" >>"$repo_dir/.asdlc_worker/open_questions.md"

  (
    cd "$repo_dir"
    .asdlc_worker/scripts/ai_audit.sh --step 1.1 --feature-id feature-one --step-plan .asdlc_worker/step_plans/step-1.1.md --design .asdlc_worker/step_designs/step-1.1-design.md --out .asdlc_worker/prompts/ai_audit_prompts/test.prompt.txt >/dev/null
  )

  local prompt
  prompt="$(cat "$repo_dir/.asdlc_worker/prompts/ai_audit_prompts/test.prompt.txt")"
  assert_contains "$prompt" 'ai_audit phase for Step 1.1 - Demo'
  assert_contains "$prompt" 'Primary context is the inline audit context below.'
  assert_contains "$prompt" 'Read these artifacts directly from the repo:'
  assert_contains "$prompt" '- Step plan: .asdlc_worker/step_plans/step-1.1.md'
  assert_contains "$prompt" '- Feature design: .asdlc_worker/step_designs/step-1.1-design.md'
  assert_contains "$prompt" '- Review result artifact: '
  assert_contains "$prompt" 'Optional references (open only if needed):'
  assert_contains "$prompt" '- Implementation plan: '
  assert_contains "$prompt" '- Requirements: '
  assert_contains "$prompt" '- Blocker log: '
  assert_contains "$prompt" '- Open questions: '
  assert_contains "$prompt" '- Decisions: '
  assert_contains "$prompt" 'Run Section 6.0 first as the mandatory ai_audit entry proof-gate against `.asdlc_worker/overmind/implementation_plan.md` target bullets, then continue Sections 6.1-6.4.'
  assert_contains "$prompt" 'Audit-loop rule: after each disposition or plan update, continue Sections 6.2-6.4 until every ai_audit gate passes; do not stop early because the user approved a follow-up bullet change.'
  assert_contains "$prompt" 'Before ending the ai_audit phase, ensure all bullets in the current step section of `.asdlc_worker/overmind/implementation_plan.md` are checklist bullets and marked `[x]`, then run `.asdlc_worker/scripts/helpers/check_ai_audit_disposition_readiness.sh 1.1 feature-one`.'
  assert_contains "$prompt" 'If that readiness check fails, keep iterating Section 6: finish dispositions and/or close remaining current-step bullets in `.asdlc_worker/overmind/implementation_plan.md`, then rerun the helper.'
  assert_contains "$prompt" 'Extended completion-line gate: output the ai_audit completion line only after all current-step bullets are `[x]` in `.asdlc_worker/overmind/implementation_plan.md`, the readiness helper passes, and the commit gate is satisfied (clean working tree).'
  assert_contains "$prompt" 'Only after the commit gate, current-step bullet closure, and readiness helper pass, end your final response with these exact last two lines: "ai_audit phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase." and "PHASE_FINISHED_CAN_CLOSE"'
  assert_contains "$prompt" "== Target bullets (from .asdlc_worker/overmind/implementation_plan.md) =="
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
  assert_contains "$prompt" " M .asdlc_worker/open_questions.md"
  assert_not_contains "$prompt" "## Plan (ordered)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_ai_audit_disposition_readiness.sh 1.1 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_ai_audit_disposition_readiness.sh 1.1 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_ai_audit_disposition_readiness.sh 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: ai_audit disposition helper should fail when the implementation-plan review gate is still open" >&2
    exit 1
  fi
  assert_contains "$out" "AI audit disposition readiness failed for step 1.1."
  assert_contains "$out" "Current step review gate in .asdlc_worker/overmind/implementation_plan.md is not [x]."
  assert_contains "$out" "Mark 'Review step implementation' complete before handing off ai_audit."
}

test_ai_audit_disposition_helper_fails_when_non_review_bullet_is_open() {
  local repo_dir="$TMP_ROOT/repo-ai-audit-disposition-helper-non-review-open"
  setup_post_review_repo "$repo_dir" "complete" 1 0

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_ai_audit_disposition_readiness.sh 1.1 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: ai_audit disposition helper should fail when a non-review current-step checklist bullet is unchecked" >&2
    exit 1
  fi
  assert_contains "$out" "AI audit disposition readiness failed for step 1.1."
  assert_contains "$out" "Current step has 1 unchecked checklist bullet(s) in .asdlc_worker/overmind/implementation_plan.md."
  assert_contains "$out" "Mark all current-step checklist bullets [x] before handing off ai_audit."
}

test_post_review_fails_when_disposition_section_is_missing() {
  local repo_dir="$TMP_ROOT/repo-post-review-disposition-missing-section"
  setup_post_review_repo "$repo_dir" "missing_disposition"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/post_review.sh --step 1.1 --dry-run 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/post_review.sh --step 1.1 --dry-run 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/post_review.sh --step 1.1 --dry-run 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: post_review should fail while the implementation-plan review gate is still open" >&2
    exit 1
  fi
  assert_contains "$out" "Post-review readiness failed for step 1.1."
  assert_contains "$out" "Current step review gate in .asdlc_worker/overmind/implementation_plan.md is not [x]."
  assert_contains "$out" "ai_audit dispositions were not finished correctly. Complete the review artifact and rerun post_review."
}

test_post_review_fails_when_non_review_bullet_is_open() {
  local repo_dir="$TMP_ROOT/repo-post-review-non-review-open"
  setup_post_review_repo "$repo_dir" "complete" 1 0

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/post_review.sh --step 1.1 --dry-run 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: post_review should fail while any current-step checklist bullet is still open" >&2
    exit 1
  fi
  assert_contains "$out" "Post-review readiness failed for step 1.1."
  assert_contains "$out" "Current step has 1 unchecked checklist bullet(s) in .asdlc_worker/overmind/implementation_plan.md."
  assert_contains "$out" "ai_audit dispositions were not finished correctly. Complete the review artifact and rerun post_review."
}

test_post_review_allows_non_executable_disposition_helper() {
  local repo_dir="$TMP_ROOT/repo-post-review-helper-no-exec"
  setup_post_review_repo "$repo_dir" "complete"
  chmod -x "$repo_dir/.asdlc_worker/scripts/helpers/check_ai_audit_disposition_readiness.sh"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/post_review.sh --step 1.1 --dry-run 2>&1)"
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
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/post_review.sh --step 1.1 2>&1)"
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
  review_plan="$(git -C "$repo_dir" show step-1.1-review:.asdlc_worker/overmind/implementation_plan.md)"
  overmind_plan="$(git -C "$repo_dir" show overmind:.asdlc_worker/overmind/implementation_plan.md)"
  if [[ "$review_plan" != "$overmind_plan" ]]; then
    echo "Assertion failed: overmind implementation plan must match review branch after sync" >&2
    exit 1
  fi
  assert_contains "$overmind_plan" "Audit closure marker"

  overmind_head_files="$(git -C "$repo_dir" show --name-only --pretty=format: refs/heads/overmind --)"
  assert_contains "$overmind_head_files" ".asdlc_worker/overmind/implementation_plan.md"
  assert_not_contains "$overmind_head_files" ".asdlc_worker/history.md"
}

test_review_brief_golden_example_exists() {
  local golden="$SOURCE_ROOT/ai/skills/yasdef-worker-user-review/assets/review_brief_GOLDEN_EXAMPLE.md"
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
    .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 2>&1
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
    git branch -D step-1.1-feature-one-user-review >/dev/null
  )

  local status=0
  local out=""
  set +e
  out="$(
    cd "$repo_dir" &&
    set_single_phase_model "$repo_dir" "ai_audit" &&
    .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 2>&1
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
    .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 2>&1
  )"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: post_review should fail when ai_audit artifact is missing" >&2
    exit 1
  fi
  assert_contains "$out" "Cannot start post_review for step 1.1: ai_audit phase is incomplete."
}

test_orchestrator_does_not_gate_implementation_when_ordered_items_unchecked
test_orchestrator_implementation_runs_when_all_ordered_items_checked
test_orchestrator_does_not_gate_implementation_when_functional_requirements_unchecked
test_step_plan_template_enforces_functional_requirement_contract
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
