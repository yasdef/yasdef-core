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

# The helper resolves its binding by walking up from its own installed location,
# so every fixture installs a copied skill script inside a synthetic worker repo
# and keeps the bound project folder outside that worker repo.
setup_worker() {
  local worker_dir="$1"
  local worker_class="${2:-back}"

  mkdir -p "$worker_dir/.asdlc_worker" "$worker_dir/.claude/skills/yasdef-worker-design/scripts"
  cp "$FIND_BLUEPRINTS" "$worker_dir/.claude/skills/yasdef-worker-design/scripts/find_blueprints.py"

  if [[ -n "$worker_class" ]]; then
    cat >"$worker_dir/.asdlc_worker/project_overmind.yaml" <<EOF
class: '$worker_class'
EOF
  fi
}

worker_script() {
  echo "$1/.claude/skills/yasdef-worker-design/scripts/find_blueprints.py"
}

setup_project() {
  local project_dir="$1"

  mkdir -p "$project_dir/feature-dir"
  touch "$project_dir/project_stack_blueprint_back.md"
  touch "$project_dir/project_stack_blueprint_front.md"
  touch "$project_dir/feature-dir/implementation_plan.md"
  touch "$project_dir/feature-dir/requirements_ears.md"
}

test_cwd_resolution_and_class_partition() {
  local worker_dir="$TMP_ROOT/worker-cwd"
  local project_dir="$TMP_ROOT/project-cwd"
  setup_worker "$worker_dir" "back"
  setup_project "$project_dir"
  local real_project_dir real_feature_dir real_worker_dir
  real_worker_dir="$(cd "$worker_dir" && pwd -P)"
  real_project_dir="$(cd "$project_dir" && pwd -P)"
  real_feature_dir="$(cd "$project_dir/feature-dir" && pwd -P)"

  # One project-root guidance file present, the other absent.
  touch "$worker_dir/AGENTS.md"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"

  assert_contains "$out" "Blueprint helper result"
  assert_contains "$out" "Feature folder: $real_feature_dir"
  assert_contains "$out" "Project-level search root: $real_project_dir"
  assert_contains "$out" "Binding file: $real_worker_dir/.asdlc_worker/project_overmind.yaml"
  assert_contains "$out" "Worker repo root: $real_worker_dir"
  assert_contains "$out" "Project AGENTS.md state: present"
  assert_contains "$out" "Project CLAUDE.md state: absent"
  assert_contains "$out" "Normalized project class: back"
  assert_contains "$out" "Relevant blueprint candidates for class back:"
  assert_contains "$out" "project_stack_blueprint_back.md"
  assert_contains "$out" "Irrelevant blueprint candidates for class back:"
  assert_contains "$out" "project_stack_blueprint_front.md"
  assert_contains "$out" "Relevant blueprint result: found 1 class-matching blueprint candidate(s)."
}

test_blueprint_in_feature_dir_is_not_found() {
  local worker_dir="$TMP_ROOT/worker-wrong-location"
  local project_dir="$TMP_ROOT/project-wrong-location"
  setup_worker "$worker_dir" "back"
  mkdir -p "$project_dir/feature-dir"
  touch "$project_dir/feature-dir/implementation_plan.md"
  touch "$project_dir/feature-dir/requirements_ears.md"
  # Blueprint is in the feature dir itself, not in its parent — should not be found
  touch "$project_dir/feature-dir/project_stack_blueprint_back.md"
  local real_project_dir
  real_project_dir="$(cd "$project_dir" && pwd -P)"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"

  assert_contains "$out" "Project-level search root: $real_project_dir"
  assert_contains "$out" "Relevant blueprint result: no blueprint files found under project-level root."
}

test_env_var_fallback_resolution() {
  local worker_dir="$TMP_ROOT/worker-envvar"
  local project_dir="$TMP_ROOT/project-envvar"
  setup_worker "$worker_dir" "back"
  setup_project "$project_dir"
  local real_project_dir real_feature_dir
  real_project_dir="$(cd "$project_dir" && pwd -P)"
  real_feature_dir="$(cd "$project_dir/feature-dir" && pwd -P)"

  local out=""
  out="$(
    cd "$TMP_ROOT"
    ASDLC_RUNTIME_PLAN_PATH="$real_feature_dir/implementation_plan.md" \
      python3 "$(worker_script "$worker_dir")"
  )"

  assert_contains "$out" "Blueprint helper result"
  assert_contains "$out" "Feature folder: $real_feature_dir"
  assert_contains "$out" "Project-level search root: $real_project_dir"
  assert_contains "$out" "Normalized project class: back"
  assert_contains "$out" "Relevant blueprint result: found 1 class-matching blueprint candidate(s)."
}

test_unresolved_class_exits_zero_and_no_candidate_lists() {
  local worker_dir="$TMP_ROOT/worker-unresolved"
  local project_dir="$TMP_ROOT/project-unresolved"
  setup_worker "$worker_dir" "unknown-stack"
  setup_project "$project_dir"

  local out=""
  local status=0
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"
  status=$?

  assert_status "0" "$status"
  assert_contains "$out" "Normalized project class: unresolved"
  assert_contains "$out" "All blueprint candidates:"
  assert_contains "$out" "Relevant blueprint result: unresolved because project class is missing"
  assert_not_contains "$out" "Relevant blueprint candidates for class"
}

test_missing_feature_dir_exits_nonzero() {
  local worker_dir="$TMP_ROOT/worker-missing-feature"
  setup_worker "$worker_dir" "back"
  local status=0
  local out=""

  set +e
  out="$(cd "$TMP_ROOT" && python3 "$(worker_script "$worker_dir")" 2>&1)"
  status=$?
  set -e

  assert_status "1" "$status"
  assert_contains "$out" "Blueprint lookup failed"
}

test_no_blueprints_exits_zero() {
  local worker_dir="$TMP_ROOT/worker-no-blueprints"
  local project_dir="$TMP_ROOT/project-no-blueprints"
  setup_worker "$worker_dir" "back"
  mkdir -p "$project_dir/feature-dir"
  touch "$project_dir/feature-dir/implementation_plan.md"
  touch "$project_dir/feature-dir/requirements_ears.md"

  local out=""
  local status=0
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"
  status=$?

  assert_status "0" "$status"
  assert_contains "$out" "Relevant blueprint result: no blueprint files found"
}

test_single_quoted_class_value() {
  local worker_dir="$TMP_ROOT/worker-quoted"
  local project_dir="$TMP_ROOT/project-quoted"
  setup_worker "$worker_dir" "front"
  setup_project "$project_dir"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"

  assert_contains "$out" "Raw project class: front"
  assert_contains "$out" "Normalized project class: front"
  assert_contains "$out" "Relevant blueprint candidates for class front:"
  assert_contains "$out" "project_stack_blueprint_front.md"
}

test_class_with_trailing_comment() {
  local worker_dir="$TMP_ROOT/worker-comment"
  local project_dir="$TMP_ROOT/project-comment"
  setup_worker "$worker_dir" ""
  cat >"$worker_dir/.asdlc_worker/project_overmind.yaml" <<'EOF'
class: back # the backend worker
EOF
  mkdir -p "$project_dir/feature-dir"
  touch "$project_dir/feature-dir/implementation_plan.md"
  touch "$project_dir/feature-dir/requirements_ears.md"
  touch "$project_dir/project_stack_blueprint_back.md"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"

  assert_contains "$out" "Raw project class: back"
  assert_contains "$out" "Normalized project class: back"
  assert_contains "$out" "Relevant blueprint result: found 1 class-matching blueprint candidate(s)."
}

test_typo_ears_filename_accepted() {
  local worker_dir="$TMP_ROOT/worker-typo"
  local project_dir="$TMP_ROOT/project-typo"
  setup_worker "$worker_dir" "back"
  mkdir -p "$project_dir/feature-dir"
  touch "$project_dir/project_stack_blueprint_back.md"
  touch "$project_dir/feature-dir/implementation_plan.md"
  # Use the misspelled filename
  touch "$project_dir/feature-dir/reqirements_ears.md"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"

  assert_contains "$out" "Blueprint helper result"
  assert_contains "$out" "Normalized project class: back"
  assert_contains "$out" "Relevant blueprint result: found 1 class-matching blueprint candidate(s)."
}

test_agents_guidance_partitioned_by_class() {
  local worker_dir="$TMP_ROOT/worker-guidance"
  local project_dir="$TMP_ROOT/project-guidance"
  setup_worker "$worker_dir" "back"
  setup_project "$project_dir"
  touch "$project_dir/project_agents_md_claude_md_backend.md"
  touch "$project_dir/project_agents_md_claude_md_frontend.md"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"

  assert_contains "$out" "All agents guidance candidates:"
  assert_contains "$out" "Relevant agents guidance candidates for class back:"
  assert_contains "$out" "project_agents_md_claude_md_backend.md"
  assert_contains "$out" "Irrelevant agents guidance candidates for class back:"
  assert_contains "$out" "project_agents_md_claude_md_frontend.md"
  assert_contains "$out" "Relevant agents guidance result: found 1 class-matching agents guidance candidate(s)."
}

test_no_agents_guidance_exits_zero() {
  local worker_dir="$TMP_ROOT/worker-no-guidance"
  local project_dir="$TMP_ROOT/project-no-guidance"
  setup_worker "$worker_dir" "back"
  setup_project "$project_dir"

  local out=""
  local status=0
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"
  status=$?

  assert_status "0" "$status"
  assert_contains "$out" "Relevant blueprint result: found 1 class-matching blueprint candidate(s)."
  assert_contains "$out" "Relevant agents guidance result: no agents guidance files found under project-level root."
}

test_no_worker_binding_reports_unresolved() {
  local unbound_dir="$TMP_ROOT/unbound/scripts"
  local project_dir="$TMP_ROOT/project-unbound"
  mkdir -p "$unbound_dir"
  cp "$FIND_BLUEPRINTS" "$unbound_dir/find_blueprints.py"
  setup_project "$project_dir"
  touch "$project_dir/project_agents_md_claude_md_backend.md"

  local out=""
  local status=0
  out="$(cd "$project_dir/feature-dir" && python3 "$unbound_dir/find_blueprints.py")"
  status=$?

  assert_status "0" "$status"
  assert_contains "$out" "Binding file: unresolved"
  assert_contains "$out" "Worker repo root: unresolved"
  assert_contains "$out" "Project AGENTS.md state: unresolved"
  assert_contains "$out" "Project CLAUDE.md state: unresolved"
  assert_contains "$out" "Raw project class: unresolved"
  assert_contains "$out" "All blueprint candidates:"
  assert_contains "$out" "All agents guidance candidates:"
  assert_not_contains "$out" "Relevant blueprint candidates for class"
}

test_both_guidance_files_present() {
  local worker_dir="$TMP_ROOT/worker-both-present"
  local project_dir="$TMP_ROOT/project-both-present"
  setup_worker "$worker_dir" "back"
  setup_project "$project_dir"
  touch "$worker_dir/AGENTS.md"
  touch "$worker_dir/CLAUDE.md"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"

  assert_contains "$out" "Project AGENTS.md state: present"
  assert_contains "$out" "Project CLAUDE.md state: present"
}

test_directory_guidance_path_is_invalid() {
  local worker_dir="$TMP_ROOT/worker-invalid-dir"
  local project_dir="$TMP_ROOT/project-invalid-dir"
  setup_worker "$worker_dir" "back"
  setup_project "$project_dir"
  mkdir -p "$worker_dir/AGENTS.md"
  touch "$worker_dir/CLAUDE.md"

  local out=""
  local status=0
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"
  status=$?

  assert_status "0" "$status"
  assert_contains "$out" "Project AGENTS.md state: invalid-directory"
  assert_contains "$out" "Project CLAUDE.md state: present"
}

test_external_guidance_does_not_satisfy_project_root_state() {
  local worker_dir="$TMP_ROOT/worker-external"
  local project_dir="$TMP_ROOT/project-external"
  local fake_home="$TMP_ROOT/fake-home"
  setup_worker "$worker_dir" "back"
  setup_project "$project_dir"
  # Guidance files outside the worker repo root: project folder and a user-home tool dir.
  touch "$project_dir/AGENTS.md"
  mkdir -p "$fake_home/.claude"
  touch "$fake_home/.claude/CLAUDE.md"

  local out=""
  out="$(cd "$project_dir/feature-dir" && HOME="$fake_home" python3 "$(worker_script "$worker_dir")")"

  assert_contains "$out" "Project AGENTS.md state: absent"
  assert_contains "$out" "Project CLAUDE.md state: absent"
  assert_not_contains "$out" "$fake_home"
}

test_symlinked_guidance_path_is_present() {
  local worker_dir="$TMP_ROOT/worker-symlink"
  local project_dir="$TMP_ROOT/project-symlink"
  setup_worker "$worker_dir" "back"
  setup_project "$project_dir"
  touch "$TMP_ROOT/external_guidance.md"
  ln -s "$TMP_ROOT/external_guidance.md" "$worker_dir/CLAUDE.md"

  local out=""
  out="$(cd "$project_dir/feature-dir" && python3 "$(worker_script "$worker_dir")")"

  assert_contains "$out" "Project AGENTS.md state: absent"
  assert_contains "$out" "Project CLAUDE.md state: present"
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
test_agents_guidance_partitioned_by_class
test_no_agents_guidance_exits_zero
test_no_worker_binding_reports_unresolved
test_both_guidance_files_present
test_directory_guidance_path_is_invalid
test_external_guidance_does_not_satisfy_project_root_state
test_symlinked_guidance_path_is_present

echo "yasdef_worker_design_find_blueprints_tests: PASS"
