#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLAN_SKILL_DIR="$SOURCE_ROOT/ai/codex/skills/yasdef-worker-plan"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export UV_CACHE_DIR="$TMP_ROOT/uv-cache"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Assertion failed: expected output to contain: $needle" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"

  mkdir -p \
    "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" \
    "$repo_dir/.asdlc_worker/step_open_questions" \
    "$repo_dir/.asdlc_worker/step_blockers" \
    "$repo_dir/.codex/skills"
  cp -R "$PLAN_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-plan"

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-demo-design.md" <<'EOF'
## Selected EARS Requirements (for planning translation)
### Requirement 1 Demo
- The system SHALL implement the feature endpoint behavior deterministically.

## Things to Decide (for final planning discussion)
- Adapter strategy: keep adapter A or switch to adapter B.
EOF
}

write_step_plan() {
  local repo_dir="$1"
  local shortlist="$2"
  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<EOF
# Step Plan: 1.1 - Demo
## Applicable UR Shortlist
$shortlist
## Plan (ordered)
- [ ] 1. Implement endpoint.
## Functional Requirements (translated from design EARS)
- [ ] FR-1.1-001 The system SHALL implement the feature endpoint behavior deterministically. EARS[REQ-1]
## Decisions Needed
- Adapter strategy | Accepted | Keep adapter A.
EOF
}

run_helper_capture() {
  local repo_dir="$1"
  local status=0
  local out=""
  set +e
  out="$(
    cd "$repo_dir" &&
    uv run python ".codex/skills/yasdef-worker-plan/scripts/check_planning_readiness.py" \
      --design ".asdlc_worker/step_designs/step-1.1-demo-design.md" \
      --step-plan ".asdlc_worker/step_plans/step-1.1-demo.md" \
      --open-questions ".asdlc_worker/step_open_questions/step-1.1-demo-open-questions.md" \
      --blockers ".asdlc_worker/step_blockers/step-1.1-demo-blockers.md" 2>&1
  )"
  status=$?
  set -e
  printf '%s\n%s' "$status" "$out"
}

test_canonical_none_is_accepted() {
  local repo_dir="$TMP_ROOT/repo-canonical-none"
  setup_repo "$repo_dir"
  write_step_plan "$repo_dir" "- None."

  local result status out
  result="$(run_helper_capture "$repo_dir")"
  status="$(printf '%s' "$result" | sed -n '1p')"
  out="$(printf '%s' "$result" | sed -n '2,$p')"

  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: expected canonical - None. to pass." >&2
    echo "$out" >&2
    exit 1
  fi
  assert_contains "$out" '"ready": true'
}

test_curated_ur_ids_are_accepted() {
  local repo_dir="$TMP_ROOT/repo-curated-ids"
  setup_repo "$repo_dir"
  write_step_plan "$repo_dir" $'- UR-0001 - Keep behavior deterministic.\n- UR-0007 - Avoid fallback parsing.'

  local result status out
  result="$(run_helper_capture "$repo_dir")"
  status="$(printf '%s' "$result" | sed -n '1p')"
  out="$(printf '%s' "$result" | sed -n '2,$p')"

  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: expected curated UR list to pass." >&2
    echo "$out" >&2
    exit 1
  fi
  assert_contains "$out" '"ready": true'
}

test_non_canonical_content_is_rejected() {
  local repo_dir="$TMP_ROOT/repo-invalid-shortlist"
  setup_repo "$repo_dir"
  write_step_plan "$repo_dir" $'- None applicable.\n- Keep it simple.'

  local result status out
  result="$(run_helper_capture "$repo_dir")"
  status="$(printf '%s' "$result" | sed -n '1p')"
  out="$(printf '%s' "$result" | sed -n '2,$p')"

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: expected invalid shortlist content to fail." >&2
    exit 1
  fi
  assert_contains "$out" "shortlist entry missing UR-xxxx id"
}

test_ur_cap_overflow_is_rejected() {
  local repo_dir="$TMP_ROOT/repo-cap-overflow"
  setup_repo "$repo_dir"
  write_step_plan "$repo_dir" $'- UR-0001\n- UR-0002\n- UR-0003\n- UR-0004\n- UR-0005\n- UR-0006\n- UR-0007\n- UR-0008\n- UR-0009'

  local result status out
  result="$(run_helper_capture "$repo_dir")"
  status="$(printf '%s' "$result" | sed -n '1p')"
  out="$(printf '%s' "$result" | sed -n '2,$p')"

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: expected shortlist cap overflow to fail." >&2
    exit 1
  fi
  assert_contains "$out" "Applicable UR Shortlist contains 9 UR ids; max is 8"
}

test_canonical_none_is_accepted
test_curated_ur_ids_are_accepted
test_non_canonical_content_is_rejected
test_ur_cap_overflow_is_rejected

echo "All ai_plan UR shortlist gate tests passed."
