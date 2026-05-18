#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORCH_SRC="$SOURCE_ROOT/ai/scripts/orchestrator.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"

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

assert_file_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "Assertion failed: expected file $file to contain: $needle" >&2
    echo "Actual file content:" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_file_not_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "Assertion failed: expected file to be absent: $path" >&2
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

assert_order() {
  local haystack="$1"
  local first="$2"
  local second="$3"
  local third="${4:-}"
  local remaining="$haystack"
  local part=""

  for part in "$first" "$second" "$third"; do
    [[ -n "$part" ]] || continue
    case "$remaining" in
      *"$part"*)
        remaining="${remaining#*"$part"}"
        ;;
      *)
        echo "Assertion failed: expected ordered output to contain: $part" >&2
        echo "Actual output:" >&2
        echo "$haystack" >&2
        exit 1
        ;;
    esac
  done
}

setup_worker_repo() {
  local repo_dir="$1"
  local ai_audit_body="${2:-echo \"ai_audit\"}"
  local post_review_body="${3:-echo \"post_review\"}"

  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/setup" \
    "$repo_dir/.asdlc_worker/step_plans" "$repo_dir/.asdlc_worker/step_review_results" \
    "$repo_dir/.asdlc_worker/overmind"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"

  cp "$ORCH_SRC" "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  chmod +x "$repo_dir/.asdlc_worker/scripts/orchestrator.sh"

  cat >"$repo_dir/.asdlc_worker/scripts/ai_design.sh" <<'EOF'
#!/usr/bin/env bash
echo "design"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_plan.sh" <<'EOF'
#!/usr/bin/env bash
echo "planning"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_implementation.sh" <<'EOF'
#!/usr/bin/env bash
echo "implementation"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_user_review.sh" <<'EOF'
#!/usr/bin/env bash
echo "user_review"
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/ai_audit.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$ai_audit_body
EOF
  cat >"$repo_dir/.asdlc_worker/scripts/post_review.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$post_review_body
EOF
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_design.sh" "$repo_dir/.asdlc_worker/scripts/ai_plan.sh" \
    "$repo_dir/.asdlc_worker/scripts/ai_implementation.sh" "$repo_dir/.asdlc_worker/scripts/ai_user_review.sh" \
    "$repo_dir/.asdlc_worker/scripts/ai_audit.sh" "$repo_dir/.asdlc_worker/scripts/post_review.sh"

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
ai_audit | echo | mock-model
EOF
  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-feature-a.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [x] 1. demo
## Functional Requirements (translated from design EARS)
- [x] FR-1.1-001 Demo requirement.
EOF
  cat >"$repo_dir/ai/step_review_results/review_result-1.1-feature-a.md" <<'EOF'
# Review Result: Step 1.1
## Disposition (per issue)
- None.
EOF

  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "seed" >README.md
    git add README.md .asdlc_worker ai overmind
    git commit -qm "seed"
  )
}

init_project_repo() {
  local source_dir="$1"
  local project_id="$2"
  local worker_uuid="$3"
  local remote_dir="${source_dir}-remote.git"

  mkdir -p "$source_dir"
  (
    cd "$source_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
  )
  cat >"$source_dir/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF
  cat >"$source_dir/init_progress_definition.yaml" <<EOF
meta_info:
  project_id: '$project_id'
steps: []
EOF
  (
    cd "$source_dir"
    git add workers.yaml init_progress_definition.yaml
    git commit -qm "init project repo"
    git init -q --bare "$remote_dir"
    git --git-dir "$remote_dir" symbolic-ref HEAD refs/heads/master
    git remote add origin "$remote_dir"
    git push -q -u origin master
  )
}

commit_project_repo_changes() {
  local source_dir="$1"
  local message="$2"
  (
    cd "$source_dir"
    git add -A
    git commit -qm "$message"
    git push -q
  )
}

create_feature() {
  local source_dir="$1"
  local feature_id="$2"
  local plan_content="$3"

  mkdir -p "$source_dir/$feature_id"
  cat >"$source_dir/$feature_id/implementation_plan.md" <<EOF
$plan_content
EOF
  cat >"$source_dir/$feature_id/requirements_ears.md" <<'EOF'
### Requirement 1 Demo
- The system SHALL support demo behavior.
EOF
  commit_project_repo_changes "$source_dir" "add feature $feature_id"
}

write_binding() {
  local repo_dir="$1"
  local source_dir="$2"
  local project_id="$3"
  local worker_uuid="$4"

  cat >"$repo_dir/ai/project_overmind.yaml" <<EOF
overmind_source_path: '$source_dir'
project_id: '$project_id'
worker_uuid: '$worker_uuid'
class: 'platform'
status: 'ready'
EOF
}

clone_remote_editor() {
  local source_dir="$1"
  local editor_dir="$2"
  git clone -q "${source_dir}-remote.git" "$editor_dir"
  git -C "$editor_dir" config user.name "Remote Editor"
  git -C "$editor_dir" config user.email "remote@example.com"
}

run_orchestrator_with_tty_input() {
  local repo_dir="$1"
  local input_text="$2"
  local expect_script="$TMP_ROOT/orchestrator-expect-$$.tcl"
  shift 2
  cat >"$expect_script" <<EOF
log_user 1
set timeout 5
set responses [split [string trim \$env(EXPECT_INPUT)] "\n"]
set idx 0
proc send_next {} {
  global responses idx
  if {\$idx >= [llength \$responses]} {
    return
  }
  send -- "[lindex \$responses \$idx]\r"
  incr idx
}
cd "$repo_dir"
spawn .asdlc_worker/scripts/orchestrator.sh $(printf ' %q' "$@")
expect {
  timeout { puts "expect timeout after 5s"; exit 124 }
  -re {Proceed\\? \\[y/n\\] $} {
    send_next
    exp_continue
  }
  -re {Choose 1 or 2: $} {
    send_next
    exp_continue
  }
  eof
}
catch wait result
exit [lindex \$result 3]
EOF
  EXPECT_INPUT="$input_text" expect "$expect_script" 2>&1
}

test_inbound_pull_rebase_happens_before_feature_discovery() {
  local repo_dir="$TMP_ROOT/repo-inbound-refresh"
  local source_dir="$TMP_ROOT/source-inbound-refresh"
  local editor_dir="$TMP_ROOT/editor-inbound-refresh"
  local project_id="project-inbound-refresh"
  local worker_uuid="10000000-0000-0000-0000-000000000001"
  local other_uuid="20000000-0000-0000-0000-000000000002"
  local out=""

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Remote-assigned step
#### Assigned: $other_uuid
- [ ] Plan and discuss the step (SP=1)
"
  clone_remote_editor "$source_dir" "$editor_dir"
  cat >"$editor_dir/feature-a/implementation_plan.md" <<EOF
### Step 1.1 Remote-assigned step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
EOF
  (
    cd "$editor_dir"
    git add feature-a/implementation_plan.md
    git commit -qm "assign feature to worker"
    git push -q
  )
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
  assert_contains "$out" "selected feature 'feature-a' (mode=auto_single, project=$project_id, step=1.1)."
  assert_file_contains "$source_dir/feature-a/implementation_plan.md" "$worker_uuid"
  assert_file_not_exists "$repo_dir/.asdlc_worker/overmind/implementation_plan.md"
}

test_inbound_pull_rebase_failure_exits_before_mirror() {
  local repo_dir="$TMP_ROOT/repo-inbound-failure"
  local source_dir="$TMP_ROOT/source-inbound-failure"
  local editor_dir="$TMP_ROOT/editor-inbound-failure"
  local project_id="project-inbound-failure"
  local worker_uuid="10000000-0000-0000-0000-000000000003"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Local step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  clone_remote_editor "$source_dir" "$editor_dir"
  cat >"$editor_dir/feature-a/implementation_plan.md" <<EOF
### Step 1.1 Remote step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
EOF
  (
    cd "$editor_dir"
    git add feature-a/implementation_plan.md
    git commit -qm "remote change"
    git push -q
  )
  printf '\n# local-dirty-change\n' >>"$source_dir/feature-a/implementation_plan.md"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Bound-source plan is dirty: $source_dir/feature-a/implementation_plan.md"
  assert_contains "$out" "git -C '$source_dir'"
  assert_file_not_exists "$repo_dir/.asdlc_worker/feature_meta_sync.yaml"
  assert_file_not_exists "$repo_dir/.asdlc_worker/feature_sync.yaml"
}

test_outbound_sync_runs_before_post_review_and_pushes_plan() {
  local repo_dir="$TMP_ROOT/repo-outbound-success"
  local source_dir="$TMP_ROOT/source-outbound-success"
  local project_id="project-outbound-success"
  local worker_uuid="10000000-0000-0000-0000-000000000004"
  local out=""

  mkdir -p "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Sync step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  setup_worker_repo "$repo_dir" "echo \"ai_audit\"; printf '\n# synced-after-ai-audit\n' >> '$source_dir/feature-a/implementation_plan.md'" "echo \"post_review\""
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh 2>&1)"
  assert_contains "$out" "orchestrator: work for step '1.1' is finished, the implementation plan is updated, and orchestrator is trying to sync it with the global implementation plan."
  assert_order "$out" "ai_audit" "orchestrator: work for step '1.1' is finished" "post_review"
  assert_file_contains "$source_dir/feature-a/implementation_plan.md" "# synced-after-ai-audit"
  assert_contains "$(git -C "$source_dir" show origin/master:feature-a/implementation_plan.md)" "# synced-after-ai-audit"
  assert_file_not_exists "$repo_dir/.asdlc_worker/overmind/implementation_plan.md"
}

test_outbound_staging_failure_stops_before_post_review_noninteractive() {
  local repo_dir="$TMP_ROOT/repo-outbound-staging-failure"
  local source_dir="$TMP_ROOT/source-outbound-staging-failure"
  local project_id="project-outbound-staging-failure"
  local worker_uuid="10000000-0000-0000-0000-000000000005"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Staging failure step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  setup_worker_repo "$repo_dir" "echo \"ai_audit\"; printf '\n# staging-failure\n' >> '$source_dir/feature-a/implementation_plan.md'; chmod 0444 '$source_dir/.git'" "echo \"post_review\""
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh 2>&1)"
  status=$?
  set -e
  chmod 0755 "$source_dir/.git" 2>/dev/null || true

  assert_nonzero_status "$status"
  assert_contains "$out" "Global implementation-plan sync failed while staging $source_dir/feature-a/implementation_plan.md"
  assert_contains "$out" "1. retry"
  assert_contains "$out" "2. finish"
  assert_contains "$out" "Global implementation-plan sync failed in a non-interactive shell."
  assert_not_contains "$out" "post_review"
}

test_outbound_commit_failure_stops_before_post_review_noninteractive() {
  local repo_dir="$TMP_ROOT/repo-outbound-commit-failure"
  local source_dir="$TMP_ROOT/source-outbound-commit-failure"
  local project_id="project-outbound-commit-failure"
  local worker_uuid="10000000-0000-0000-0000-000000000006"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Commit failure step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  setup_worker_repo "$repo_dir" "echo \"ai_audit\"; printf '\n# commit-failure\n' >> '$source_dir/feature-a/implementation_plan.md'" "echo \"post_review\""
  cat >"$source_dir/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "pre-commit rejected" >&2
exit 1
EOF
  chmod +x "$source_dir/.git/hooks/pre-commit"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Global implementation-plan sync failed while creating an ASDLC sync commit for $source_dir/feature-a/implementation_plan.md."
  assert_contains "$out" "1. retry"
  assert_contains "$out" "2. finish"
  assert_not_contains "$out" "post_review"
}

test_fails_before_step_when_bound_source_plan_is_dirty() {
  local repo_dir="$TMP_ROOT/repo-dirty-plan-sync"
  local source_dir="$TMP_ROOT/source-dirty-plan-sync"
  local project_id="project-dirty-plan-sync"
  local worker_uuid="10000000-0000-0000-0000-000000000011"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Pre-dirty step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  setup_worker_repo "$repo_dir" "echo \"ai_audit\"" "echo \"post_review\""
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  printf '\n# dirty-before-step\n' >>"$source_dir/feature-a/implementation_plan.md"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Bound-source plan is dirty: $source_dir/feature-a/implementation_plan.md"
  assert_contains "$out" "Commit, stash, or restore the plan before rerunning"
  assert_not_contains "$out" "ai_audit"
  assert_not_contains "$out" "post_review"
}

test_outbound_rebase_conflict_stops_before_post_review_noninteractive() {
  local repo_dir="$TMP_ROOT/repo-outbound-rebase-failure"
  local source_dir="$TMP_ROOT/source-outbound-rebase-failure"
  local editor_dir="$TMP_ROOT/editor-outbound-rebase-failure"
  local project_id="project-outbound-rebase-failure"
  local worker_uuid="10000000-0000-0000-0000-000000000007"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Base step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  clone_remote_editor "$source_dir" "$editor_dir"
  setup_worker_repo "$repo_dir" "echo \"ai_audit\"; cat > '$source_dir/feature-a/implementation_plan.md' <<'PLAN'
### Step 1.1 Worker version
#### Assigned: $worker_uuid
- [x] Plan and discuss the step (SP=1)
PLAN
cat > '$editor_dir/feature-a/implementation_plan.md' <<'PLAN'
### Step 1.1 Remote version
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
PLAN
(cd '$editor_dir' && git add feature-a/implementation_plan.md && git commit -qm 'remote conflicting change' && git push -q)" "echo \"post_review\""
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Global implementation-plan sync failed while rebasing the bound ASDLC project repo: $source_dir"
  assert_contains "$out" "Selected feature source plan: $source_dir/feature-a/implementation_plan.md"
  assert_contains "$out" "1. retry"
  assert_contains "$out" "2. finish"
  assert_not_contains "$out" "post_review"
}

test_outbound_push_failure_stops_before_post_review_noninteractive() {
  local repo_dir="$TMP_ROOT/repo-outbound-push-failure"
  local source_dir="$TMP_ROOT/source-outbound-push-failure"
  local remote_dir="${source_dir}-remote.git"
  local project_id="project-outbound-push-failure"
  local worker_uuid="10000000-0000-0000-0000-000000000008"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir" "echo \"ai_audit\"; printf '\n# push-failure\n' >> '$source_dir/feature-a/implementation_plan.md'" "echo \"post_review\""
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Push failure step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  cat >"$remote_dir/hooks/pre-receive" <<'EOF'
#!/usr/bin/env bash
echo "push rejected by remote hook" >&2
exit 1
EOF
  chmod +x "$remote_dir/hooks/pre-receive"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Global implementation-plan sync failed while pushing the ASDLC sync commit from $source_dir."
  assert_contains "$out" "The ASDLC plan sync commit exists locally but could not be pushed."
  assert_contains "$out" "1. retry"
  assert_contains "$out" "2. finish"
  assert_not_contains "$out" "post_review"
}

test_outbound_retry_repeats_sync_and_continues_to_post_review() {
  local repo_dir="$TMP_ROOT/repo-outbound-retry"
  local source_dir="$TMP_ROOT/source-outbound-retry"
  local project_id="project-outbound-retry"
  local worker_uuid="10000000-0000-0000-0000-000000000009"
  local out=""

  mkdir -p "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Retry step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  setup_worker_repo "$repo_dir" "echo \"ai_audit\"; printf '\n# retry-success\n' >> '$source_dir/feature-a/implementation_plan.md'" "echo \"post_review\""
  cat >"$source_dir/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
marker="$(git rev-parse --git-dir)/allow_commit_after_retry"
if [[ ! -f "$marker" ]]; then
  touch "$marker"
  echo "fail once" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$source_dir/.git/hooks/pre-commit"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
ai_audit | echo | mock-model
post_review | echo | mock-model
EOF

  out="$(run_orchestrator_with_tty_input "$repo_dir" $'y\n1\n')"
  assert_contains "$out" "Global implementation-plan sync failed while creating an ASDLC sync commit"
  assert_contains "$out" "Choose 1 or 2:"
  assert_contains "$out" "post_review"
  assert_file_contains "$source_dir/feature-a/implementation_plan.md" "# retry-success"
}

test_outbound_finish_skips_sync_and_continues_to_post_review() {
  local repo_dir="$TMP_ROOT/repo-outbound-finish"
  local source_dir="$TMP_ROOT/source-outbound-finish"
  local remote_dir="${source_dir}-remote.git"
  local project_id="project-outbound-finish"
  local worker_uuid="10000000-0000-0000-0000-000000000010"
  local out=""

  mkdir -p "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Finish step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  setup_worker_repo "$repo_dir" "echo \"ai_audit\"; printf '\n# finish-skip\n' >> '$source_dir/feature-a/implementation_plan.md'" "echo \"post_review\""
  cat >"$remote_dir/hooks/pre-receive" <<'EOF'
#!/usr/bin/env bash
echo "push rejected by remote hook" >&2
exit 1
EOF
  chmod +x "$remote_dir/hooks/pre-receive"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"
  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
ai_audit | echo | mock-model
post_review | echo | mock-model
EOF

  out="$(run_orchestrator_with_tty_input "$repo_dir" $'y\n2\n')"
  assert_contains "$out" "Global implementation-plan sync failed while pushing the ASDLC sync commit"
  assert_contains "$out" "orchestrator: skipping global implementation-plan sync for step '1.1' and continuing to post_review."
  assert_contains "$out" "post_review"
}

test_resume_succeeds_without_local_runtime_mirror_files() {
  local repo_dir="$TMP_ROOT/repo-resume-no-mirror-needed"
  local source_dir="$TMP_ROOT/source-resume-no-mirror-needed"
  local project_id="project-resume-no-mirror-needed"
  local worker_uuid="10000000-0000-0000-0000-000000000012"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"
  init_project_repo "$source_dir" "$project_id" "$worker_uuid"
  create_feature "$source_dir" "feature-a" "### Step 1.1 Resume step
#### Assigned: $worker_uuid
- [ ] Plan and discuss the step (SP=1)
"
  write_binding "$repo_dir" "$source_dir" "$project_id" "$worker_uuid"

  (cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --dry-run >/dev/null 2>&1)
  (
    cd "$repo_dir"
    git checkout -q -b non-overmind-branch
  )

  cat >"$repo_dir/ai/setup/models.md" <<'EOF'
design | echo | mock-model
planning | echo | mock-model
implementation | echo | mock-model
user_review | echo | mock-model
ai_audit | echo | mock-model
EOF

  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/orchestrator.sh --resume 1.1 --dry-run 2>&1)"
  status=$?
  set -e

  assert_equal "$status" "0"
  assert_not_contains "$out" "overmind/implementation_plan.md"
  assert_not_contains "$out" "overmind/reqirements_ears.md"
  assert_not_contains "$out" "Cannot resume on branch"
}

if [[ -n "${ONLY:-}" ]]; then
  "$ONLY"
else
  test_inbound_pull_rebase_happens_before_feature_discovery
  test_inbound_pull_rebase_failure_exits_before_mirror
  test_outbound_sync_runs_before_post_review_and_pushes_plan
  test_outbound_staging_failure_stops_before_post_review_noninteractive
  test_outbound_commit_failure_stops_before_post_review_noninteractive
  test_fails_before_step_when_bound_source_plan_is_dirty
  test_outbound_rebase_conflict_stops_before_post_review_noninteractive
  test_outbound_push_failure_stops_before_post_review_noninteractive
  test_outbound_retry_repeats_sync_and_continues_to_post_review
  test_outbound_finish_skips_sync_and_continues_to_post_review
  test_resume_succeeds_without_local_runtime_mirror_files
fi

echo "All orchestrator git sync tests passed."
