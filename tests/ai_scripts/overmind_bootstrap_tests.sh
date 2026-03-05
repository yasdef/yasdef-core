#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP_SRC="$SOURCE_ROOT/overmind/bootstrap_overmind.sh"

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

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Assertion failed: expected file to exist: $path" >&2
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

assert_nonzero_status() {
  local status="$1"
  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: expected non-zero status" >&2
    exit 1
  fi
}

setup_script() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/overmind"
  cp "$BOOTSTRAP_SRC" "$repo_dir/overmind/bootstrap_overmind.sh"
  chmod +x "$repo_dir/overmind/bootstrap_overmind.sh"
}

setup_git_repo() {
  local repo_dir="$1"
  setup_script "$repo_dir"
  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "seed" >README.md
    git add README.md
    git commit -qm "seed"
  )
}

setup_git_repo_with_origin() {
  local repo_dir="$1"
  setup_git_repo "$repo_dir"
  (
    cd "$repo_dir"
    git init --bare -q "$repo_dir/remote.git"
    git remote add origin "$repo_dir/remote.git"
  )
}

test_bootstrap_success_creates_branch_registry_and_upstream() {
  local repo_dir="$TMP_ROOT/repo-success"
  mkdir -p "$repo_dir"
  setup_git_repo_with_origin "$repo_dir"

  local out
  out="$(
    cd "$repo_dir" &&
    overmind/bootstrap_overmind.sh
  )"

  assert_contains "$out" "Overmind bootstrap complete."
  assert_contains "$out" "Branch: overmind"
  assert_contains "$out" "Registry: overmind/worker_registry.yaml"
  assert_contains "$out" "Remote: origin"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"

  local registry="$repo_dir/overmind/worker_registry.yaml"
  assert_file_exists "$registry"
  assert_contains "$(cat "$registry")" "version: 1"
  assert_contains "$(cat "$registry")" "workers: []"

  local upstream
  upstream="$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name @{u})"
  assert_equal "origin/overmind" "$upstream"

  if ! git --git-dir "$repo_dir/remote.git" show-ref --verify --quiet refs/heads/overmind; then
    echo "Assertion failed: expected remote branch refs/heads/overmind" >&2
    exit 1
  fi
}

test_bootstrap_success_preserves_existing_registry() {
  local repo_dir="$TMP_ROOT/repo-preserve"
  mkdir -p "$repo_dir"
  setup_git_repo_with_origin "$repo_dir"

  (
    cd "$repo_dir"
    git checkout -b overmind >/dev/null
    cat >overmind/worker_registry.yaml <<'EOF'
version: 99
generated_at: "manual"
description: "custom registry"
workers:
  - id: worker-1
EOF
    git add overmind/worker_registry.yaml
    git commit -qm "custom registry"
    git push -u origin overmind >/dev/null
    git checkout -b scratch >/dev/null
  )

  local before
  before="$(cat "$repo_dir/overmind/worker_registry.yaml")"
  local out
  out="$(
    cd "$repo_dir" &&
    overmind/bootstrap_overmind.sh
  )"
  local after
  after="$(cat "$repo_dir/overmind/worker_registry.yaml")"

  assert_equal "$before" "$after"
  assert_contains "$out" "Registry already exists: overmind/worker_registry.yaml (preserved)."
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
}

test_bootstrap_success_commits_and_pushes_existing_registry_changes() {
  local repo_dir="$TMP_ROOT/repo-update-existing"
  mkdir -p "$repo_dir"
  setup_git_repo_with_origin "$repo_dir"

  (
    cd "$repo_dir"
    git checkout -b overmind >/dev/null
    cat >overmind/worker_registry.yaml <<'EOF'
version: 1
generated_at: "manual"
description: "custom registry"
workers:
  - id: worker-1
EOF
    git add overmind/worker_registry.yaml
    git commit -qm "custom registry"
    git push -u origin overmind >/dev/null

    cat >overmind/worker_registry.yaml <<'EOF'
version: 1
generated_at: "manual"
description: "custom registry"
workers:
  - id: worker-1
  - id: worker-2
EOF
  )

  local out
  out="$(
    cd "$repo_dir" &&
    overmind/bootstrap_overmind.sh
  )"

  assert_contains "$out" "Overmind bootstrap complete."
  assert_contains "$out" "Registry already exists: overmind/worker_registry.yaml (preserved)."
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
  assert_equal "Update overmind worker registry" "$(git -C "$repo_dir" log -1 --pretty=%s)"

  local local_head
  local remote_head
  local_head="$(git -C "$repo_dir" rev-parse HEAD)"
  remote_head="$(git --git-dir "$repo_dir/remote.git" rev-parse refs/heads/overmind)"
  assert_equal "$local_head" "$remote_head"

  local remote_registry
  remote_registry="$(git --git-dir "$repo_dir/remote.git" show refs/heads/overmind:overmind/worker_registry.yaml)"
  assert_contains "$remote_registry" "- id: worker-2"
}

test_bootstrap_fails_outside_git_repo() {
  local dir="$TMP_ROOT/not-a-repo"
  mkdir -p "$dir"
  setup_script "$dir"

  local status=0
  local out=""
  set +e
  out="$(cd "$dir" && overmind/bootstrap_overmind.sh 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Not a git repository. Run this script inside a git repository."
}

test_bootstrap_help_prints_usage() {
  local dir="$TMP_ROOT/help-not-repo"
  mkdir -p "$dir"
  setup_script "$dir"

  local status=0
  local out=""
  set +e
  out="$(cd "$dir" && overmind/bootstrap_overmind.sh --help 2>&1)"
  status=$?
  set -e

  assert_equal "0" "$status"
  assert_contains "$out" "Usage: overmind/bootstrap_overmind.sh [--help]"
}

test_bootstrap_fails_when_no_remote() {
  local repo_dir="$TMP_ROOT/repo-no-remote"
  mkdir -p "$repo_dir"
  setup_git_repo "$repo_dir"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && overmind/bootstrap_overmind.sh 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "No git remote configured."
}

test_bootstrap_rejects_remote_flag() {
  local repo_dir="$TMP_ROOT/repo-remote-flag"
  mkdir -p "$repo_dir"
  setup_git_repo_with_origin "$repo_dir"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && overmind/bootstrap_overmind.sh --remote=origin 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Unknown argument: --remote=origin"
}

test_bootstrap_fails_for_unknown_argument() {
  local dir="$TMP_ROOT/repo-unknown-arg"
  mkdir -p "$dir"
  setup_script "$dir"

  local status=0
  local out=""
  set +e
  out="$(cd "$dir" && overmind/bootstrap_overmind.sh --wat 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Unknown argument: --wat"
}

test_bootstrap_surfaces_push_failure() {
  local repo_dir="$TMP_ROOT/repo-push-fail"
  mkdir -p "$repo_dir"
  setup_git_repo "$repo_dir"

  (
    cd "$repo_dir"
    git remote add origin "$repo_dir/nonexistent-remote.git"
  )

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && overmind/bootstrap_overmind.sh 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Failed to push branch 'overmind' to remote 'origin'."
}

test_bootstrap_success_creates_branch_registry_and_upstream
test_bootstrap_success_preserves_existing_registry
test_bootstrap_success_commits_and_pushes_existing_registry_changes
test_bootstrap_fails_outside_git_repo
test_bootstrap_help_prints_usage
test_bootstrap_fails_when_no_remote
test_bootstrap_rejects_remote_flag
test_bootstrap_fails_for_unknown_argument
test_bootstrap_surfaces_push_failure

echo "All overmind bootstrap tests passed."
