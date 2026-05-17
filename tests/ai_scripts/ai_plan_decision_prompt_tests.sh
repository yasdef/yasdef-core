#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_PLAN_SRC="$SOURCE_ROOT/ai/scripts/ai_plan.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"
PROCESS_SRC="$SOURCE_ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
TEMPLATE_SRC="$SOURCE_ROOT/ai/templates/step_plan_TEMPLATE.md"

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

setup_repo() {
  local repo_dir="$1"
  local open_questions_line="$2"

  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/step_designs" "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/templates" "$repo_dir/.asdlc_worker/overmind"
  cp "$AI_PLAN_SRC" "$repo_dir/.asdlc_worker/scripts/ai_plan.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp "$PROCESS_SRC" "$repo_dir/.asdlc_worker/AI_DEVELOPMENT_PROCESS.md"
  cp "$TEMPLATE_SRC" "$repo_dir/.asdlc_worker/templates/step_plan_TEMPLATE.md"
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_plan.sh"

  cat >"$repo_dir/.asdlc_worker/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [ ] Plan and discuss the step. [REQ-1]
- [ ] Implement the feature endpoint. [REQ-1]
- [ ] Review step implementation.
EOF

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-demo-design.md" <<'EOF'
## Target Bullets
- Implement the feature endpoint.

## First-Feature Bootstrap (only if needed)
- Bootstrap required: yes
- Repo state rationale: This is the first implementation work on an empty backend repo.
- Blueprint result: relevant blueprint found
- Blueprint evidence: /tmp/project_stack_blueprint_back.md
- User stack decision: None
- Planning handoff: Scaffold creation must be the first ordered plan work item before endpoint implementation; create the backend service scaffold from the approved blueprint.

## Things to Decide (for final planning discussion)
- Select adapter strategy: keep adapter A default or switch to adapter B.

## Applicable AGENTS.md Constraints
- Follow AGENTS.md constraints relevant to this step.

## Applicable UR Shortlist
- UR-0001 - Keep behavior deterministic.

## Applicable ADR Shortlist
- ADR-0001 - Preserve existing API contract.
EOF

  cat >"$repo_dir/.asdlc_worker/open_questions.md" <<EOF
## Step 1.1 Demo
$open_questions_line
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

run_plan() {
  local repo_dir="$1"
  shift
  (
    cd "$repo_dir"
    export ASDLC_RUNTIME_PLAN_PATH=".asdlc_worker/overmind/implementation_plan.md"
    export ASDLC_RUNTIME_EARS_PATH=".asdlc_worker/overmind/reqirements_ears.md"
    .asdlc_worker/scripts/ai_plan.sh --step 1.1 --feature-id demo --out .asdlc_worker/step_plans/step-1.1-demo.md "$@"
  )
}

test_decision_prompt_contract_and_numeric_reply() {
  local repo_dir="$TMP_ROOT/repo-decision-contract"
  setup_repo "$repo_dir" "- Should we use adapter A or adapter B?"

  local out
  out="$(run_plan "$repo_dir")"

  assert_contains "$out" 'Use .asdlc_worker/AI_DEVELOPMENT_PROCESS.md (Section 2, Estimation Gates, Prompt governance) as the process rules for this phase.'
  assert_not_contains "$out" 'Treat design `## Things to Decide (for final planning discussion)` as required handoff input for user-facing clarification and decision resolution; do not invent a parallel structure.'
  assert_not_contains "$out" 'Decision prompts (required for unresolved design decisions): for each unresolved item in design `## Things to Decide`, ask exactly two options (`1.` recommended, `2.` alternative) and accept numeric reply `1` or `2`.'
  assert_not_contains "$out" 'Bootstrap source-of-truth contract: only use an explicit design bootstrap section if it is present; otherwise treat the step as normal feature work and do not re-investigate repo emptiness on your own.'
  assert_contains "$out" "Open questions currently present for this step: YES."
  assert_contains "$out" "== Design bootstrap handoff (optional source of truth) =="
  assert_contains "$out" "- Bootstrap required: yes"
  assert_contains "$out" "- Planning handoff: Scaffold creation must be the first ordered plan work item before endpoint implementation; create the backend service scaffold from the approved blueprint."
  assert_contains "$out" "== Design-extracted things to decide =="
  assert_contains "$out" "- Select adapter strategy: keep adapter A default or switch to adapter B."
}

test_clear_path_signal_is_unchanged() {
  local repo_dir="$TMP_ROOT/repo-clear-path"
  setup_repo "$repo_dir" "- No open questions."

  local out
  out="$(run_plan "$repo_dir")"

  assert_contains "$out" "Open questions currently present for this step: NO."
  assert_contains "$out" "== Design-extracted things to decide =="
}

test_feature_rich_mode_block_is_opt_in() {
  local repo_dir="$TMP_ROOT/repo-feature-rich-opt-in"
  setup_repo "$repo_dir" "- No open questions."

  local rich_out
  rich_out="$(run_plan "$repo_dir" --feature-rich-design-planning)"
  assert_contains "$rich_out" "Feature-rich design/planning mode: ENABLED (planning-only add-on)."
  assert_contains "$rich_out" "record each in \`## Decisions Needed\` as \`Accepted\` or \`Deferred\`"

  local default_out
  default_out="$(run_plan "$repo_dir")"
  assert_not_contains "$default_out" "Feature-rich design/planning mode: ENABLED (planning-only add-on)."
}

test_decision_prompt_contract_and_numeric_reply
test_clear_path_signal_is_unchanged
test_feature_rich_mode_block_is_opt_in

echo "All ai_plan decision prompt tests passed."
