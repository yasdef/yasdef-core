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
    echo "Assertion failed: expected output to NOT contain: $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_nonzero_status() {
  local status="$1"
  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: expected non-zero status" >&2
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
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/setup" "$repo_dir/ai/step_plans" "$repo_dir/overmind"

  cp "$ORCH_SRC" "$repo_dir/ai/scripts/orchestrator.sh"
  chmod +x "$repo_dir/ai/scripts/orchestrator.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'MODELS'
design | echo | mock-model
MODELS

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. demo
## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 The system SHALL execute demo behavior. EARS[REQ-1]
EOF

  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    mkdir -p ai overmind
    echo "seed" > README.md
    git add README.md ai overmind
    git commit -qm "seed"
  )
}

setup_remote_with_master() {
  local repo_dir="$1"
  (
    cd "$repo_dir"
    git init --bare -q "$repo_dir/remote.git"
    git remote add origin "$repo_dir/remote.git"
    git push -u origin master >/dev/null
  )
}

create_local_overmind_plan() {
  local repo_dir="$1"
  local plan_content="$2"
  (
    cd "$repo_dir"
    git checkout -b overmind >/dev/null
    mkdir -p overmind
    cat > overmind/implementation_plan.md <<PLAN
$plan_content
PLAN
    git add overmind/implementation_plan.md
    git commit -qm "local overmind plan"
    git checkout master >/dev/null
  )
}

push_local_overmind() {
  local repo_dir="$1"
  (
    cd "$repo_dir"
    git checkout overmind >/dev/null
    git push -u origin overmind >/dev/null
    git checkout master >/dev/null
  )
}

add_master_worker_id_file() {
  local repo_dir="$1"
  local worker_id="$2"
  (
    cd "$repo_dir"
    printf '%s\n' "$worker_id" > "ai/${worker_id}_dont_touch.txt"
    git add "ai/${worker_id}_dont_touch.txt"
    git commit -qm "add worker id"
  )
}

test_assigned_step_selection_uses_worker_uuid_and_switches_to_overmind() {
  local repo_dir="$TMP_ROOT/repo-assigned-selection"
  local worker_id="11111111-1111-1111-1111-111111111111"
  local other_id="22222222-2222-2222-2222-222222222222"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  setup_remote_with_master "$repo_dir"

  create_local_overmind_plan "$repo_dir" "### Step 1.1 Wrong worker
#### Assigned: $other_id
- [ ] Plan and discuss the step (SP=1)

### Step 2.2 Correct worker
#### Assigned: $worker_id
- [ ] Plan and discuss the step (SP=1)
"
  push_local_overmind "$repo_dir"
  add_master_worker_id_file "$repo_dir" "$worker_id"

  local out
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --debug --dry-run 2>&1)"

  assert_contains "$out" "dry-run log: ai/logs/repo-assigned-selection-design-2-2-log"
  assert_not_contains "$out" "design-1-1-log"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
}

test_fails_when_local_overmind_branch_missing() {
  local repo_dir="$TMP_ROOT/repo-local-overmind-missing"
  local worker_id="33333333-3333-3333-3333-333333333333"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  setup_remote_with_master "$repo_dir"

  # Create remote overmind branch and then remove local overmind branch.
  create_local_overmind_plan "$repo_dir" "### Step 1.1 Demo
#### Assigned: $worker_id
- [ ] Plan and discuss the step (SP=1)
"
  push_local_overmind "$repo_dir"
  (
    cd "$repo_dir"
    git branch -D overmind >/dev/null
  )
  add_master_worker_id_file "$repo_dir" "$worker_id"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Step selection requires local Git branch 'overmind'."
}

test_fails_when_remote_overmind_branch_missing() {
  local repo_dir="$TMP_ROOT/repo-remote-overmind-missing"
  local worker_id="44444444-4444-4444-4444-444444444444"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  setup_remote_with_master "$repo_dir"

  create_local_overmind_plan "$repo_dir" "### Step 1.1 Demo
#### Assigned: $worker_id
- [ ] Plan and discuss the step (SP=1)
"
  add_master_worker_id_file "$repo_dir" "$worker_id"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Step selection requires remote Git branch 'origin/overmind'."
}

test_fails_when_remote_sync_ff_only_fails() {
  local repo_dir="$TMP_ROOT/repo-sync-failure"
  local worker_id="55555555-5555-5555-5555-555555555555"
  local clone_dir="$TMP_ROOT/repo-sync-failure-clone"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  setup_remote_with_master "$repo_dir"

  create_local_overmind_plan "$repo_dir" "### Step 1.1 Demo
#### Assigned: $worker_id
- [ ] Plan and discuss the step (SP=1)
"
  push_local_overmind "$repo_dir"
  add_master_worker_id_file "$repo_dir" "$worker_id"

  # Make local overmind diverge.
  (
    cd "$repo_dir"
    git checkout overmind >/dev/null
    echo "# local divergence" >> overmind/implementation_plan.md
    git add overmind/implementation_plan.md
    git commit -qm "local divergence"
    git checkout master >/dev/null
  )

  # Make remote overmind diverge via a second clone.
  git clone -q "$repo_dir/remote.git" "$clone_dir"
  (
    cd "$clone_dir"
    git config user.name "Test User"
    git config user.email "test@example.com"
    git checkout -q overmind
    echo "# remote divergence" >> overmind/implementation_plan.md
    git add overmind/implementation_plan.md
    git commit -qm "remote divergence"
    git push -q origin overmind
  )

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Failed to sync local Git branch 'overmind' from 'origin/overmind'."
}

test_fails_when_worker_id_file_missing() {
  local repo_dir="$TMP_ROOT/repo-worker-id-missing"
  local worker_id="66666666-6666-6666-6666-666666666666"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  setup_remote_with_master "$repo_dir"

  create_local_overmind_plan "$repo_dir" "### Step 1.1 Demo
#### Assigned: $worker_id
- [ ] Plan and discuss the step (SP=1)
"
  push_local_overmind "$repo_dir"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "No worker identity file found matching ai/*_dont_touch.txt."
}

test_fails_when_no_steps_assigned_to_worker() {
  local repo_dir="$TMP_ROOT/repo-no-assigned-steps"
  local worker_id="77777777-7777-7777-7777-777777777777"
  local other_id="88888888-8888-8888-8888-888888888888"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  setup_remote_with_master "$repo_dir"

  create_local_overmind_plan "$repo_dir" "### Step 1.1 Demo
#### Assigned: $other_id
- [ ] Plan and discuss the step (SP=1)
"
  push_local_overmind "$repo_dir"
  add_master_worker_id_file "$repo_dir" "$worker_id"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "No steps in overmind/implementation_plan.md are assigned to worker UUID '$worker_id'."
}

test_assigned_steps_without_free_bullets_reports_no_work() {
  local repo_dir="$TMP_ROOT/repo-assigned-no-free-bullets"
  local worker_id="99999999-9999-9999-9999-999999999999"
  mkdir -p "$repo_dir"
  setup_repo "$repo_dir"
  setup_remote_with_master "$repo_dir"

  create_local_overmind_plan "$repo_dir" "### Step 1.1 Demo
#### Assigned: $worker_id
- [x] Plan and discuss the step (SP=1)
"
  push_local_overmind "$repo_dir"
  add_master_worker_id_file "$repo_dir" "$worker_id"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "No free unchecked bullets remain for worker UUID '$worker_id' in overmind/implementation_plan.md."
}

test_assigned_step_selection_uses_worker_uuid_and_switches_to_overmind
test_fails_when_local_overmind_branch_missing
test_fails_when_remote_overmind_branch_missing
test_fails_when_remote_sync_ff_only_fails
test_fails_when_worker_id_file_missing
test_fails_when_no_steps_assigned_to_worker
test_assigned_steps_without_free_bullets_reports_no_work

echo "All orchestrator assignment tests passed."
