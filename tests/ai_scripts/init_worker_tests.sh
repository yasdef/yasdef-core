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

assert_nonzero_status() {
  local status="$1"
  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: expected non-zero status" >&2
    exit 1
  fi
}

setup_worker_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/ai/scripts"
  cp "$INIT_WORKER_SRC" "$repo_dir/ai/scripts/init_worker.sh"
  chmod +x "$repo_dir/ai/scripts/init_worker.sh"

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

resolved_path() {
  local path="$1"
  (cd "$path" && pwd -P)
}

binding_file_content_from_branch() {
  local repo_dir="$1"
  local branch="$2"
  git -C "$repo_dir" show "${branch}:ai/project_overmind.yaml" 2>/dev/null || true
}

assert_branch_exists() {
  local repo_dir="$1"
  local branch="$2"
  if ! git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "Assertion failed: expected branch to exist: $branch" >&2
    exit 1
  fi
}

assert_no_legacy_identity_files() {
  local repo_dir="$1"
  local count="0"
  count="$(find "$repo_dir/ai" -maxdepth 1 -type f -name '*_dont_touch.txt' | wc -l | tr -d '[:space:]')"
  assert_equal "0" "$count"
}

run_init_worker() {
  local repo_dir="$1"
  local worker_uuid="$2"
  local overmind_path="$3"

  printf '%s\n%s\n' "$worker_uuid" "$overmind_path" | (
    cd "$repo_dir"
    ai/scripts/init_worker.sh
  )
}

test_init_worker_success_creates_project_overmind_binding() {
  local repo_dir="$TMP_ROOT/repo-success"
  local overmind_dir="$TMP_ROOT/overmind-success"
  local worker_uuid="11111111-1111-1111-1111-111111111111"
  local out=""
  local expected=""
  local overmind_resolved=""

  mkdir -p "$repo_dir" "$overmind_dir/project-alpha"
  setup_worker_repo "$repo_dir"

  cat >"$overmind_dir/project-alpha/workers.yaml" <<EOF
version: 1
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF

  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$overmind_dir" 2>&1)"
  assert_contains "$out" "Worker init complete."
  assert_contains "$out" "Binding file: ai/project_overmind.yaml"
  assert_contains "$out" "Worker UUID: $worker_uuid"
  assert_contains "$out" "Worker class: platform"
  assert_contains "$out" "Worker status: ready"
  assert_contains "$out" "Overmind binding commit:"
  assert_contains "$out" "Current branch: overmind"
  assert_contains "$out" "you are in overmind branch now, if you need this changes in main/master you can merge it manually"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
  assert_branch_exists "$repo_dir" "overmind"

  overmind_resolved="$(resolved_path "$overmind_dir")"
  expected="$(cat <<EOF
overmind_source_path: '$overmind_resolved'
worker_uuid: '$worker_uuid'
class: 'platform'
status: 'ready'
EOF
)"
  assert_equal "$expected" "$(binding_file_content_from_branch "$repo_dir" "overmind")"
  assert_no_legacy_identity_files "$repo_dir"
}

test_init_worker_fails_when_overmind_path_missing() {
  local repo_dir="$TMP_ROOT/repo-missing-path"
  local missing_path="$TMP_ROOT/does-not-exist-overmind"
  local worker_uuid="22222222-2222-2222-2222-222222222222"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"

  set +e
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$missing_path" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Overmind repo path not found"
  assert_equal "master" "$(git -C "$repo_dir" branch --show-current)"
}

test_init_worker_fails_when_workers_yaml_missing() {
  local repo_dir="$TMP_ROOT/repo-missing-workers"
  local overmind_dir="$TMP_ROOT/overmind-missing-workers"
  local worker_uuid="33333333-3333-3333-3333-333333333333"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$overmind_dir"
  setup_worker_repo "$repo_dir"

  set +e
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$overmind_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "No project workers.yaml files found under overmind source"
}

test_init_worker_fails_when_uuid_not_registered() {
  local repo_dir="$TMP_ROOT/repo-unknown-uuid"
  local overmind_dir="$TMP_ROOT/overmind-unknown-uuid"
  local worker_uuid="44444444-4444-4444-4444-444444444444"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$overmind_dir/project-one"
  setup_worker_repo "$repo_dir"

  cat >"$overmind_dir/project-one/workers.yaml" <<'EOF'
workers:
  - uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    class: "platform"
    status: "ready"
EOF

  set +e
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$overmind_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "No registered worker found for UUID '$worker_uuid'"
}

test_init_worker_fails_when_uuid_duplicate() {
  local repo_dir="$TMP_ROOT/repo-duplicate-uuid"
  local overmind_dir="$TMP_ROOT/overmind-duplicate-uuid"
  local worker_uuid="55555555-5555-5555-5555-555555555555"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$overmind_dir/project-a" "$overmind_dir/project-b"
  setup_worker_repo "$repo_dir"

  cat >"$overmind_dir/project-a/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF
  cat >"$overmind_dir/project-b/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "backend"
    status: "active"
EOF

  set +e
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$overmind_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "resolved to multiple registrations"
}

test_init_worker_is_deterministic_and_refreshes_metadata() {
  local repo_dir="$TMP_ROOT/repo-deterministic"
  local overmind_dir="$TMP_ROOT/overmind-deterministic"
  local worker_uuid="66666666-6666-6666-6666-666666666666"
  local first=""
  local second=""
  local third=""
  local out_second=""
  local overmind_head_before=""
  local overmind_head_after=""

  mkdir -p "$repo_dir" "$overmind_dir/project-z"
  setup_worker_repo "$repo_dir"

  cat >"$overmind_dir/project-z/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF

  run_init_worker "$repo_dir" "$worker_uuid" "$overmind_dir" >/dev/null
  first="$(binding_file_content_from_branch "$repo_dir" "overmind")"
  overmind_head_before="$(git -C "$repo_dir" rev-parse overmind)"

  out_second="$(run_init_worker "$repo_dir" "$worker_uuid" "$overmind_dir" 2>&1)"
  second="$(binding_file_content_from_branch "$repo_dir" "overmind")"
  overmind_head_after="$(git -C "$repo_dir" rev-parse overmind)"
  assert_equal "$first" "$second"
  assert_equal "$overmind_head_before" "$overmind_head_after"
  assert_contains "$out_second" "Overmind binding commit: none (already up to date)"

  cat >"$overmind_dir/project-z/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "backend"
    status: "paused"
EOF

  run_init_worker "$repo_dir" "$worker_uuid" "$overmind_dir" >/dev/null
  third="$(binding_file_content_from_branch "$repo_dir" "overmind")"
  assert_contains "$third" "class: 'backend'"
  assert_contains "$third" "status: 'paused'"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"

  assert_no_legacy_identity_files "$repo_dir"
}

test_init_worker_fails_when_registry_data_unusable() {
  local repo_dir="$TMP_ROOT/repo-unusable-registry"
  local overmind_dir="$TMP_ROOT/overmind-unusable-registry"
  local worker_uuid="77777777-7777-7777-7777-777777777777"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$overmind_dir/project-m"
  setup_worker_repo "$repo_dir"

  cat >"$overmind_dir/project-m/workers.yaml" <<'EOF'
version: 1
items:
  - uuid: "77777777-7777-7777-7777-777777777777"
    class: "platform"
    status: "ready"
EOF

  set +e
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$overmind_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "missing 'workers:' key"
}

test_init_worker_success_creates_project_overmind_binding
test_init_worker_fails_when_overmind_path_missing
test_init_worker_fails_when_workers_yaml_missing
test_init_worker_fails_when_uuid_not_registered
test_init_worker_fails_when_uuid_duplicate
test_init_worker_is_deterministic_and_refreshes_metadata
test_init_worker_fails_when_registry_data_unusable

echo "All init worker script tests passed."
