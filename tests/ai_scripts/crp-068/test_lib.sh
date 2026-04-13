#!/usr/bin/env bash
set -euo pipefail

TEST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$TEST_LIB_DIR/../../.." && pwd)"

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
    echo "Assertion failed: expected output to not contain: $needle" >&2
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

assert_file_not_exists() {
  local path="$1"
  if [[ -f "$path" ]]; then
    echo "Assertion failed: expected file to not exist: $path" >&2
    exit 1
  fi
}

new_test_repo() {
  local name="$1"
  local repo_dir="$TMP_ROOT/$name"
  mkdir -p "$repo_dir"
  printf '%s' "$repo_dir"
}

copy_file_from_repo_root() {
  local repo_dir="$1"
  local relative_path="$2"
  mkdir -p "$repo_dir/$(dirname "$relative_path")"
  cp "$SOURCE_ROOT/$relative_path" "$repo_dir/$relative_path"
}

copy_executable_from_repo_root() {
  local repo_dir="$1"
  local relative_path="$2"
  copy_file_from_repo_root "$repo_dir" "$relative_path"
  chmod +x "$repo_dir/$relative_path"
}

init_git_repo_with_overmind_branch() {
  local repo_dir="$1"
  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "seed" >README.md
    git add -A
    git commit -qm "seed"
    git checkout -b overmind >/dev/null
  )
}

seed_models_file() {
  local repo_dir="$1"
  shift
  mkdir -p "$repo_dir/overmind/setup"
  {
    echo "# Phase | Command | Model | Extra Arg 1 (optional) | Extra Arg 2 (optional) | ..."
    local line=""
    for line in "$@"; do
      echo "$line"
    done
  } >"$repo_dir/overmind/setup/models.md"
}

seed_feature_br_summary_file() {
  local repo_dir="$1"
  local artifact_root="$2"
  local project_type_code="${3:-B}"
  mkdir -p "$repo_dir/$artifact_root"
  cat >"$repo_dir/$artifact_root/feature_br_summary.md" <<EOF
# Feature Business Requirements Summary

## 1. Document Meta
- project_type_code: $project_type_code
- source_type: [UNFILLED]
- last_updated: [UNFILLED]
- ready_to_ears: false
EOF
}

seed_missing_data_file_with_unresolved_item() {
  local repo_dir="$1"
  local artifact_root="$2"
  mkdir -p "$repo_dir/$artifact_root"
  cat >"$repo_dir/$artifact_root/missing_br_data.md" <<'EOF'
# Missing Business Data

## 3. Unresolved Items Ledger (Rised)
- rised_item_1: source=## 15. Open Questions -> critical_questions; rised=false; unresolved_item=Need policy owner decision

## 6. Latest User Answers
- answers: [UNFILLED]
EOF
}

seed_user_input_file() {
  local repo_dir="$1"
  local artifact_root="$2"
  mkdir -p "$repo_dir/$artifact_root"
  cat >"$repo_dir/$artifact_root/user_br_input.md" <<'EOF'
# User Business Input
- feature_id: FTR-10
- feature_title: Contract test fixture
EOF
}

seed_epic_story_source_file() {
  local repo_dir="$1"
  local source_relative_path="$2"
  mkdir -p "$repo_dir/$(dirname "$source_relative_path")"
  cat >"$repo_dir/$source_relative_path" <<'EOF'
# Epic Story Input

Business users need deterministic artifact path routing for BR generation workflows.
EOF
}

write_pass_user_input_helper() {
  local repo_dir="$1"
  local helper_path="$repo_dir/overmind/scripts/helper/check_task_to_br_quality.sh"
  mkdir -p "$(dirname "$helper_path")"
  cat >"$helper_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "$helper_path"
}

write_pass_readiness_helpers() {
  local repo_dir="$1"
  local user_helper="$repo_dir/overmind/scripts/helper/check_task_to_br_quality.sh"
  local repo_helper="$repo_dir/overmind/scripts/helper/check_business_context_filled_from_repo.sh"
  mkdir -p "$(dirname "$user_helper")"
  cat >"$user_helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  cat >"$repo_helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "$user_helper" "$repo_helper"
}

install_codex_capture_stub() {
  local repo_dir="$1"
  local codex_path="$repo_dir/bin/codex"
  mkdir -p "$repo_dir/bin"
  cat >"$codex_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

capture_dir="${TEST_CAPTURE_DIR:-}"
if [[ -n "$capture_dir" ]]; then
  mkdir -p "$capture_dir"
  printf '%s\n' "$@" >"$capture_dir/codex_args.txt"
  printf '%s' "${!#}" >"$capture_dir/codex_prompt.txt"
fi

phase2_target_root="${TEST_PHASE2_TARGET_ROOT:-}"
if [[ -n "$phase2_target_root" ]]; then
  missing_data_path="$phase2_target_root/missing_br_data.md"
  if [[ -f "$missing_data_path" ]]; then
    perl -0pi -e 's/rised=false/rised=true/g' "$missing_data_path"
  fi
fi
EOF
  chmod +x "$codex_path"
}
