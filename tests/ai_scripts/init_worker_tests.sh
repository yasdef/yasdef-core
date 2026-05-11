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
    echo "Assertion failed: expected output not to contain: $needle" >&2
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

test_init_worker_success_creates_project_overmind_binding() {
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

  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  assert_contains "$out" "Worker init complete."
  assert_contains "$out" "Binding file: ai/project_overmind.yaml"
  assert_contains "$out" "Worker UUID: $worker_uuid"
  assert_contains "$out" "Project ID: $project_id"
  assert_contains "$out" "Worker class: platform"
  assert_contains "$out" "Worker status: ready"
  assert_contains "$out" "Overmind binding commit:"
  assert_contains "$out" "Current branch: overmind"
  assert_contains "$out" "you are in overmind branch now, if you need this changes in main/master you can merge it manually"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
  assert_branch_exists "$repo_dir" "overmind"

  project_resolved="$(resolved_path "$project_dir")"
  expected="$(cat <<EOF
overmind_source_path: '$project_resolved'
project_id: '$project_id'
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
  local missing_path="$TMP_ROOT/does-not-exist-project"
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
  local project_dir="$TMP_ROOT/project-missing-workers"
  local worker_uuid="33333333-3333-3333-3333-333333333333"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$project_dir"
  setup_worker_repo "$repo_dir"

  set +e
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Project repo does not contain a root workers.yaml"
}

test_init_worker_fails_when_init_progress_definition_missing() {
  local repo_dir="$TMP_ROOT/repo-missing-definition"
  local project_dir="$TMP_ROOT/project-missing-definition"
  local worker_uuid="33333333-3333-3333-3333-333333333334"
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
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Project repo is missing init_progress_definition.yaml"
}

test_init_worker_fails_when_meta_info_project_id_missing() {
  local repo_dir="$TMP_ROOT/repo-missing-project-id"
  local project_dir="$TMP_ROOT/project-missing-project-id"
  local worker_uuid="33333333-3333-3333-3333-333333333335"
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
  cat >"$project_dir/init_progress_definition.yaml" <<'EOF'
meta_info:
  project_type_code: "B"
steps: []
EOF

  set +e
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "meta_info.project_id is missing or empty"
}

test_init_worker_fails_when_uuid_not_registered() {
  local repo_dir="$TMP_ROOT/repo-unknown-uuid"
  local project_dir="$TMP_ROOT/project-unknown-uuid"
  local worker_uuid="44444444-4444-4444-4444-444444444444"
  local out=""
  local status=0

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"
  write_project_repo "$project_dir" "some-project" "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

  set +e
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "No registered worker found for UUID '$worker_uuid'"
}

test_init_worker_fails_when_uuid_duplicate_in_single_workers_yaml() {
  local repo_dir="$TMP_ROOT/repo-duplicate-uuid"
  local project_dir="$TMP_ROOT/project-duplicate-uuid"
  local worker_uuid="55555555-5555-5555-5555-555555555555"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$project_dir"
  setup_worker_repo "$repo_dir"
  cat >"$project_dir/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
  - uuid: "$worker_uuid"
    class: "backend"
    status: "active"
EOF
  cat >"$project_dir/init_progress_definition.yaml" <<EOF
meta_info:
  project_id: 'proj-dup'
steps: []
EOF

  set +e
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "resolved to multiple entries in"
}

test_init_worker_is_deterministic_and_refreshes_metadata() {
  local repo_dir="$TMP_ROOT/repo-deterministic"
  local project_dir="$TMP_ROOT/project-deterministic"
  local worker_uuid="66666666-6666-6666-6666-666666666666"
  local project_id="project-z"
  local first=""
  local second=""
  local third=""
  local out_second=""
  local overmind_head_before=""
  local overmind_head_after=""

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"
  write_project_repo "$project_dir" "$project_id" "$worker_uuid"

  run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" >/dev/null
  first="$(binding_file_content_from_branch "$repo_dir" "overmind")"
  overmind_head_before="$(git -C "$repo_dir" rev-parse overmind)"

  out_second="$(run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  second="$(binding_file_content_from_branch "$repo_dir" "overmind")"
  overmind_head_after="$(git -C "$repo_dir" rev-parse overmind)"
  assert_equal "$first" "$second"
  assert_equal "$overmind_head_before" "$overmind_head_after"
  assert_contains "$out_second" "Overmind binding commit: none (already up to date)"

  cat >"$project_dir/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "backend"
    status: "paused"
EOF

  run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" >/dev/null
  third="$(binding_file_content_from_branch "$repo_dir" "overmind")"
  assert_contains "$third" "class: 'backend'"
  assert_contains "$third" "status: 'paused'"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"

  assert_no_legacy_identity_files "$repo_dir"
}

test_init_worker_warns_with_blueprint_before_overmind_checkout() {
  local repo_dir="$TMP_ROOT/repo-agents-blueprint"
  local project_dir="$TMP_ROOT/project-agents-blueprint"
  local worker_uuid="99999999-9999-9999-9999-999999999999"
  local project_id="project-agents-blueprint"
  local worker_class="backend"
  local out=""
  local project_resolved=""
  local blueprint_path=""

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"
  write_project_repo "$project_dir" "$project_id" "$worker_uuid" "$worker_class"
  echo "# Backend blueprint" >"$project_dir/project_stack_blueprint_${worker_class}.md"

  (
    cd "$repo_dir"
    git checkout -q -b overmind
    echo "# Branch-only guidance" >AGENTS.md
    git add AGENTS.md
    git commit -qm "add overmind-only agents"
    git checkout -q master
  )

  project_resolved="$(resolved_path "$project_dir")"
  blueprint_path="$project_resolved/project_stack_blueprint_${worker_class}.md"

  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  assert_contains "$out" "before start implementing things, ask model to create AGENTS.md"
  assert_contains "$out" "pass $blueprint_path to your prompt so model can use best practices"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
}

test_init_worker_warns_without_blueprint_when_agents_missing() {
  local repo_dir="$TMP_ROOT/repo-agents-no-blueprint"
  local project_dir="$TMP_ROOT/project-agents-no-blueprint"
  local worker_uuid="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  local out=""

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"
  write_project_repo "$project_dir" "project-agents-no-blueprint" "$worker_uuid" "frontend"

  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  assert_contains "$out" "before start implementing things, dont forget to create AGENTS.md"
  assert_not_contains "$out" "pass "
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
}

test_init_worker_suppresses_agents_warning_when_agents_exists() {
  local repo_dir="$TMP_ROOT/repo-agents-present"
  local project_dir="$TMP_ROOT/project-agents-present"
  local worker_uuid="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
  local out=""

  mkdir -p "$repo_dir"
  setup_worker_repo "$repo_dir"
  write_project_repo "$project_dir" "project-agents-present" "$worker_uuid" "mobile"
  echo "# Project guidance" >"$repo_dir/AGENTS.md"
  (
    cd "$repo_dir"
    git add AGENTS.md
    git commit -qm "add agents guidance"
  )

  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  assert_not_contains "$out" "before start implementing things"
  assert_equal "overmind" "$(git -C "$repo_dir" branch --show-current)"
}

test_init_worker_fails_when_registry_data_unusable() {
  local repo_dir="$TMP_ROOT/repo-unusable-registry"
  local project_dir="$TMP_ROOT/project-unusable-registry"
  local worker_uuid="77777777-7777-7777-7777-777777777777"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$project_dir"
  setup_worker_repo "$repo_dir"
  cat >"$project_dir/workers.yaml" <<'EOF'
version: 1
items:
  - uuid: "77777777-7777-7777-7777-777777777777"
    class: "platform"
    status: "ready"
EOF
  cat >"$project_dir/init_progress_definition.yaml" <<'EOF'
meta_info:
  project_id: 'proj-m'
steps: []
EOF

  set +e
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$project_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "missing 'workers:' key"
}

test_init_worker_rejects_multi_project_layout() {
  local repo_dir="$TMP_ROOT/repo-multi-project"
  local parent_dir="$TMP_ROOT/parent-multi-project"
  local worker_uuid="88888888-8888-8888-8888-888888888888"
  local out=""
  local status=0

  mkdir -p "$repo_dir" "$parent_dir/projects/proj-a"
  setup_worker_repo "$repo_dir"
  cat >"$parent_dir/projects/proj-a/workers.yaml" <<EOF
workers:
  - uuid: "$worker_uuid"
    class: "platform"
    status: "ready"
EOF

  set +e
  out="$(run_init_worker "$repo_dir" "$worker_uuid" "$parent_dir" 2>&1)"
  status=$?
  set -e

  assert_nonzero_status "$status"
  assert_contains "$out" "Project repo does not contain a root workers.yaml"
}

test_init_worker_success_creates_project_overmind_binding
test_init_worker_fails_when_overmind_path_missing
test_init_worker_fails_when_workers_yaml_missing
test_init_worker_fails_when_init_progress_definition_missing
test_init_worker_fails_when_meta_info_project_id_missing
test_init_worker_fails_when_uuid_not_registered
test_init_worker_fails_when_uuid_duplicate_in_single_workers_yaml
test_init_worker_is_deterministic_and_refreshes_metadata
test_init_worker_warns_with_blueprint_before_overmind_checkout
test_init_worker_warns_without_blueprint_when_agents_missing
test_init_worker_suppresses_agents_warning_when_agents_exists
test_init_worker_fails_when_registry_data_unusable
test_init_worker_rejects_multi_project_layout

echo "All init worker script tests passed."
