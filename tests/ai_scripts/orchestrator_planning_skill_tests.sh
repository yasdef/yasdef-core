#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"
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

assert_equal() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"
  local worker_uuid="11111111-1111-1111-1111-111111111111"
  local source_dir="$TMP_ROOT/source-planning-${repo_dir##*/}"
  local remote_dir="${source_dir}-remote.git"
  mkdir -p \
    "$repo_dir/.asdlc_worker/scripts/helpers" \
    "$repo_dir/.asdlc_worker/setup" \
    "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" \
    "$repo_dir/.asdlc_worker/step_open_questions" \
    "$repo_dir/.asdlc_worker/step_blockers" \
    "$repo_dir/.asdlc_worker/step_review_results" \
    "$repo_dir/.asdlc_worker/prompts" \
    "$repo_dir/.asdlc_worker/logs" \
    "$repo_dir/.asdlc_worker/overmind" \
    "$repo_dir/.codex/skills"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"

  cp "$ORCH_SRC" "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp -R "$PLAN_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-plan"
  chmod +x \
    "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"

  cat >"$repo_dir/.asdlc_worker/scripts/ai_implementation.sh" <<'EOF'
#!/usr/bin/env bash
echo "implementation-stub"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_user_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "user-review-stub"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_audit.sh" <<'EOF'
#!/usr/bin/env bash
echo "ai-audit-stub"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/post_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "post-review-stub"
EOF
  chmod +x \
    "$repo_dir/.asdlc_worker/scripts/ai_implementation.sh" \
    "$repo_dir/.asdlc_worker/scripts/ai_user_review.sh" \
    "$repo_dir/.asdlc_worker/scripts/ai_audit.sh" \
    "$repo_dir/.asdlc_worker/scripts/post_review.sh"

  cat >"$repo_dir/.asdlc_worker/scripts/fake_model.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

COUNTER_FILE=".asdlc_worker/logs/planning-counter.txt"
count=0
if [[ -f "$COUNTER_FILE" ]]; then
  count="$(cat "$COUNTER_FILE")"
fi
count=$((count + 1))
printf '%s' "$count" >"$COUNTER_FILE"

plan=".asdlc_worker/step_plans/step-1.1-feature-one.md"
open_questions=".asdlc_worker/step_open_questions/step-1.1-feature-one-open-questions.md"
blockers=".asdlc_worker/step_blockers/step-1.1-feature-one-blockers.md"
mkdir -p "$(dirname "$plan")" "$(dirname "$open_questions")" "$(dirname "$blockers")"

write_complete_plan() {
  cat >"$plan" <<'PLAN'
# Step Plan: 1.1 - Demo
## Applicable UR Shortlist
- None.
## Plan (ordered)
- [ ] 1. Implement demo behavior.
## Functional Requirements (translated from design EARS)
- [ ] FR-1.1-001 The system SHALL implement demo behavior. EARS[REQ-1]
## Decisions Needed
- Adapter strategy | Accepted | Keep adapter A for now.
PLAN
}

case "${PLANNING_SCENARIO:-clean_first}" in
  readiness_retry)
    if [[ "$count" -eq 1 ]]; then
      cat >"$plan" <<'PLAN'
# Step Plan: 1.1 - Demo
## Applicable UR Shortlist
- None.
## Plan (ordered)
- [ ] 1. Implement demo behavior.
PLAN
      : >"$open_questions"
      : >"$blockers"
    else
      write_complete_plan
      : >"$open_questions"
      : >"$blockers"
    fi
    ;;
  ledger_retry)
    write_complete_plan
    if [[ "$count" -eq 1 ]]; then
      cat >"$open_questions" <<'LEDGER'
- Need explicit adapter confirmation from the user.
LEDGER
      : >"$blockers"
    else
      : >"$open_questions"
      : >"$blockers"
    fi
    ;;
  clean_first)
    write_complete_plan
    : >"$open_questions"
    : >"$blockers"
    ;;
  *)
    echo "unknown scenario: ${PLANNING_SCENARIO:-}" >&2
    exit 1
    ;;
esac

echo "MODEL_RUN=$count"
echo "Token usage: input=1 output=1 total=2"
EOF
  chmod +x "$repo_dir/.asdlc_worker/scripts/fake_model.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
planning | .asdlc_worker/scripts/fake_model.sh | mock-model
EOF

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-feature-one-design.md" <<'EOF'
## Selected EARS Requirements (for planning translation)
### Requirement 1 Demo
- The system SHALL implement demo behavior.

## Things to Decide (for final planning discussion)
- Adapter strategy: keep adapter A or switch to adapter B.
EOF

  mkdir -p "$source_dir/feature-one"
  cat >"$source_dir/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF
  cat >"$source_dir/init_progress_definition.yaml" <<'EOF'
meta_info:
  project_id: 'project-planning'
steps: []
EOF
  cat >"$source_dir/feature-one/implementation_plan.md" <<EOF
### Step 1.1 Demo
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step. [REQ-1]
- [ ] Implement demo behavior. [REQ-1]
EOF
  cat >"$source_dir/feature-one/requirements_ears.md" <<'EOF'
### Requirement 1 Demo
- The system SHALL implement demo behavior.
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
project_id: 'project-planning'
worker_uuid: '$worker_uuid'
class: 'platform'
status: 'ready'
EOF

  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
  )
}

run_orchestrator_capture() {
  local repo_dir="$1"
  local scenario="$2"
  local rc=0
  local out=""
  set +e
  out="$(
    cd "$repo_dir" && \
      PLANNING_SCENARIO="$scenario" .asdlc_worker/scripts/orchestrator.sh -- --step 1.1 2>&1
  )"
  rc=$?
  set -e
  printf '%s\n%s' "$rc" "$out"
}

test_orchestrator_retries_when_readiness_fails() {
  local repo_dir="$TMP_ROOT/repo-readiness-retry"
  setup_repo "$repo_dir"

  local result rc out
  result="$(run_orchestrator_capture "$repo_dir" "readiness_retry")"
  rc="$(printf '%s' "$result" | sed -n '1p')"
  out="$(printf '%s' "$result" | sed -n '2,$p')"

  assert_contains "$out" "Cannot start post_review for step 1.1"
  assert_contains "$out" "re-running planning for step 1.1"
  assert_equal "2" "$(cat "$repo_dir/.asdlc_worker/logs/planning-counter.txt")"
  [[ "$rc" -ne 0 ]] || exit 1
}

test_orchestrator_retries_when_ledger_is_dirty() {
  local repo_dir="$TMP_ROOT/repo-ledger-retry"
  setup_repo "$repo_dir"

  local result rc out
  result="$(run_orchestrator_capture "$repo_dir" "ledger_retry")"
  rc="$(printf '%s' "$result" | sed -n '1p')"
  out="$(printf '%s' "$result" | sed -n '2,$p')"

  assert_contains "$out" "Cannot start post_review for step 1.1"
  assert_contains "$out" "re-running planning for step 1.1"
  assert_equal "2" "$(cat "$repo_dir/.asdlc_worker/logs/planning-counter.txt")"
  [[ "$rc" -ne 0 ]] || exit 1
}

test_orchestrator_stops_when_ready_and_ledgers_clean() {
  local repo_dir="$TMP_ROOT/repo-clean-first"
  setup_repo "$repo_dir"

  run_orchestrator_capture "$repo_dir" "clean_first" >/tmp/orch-planning.out
  assert_equal "1" "$(cat "$repo_dir/.asdlc_worker/logs/planning-counter.txt")"
}

test_orchestrator_retries_when_readiness_fails
test_orchestrator_retries_when_ledger_is_dirty
test_orchestrator_stops_when_ready_and_ledgers_clean

echo "orchestrator_planning_skill_tests: PASS"
