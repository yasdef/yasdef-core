#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_PLAN_SRC="$SOURCE_ROOT/ai/scripts/ai_plan.sh"
PROCESS_SRC="$SOURCE_ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
TEMPLATE_SRC="$SOURCE_ROOT/ai/templates/step_plan_TEMPLATE.md"

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

setup_repo() {
  local repo_dir="$1"

  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/step_designs" "$repo_dir/ai/step_plans" "$repo_dir/ai/templates"
  cp "$AI_PLAN_SRC" "$repo_dir/ai/scripts/ai_plan.sh"
  cp "$PROCESS_SRC" "$repo_dir/ai/AI_DEVELOPMENT_PROCESS.md"
  cp "$TEMPLATE_SRC" "$repo_dir/ai/templates/step_plan_TEMPLATE.md"
  chmod +x "$repo_dir/ai/scripts/ai_plan.sh"

  cat >"$repo_dir/ai/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [ ] Plan and discuss the step. [REQ-1]
- [ ] Implement the feature endpoint. [REQ-1]
- [ ] Review step implementation.
EOF

  cat >"$repo_dir/ai/step_designs/step-1.1-design.md" <<'EOF'
## Target Bullets
- Implement the feature endpoint.

## Applicable AGENTS.md Constraints
- Follow AGENTS.md constraints relevant to this step.

## Applicable UR Shortlist
- UR-0001 - Keep behavior deterministic.

## Applicable ADR Shortlist
- ADR-0001 - Preserve existing API contract.
EOF

  cat >"$repo_dir/ai/open_questions.md" <<'EOF'
## Step 1.1 Demo
- No open questions.
EOF

  cat >"$repo_dir/ai/blocker_log.md" <<'EOF'
## Step 1.1 Demo
- No blockers.
EOF

  cat >"$repo_dir/ai/decisions.md" <<'EOF'
## ADR-0001 - Baseline
- **Status**: Accepted
EOF

  cat >"$repo_dir/reqirements_ears.md" <<'EOF'
### Requirement 1 API behavior
- Endpoint returns deterministic response.
EOF

  cat >"$repo_dir/AGENTS.md" <<'EOF'
Project constraints placeholder.
EOF

  (
    cd "$repo_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add .
    git commit -qm "seed"
  )
}

write_step_plan_with_shortlist() {
  local repo_dir="$1"
  local shortlist="$2"
  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<EOF
# Step Plan: 1.1 - Demo
Date: 2026-02-27
Planner model/session: test
Execution model/session (intended): test

## Target Bullets
- Implement the feature endpoint.

## Design Anchor (scope source of truth)
- Feature design: \`ai/step_designs/step-1.1-design.md\`

## Requirement Tags
- REQ-1

## Applicable UR Shortlist
$shortlist

## Plan (ordered)
- 1. Implement endpoint.

## Implementation Notes / Constraints
- Follow AGENTS.md.

## Tests
- Add tests.

## Docs / Artifacts
- None.

## Risks / Edge Cases
- None.

## Decisions Needed
- None.
EOF
}

write_step_plan_missing_shortlist_section() {
  local repo_dir="$1"
  cat >"$repo_dir/ai/step_plans/step-1.1.md" <<'EOF'
# Step Plan: 1.1 - Demo
Date: 2026-02-27
Planner model/session: test
Execution model/session (intended): test

## Target Bullets
- Implement the feature endpoint.

## Design Anchor (scope source of truth)
- Feature design: `ai/step_designs/step-1.1-design.md`

## Requirement Tags
- REQ-1

## Plan (ordered)
- 1. Implement endpoint.
EOF
}

run_plan_capture() {
  local repo_dir="$1"
  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && ai/scripts/ai_plan.sh --step 1.1 --out ai/step_plans/step-1.1.md 2>&1)"
  status=$?
  set -e
  printf '%s\n%s' "$status" "$out"
}

test_missing_shortlist_section_fails_fast() {
  local repo_dir="$TMP_ROOT/repo-missing-shortlist"
  setup_repo "$repo_dir"
  write_step_plan_missing_shortlist_section "$repo_dir"

  local result status out
  result="$(run_plan_capture "$repo_dir")"
  status="$(printf '%s' "$result" | sed -n '1p')"
  out="$(printf '%s' "$result" | sed -n '2,$p')"

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: expected missing shortlist section to fail." >&2
    exit 1
  fi
  assert_contains "$out" "Planning gate failed for step plan: missing section"
  assert_contains "$out" "Required section: ## Applicable UR Shortlist"
  assert_not_contains "$out" "Planning phase for Step 1.1."
}

test_canonical_none_is_accepted() {
  local repo_dir="$TMP_ROOT/repo-canonical-none"
  setup_repo "$repo_dir"
  write_step_plan_with_shortlist "$repo_dir" "- None."

  local result status out
  result="$(run_plan_capture "$repo_dir")"
  status="$(printf '%s' "$result" | sed -n '1p')"
  out="$(printf '%s' "$result" | sed -n '2,$p')"

  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: expected canonical - None. to pass." >&2
    echo "$out" >&2
    exit 1
  fi
  assert_contains "$out" "Planning phase for Step 1.1."
}

test_curated_ur_ids_are_accepted() {
  local repo_dir="$TMP_ROOT/repo-curated-ids"
  setup_repo "$repo_dir"
  write_step_plan_with_shortlist "$repo_dir" $'- UR-0001 - Keep behavior deterministic.\n- UR-0007 - Avoid fallback parsing.'

  local result status out
  result="$(run_plan_capture "$repo_dir")"
  status="$(printf '%s' "$result" | sed -n '1p')"
  out="$(printf '%s' "$result" | sed -n '2,$p')"

  if [[ "$status" -ne 0 ]]; then
    echo "Assertion failed: expected curated UR list to pass." >&2
    echo "$out" >&2
    exit 1
  fi
  assert_contains "$out" "Planning phase for Step 1.1."
}

test_non_canonical_content_is_rejected() {
  local repo_dir="$TMP_ROOT/repo-invalid-shortlist"
  setup_repo "$repo_dir"
  write_step_plan_with_shortlist "$repo_dir" $'- None applicable.\n- Keep it simple.'

  local result status out
  result="$(run_plan_capture "$repo_dir")"
  status="$(printf '%s' "$result" | sed -n '1p')"
  out="$(printf '%s' "$result" | sed -n '2,$p')"

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: expected invalid shortlist content to fail." >&2
    exit 1
  fi
  assert_contains "$out" "invalid shortlist entry"
  assert_contains "$out" "exact: - None."
}

test_ur_cap_overflow_is_rejected() {
  local repo_dir="$TMP_ROOT/repo-cap-overflow"
  setup_repo "$repo_dir"
  write_step_plan_with_shortlist "$repo_dir" $'- UR-0001\n- UR-0002\n- UR-0003\n- UR-0004\n- UR-0005\n- UR-0006\n- UR-0007\n- UR-0008\n- UR-0009'

  local result status out
  result="$(run_plan_capture "$repo_dir")"
  status="$(printf '%s' "$result" | sed -n '1p')"
  out="$(printf '%s' "$result" | sed -n '2,$p')"

  if [[ "$status" -eq 0 ]]; then
    echo "Assertion failed: expected shortlist cap overflow to fail." >&2
    exit 1
  fi
  assert_contains "$out" "too many UR IDs (9). Prioritize to 8 or fewer IDs."
}

test_missing_shortlist_section_fails_fast
test_canonical_none_is_accepted
test_curated_ur_ids_are_accepted
test_non_canonical_content_is_rejected
test_ur_cap_overflow_is_rejected

echo "All ai_plan UR shortlist gate tests passed."
