#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR_SRC="$SOURCE_ROOT/ai/scripts/validate_user_review.sh"

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
  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai"

  cp "$VALIDATOR_SRC" "$repo_dir/ai/scripts/validate_user_review.sh"
  chmod +x "$repo_dir/ai/scripts/validate_user_review.sh"

  cat >"$repo_dir/ai/user_review.md" <<'UR'
# User review rules

- **ID**: UR-0001
- **Status**: Accepted
- **Date**: 2026-03-03
- **Context**: Baseline
- **Trigger**: User review updates durable rule bank.
- **Rule**: Keep one canonical rule entry per intent.
- **How to verify**: Confirm required fields and avoid duplicate IDs.
- **Example(s)**: Update existing UR instead of adding a duplicate.
- **References**: `ai/user_review.md`
UR

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
  )
}

append_valid_entry() {
  local file="$1"
  local id="$2"
  local trigger="$3"
  local rule="$4"
  cat >>"$file" <<UR

- **ID**: $id
- **Status**: Accepted
- **Date**: 2026-03-03
- **Context**: Test
- **Trigger**: $trigger
- **Rule**: $rule
- **How to verify**: Run validator and confirm required fields are present.
- **Example(s)**: Use one canonical UR id for one rule intent.
- **References**: ai/user_review.md
UR
}

test_validator_passes_for_valid_new_entry() {
  local repo_dir="$TMP_ROOT/repo-validator-pass"
  setup_repo "$repo_dir"

  append_valid_entry "$repo_dir/ai/user_review.md" "UR-0002" "Validation gate runs after user review changes." "Reject incomplete UR entries."

  local out=""
  out="$(cd "$repo_dir" && ai/scripts/validate_user_review.sh 2>&1)"
  assert_contains "$out" "UR hygiene validation passed"
}

test_validator_fails_on_missing_required_fields() {
  local repo_dir="$TMP_ROOT/repo-validator-missing"
  setup_repo "$repo_dir"

  cat >>"$repo_dir/ai/user_review.md" <<'UR'

- **ID**: UR-0002
- **Status**: Accepted
- **Date**: 2026-03-03
- **Context**: Test
- **Trigger**: Missing fields test.
- **Rule**: New entries must include required fields.
- **Example(s)**: Missing How to verify and References.
UR

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/validate_user_review.sh 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: validator should fail on missing required fields" >&2
    exit 1
  fi
  assert_contains "$out" "missing required fields"
  assert_contains "$out" "How to verify"
  assert_contains "$out" "References"
}

test_validator_fails_on_duplicate_id() {
  local repo_dir="$TMP_ROOT/repo-validator-duplicate"
  setup_repo "$repo_dir"

  append_valid_entry "$repo_dir/ai/user_review.md" "UR-0001" "Duplicate id trigger." "Duplicate ID should fail."

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/validate_user_review.sh 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: validator should fail on duplicate IDs" >&2
    exit 1
  fi
  assert_contains "$out" "Duplicate UR ID detected: UR-0001"
}

test_validator_fails_on_overlap() {
  local repo_dir="$TMP_ROOT/repo-validator-overlap"
  setup_repo "$repo_dir"

  append_valid_entry "$repo_dir/ai/user_review.md" "UR-0002" "User review updates durable rule bank." "Keep one canonical rule entry per intent."

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/validate_user_review.sh 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: validator should fail on overlap" >&2
    exit 1
  fi
  assert_contains "$out" "Overlap detected between UR-0001 and UR-0002"
}

test_validator_passes_for_unchanged_file() {
  local repo_dir="$TMP_ROOT/repo-validator-unchanged"
  setup_repo "$repo_dir"

  local out=""
  out="$(cd "$repo_dir" && ai/scripts/validate_user_review.sh 2>&1)"
  assert_contains "$out" "no new/updated UR entries detected"
}

test_validator_passes_for_valid_new_entry
test_validator_fails_on_missing_required_fields
test_validator_fails_on_duplicate_id
test_validator_fails_on_overlap
test_validator_passes_for_unchanged_file

echo "All user review validator tests passed."
