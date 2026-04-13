#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_lib.sh"

SCAFFOLD_SCRIPT="$SOURCE_ROOT/overmind/scripts/feature_br_scaffold.sh"
SCAN_SCRIPT="$SOURCE_ROOT/overmind/scripts/feature_scan_repo_for_br.sh"
TASK_SCRIPT="$SOURCE_ROOT/overmind/scripts/feature_task_to_br.sh"
CLARIFICATION_SCRIPT="$SOURCE_ROOT/overmind/scripts/feature_user_br_clarification.sh"

assert_nonzero_status() {
  local status="$1"
  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: expected non-zero status" >&2
    exit 1
  fi
}

setup_staged_workspace() {
  local repo_dir="$1"

  mkdir -p \
    "$repo_dir/asdlc/.commands" \
    "$repo_dir/asdlc/.rules" \
    "$repo_dir/asdlc/.setup" \
    "$repo_dir/asdlc/.helper" \
    "$repo_dir/asdlc/.templates" \
    "$repo_dir/asdlc/.golden_examples" \
    "$repo_dir/asdlc/projects/p1/feature-a"

  cp "$SCAFFOLD_SCRIPT" "$repo_dir/asdlc/.commands/feature_br_scaffold.sh"
  cp "$SCAN_SCRIPT" "$repo_dir/asdlc/.commands/feature_scan_repo_for_br.sh"
  cp "$TASK_SCRIPT" "$repo_dir/asdlc/.commands/feature_task_to_br.sh"
  cp "$CLARIFICATION_SCRIPT" "$repo_dir/asdlc/.commands/feature_user_br_clarification.sh"

  cp "$SOURCE_ROOT/overmind/rules/repo_br_scan_rule.md" "$repo_dir/asdlc/.rules/repo_br_scan_rule.md"
  cp "$SOURCE_ROOT/overmind/rules/task_to_br_rule.md" "$repo_dir/asdlc/.rules/task_to_br_rule.md"
  cp "$SOURCE_ROOT/overmind/rules/user_br_clarification_rule.md" "$repo_dir/asdlc/.rules/user_br_clarification_rule.md"

  cp "$SOURCE_ROOT/overmind/scripts/helper/check_business_context_filled_from_repo.sh" "$repo_dir/asdlc/.helper/check_business_context_filled_from_repo.sh"
  cp "$SOURCE_ROOT/overmind/scripts/helper/check_task_to_br_quality.sh" "$repo_dir/asdlc/.helper/check_task_to_br_quality.sh"

  cp "$SOURCE_ROOT/overmind/templates/feature_br_summary_TEMPLATE.md" "$repo_dir/asdlc/.templates/feature_br_summary_TEMPLATE.md"
  cp "$SOURCE_ROOT/overmind/templates/missing_br_data_TEMPLATE.md" "$repo_dir/asdlc/.templates/missing_br_data_TEMPLATE.md"
  cp "$SOURCE_ROOT/overmind/golden_examples/missing_br_data_GOLDEN_EXAMPLE.md" "$repo_dir/asdlc/.golden_examples/missing_br_data_GOLDEN_EXAMPLE.md"

  chmod +x "$repo_dir/asdlc/.commands/feature_br_scaffold.sh"
  chmod +x "$repo_dir/asdlc/.commands/feature_scan_repo_for_br.sh"
  chmod +x "$repo_dir/asdlc/.commands/feature_task_to_br.sh"
  chmod +x "$repo_dir/asdlc/.commands/feature_user_br_clarification.sh"
  chmod +x "$repo_dir/asdlc/.helper/check_business_context_filled_from_repo.sh"
  chmod +x "$repo_dir/asdlc/.helper/check_task_to_br_quality.sh"

  cat >"$repo_dir/asdlc/asdlc_metadata.yaml" <<'OUT'
meta:
  description: "test"
projects:
OUT

  cat >"$repo_dir/asdlc/.setup/models.md" <<'OUT'
repo_analyse | codex | gpt-5.4
task_to_br | codex | gpt-5.4
user_br_clarification | codex | gpt-5.4
OUT

  cat >"$repo_dir/asdlc/projects/p1/init_progress_definition.yaml" <<'OUT'
meta_info:
  project_type_code: "B"
  project_type_label: "Existing project with partial context"

steps: []
OUT

  (
    cd "$repo_dir/asdlc"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "seed" >README.md
    git add .
    git commit -qm "seed"
  )
}

test_rejects_non_staged_invocation_for_all_feature_scripts() {
  local out=""
  local status=0

  set +e
  out="$(cd "$SOURCE_ROOT" && "$SCAFFOLD_SCRIPT" --path "projects/p1/feature-a" 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Run this command from ASDLC staged path"

  set +e
  out="$(cd "$SOURCE_ROOT" && "$SCAN_SCRIPT" --feature_path "projects/p1/feature-a" 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Run this command from ASDLC staged path"

  set +e
  out="$(cd "$SOURCE_ROOT" && "$TASK_SCRIPT" --feature_path "projects/p1/feature-a" 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Run this command from ASDLC staged path"

  set +e
  out="$(cd "$SOURCE_ROOT" && "$CLARIFICATION_SCRIPT" --feature_path "projects/p1/feature-a" 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Run this command from ASDLC staged path"
}

test_scaffold_uses_path_only_and_writes_feature_summary() {
  local repo_dir
  repo_dir="$(new_test_repo "scaffold-path-contract")"
  setup_staged_workspace "$repo_dir"

  local out=""
  local status=0
  local summary_count=""

  set +e
  out="$(cd "$repo_dir/asdlc" && .commands/feature_br_scaffold.sh --feature_path "projects/p1/feature-a" 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Unknown argument: --feature_path"

  out="$(cd "$repo_dir/asdlc" && printf 'FTR-10\nPath Contract\n' | .commands/feature_br_scaffold.sh --path "projects/p1")"
  assert_contains "$out" "Created feature folder: projects/p1/"
  assert_contains "$out" "Updated projects/p1/"
  summary_count="$(find "$repo_dir/asdlc/projects/p1" -mindepth 2 -maxdepth 2 -type f -name 'feature_br_summary.md' | wc -l | tr -d ' ')"
  assert_equal "1" "$summary_count"
}

test_other_scripts_use_feature_path_and_require_feature_summary() {
  local repo_dir
  repo_dir="$(new_test_repo "feature-path-contract")"
  setup_staged_workspace "$repo_dir"

  local out=""
  local status=0

  set +e
  out="$(cd "$repo_dir/asdlc" && .commands/feature_scan_repo_for_br.sh --path "projects/p1/feature-a" 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Unknown argument: --path"

  set +e
  out="$(cd "$repo_dir/asdlc" && .commands/feature_scan_repo_for_br.sh --feature_path "projects/p1/feature-a" 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Required file not found: projects/p1/feature-a/feature_br_summary.md"

  set +e
  out="$(cd "$repo_dir/asdlc" && .commands/feature_task_to_br.sh --path "projects/p1/feature-a" 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Unknown argument: --path"

  set +e
  out="$(cd "$repo_dir/asdlc" && .commands/feature_task_to_br.sh --feature_path "projects/p1/feature-a" 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Required file not found: projects/p1/feature-a/feature_br_summary.md"

  set +e
  out="$(cd "$repo_dir/asdlc" && .commands/feature_user_br_clarification.sh --path "projects/p1/feature-a" 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Unknown argument: --path"

  set +e
  out="$(cd "$repo_dir/asdlc" && .commands/feature_user_br_clarification.sh --feature_path "projects/p1/feature-a" 2>&1)"
  status=$?
  set -e
  assert_nonzero_status "$status"
  assert_contains "$out" "Required file not found: projects/p1/feature-a/feature_br_summary.md"
}

test_rejects_non_staged_invocation_for_all_feature_scripts
test_scaffold_uses_path_only_and_writes_feature_summary
test_other_scripts_use_feature_path_and_require_feature_summary

echo "All CRP-068 feature path staged contract tests passed."
