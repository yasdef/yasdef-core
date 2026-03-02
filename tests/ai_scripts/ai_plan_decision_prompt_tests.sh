#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_PLAN_SRC="$SOURCE_ROOT/ai/scripts/ai_plan.sh"
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

  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/step_designs" "$repo_dir/ai/step_plans" "$repo_dir/ai/templates"
  cp "$AI_PLAN_SRC" "$repo_dir/ai/scripts/ai_plan.sh"
  cp "$PROCESS_SRC" "$repo_dir/ai/AI_DEVELOPMENT_PROCESS.md"
  cp "$TEMPLATE_SRC" "$repo_dir/ai/templates/step_plan_TEMPLATE.md"
  chmod +x "$repo_dir/ai/scripts/ai_plan.sh"

  cat >"$repo_dir/ai/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [ ] Plan and discuss the step. [REQ-1]
- [ ] Implement the feature endpoint. [REQ-1]
- [ ] Review step implementation.
EOF

  cat >"$repo_dir/ai/step_designs/step-1.1-design.md" <<'EOF'
## Target Bullets
- Implement the feature endpoint.

## Things to Decide (for final planning discussion)
- Select adapter strategy: keep adapter A default or switch to adapter B.

## Applicable AGENTS.md Constraints
- Follow AGENTS.md constraints relevant to this step.

## Applicable UR Shortlist
- UR-0001 - Keep behavior deterministic.

## Applicable ADR Shortlist
- ADR-0001 - Preserve existing API contract.
EOF

  cat >"$repo_dir/ai/open_questions.md" <<EOF
## Step 1.1 Demo
$open_questions_line
EOF

  cat >"$repo_dir/ai/blocker_log.md" <<'EOF'
## Step 1.1 Demo
- No blockers.
EOF

  cat >"$repo_dir/ai/decisions.md" <<'EOF'
## ADR-0001 - Baseline
- **Status**: Accepted
EOF

  cat >"$repo_dir/reqirements_ears.md" <<'EOF'
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
  (
    cd "$repo_dir"
    ai/scripts/ai_plan.sh --step 1.1 --out ai/step_plans/step-1.1.md
  )
}

test_decision_prompt_contract_and_numeric_reply() {
  local repo_dir="$TMP_ROOT/repo-decision-contract"
  setup_repo "$repo_dir" "- Should we use adapter A or adapter B?"

  local out
  out="$(run_plan "$repo_dir")"

  assert_contains "$out" 'Decision prompts (required for unresolved design decisions): for each unresolved item in design `## Things to Decide`, ask exactly two options (`1.` recommended, `2.` alternative) and accept numeric reply `1` or `2`.'
  assert_contains "$out" 'If design `## Things to Decide` is missing or weak, derive concrete plan-critical decisions from design trade-offs/risks/prerequisites and ask two-option prompts when the choice impacts implementation path.'
  assert_contains "$out" 'If no plan-critical trade-off remains, explicitly state why no additional decision prompt is needed before closing planning.'
  assert_not_contains "$out" 'Decision prompts (if required): ask only for unclear/blocking choices'
  assert_not_contains "$out" "1. <recommended/default option> (Recommended)"
  assert_not_contains "$out" "2. <alternative option>"
  assert_contains "$out" "Open questions currently present for this step: YES."
  assert_contains "$out" "== Design-extracted things to decide =="
  assert_contains "$out" "- Select adapter strategy: keep adapter A default or switch to adapter B."
}

test_clear_path_signal_is_unchanged() {
  local repo_dir="$TMP_ROOT/repo-clear-path"
  setup_repo "$repo_dir" "- No open questions."

  local out
  out="$(run_plan "$repo_dir")"

  assert_contains "$out" "Open questions currently present for this step: NO."
  assert_contains "$out" 'Decision prompts (required for unresolved design decisions): for each unresolved item in design `## Things to Decide`, ask exactly two options (`1.` recommended, `2.` alternative) and accept numeric reply `1` or `2`.'
  assert_contains "$out" "== Design-extracted things to decide =="
}

test_decision_prompt_contract_and_numeric_reply
test_clear_path_signal_is_unchanged

echo "All ai_plan decision prompt tests passed."
