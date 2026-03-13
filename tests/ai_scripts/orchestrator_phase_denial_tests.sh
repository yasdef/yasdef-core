#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

assert_occurrences() {
  local haystack="$1"
  local needle="$2"
  local expected_count="$3"
  local actual_count
  actual_count="$(printf '%s' "$haystack" | grep -F -o "$needle" | wc -l | tr -d '[:space:]')"
  if [[ "$actual_count" != "$expected_count" ]]; then
    echo "Assertion failed: expected '$needle' to appear $expected_count times, got $actual_count" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Assertion failed: expected file to exist: $path" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/setup" "$repo_dir/ai/step_plans" \
    "$repo_dir/ai/step_designs" "$repo_dir/ai/step_review_results" "$repo_dir/overmind"

  cp "$ORCH_SRC" "$repo_dir/ai/scripts/orchestrator.sh"
  chmod +x "$repo_dir/ai/scripts/orchestrator.sh"

  cat >"$repo_dir/ai/scripts/ai_design.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'design-prompt\n'
SCRIPT

  cat >"$repo_dir/ai/scripts/ai_plan.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'planning-prompt\n'
SCRIPT

  cat >"$repo_dir/ai/scripts/ai_implementation.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$(dirname "$out")"
printf 'implementation-prompt\n' >"$out"
SCRIPT

  cat >"$repo_dir/ai/scripts/ai_user_review.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
step_plan=""
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --step-plan)
      step_plan="$2"
      shift 2
      ;;
    --out)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
step="$(basename "$step_plan")"
step="${step#step-}"
step="${step%.md}"
mkdir -p "$(dirname "$out")" "ai/step_review_results"
printf 'user-review-prompt\n' >"$out"
cat >"ai/step_review_results/review_result-$step.md" <<'REVIEW'
## Critical
- (none)
## High
- (none)
## Medium
- (none)
## Low
- (none)
## Disposition (per issue)
- **Accepted**: none
REVIEW
SCRIPT

  cat >"$repo_dir/ai/scripts/ai_audit.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$(dirname "$out")"
printf 'ai-audit-prompt\n' >"$out"
SCRIPT

  cat >"$repo_dir/ai/scripts/post_review.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'post_review\n'
SCRIPT

  cat >"$repo_dir/ai/scripts/fake_model.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'model-run %s\n' "$*"
SCRIPT

  chmod +x "$repo_dir/ai/scripts/ai_design.sh" "$repo_dir/ai/scripts/ai_plan.sh" \
    "$repo_dir/ai/scripts/ai_implementation.sh" "$repo_dir/ai/scripts/ai_user_review.sh" \
    "$repo_dir/ai/scripts/ai_audit.sh" "$repo_dir/ai/scripts/post_review.sh" \
    "$repo_dir/ai/scripts/fake_model.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'MODELS'
design | ai/scripts/fake_model.sh | mock-model
planning | ai/scripts/fake_model.sh | mock-model
implementation | ai/scripts/fake_model.sh | mock-model
user_review | ai/scripts/fake_model.sh | mock-model
ai_audit | ai/scripts/fake_model.sh | mock-model
MODELS

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'STEPPLAN'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. demo
## Functional Requirements (translated from design EARS)
### FR-1.1-01
- Source EARS Block: REQ-1
- Requirement: The system SHALL execute demo behavior.
- Plan Links: 1
- Verification: demo
- Status: done
STEPPLAN

  cat >"$repo_dir/overmind/implementation_plan.md" <<'IMPLPLAN'
### Step 1.1 Demo
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1)
- [x] Implement part A (SP=3)
- [ ] Review step implementation (SP=1)
IMPLPLAN

  cat >"$repo_dir/ai/step_designs/step-1.1-design.md" <<'DESIGN'
## Goal
- demo
## In Scope
- demo
## Out of Scope
- demo
DESIGN

  cat >"$repo_dir/ai/blocker_log.md" <<'EOF2'
# Blocker Log
EOF2
  cat >"$repo_dir/ai/open_questions.md" <<'EOF2'
# Open Questions
EOF2
  cat >"$repo_dir/ai/user_review.md" <<'EOF2'
# User review rules
EOF2

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
  )
}

run_planning_denial_stops_downstream_prompts() {
  local repo_dir="$TMP_ROOT/repo-planning-denial"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  local out
  out="$(cd "$repo_dir" && script -q /dev/null ai/scripts/orchestrator.sh --phase planning --phase implementation --phase user_review --phase ai_audit --phase post_review -- --step 1.1 2>&1)"

  assert_contains "$out" "I am going to run next stage: planning"
  assert_not_contains "$out" "I am going to run next stage: implementation"
  assert_not_contains "$out" "I am going to run next stage: user_review"
  assert_not_contains "$out" "I am going to run next stage: ai_audit"
  assert_contains "$out" "Execution stopped: user denied phase progression at planning."
  assert_occurrences "$out" "Execution stopped: user denied phase progression at" 1
}

run_implementation_denial_stops_downstream_prompts() {
  local repo_dir="$TMP_ROOT/repo-implementation-denial"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  local out
  out="$(cd "$repo_dir" && script -q /dev/null ai/scripts/orchestrator.sh --phase implementation --phase user_review --phase ai_audit --phase post_review -- --step 1.1 2>&1)"

  assert_contains "$out" "I am going to run next stage: implementation"
  assert_not_contains "$out" "I am going to run next stage: user_review"
  assert_not_contains "$out" "I am going to run next stage: ai_audit"
  assert_contains "$out" "Execution stopped: user denied phase progression at implementation."
  assert_occurrences "$out" "Execution stopped: user denied phase progression at" 1
}

run_user_review_denial_stops_downstream_prompts() {
  local repo_dir="$TMP_ROOT/repo-user-review-denial"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  local out
  out="$(cd "$repo_dir" && script -q /dev/null ai/scripts/orchestrator.sh --phase user_review --phase ai_audit --phase post_review -- --step 1.1 2>&1)"

  assert_contains "$out" "I am going to run next stage: user_review"
  assert_not_contains "$out" "I am going to run next stage: ai_audit"
  assert_contains "$out" "Execution stopped: user denied phase progression at user_review."
  assert_occurrences "$out" "Execution stopped: user denied phase progression at" 1
}

run_ai_audit_denial_stops_post_review_prompt() {
  local repo_dir="$TMP_ROOT/repo-ai-audit-denial"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  local out
  out="$(cd "$repo_dir" && script -q /dev/null ai/scripts/orchestrator.sh --phase ai_audit --phase post_review -- --step 1.1 2>&1)"

  assert_contains "$out" "I am going to run next stage: ai_audit"
  assert_not_contains "$out" "I am going to run next stage: post_review"
  assert_contains "$out" "Execution stopped: user denied phase progression at ai_audit."
  assert_occurrences "$out" "Execution stopped: user denied phase progression at" 1
}

run_interactive_yes_path_still_executes_all_requested_phases() {
  local repo_dir="$TMP_ROOT/repo-interactive-yes-regression"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  if ! command -v expect >/dev/null 2>&1; then
    echo "Skipping interactive-yes regression test: 'expect' not found."
    return 0
  fi

  local out
  out="$(
    EXPECT_REPO_DIR="$repo_dir" expect <<'EXPECT_EOF'
set timeout 30
set repo $env(EXPECT_REPO_DIR)
spawn bash -lc "cd \"$repo\" && ai/scripts/orchestrator.sh --phase planning --phase implementation --phase user_review --phase ai_audit --phase post_review -- --step 1.1"
expect "I am going to run next stage: planning"
send -- "y\r"
expect "I am going to run next stage: implementation"
send -- "y\r"
expect "I am going to run next stage: user_review"
send -- "y\r"
expect "I am going to run next stage: ai_audit"
send -- "y\r"
expect eof
EXPECT_EOF
  )"

  assert_not_contains "$out" "Execution stopped: user denied phase progression at"
  assert_contains "$out" "I am going to run next stage: planning"
  assert_contains "$out" "I am going to run next stage: implementation"
  assert_contains "$out" "I am going to run next stage: user_review"
  assert_contains "$out" "I am going to run next stage: ai_audit"
  assert_contains "$out" "post_review"
}

run_noninteractive_no_denial_path_still_executes_all_requested_phases() {
  local repo_dir="$TMP_ROOT/repo-no-denial-regression"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"

  local out
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --phase planning --phase implementation --phase user_review --phase ai_audit --phase post_review -- --step 1.1 2>&1)"

  assert_not_contains "$out" "Execution stopped: user denied phase progression at"
  assert_contains "$out" "post_review"
  assert_file_exists "$repo_dir/ai/prompts/plan_prompts/repo-no-denial-regression-latest-planning-prompt.txt"
  assert_file_exists "$repo_dir/ai/prompts/impl_prompts/repo-no-denial-regression-latest-implementation-prompt.txt"
  assert_file_exists "$repo_dir/ai/prompts/user_review_prompts/repo-no-denial-regression-latest-user-review-prompt.txt"
  assert_file_exists "$repo_dir/ai/prompts/ai_audit_prompts/repo-no-denial-regression-latest-ai-audit-prompt.txt"
}

run_planning_denial_stops_downstream_prompts
run_implementation_denial_stops_downstream_prompts
run_user_review_denial_stops_downstream_prompts
run_ai_audit_denial_stops_post_review_prompt
run_interactive_yes_path_still_executes_all_requested_phases
run_noninteractive_no_denial_path_still_executes_all_requested_phases

echo "All orchestrator phase denial tests passed."
