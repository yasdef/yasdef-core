#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_DIR="$SOURCE_ROOT/src/yasdef_worker/_data/skills/yasdef-worker-design"
FIND_BLUEPRINTS="$SKILL_DIR/scripts/find_blueprints.py"

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
    echo "Assertion failed: expected output NOT to contain: $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_status() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed: expected status $expected, got $actual" >&2
    exit 1
  fi
}

setup_project() {
  local project_dir="$1"
  local worker_class="${2:-back}"

  mkdir -p "$project_dir/.asdlc_worker" "$project_dir/feature-dir"

  touch "$project_dir/project_stack_blueprint_back.md"
  touch "$project_dir/project_stack_blueprint_front.md"

  cat >"$project_dir/.asdlc_worker/project_overmind.yaml" <<EOF
class: '$worker_class'
EOF

  touch "$project_dir/feature-dir/implementation_plan.md"
  touch "$project_dir/feature-dir/requirements_ears.md"
}

test_cwd_resolution_and_class_partition() {
  local project_dir="$TMP_ROOT/project-cwd"
  setup_project "$project_dir" "back"
  local real_project_dir real_feature_dir
  real_project_dir="$(cd "$project_dir" && pwd -P)"
  real_feature_dir="$(cd "$project_dir/feature-dir" && pwd -P)"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$FIND_BLUEPRINTS")"

  assert_contains "$out" "Blueprint helper result"
  assert_contains "$out" "Feature folder: $real_feature_dir"
  assert_contains "$out" "Project-level search root: $real_project_dir"
  assert_contains "$out" "Normalized project class: back"
  assert_contains "$out" "Relevant blueprint candidates for class back:"
  assert_contains "$out" "project_stack_blueprint_back.md"
  assert_contains "$out" "Irrelevant blueprint candidates for class back:"
  assert_contains "$out" "project_stack_blueprint_front.md"
  assert_contains "$out" "Relevant blueprint result: found 1 class-matching blueprint candidate(s)."
}

test_blueprint_in_feature_dir_is_not_found() {
  local project_dir="$TMP_ROOT/project-wrong-location"
  mkdir -p "$project_dir/.asdlc_worker" "$project_dir/feature-dir"
  cat >"$project_dir/.asdlc_worker/project_overmind.yaml" <<'EOF'
class: 'back'
EOF
  touch "$project_dir/feature-dir/implementation_plan.md"
  touch "$project_dir/feature-dir/requirements_ears.md"
  # Blueprint is in the feature dir itself, not in its parent — should not be found
  touch "$project_dir/feature-dir/project_stack_blueprint_back.md"
  local real_project_dir
  real_project_dir="$(cd "$project_dir" && pwd -P)"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$FIND_BLUEPRINTS")"

  assert_contains "$out" "Project-level search root: $real_project_dir"
  assert_contains "$out" "Relevant blueprint result: no blueprint files found under project-level root."
}

test_env_var_fallback_resolution() {
  local project_dir="$TMP_ROOT/project-envvar"
  setup_project "$project_dir" "back"
  local real_project_dir real_feature_dir
  real_project_dir="$(cd "$project_dir" && pwd -P)"
  real_feature_dir="$(cd "$project_dir/feature-dir" && pwd -P)"

  local out=""
  out="$(
    cd "$TMP_ROOT"
    ASDLC_RUNTIME_PLAN_PATH="$real_feature_dir/implementation_plan.md" \
      python3 "$FIND_BLUEPRINTS"
  )"

  assert_contains "$out" "Blueprint helper result"
  assert_contains "$out" "Feature folder: $real_feature_dir"
  assert_contains "$out" "Project-level search root: $real_project_dir"
  assert_contains "$out" "Normalized project class: back"
  assert_contains "$out" "Relevant blueprint result: found 1 class-matching blueprint candidate(s)."
}

test_unresolved_class_exits_zero_and_no_candidate_lists() {
  local project_dir="$TMP_ROOT/project-unresolved"
  setup_project "$project_dir" "unknown-stack"

  local out=""
  local status=0
  out="$(cd "$project_dir/feature-dir" && python3 "$FIND_BLUEPRINTS")"
  status=$?

  assert_status "0" "$status"
  assert_contains "$out" "Normalized project class: unresolved"
  assert_contains "$out" "All blueprint candidates:"
  assert_contains "$out" "Relevant blueprint result: unresolved because project class is missing"
  assert_not_contains "$out" "Relevant blueprint candidates for class"
}

test_missing_feature_dir_exits_nonzero() {
  local status=0
  local out=""

  set +e
  out="$(cd "$TMP_ROOT" && python3 "$FIND_BLUEPRINTS" 2>&1)"
  status=$?
  set -e

  assert_status "1" "$status"
  assert_contains "$out" "Blueprint lookup failed"
}

test_no_blueprints_exits_zero() {
  local project_dir="$TMP_ROOT/project-no-blueprints"
  mkdir -p "$project_dir/.asdlc_worker" "$project_dir/feature-dir"
  cat >"$project_dir/.asdlc_worker/project_overmind.yaml" <<'EOF'
class: 'back'
EOF
  touch "$project_dir/feature-dir/implementation_plan.md"
  touch "$project_dir/feature-dir/requirements_ears.md"

  local out=""
  local status=0
  out="$(cd "$project_dir/feature-dir" && python3 "$FIND_BLUEPRINTS")"
  status=$?

  assert_status "0" "$status"
  assert_contains "$out" "Relevant blueprint result: no blueprint files found"
}

test_single_quoted_class_value() {
  local project_dir="$TMP_ROOT/project-quoted"
  setup_project "$project_dir" "front"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$FIND_BLUEPRINTS")"

  assert_contains "$out" "Raw project class: front"
  assert_contains "$out" "Normalized project class: front"
  assert_contains "$out" "Relevant blueprint candidates for class front:"
  assert_contains "$out" "project_stack_blueprint_front.md"
}

test_class_with_trailing_comment() {
  local project_dir="$TMP_ROOT/project-comment"
  mkdir -p "$project_dir/.asdlc_worker" "$project_dir/feature-dir"
  cat >"$project_dir/.asdlc_worker/project_overmind.yaml" <<'EOF'
class: back # the backend worker
EOF
  touch "$project_dir/feature-dir/implementation_plan.md"
  touch "$project_dir/feature-dir/requirements_ears.md"
  touch "$project_dir/project_stack_blueprint_back.md"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$FIND_BLUEPRINTS")"

  assert_contains "$out" "Raw project class: back"
  assert_contains "$out" "Normalized project class: back"
  assert_contains "$out" "Relevant blueprint result: found 1 class-matching blueprint candidate(s)."
}

test_typo_ears_filename_accepted() {
  local project_dir="$TMP_ROOT/project-typo"
  mkdir -p "$project_dir/.asdlc_worker" "$project_dir/feature-dir"
  cat >"$project_dir/.asdlc_worker/project_overmind.yaml" <<'EOF'
class: 'back'
EOF
  touch "$project_dir/project_stack_blueprint_back.md"
  touch "$project_dir/feature-dir/implementation_plan.md"
  # Use the misspelled filename
  touch "$project_dir/feature-dir/reqirements_ears.md"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$FIND_BLUEPRINTS")"

  assert_contains "$out" "Blueprint helper result"
  assert_contains "$out" "Normalized project class: back"
  assert_contains "$out" "Relevant blueprint result: found 1 class-matching blueprint candidate(s)."
}

test_cwd_resolution_and_class_partition
test_blueprint_in_feature_dir_is_not_found
test_env_var_fallback_resolution
test_unresolved_class_exits_zero_and_no_candidate_lists
test_missing_feature_dir_exits_nonzero
test_no_blueprints_exits_zero
test_single_quoted_class_value
test_class_with_trailing_comment
test_typo_ears_filename_accepted

echo "yasdef_worker_design_find_blueprints_tests: PASS"
