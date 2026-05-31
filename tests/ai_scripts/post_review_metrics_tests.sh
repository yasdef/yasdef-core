#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POST_REVIEW_SRC="$SOURCE_ROOT/ai/scripts/post_review.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export ASDLC_RUNTIME_PLAN_PATH=".asdlc_worker/overmind/implementation_plan.md"
export ASDLC_RUNTIME_EARS_PATH=".asdlc_worker/overmind/reqirements_ears.md"

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

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

setup_post_review_repo() {
  local repo_dir="$1"
  local include_seed_python_class="${2:-0}"
  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/step_plans" \
    "$repo_dir/.asdlc_worker/step_review_results" "$repo_dir/.asdlc_worker/overmind"
  ln -s .asdlc_worker "$repo_dir/ai"
  ln -s .asdlc_worker/overmind "$repo_dir/overmind"

  cp "$POST_REVIEW_SRC" "$repo_dir/.asdlc_worker/scripts/post_review.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  chmod +x "$repo_dir/.asdlc_worker/scripts/post_review.sh"

  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
EOF

  cat >"$repo_dir/overmind/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
Est. step total: 5 SP
- [x] Plan and discuss the step (SP=1)
- [x] Implement part A (SP=2)
- [x] Review step implementation (SP=1)
EOF

  cat >"$repo_dir/ai/step_review_results/review_result-1.1.md" <<'EOF'
### F-01
- Severity: High
- Disposition state:
  - [x] follow_up_created: 1.1a
  - [ ] raised_to_coordinator:
  - [ ] rejected:
EOF

  if [[ "$include_seed_python_class" == "1" ]]; then
    mkdir -p "$repo_dir/src"
    cat >"$repo_dir/src/existing.py" <<'EOF'
class SeedThing:
    pass
EOF
  fi

  (
    cd "$repo_dir"
    git init -q -b master
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
    git branch overmind
    git checkout -qb step-1.1-implementation
    git checkout -qb step-1.1-review
  )
}

commit_all() {
  local repo_dir="$1"
  local message="$2"
  (
    cd "$repo_dir"
    git add -A
    git commit -qm "$message"
  )
}

run_post_review_dry_run() {
  local repo_dir="$1"
  (
    cd "$repo_dir"
    .asdlc_worker/scripts/post_review.sh --step 1.1 --dry-run 2>&1
  )
}

run_post_review() {
  local repo_dir="$1"
  (
    cd "$repo_dir"
    .asdlc_worker/scripts/post_review.sh --step 1.1 2>&1
  )
}

extract_new_files_added() {
  local output="$1"
  printf '%s\n' "$output" | sed -n 's/^new files added: \([0-9][0-9]*\)$/\1/p' | tail -n 1
}

assert_new_files_added_equals() {
  local output="$1"
  local expected="$2"
  local actual
  actual="$(extract_new_files_added "$output")"
  if [[ -z "$actual" ]]; then
    echo "Assertion failed: could not extract 'new files added' from output" >&2
    echo "$output" >&2
    exit 1
  fi
  assert_equals "$expected" "$actual"
}

test_counts_required_minimum_extensions() {
  local repo_dir="$TMP_ROOT/repo-required-minimum"
  setup_post_review_repo "$repo_dir"

  mkdir -p "$repo_dir/src/main/java/com/example" "$repo_dir/src/python" "$repo_dir/src/web" \
    "$repo_dir/src/go" "$repo_dir/src/kotlin"

  cat >"$repo_dir/src/main/java/com/example/JavaThing.java" <<'EOF'
package com.example;
public class JavaThing {}
EOF
  cat >"$repo_dir/src/python/thing.py" <<'EOF'
class PyThing:
    pass
EOF
  cat >"$repo_dir/src/web/thing.tsx" <<'EOF'
export class TsxThing {}
EOF
  cat >"$repo_dir/src/go/thing.go" <<'EOF'
package demo
type GoThing struct {}
EOF
  cat >"$repo_dir/src/kotlin/Thing.kt" <<'EOF'
data class KtThing(val id: Int)
EOF

  commit_all "$repo_dir" "add required minimum class fixtures"

  local out
  out="$(run_post_review_dry_run "$repo_dir")"
  assert_new_files_added_equals "$out" "5"
}

test_counts_remaining_baseline_extensions_and_skips_unsupported() {
  local repo_dir="$TMP_ROOT/repo-remaining-baseline"
  setup_post_review_repo "$repo_dir"

  mkdir -p "$repo_dir/src/ts" "$repo_dir/src/js" "$repo_dir/src/cs" "$repo_dir/src/cpp" \
    "$repo_dir/src/php" "$repo_dir/src/ruby" "$repo_dir/src/unsupported"

  cat >"$repo_dir/src/ts/thing.ts" <<'EOF'
export interface TsThing {}
EOF
  cat >"$repo_dir/src/js/thing.js" <<'EOF'
class JsThing {}
EOF
  cat >"$repo_dir/src/js/thing.jsx" <<'EOF'
class JsxThing extends React.Component {}
EOF
  cat >"$repo_dir/src/cs/Thing.cs" <<'EOF'
public record CsThing(int Id);
EOF
  cat >"$repo_dir/src/cpp/thing.cpp" <<'EOF'
class CppThing {};
EOF
  cat >"$repo_dir/src/cpp/thing.cc" <<'EOF'
struct CcThing {};
EOF
  cat >"$repo_dir/src/cpp/thing.cxx" <<'EOF'
class CxxThing {};
EOF
  cat >"$repo_dir/src/cpp/thing.hpp" <<'EOF'
struct HppThing {};
EOF
  cat >"$repo_dir/src/php/thing.php" <<'EOF'
<?php
class PhpThing {}
EOF
  cat >"$repo_dir/src/ruby/thing.rb" <<'EOF'
class RbThing
end
EOF
  cat >"$repo_dir/src/unsupported/thing.swift" <<'EOF'
class SwiftThing {}
EOF

  commit_all "$repo_dir" "add remaining baseline class fixtures"

  local out
  out="$(run_post_review_dry_run "$repo_dir")"
  assert_new_files_added_equals "$out" "11"
}

test_modified_existing_file_is_not_counted() {
  local repo_dir="$TMP_ROOT/repo-modified-not-added"
  setup_post_review_repo "$repo_dir" "1"

  cat >"$repo_dir/src/existing.py" <<'EOF'
class SeedThing:
    pass

class ChangedThing:
    pass
EOF

  commit_all "$repo_dir" "modify existing class file only"

  local out
  out="$(run_post_review_dry_run "$repo_dir")"
  assert_new_files_added_equals "$out" "0"
}

test_working_tree_snapshot_includes_pending_new_files() {
  local repo_dir="$TMP_ROOT/repo-snapshot"
  setup_post_review_repo "$repo_dir"

  mkdir -p "$repo_dir/src/pending"
  cat >"$repo_dir/src/pending/PendingThing.go" <<'EOF'
package pending
type PendingThing struct {}
EOF

  local out
  out="$(run_post_review "$repo_dir")"
  assert_contains "$out" "+ working-tree snapshot"
  assert_contains "$out" "New files added: 1"
  assert_contains "$out" "metrics were already captured"

  local history
  history="$(cat "$repo_dir/ai/history.md")"
  assert_contains "$history" "- New files added: 1"
}

test_help_text_describes_multilang_scope() {
  local repo_dir="$TMP_ROOT/repo-help"
  setup_post_review_repo "$repo_dir"
  local out
  out="$(bash "$repo_dir/.asdlc_worker/scripts/post_review.sh" --help)"
  assert_contains "$out" "New files added (newly created files, excludes .asdlc_worker/**), measured from the same delta."
  assert_contains "$out" "Files touched (modified existing files, excludes .asdlc_worker/**), measured from the same delta."
}

test_counts_required_minimum_extensions
test_counts_remaining_baseline_extensions_and_skips_unsupported
test_modified_existing_file_is_not_counted
test_working_tree_snapshot_includes_pending_new_files
test_help_text_describes_multilang_scope

echo "All post-review metrics tests passed."
