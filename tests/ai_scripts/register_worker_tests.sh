#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTER_WORKER_SRC="$SOURCE_ROOT/ai/scripts/register_worker.sh"
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

resolved_path() {
  local path="$1"
  (cd "$path" && pwd -P)
}

setup_worker_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers"
  cp "$REGISTER_WORKER_SRC" "$repo_dir/.asdlc_worker/scripts/register_worker.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  chmod +x "$repo_dir/.asdlc_worker/scripts/register_worker.sh"

  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "seed" >README.md
    git add README.md .asdlc_worker
    git commit -qm "seed"
  )
}

run_register_worker() {
  local repo_dir="$1"
  local worker_uuid="$2"
  local project_path="$3"

  printf '%s\n%s\n' "$worker_uuid" "$project_path" | (
    cd "$repo_dir"
    .asdlc_worker/scripts/register_worker.sh
  )
}

write_project_repo() {
  local project_dir="$1"
  local project_id="$2"
  local worker_uuid="$3"
  local worker_class="${4:-platform}"
  local worker_status="${5:-ready}"

  mkdir -p "$project_dir"
  cat >"$project_dir/workers.yaml" <<EOF
version: 1
workers:
  - uuid: "$worker_uuid"
    class: "$worker_class"
    status: "$worker_status"
EOF
  cat >"$project_dir/init_progress_definition.yaml" <<EOF
meta_info:
  project_id: '$project_id'
steps: []
EOF
}

test_register_worker_success_writes_binding() {
  local repo_dir="$TMP_ROOT/repo-success"
  local project_dir="$TMP_ROOT/project-success"
  local worker_uuid="11111111-1111-1111-1111-111111111111"
  local project_id="project-alpha"
  local out=""
  local expected=""
  local project_resolved=""

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"
  write_project_repo "$project_dir" "$project_id" "$worker_uuid"

  out="$(run_register_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  assert_contains "$out" "Worker registration complete."
  assert_contains "$out" "Binding file: .asdlc_worker/project_overmind.yaml"
  assert_contains "$out" "Project ID: $project_id"
  assert_contains "$out" "Worker UUID: $worker_uuid"

  project_resolved="$(resolved_path "$project_dir")"
  expected="$(cat <<EOF
overmind_source_path: '$project_resolved'
project_id: '$project_id'
worker_uuid: '$worker_uuid'
class: 'platform'
status: 'ready'
EOF
)"
  assert_file_exists "$repo_dir/.asdlc_worker/project_overmind.yaml"
  assert_equal "$expected" "$(cat "$repo_dir/.asdlc_worker/project_overmind.yaml")"
}

test_register_worker_fails_when_project_path_missing() {
  local repo_dir="$TMP_ROOT/repo-missing-project"
  local missing_path="$TMP_ROOT/missing-project"
  local worker_uuid="22222222-2222-2222-2222-222222222222"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"

  set +e
  out="$(run_register_worker "$repo_dir" "$worker_uuid" "$missing_path" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Overmind repo path not found"
}

test_register_worker_fails_when_workers_yaml_missing() {
  local repo_dir="$TMP_ROOT/repo-missing-workers"
  local project_dir="$TMP_ROOT/project-missing-workers"
  local worker_uuid="33333333-3333-3333-3333-333333333333"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$project_dir"
  setup_worker_repo "$repo_dir"

  set +e
  out="$(run_register_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Project repo does not contain a root workers.yaml"
}

test_register_worker_fails_when_definition_missing() {
  local repo_dir="$TMP_ROOT/repo-missing-definition"
  local project_dir="$TMP_ROOT/project-missing-definition"
  local worker_uuid="44444444-4444-4444-4444-444444444444"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$project_dir"
  setup_worker_repo "$repo_dir"
  cat >"$project_dir/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF

  set +e
  out="$(run_register_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Project repo is missing init_progress_definition.yaml"
}

test_register_worker_fails_when_uuid_not_registered() {
  local repo_dir="$TMP_ROOT/repo-missing-uuid"
  local project_dir="$TMP_ROOT/project-missing-uuid"
  local worker_uuid="55555555-5555-5555-5555-555555555555"
  local registered_uuid="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"
  write_project_repo "$project_dir" "project-beta" "$registered_uuid"

  set +e
  out="$(run_register_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "No registered worker found for UUID"
}

test_register_worker_rewrites_binding_deterministically() {
  local repo_dir="$TMP_ROOT/repo-deterministic"
  local project_dir="$TMP_ROOT/project-deterministic"
  local worker_uuid="66666666-6666-6666-6666-666666666666"
  local first_content=""
  local second_content=""

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"
  write_project_repo "$project_dir" "project-gamma" "$worker_uuid" "platform" "ready"

  run_register_worker "$repo_dir" "$worker_uuid" "$project_dir" >/dev/null
  first_content="$(cat "$repo_dir/.asdlc_worker/project_overmind.yaml")"

  run_register_worker "$repo_dir" "$worker_uuid" "$project_dir" >/dev/null
  second_content="$(cat "$repo_dir/.asdlc_worker/project_overmind.yaml")"
  assert_equal "$first_content" "$second_content"

  write_project_repo "$project_dir" "project-gamma" "$worker_uuid" "backend" "busy"
  run_register_worker "$repo_dir" "$worker_uuid" "$project_dir" >/dev/null
  assert_contains "$(cat "$repo_dir/.asdlc_worker/project_overmind.yaml")" "class: 'backend'"
  assert_contains "$(cat "$repo_dir/.asdlc_worker/project_overmind.yaml")" "status: 'busy'"
}

test_register_worker_success_writes_binding
test_register_worker_fails_when_project_path_missing
test_register_worker_fails_when_workers_yaml_missing
test_register_worker_fails_when_definition_missing
test_register_worker_fails_when_uuid_not_registered
test_register_worker_rewrites_binding_deterministically

echo "register_worker_tests: PASS"
