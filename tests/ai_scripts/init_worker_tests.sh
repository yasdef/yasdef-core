#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INIT_WORKER_SRC="$SOURCE_ROOT/ai/scripts/init_worker.sh"

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
  mkdir -p "$repo_dir/ai/scripts"
  cp "$INIT_WORKER_SRC" "$repo_dir/ai/scripts/init_worker.sh"
  chmod +x "$repo_dir/ai/scripts/init_worker.sh"
}

setup_git_repo() {
  local repo_dir="$1"
  setup_script "$repo_dir"
  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "seed" >README.md
    mkdir -p ai
    git add README.md ai
    git commit -qm "seed"
  )
}

setup_repo_with_origin_and_overmind() {
  local repo_dir="$1"
  setup_git_repo "$repo_dir"

  (
    cd "$repo_dir"
    git init --bare -q "$repo_dir/remote.git"
    git remote add origin "$repo_dir/remote.git"
    git push -u origin master >/dev/null

    git checkout -b overmind >/dev/null
    cat >worker_registry.yaml <<'EOF'
version: 1
generated_at: "2026-03-04T00:00:00Z"
description: "Local worker registry for Overmind git-based coordination."
workers: []
EOF
    git add worker_registry.yaml
    git commit -qm "bootstrap registry"
    git push -u origin overmind >/dev/null
    git checkout master >/dev/null
  )
}

find_worker_id_file() {
  local repo_dir="$1"
  find "$repo_dir/ai" -maxdepth 1 -type f -name '*dont_change_or_remove*' | sort | head -n 1
}

worker_id_from_overmind_branch() {
  local repo_dir="$1"
  git -C "$repo_dir" show overmind:ai/worker_id_dont_change_or_remove.txt 2>/dev/null | head -n 1 | tr -d '[:space:]'
}

count_registry_occurrences() {
  local content="$1"
  local worker_id="$2"
  grep -cE "^[[:space:]]*-[[:space:]]*${worker_id}[[:space:]]*$" <<<"$content" || true
}

test_init_worker_success_registers_and_returns_master() {
  local repo_dir="$TMP_ROOT/repo-success"
  mkdir -p "$repo_dir"
  setup_repo_with_origin_and_overmind "$repo_dir"

  local out
  out="$(
    cd "$repo_dir" &&
    ai/scripts/init_worker.sh
  )"

  assert_contains "$out" "Worker init complete."
  assert_contains "$out" "Committed local overmind changes:"
  assert_contains "$out" "Pushing local overmind commit to remote 'origin/overmind'..."
  assert_contains "$out" "Local overmind commit:"
  assert_equal "master" "$(git -C "$repo_dir" branch --show-current)"

  local worker_id
  worker_id="$(worker_id_from_overmind_branch "$repo_dir")"
  if [[ -z "$worker_id" ]]; then
    echo "Assertion failed: worker id is empty" >&2
    exit 1
  fi

  local remote_registry
  remote_registry="$(git --git-dir "$repo_dir/remote.git" show overmind:worker_registry.yaml)"
  assert_equal "1" "$(count_registry_occurrences "$remote_registry" "$worker_id")"

  local overmind_subject
  overmind_subject="$(git -C "$repo_dir" log overmind -1 --pretty=%s)"
  assert_contains "$overmind_subject" "Register worker "

  local worker_file
  worker_file="$(find_worker_id_file "$repo_dir")"
  if [[ -n "$worker_file" ]]; then
    echo "Assertion failed: worker id file should not exist on master working tree" >&2
    exit 1
  fi

  local status_short
  status_short="$(git -C "$repo_dir" status --short)"
  assert_not_contains "$status_short" "ai/worker_id_dont_change_or_remove.txt"
}

test_init_worker_fails_when_no_overmind_branch() {
  local repo_dir="$TMP_ROOT/repo-no-overmind"
  mkdir -p "$repo_dir"
  setup_git_repo "$repo_dir"

  (
    cd "$repo_dir"
    git init --bare -q "$repo_dir/remote.git"
    git remote add origin "$repo_dir/remote.git"
    git push -u origin master >/dev/null
  )

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/init_worker.sh 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "no orchestrator detected, unable to proceed"
  assert_equal "master" "$(git -C "$repo_dir" branch --show-current)"
}

test_init_worker_fails_when_no_remote() {
  local repo_dir="$TMP_ROOT/repo-no-remote"
  mkdir -p "$repo_dir"
  setup_git_repo "$repo_dir"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/init_worker.sh 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "No git remote configured."
}

test_init_worker_fails_outside_git_repo() {
  local dir="$TMP_ROOT/not-a-repo"
  mkdir -p "$dir"
  setup_script "$dir"

  local status=0
  local out=""
  set +e
  out="$(cd "$dir" && ai/scripts/init_worker.sh 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Not a git repository."
}

test_init_worker_is_idempotent() {
  local repo_dir="$TMP_ROOT/repo-idempotent"
  mkdir -p "$repo_dir"
  setup_repo_with_origin_and_overmind "$repo_dir"

  (
    cd "$repo_dir"
    ai/scripts/init_worker.sh >/dev/null
  )

  local worker_id_before
  worker_id_before="$(worker_id_from_overmind_branch "$repo_dir")"

  local out_second
  out_second="$(
    cd "$repo_dir" &&
    ai/scripts/init_worker.sh
  )"
  local worker_id_after
  worker_id_after="$(worker_id_from_overmind_branch "$repo_dir")"

  assert_equal "$worker_id_before" "$worker_id_after"
  assert_contains "$out_second" "Worker already registered in worker_registry.yaml."
  assert_contains "$out_second" "No local overmind commit needed; worker already registered."
  assert_contains "$out_second" "Local overmind commit: none (worker already registered)"
  assert_equal "master" "$(git -C "$repo_dir" branch --show-current)"

  local remote_registry
  remote_registry="$(git --git-dir "$repo_dir/remote.git" show overmind:worker_registry.yaml)"
  assert_equal "1" "$(count_registry_occurrences "$remote_registry" "$worker_id_after")"
}

test_init_worker_restores_master_on_push_failure() {
  local repo_dir="$TMP_ROOT/repo-push-failure"
  mkdir -p "$repo_dir"
  setup_repo_with_origin_and_overmind "$repo_dir"

  cat >"$repo_dir/remote.git/hooks/pre-receive" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$repo_dir/remote.git/hooks/pre-receive"

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/init_worker.sh 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Failed to push registration to remote 'origin'."
  assert_equal "master" "$(git -C "$repo_dir" branch --show-current)"
}

test_init_worker_success_registers_and_returns_master
test_init_worker_fails_when_no_overmind_branch
test_init_worker_fails_when_no_remote
test_init_worker_fails_outside_git_repo
test_init_worker_is_idempotent
test_init_worker_restores_master_on_push_failure

echo "All init worker script tests passed."
