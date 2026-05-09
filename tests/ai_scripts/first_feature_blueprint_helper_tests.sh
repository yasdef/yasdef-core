#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER_SRC="$SOURCE_ROOT/ai/scripts/helpers/helper_find_blueprints.sh"

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

setup_repo() {
  local repo_dir="$1"
  local worker_class="$2"

  mkdir -p "$repo_dir/ai/scripts/helpers" "$repo_dir/source-project/feature-a"
  cp "$HELPER_SRC" "$repo_dir/ai/scripts/helpers/helper_find_blueprints.sh"
  chmod +x "$repo_dir/ai/scripts/helpers/helper_find_blueprints.sh"

  cat >"$repo_dir/ai/project_overmind.yaml" <<EOF
worker_uuid: 'worker-1'
class: '$worker_class'
status: 'active'
EOF

  cat >"$repo_dir/source-project/feature-a/implementation_plan.md" <<'EOF'
# source plan
EOF

  cat >"$repo_dir/source-project/feature-a/requirements_ears.md" <<'EOF'
# source ears
EOF
}

run_helper_from_feature_dir() {
  local repo_dir="$1"
  (
    cd "$repo_dir/source-project/feature-a"
    "$repo_dir/ai/scripts/helpers/helper_find_blueprints.sh"
  )
}

test_matching_blueprint_is_reported() {
  local repo_dir="$TMP_ROOT/helper-match"
  setup_repo "$repo_dir" "backend"
  cat >"$repo_dir/source-project/project_stack_blueprint_back.md" <<'EOF'
# backend blueprint
EOF

  local out
  out="$(run_helper_from_feature_dir "$repo_dir")"
  assert_contains "$out" "Normalized project class: back"
  assert_contains "$out" "Relevant blueprint candidates for class back:"
  assert_contains "$out" "$repo_dir/source-project/project_stack_blueprint_back.md"
  assert_contains "$out" "Relevant blueprint result: found 1 class-matching blueprint candidate(s)."
}

test_missing_blueprints_are_reported() {
  local repo_dir="$TMP_ROOT/helper-missing"
  setup_repo "$repo_dir" "backend"

  local out
  out="$(run_helper_from_feature_dir "$repo_dir")"
  assert_contains "$out" "Blueprint search result: no blueprint files found under project-level root."
}

test_irrelevant_blueprints_are_reported() {
  local repo_dir="$TMP_ROOT/helper-irrelevant"
  setup_repo "$repo_dir" "backend"
  cat >"$repo_dir/source-project/project_stack_blueprint_front.md" <<'EOF'
# frontend blueprint
EOF

  local out
  out="$(run_helper_from_feature_dir "$repo_dir")"
  assert_contains "$out" "Irrelevant blueprint candidates for class back:"
  assert_contains "$out" "$repo_dir/source-project/project_stack_blueprint_front.md"
  assert_contains "$out" "Relevant blueprint result: no class-matching blueprint found. Ask the user to choose the stack/scaffold direction."
}

test_matching_blueprint_is_reported
test_missing_blueprints_are_reported
test_irrelevant_blueprints_are_reported

echo "All first-feature blueprint helper tests passed."
