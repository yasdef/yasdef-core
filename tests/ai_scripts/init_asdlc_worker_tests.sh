#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INIT_RUNTIME_SRC="$SOURCE_ROOT/ai/scripts/init_asdlc_worker.sh"

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

assert_equal() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed: expected '$expected', got '$actual'" >&2
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

assert_dir_exists() {
  local path="$1"
  if [[ ! -d "$path" ]]; then
    echo "Assertion failed: expected directory to exist: $path" >&2
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

assert_line_count() {
  local expected="$1"
  local pattern="$2"
  local file="$3"
  local actual
  actual="$(grep -Fxc "$pattern" "$file" || true)"
  assert_equal "$expected" "$actual"
}

assert_file_tracked_at_head() {
  local repo_dir="$1"
  local path="$2"
  if ! git -C "$repo_dir" ls-tree -r --name-only HEAD | grep -Fxq "$path"; then
    echo "Assertion failed: expected HEAD to track file: $path" >&2
    exit 1
  fi
}

assert_git_status_clean() {
  local repo_dir="$1"
  local status=""
  status="$(git -C "$repo_dir" status --porcelain --untracked-files=all)"
  if [[ -n "$status" ]]; then
    echo "Assertion failed: expected clean git status in $repo_dir" >&2
    echo "$status" >&2
    exit 1
  fi
}

resolved_path() {
  local path="$1"
  (cd "$path" && pwd -P)
}

run_init_runtime() {
  local target_path="$1"
  printf '%s\n' "$target_path" | \
    GIT_AUTHOR_NAME="Test User" \
    GIT_AUTHOR_EMAIL="test@example.com" \
    GIT_COMMITTER_NAME="Test User" \
    GIT_COMMITTER_EMAIL="test@example.com" \
    "$INIT_RUNTIME_SRC"
}

seed_repo() {
  local repo_dir="$1"
  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "seed" >README.md
    git add README.md
    git commit -qm "seed"
  )
}

test_init_fails_when_target_missing() {
  local missing_dir="$TMP_ROOT/missing-repo"
  local out=""
  local status=0

  set +e
  out="$(run_init_runtime "$missing_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Target repository path does not exist"
}

test_init_fails_when_target_is_not_directory() {
  local file_path="$TMP_ROOT/not-a-dir.txt"
  local out=""
  local status=0

  echo "demo" >"$file_path"

  set +e
  out="$(run_init_runtime "$file_path" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Target repository path is not a directory"
}

test_init_fails_when_target_is_nested_inside_git_repo() {
  local repo_dir="$TMP_ROOT/parent-repo"
  local nested_dir="$repo_dir/nested/child"
  local out=""
  local status=0

  mkdir -p "$nested_dir"
  seed_repo "$repo_dir"

  set +e
  out="$(run_init_runtime "$nested_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "must be the git repository root"
}

test_init_bootstraps_existing_git_root() {
  local repo_dir="$TMP_ROOT/existing-git-repo"
  local runtime_dir="$repo_dir/.asdlc_worker"
  local out=""
  local repo_resolved=""

  mkdir -p "$repo_dir"
  seed_repo "$repo_dir"

  out="$(run_init_runtime "$repo_dir" 2>&1)"
  assert_contains "$out" "ASDLC worker runtime install complete."
  assert_contains "$out" "Registration command: .asdlc_worker/scripts/register_worker.sh"

  repo_resolved="$(resolved_path "$repo_dir")"
  assert_dir_exists "$runtime_dir/scripts"
  assert_dir_exists "$runtime_dir/golden_examples"
  assert_dir_exists "$runtime_dir/templates"
  assert_dir_exists "$runtime_dir/logs"
  assert_dir_exists "$runtime_dir/prompts"
  assert_dir_exists "$runtime_dir/overmind"
  assert_file_exists "$runtime_dir/scripts/register_worker.sh"
  assert_file_exists "$runtime_dir/scripts/helpers/runtime_layout.sh"
  assert_file_exists "$runtime_dir/AI_DEVELOPMENT_PROCESS.md"
  assert_file_exists "$runtime_dir/asdlc_worker.yaml"
  assert_contains "$(cat "$runtime_dir/asdlc_worker.yaml")" "worker_repo_root: '$repo_resolved'"
  assert_line_count "1" ".asdlc_worker/scripts" "$repo_dir/.git/info/exclude"
  assert_line_count "1" ".asdlc_worker/AI_DEVELOPMENT_PROCESS.md" "$repo_dir/.git/info/exclude"
  assert_file_tracked_at_head "$repo_dir" ".asdlc_worker/asdlc_worker.yaml"
  assert_file_tracked_at_head "$repo_dir" ".asdlc_worker/blocker_log.md"
  assert_file_tracked_at_head "$repo_dir" ".asdlc_worker/decisions.md"
  assert_file_tracked_at_head "$repo_dir" ".asdlc_worker/history.md"
  assert_file_tracked_at_head "$repo_dir" ".asdlc_worker/open_questions.md"
  assert_file_tracked_at_head "$repo_dir" ".asdlc_worker/user_review.md"
  assert_equal "asdlc worker added" "$(git -C "$repo_dir" log -1 --pretty=%s)"
  assert_git_status_clean "$repo_dir"
}

test_init_git_inits_repo_when_missing() {
  local repo_dir="$TMP_ROOT/no-git-repo"
  local out=""

  mkdir -p "$repo_dir"
  out="$(run_init_runtime "$repo_dir" 2>&1)"

  assert_contains "$out" "ASDLC worker runtime install complete."
  assert_equal "true" "$(git -C "$repo_dir" rev-parse --is-inside-work-tree 2>/dev/null)"
  assert_dir_exists "$repo_dir/.git"
  assert_file_tracked_at_head "$repo_dir" ".asdlc_worker/asdlc_worker.yaml"
}

test_update_preserves_local_state_and_is_idempotent() {
  local repo_dir="$TMP_ROOT/update-repo"
  local runtime_dir="$repo_dir/.asdlc_worker"
  local custom_file="$runtime_dir/custom-local-state.txt"
  local old_process_marker="stale process"
  local out=""

  mkdir -p "$repo_dir"
  seed_repo "$repo_dir"
  run_init_runtime "$repo_dir" >/dev/null

  echo "keep me" >"$custom_file"
  echo "$old_process_marker" >"$runtime_dir/AI_DEVELOPMENT_PROCESS.md"
  mkdir -p "$runtime_dir/logs"
  echo "stale log" >"$runtime_dir/logs/old.log"

  out="$(run_init_runtime "$repo_dir" 2>&1)"
  assert_contains "$out" "ASDLC worker runtime update complete."
  assert_file_exists "$custom_file"
  assert_contains "$(cat "$custom_file")" "keep me"
  if grep -Fq "$old_process_marker" "$runtime_dir/AI_DEVELOPMENT_PROCESS.md"; then
    echo "Assertion failed: expected updated AI_DEVELOPMENT_PROCESS.md to overwrite stale content" >&2
    exit 1
  fi
  if [[ -e "$runtime_dir/logs/old.log" ]]; then
    echo "Assertion failed: expected generated logs directory to be overwritten during update" >&2
    exit 1
  fi
  assert_line_count "1" ".asdlc_worker/scripts" "$repo_dir/.git/info/exclude"
  assert_line_count "1" ".asdlc_worker/scripts/helpers" "$repo_dir/.git/info/exclude"
}

test_init_stashes_unrelated_changes_after_install_commit() {
  local repo_dir="$TMP_ROOT/repo-dirty-before-init"
  local out=""
  local stash_list=""

  mkdir -p "$repo_dir"
  seed_repo "$repo_dir"
  echo "dirty" >>"$repo_dir/README.md"
  echo "local note" >"$repo_dir/local-note.txt"

  out="$(run_init_runtime "$repo_dir" 2>&1)"
  assert_contains "$out" "ASDLC worker runtime install complete."
  assert_contains "$out" "Stashed unrelated worktree changes: asdlc worker init unrelated changes"
  assert_equal "asdlc worker added" "$(git -C "$repo_dir" log -1 --pretty=%s)"
  assert_file_tracked_at_head "$repo_dir" ".asdlc_worker/asdlc_worker.yaml"
  assert_git_status_clean "$repo_dir"

  stash_list="$(git -C "$repo_dir" stash list)"
  assert_contains "$stash_list" "asdlc worker init unrelated changes"
}

test_init_fails_when_target_input_is_empty() {
  local out=""
  local status=0

  set +e
  out="$(printf '\n' | "$INIT_RUNTIME_SRC" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Input cannot be empty."
}

test_init_fails_when_target_missing
test_init_fails_when_target_is_not_directory
test_init_fails_when_target_is_nested_inside_git_repo
test_init_bootstraps_existing_git_root
test_init_git_inits_repo_when_missing
test_update_preserves_local_state_and_is_idempotent
test_init_stashes_unrelated_changes_after_install_commit
test_init_fails_when_target_input_is_empty

echo "init_asdlc_worker_tests: PASS"
