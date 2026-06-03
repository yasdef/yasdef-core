#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_DIR="$SOURCE_ROOT/ai/skills/yasdef-worker-ai-audit"
ENTRY_SCRIPT="$SKILL_DIR/scripts/check_ai_audit_entry.py"
BUILD_CONTEXT="$SKILL_DIR/scripts/build_ai_audit_context.py"
CHECK_CLOSURE="$SKILL_DIR/scripts/check_ai_audit_closure.py"
APPEND_FOLLOW_UP="$SKILL_DIR/scripts/append_follow_up_step.py"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export UV_CACHE_DIR="$TMP_ROOT/uv-cache"

WORKER_ID="worker-42"
FEATURE_ID="feat-a"
STEP="1.6"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Assertion failed: expected output to contain: $needle" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "Assertion failed: expected output not to contain: $needle" >&2
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

# Build a worker repo whose ABSOLUTE path itself contains "projects/" so we
# exercise the right-most match in derive_asdlc_repo_root.
new_repo() {
  local label="$1"
  local repo_dir="$TMP_ROOT/projects/host-area/$label"
  mkdir -p "$repo_dir/.asdlc_worker/step_plans" \
           "$repo_dir/.asdlc_worker/step_designs" \
           "$repo_dir/.asdlc_worker/step_review_results"
  ( cd "$repo_dir" && git init -q && git checkout -q -b main )
  printf '%s\n' "$repo_dir"
}

seed_step_plan() {
  local repo_dir="$1"
  cat >"$repo_dir/.asdlc_worker/step_plans/step-$STEP-$FEATURE_ID.md" <<'EOF'
# Plan
- bullet
EOF
}

seed_design() {
  local repo_dir="$1"
  local title="${2:-Feature Design: $STEP - sample}"
  cat >"$repo_dir/.asdlc_worker/step_designs/step-$STEP-$FEATURE_ID-design.md" <<EOF
# $title

## Target Bullets (excluding planning/review)
- [ ] do thing one

## Selected EARS Requirements (for planning translation)
- WHEN x, THE system SHALL y.

## Goal
- goal text

## In Scope
- in scope text

## Out of Scope
- out of scope text

## Linked Artifacts (in scope)
- None.
EOF
}

seed_user_review_branch() {
  local repo_dir="$1"
  ( cd "$repo_dir" \
      && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
      && git checkout -q -b "step-$STEP-$FEATURE_ID-user-review" \
      && git checkout -q main )
}

seed_asdlc_repo() {
  local repo_dir="$1"
  local feature_dir="$repo_dir/asdlc-side/projects/proj-a/$FEATURE_ID"
  mkdir -p "$feature_dir"
  cat >"$feature_dir/implementation_plan.md" <<EOF
# Plan

### Step $STEP Demo [REQ-1]
#### Assigned: $WORKER_ID
- [ ] do thing one
- [ ] do thing two
EOF
  printf '%s\n' "$feature_dir/implementation_plan.md"
}

seed_asdlc_repo_with_repo_heading() {
  # Variant for append_follow_up_step tests: parent step carries #### Repo:.
  local repo_dir="$1" repo_value="${2:-backend}"
  local feature_dir="$repo_dir/asdlc-side/projects/proj-a/$FEATURE_ID"
  mkdir -p "$feature_dir"
  cat >"$feature_dir/implementation_plan.md" <<EOF
# Plan

### Step $STEP Demo [REQ-1]
#### Repo: $repo_value
#### Assigned: $WORKER_ID
- [ ] do thing one
- [ ] do thing two
EOF
  printf '%s\n' "$feature_dir/implementation_plan.md"
}

seed_review_result() {
  local repo_dir="$1"
  local body="$2"
  local path="$repo_dir/.asdlc_worker/step_review_results/review_result-$STEP-$FEATURE_ID.md"
  printf '%s\n' "$body" >"$path"
  printf '%s\n' "$path"
}

mark_step_bullets_x() {
  local plan_path="$1"
  # Mark every "- [ ]" → "- [x]" inside the file (test setup helper).
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' 's/- \[ \]/- [x]/g' "$plan_path"
  else
    sed -i 's/- \[ \]/- [x]/g' "$plan_path"
  fi
}

# ─── Entry gate tests ───────────────────────────────────────────────────────

test_entry_gate_all_present() {
  local repo_dir
  repo_dir="$(new_repo entry_pass)"
  seed_step_plan "$repo_dir"
  seed_design "$repo_dir"
  seed_user_review_branch "$repo_dir"

  local out status
  out="$(cd "$repo_dir" && uv run python "$ENTRY_SCRIPT" --step "$STEP" --feature-id "$FEATURE_ID" 2>&1)"
  status=$?
  assert_status 0 "$status"
  assert_contains "$out" "OK: ai_audit entry preconditions passed"
}

test_entry_gate_missing_step_plan() {
  local repo_dir
  repo_dir="$(new_repo entry_no_plan)"
  seed_design "$repo_dir"
  seed_user_review_branch "$repo_dir"

  local out status
  out="$(cd "$repo_dir" && uv run python "$ENTRY_SCRIPT" --step "$STEP" --feature-id "$FEATURE_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "MISSING: step plan"
}

test_entry_gate_missing_design() {
  local repo_dir
  repo_dir="$(new_repo entry_no_design)"
  seed_step_plan "$repo_dir"
  seed_user_review_branch "$repo_dir"

  local out status
  out="$(cd "$repo_dir" && uv run python "$ENTRY_SCRIPT" --step "$STEP" --feature-id "$FEATURE_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "MISSING: design artifact"
}

test_entry_gate_missing_user_review_branch() {
  local repo_dir
  repo_dir="$(new_repo entry_no_branch)"
  seed_step_plan "$repo_dir"
  seed_design "$repo_dir"
  ( cd "$repo_dir" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )

  local out status
  out="$(cd "$repo_dir" && uv run python "$ENTRY_SCRIPT" --step "$STEP" --feature-id "$FEATURE_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "MISSING: user_review branch"
}

# ─── Context builder tests ─────────────────────────────────────────────────

test_builder_happy_path_emits_required_sections() {
  local repo_dir plan_path
  repo_dir="$(new_repo builder_happy)"
  seed_step_plan "$repo_dir"
  seed_design "$repo_dir"
  plan_path="$(seed_asdlc_repo "$repo_dir")"

  local design="$repo_dir/.asdlc_worker/step_designs/step-$STEP-$FEATURE_ID-design.md"
  local out status
  out="$(cd "$repo_dir" && uv run python "$BUILD_CONTEXT" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --design "$design" --runtime-plan "$plan_path" \
    --worker-id "$WORKER_ID")" && status=$? || status=$?
  assert_status 0 "$status"
  assert_contains "$out" "# YASDEF AI Audit Context: Step $STEP"
  assert_contains "$out" "## Target Bullets (excluding planning/review)"
  assert_contains "$out" "## Selected EARS Requirements (for planning translation)"
  assert_contains "$out" "## Goal"
  assert_contains "$out" "## In Scope"
  assert_contains "$out" "## Out of Scope"
  assert_contains "$out" "## Linked Artifacts (in scope)"
  assert_contains "$out" "Worker id: $WORKER_ID"
  assert_contains "$out" "asdlc_repo_path:"
  assert_contains "$out" "Raised questions directory (ASDLC repo): $repo_dir/asdlc-side/projects/proj-a/$FEATURE_ID/raised_questions"
  # Builder must not surface design sections that are explicitly excluded.
  assert_not_contains "$out" "## Risks and Mitigations"
  assert_not_contains "$out" "## Proposal / Design Details"
}

test_builder_rejects_filename_feature_mismatch() {
  local repo_dir plan_path
  repo_dir="$(new_repo builder_filename)"
  seed_step_plan "$repo_dir"
  seed_design "$repo_dir"
  plan_path="$(seed_asdlc_repo "$repo_dir")"

  cp "$repo_dir/.asdlc_worker/step_designs/step-$STEP-$FEATURE_ID-design.md" \
     "$repo_dir/.asdlc_worker/step_designs/step-$STEP-other-feat-design.md"

  local out status
  out="$(cd "$repo_dir" && uv run python "$BUILD_CONTEXT" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --design "$repo_dir/.asdlc_worker/step_designs/step-$STEP-other-feat-design.md" \
    --runtime-plan "$plan_path" \
    --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "EXPECTED design filename"
}

test_builder_rejects_title_without_step() {
  local repo_dir plan_path
  repo_dir="$(new_repo builder_title)"
  seed_step_plan "$repo_dir"
  seed_design "$repo_dir" "Feature Design: unrelated title"
  plan_path="$(seed_asdlc_repo "$repo_dir")"

  local design="$repo_dir/.asdlc_worker/step_designs/step-$STEP-$FEATURE_ID-design.md"
  local out status
  out="$(cd "$repo_dir" && uv run python "$BUILD_CONTEXT" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --design "$design" --runtime-plan "$plan_path" \
    --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "EXPECTED design title to include step $STEP"
}

test_builder_word_boundary_step_in_title() {
  # Title contains "11.6" but step is "1.6" — must reject.
  local repo_dir plan_path
  repo_dir="$(new_repo builder_word_boundary)"
  seed_step_plan "$repo_dir"
  seed_design "$repo_dir" "Feature Design: 11.6 - confusable"
  plan_path="$(seed_asdlc_repo "$repo_dir")"

  local design="$repo_dir/.asdlc_worker/step_designs/step-$STEP-$FEATURE_ID-design.md"
  local out status
  out="$(cd "$repo_dir" && uv run python "$BUILD_CONTEXT" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --design "$design" --runtime-plan "$plan_path" \
    --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "EXPECTED design title to include step $STEP"
}

test_builder_derives_asdlc_root_with_projects_in_host_path() {
  # new_repo seeds repos under $TMP_ROOT/projects/host-area/ — the very trap
  # that broke the previous derive_asdlc_repo_root implementation.
  local repo_dir plan_path
  repo_dir="$(new_repo builder_host_projects)"
  seed_step_plan "$repo_dir"
  seed_design "$repo_dir"
  plan_path="$(seed_asdlc_repo "$repo_dir")"

  local design="$repo_dir/.asdlc_worker/step_designs/step-$STEP-$FEATURE_ID-design.md"
  # derive_asdlc_repo_root canonicalizes via .resolve(); the raised-questions
  # path is built from the unresolved runtime-plan input. Build both forms.
  local resolved_root unresolved_root
  resolved_root="$(cd "$repo_dir/asdlc-side" && pwd -P)"
  unresolved_root="$repo_dir/asdlc-side"
  local out status
  out="$(cd "$repo_dir" && uv run python "$BUILD_CONTEXT" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --design "$design" --runtime-plan "$plan_path" \
    --worker-id "$WORKER_ID")" && status=$? || status=$?
  assert_status 0 "$status"
  assert_contains "$out" "asdlc_repo_path: $resolved_root"
  assert_contains "$out" "Raised questions directory (ASDLC repo): $unresolved_root/projects/proj-a/$FEATURE_ID/raised_questions"
}

test_builder_rejects_runtime_plan_with_wrong_layout() {
  local repo_dir
  repo_dir="$(new_repo builder_layout)"
  seed_step_plan "$repo_dir"
  seed_design "$repo_dir"
  printf '# Plan\n' >"$repo_dir/bogus.md"

  local design="$repo_dir/.asdlc_worker/step_designs/step-$STEP-$FEATURE_ID-design.md"
  local out status
  out="$(cd "$repo_dir" && uv run python "$BUILD_CONTEXT" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --design "$design" --runtime-plan "$repo_dir/bogus.md" \
    --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "runtime plan must point at"
}

# ─── Closure check tests ───────────────────────────────────────────────────

closure_review_body_with_finding() {
  local finding_state="$1"
  cat <<EOF
### F-01
- Severity: High
- Disposition state:
$finding_state
EOF
}

test_closure_happy_path() {
  local repo_dir plan_path
  repo_dir="$(new_repo closure_happy)"
  plan_path="$(seed_asdlc_repo "$repo_dir")"
  mark_step_bullets_x "$plan_path"
  seed_review_result "$repo_dir" "$(closure_review_body_with_finding "$(printf '  - [x] rejected: false positive\n  - [ ] follow_up_created:\n  - [ ] raised_to_coordinator:')")" >/dev/null

  local out status
  out="$(cd "$repo_dir" && uv run python "$CHECK_CLOSURE" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --runtime-plan "$plan_path" --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 0 "$status"
  assert_contains "$out" "OK: ai_audit closure check passed"
}

test_closure_missing_disposition() {
  local repo_dir plan_path
  repo_dir="$(new_repo closure_missing)"
  plan_path="$(seed_asdlc_repo "$repo_dir")"
  mark_step_bullets_x "$plan_path"
  seed_review_result "$repo_dir" "$(closure_review_body_with_finding "$(printf '  - [ ] rejected:\n  - [ ] follow_up_created:\n  - [ ] raised_to_coordinator:')")" >/dev/null

  local out status
  out="$(cd "$repo_dir" && uv run python "$CHECK_CLOSURE" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --runtime-plan "$plan_path" --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "ERROR: Disposition phase needed"
  assert_contains "$out" "F-01"
}

test_closure_conflicting_disposition() {
  local repo_dir plan_path
  repo_dir="$(new_repo closure_conflict)"
  plan_path="$(seed_asdlc_repo "$repo_dir")"
  mark_step_bullets_x "$plan_path"
  seed_review_result "$repo_dir" "$(closure_review_body_with_finding "$(printf "  - [x] rejected: a\n  - [x] follow_up_created: %sa\n  - [ ] raised_to_coordinator:" "$STEP")")" >/dev/null

  local out status
  out="$(cd "$repo_dir" && uv run python "$CHECK_CLOSURE" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --runtime-plan "$plan_path" --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "ERROR: Conflicting disposition state"
}

test_closure_missing_follow_up_step() {
  local repo_dir plan_path
  repo_dir="$(new_repo closure_no_followup)"
  plan_path="$(seed_asdlc_repo "$repo_dir")"
  mark_step_bullets_x "$plan_path"
  seed_review_result "$repo_dir" "$(closure_review_body_with_finding "$(printf "  - [ ] rejected:\n  - [x] follow_up_created: %sa\n  - [ ] raised_to_coordinator:" "$STEP")")" >/dev/null

  local out status
  out="$(cd "$repo_dir" && uv run python "$CHECK_CLOSURE" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --runtime-plan "$plan_path" --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "ERROR: Missing follow-up step"
  assert_contains "$out" "expected: ### Step ${STEP}a"
}

test_closure_missing_raised_question_file() {
  local repo_dir plan_path
  repo_dir="$(new_repo closure_no_raised)"
  plan_path="$(seed_asdlc_repo "$repo_dir")"
  mark_step_bullets_x "$plan_path"
  local raised_ref="projects/proj-a/$FEATURE_ID/raised_questions/$STEP-$WORKER_ID-F01.md"
  seed_review_result "$repo_dir" "$(closure_review_body_with_finding "$(printf '  - [ ] rejected:\n  - [ ] follow_up_created:\n  - [x] raised_to_coordinator: %s' "$raised_ref")")" >/dev/null

  local out status
  out="$(cd "$repo_dir" && uv run python "$CHECK_CLOSURE" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --runtime-plan "$plan_path" --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "ERROR: Missing raised-question file"
  assert_contains "$out" "$raised_ref"
}

test_closure_target_bullets_not_marked() {
  local repo_dir plan_path
  repo_dir="$(new_repo closure_bullets)"
  plan_path="$(seed_asdlc_repo "$repo_dir")"
  # Leave current-step bullets [ ] on purpose.
  seed_review_result "$repo_dir" "$(closure_review_body_with_finding "$(printf '  - [x] rejected: ok\n  - [ ] follow_up_created:\n  - [ ] raised_to_coordinator:')")" >/dev/null

  local out status
  out="$(cd "$repo_dir" && uv run python "$CHECK_CLOSURE" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --runtime-plan "$plan_path" --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "ERROR: Target bullets not marked"
  assert_contains "$out" "do thing one"
}

test_closure_word_boundary_does_not_match_letter_suffix() {
  # Plan only has Step "1.6a"; running closure for "1.6" must report the
  # current step section as missing, NOT mistakenly bind to 1.6a.
  local repo_dir feature_dir plan_path
  repo_dir="$(new_repo closure_word_boundary)"
  feature_dir="$repo_dir/asdlc-side/projects/proj-a/$FEATURE_ID"
  mkdir -p "$feature_dir"
  plan_path="$feature_dir/implementation_plan.md"
  cat >"$plan_path" <<EOF
# Plan

### Step ${STEP}a Follow-up [REQ-1]
#### Assigned: $WORKER_ID
- [x] follow-up done
EOF
  seed_review_result "$repo_dir" "$(closure_review_body_with_finding "$(printf '  - [x] rejected: ok\n  - [ ] follow_up_created:\n  - [ ] raised_to_coordinator:')")" >/dev/null

  local out status
  out="$(cd "$repo_dir" && uv run python "$CHECK_CLOSURE" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --runtime-plan "$plan_path" --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "Current step section \`### Step $STEP\` not found"
}

test_closure_no_findings() {
  local repo_dir plan_path
  repo_dir="$(new_repo closure_no_findings)"
  plan_path="$(seed_asdlc_repo "$repo_dir")"
  mark_step_bullets_x "$plan_path"
  seed_review_result "$repo_dir" "# Empty" >/dev/null

  local out status
  out="$(cd "$repo_dir" && uv run python "$CHECK_CLOSURE" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --runtime-plan "$plan_path" --worker-id "$WORKER_ID" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "ERROR: Disposition phase needed"
}

test_closure_errors_go_to_stderr() {
  local repo_dir plan_path stdout_only stderr_only
  repo_dir="$(new_repo closure_stderr)"
  plan_path="$(seed_asdlc_repo "$repo_dir")"
  mark_step_bullets_x "$plan_path"
  seed_review_result "$repo_dir" "$(closure_review_body_with_finding "$(printf '  - [ ] rejected:\n  - [ ] follow_up_created:\n  - [ ] raised_to_coordinator:')")" >/dev/null

  local tmp_out="$TMP_ROOT/stdout.txt"
  local tmp_err="$TMP_ROOT/stderr.txt"
  ( cd "$repo_dir" && uv run python "$CHECK_CLOSURE" \
    --step "$STEP" --feature-id "$FEATURE_ID" \
    --runtime-plan "$plan_path" --worker-id "$WORKER_ID" \
    >"$tmp_out" 2>"$tmp_err" ) || true
  stdout_only="$(cat "$tmp_out")"
  stderr_only="$(cat "$tmp_err")"
  assert_not_contains "$stdout_only" "ERROR: Disposition phase needed"
  assert_contains "$stderr_only" "ERROR: Disposition phase needed"
}

# ─── append_follow_up_step tests ───────────────────────────────────────────

test_append_follow_up_happy_path() {
  local repo_dir plan_path
  repo_dir="$(new_repo append_happy)"
  plan_path="$(seed_asdlc_repo_with_repo_heading "$repo_dir" "backend")"

  local out status
  out="$(cd "$repo_dir" && uv run python "$APPEND_FOLLOW_UP" \
    --runtime-plan "$plan_path" --parent-step "$STEP" \
    --worker-id "$WORKER_ID" \
    --title "Remove unapproved Lombok dependency" \
    --bullet "Replace Lombok annotations with explicit accessors" \
    --bullet "Remove org.projectlombok:lombok from pom.xml" 2>&1)" && status=$? || status=$?
  assert_status 0 "$status"
  assert_contains "$out" "${STEP}a"

  local plan_text
  plan_text="$(cat "$plan_path")"
  assert_contains "$plan_text" "### Step ${STEP}a Remove unapproved Lombok dependency"
  assert_contains "$plan_text" "#### Assigned: $WORKER_ID"
  assert_contains "$plan_text" "#### Repo: backend"
  assert_contains "$plan_text" "#### Depends on: $STEP"
  assert_contains "$plan_text" "- [ ] Plan and discuss the step."
  assert_contains "$plan_text" "- [ ] Replace Lombok annotations with explicit accessors"
  assert_contains "$plan_text" "- [ ] Remove org.projectlombok:lombok from pom.xml"
  assert_contains "$plan_text" "- [ ] Review step implementation."
}

test_append_follow_up_parent_missing() {
  local repo_dir plan_path
  repo_dir="$(new_repo append_no_parent)"
  plan_path="$(seed_asdlc_repo_with_repo_heading "$repo_dir" "backend")"

  local out status
  out="$(cd "$repo_dir" && uv run python "$APPEND_FOLLOW_UP" \
    --runtime-plan "$plan_path" --parent-step "9.9" \
    --worker-id "$WORKER_ID" \
    --title "Anything" \
    --bullet "Some action" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "parent step \`### Step 9.9\` not found"
}

test_append_follow_up_parent_missing_repo() {
  local repo_dir plan_path
  repo_dir="$(new_repo append_no_repo)"
  plan_path="$(seed_asdlc_repo "$repo_dir")"  # uses fixture WITHOUT #### Repo:

  local out status
  out="$(cd "$repo_dir" && uv run python "$APPEND_FOLLOW_UP" \
    --runtime-plan "$plan_path" --parent-step "$STEP" \
    --worker-id "$WORKER_ID" \
    --title "Anything" \
    --bullet "Some action" 2>&1)" && status=$? || status=$?
  assert_status 1 "$status"
  assert_contains "$out" "has no \`#### Repo:\` heading"
}

test_append_follow_up_picks_next_letter() {
  local repo_dir plan_path
  repo_dir="$(new_repo append_next_letter)"
  plan_path="$(seed_asdlc_repo_with_repo_heading "$repo_dir" "backend")"

  # First call → expect "a"
  local first_out
  first_out="$(cd "$repo_dir" && uv run python "$APPEND_FOLLOW_UP" \
    --runtime-plan "$plan_path" --parent-step "$STEP" \
    --worker-id "$WORKER_ID" --title "First" --bullet "x")"
  assert_contains "$first_out" "${STEP}a"

  # Second call → expect "b" (a is now taken)
  local second_out
  second_out="$(cd "$repo_dir" && uv run python "$APPEND_FOLLOW_UP" \
    --runtime-plan "$plan_path" --parent-step "$STEP" \
    --worker-id "$WORKER_ID" --title "Second" --bullet "y")"
  assert_contains "$second_out" "${STEP}b"

  local plan_text
  plan_text="$(cat "$plan_path")"
  assert_contains "$plan_text" "### Step ${STEP}a First"
  assert_contains "$plan_text" "### Step ${STEP}b Second"
}

test_append_follow_up_inserts_before_next_step() {
  # Parent (Step $STEP) is followed by Step 9.9. New block must land between
  # them, not at end of file.
  local repo_dir plan_path
  repo_dir="$(new_repo append_insertion)"
  plan_path="$(seed_asdlc_repo_with_repo_heading "$repo_dir" "backend")"
  cat >>"$plan_path" <<EOF

### Step 9.9 Tail Step
#### Repo: backend
#### Assigned: other
- [ ] tail bullet
EOF

  ( cd "$repo_dir" && uv run python "$APPEND_FOLLOW_UP" \
    --runtime-plan "$plan_path" --parent-step "$STEP" \
    --worker-id "$WORKER_ID" --title "Inserted" --bullet "do it" >/dev/null )

  # Verify ordering: parent → new step → tail step.
  local order_check
  order_check="$(grep -nE '^### Step ' "$plan_path")"
  assert_contains "$order_check" "### Step $STEP Demo"
  assert_contains "$order_check" "### Step ${STEP}a Inserted"
  assert_contains "$order_check" "### Step 9.9 Tail Step"

  local parent_line new_line tail_line
  parent_line=$(grep -n "^### Step $STEP Demo" "$plan_path" | head -1 | cut -d: -f1)
  new_line=$(grep -n "^### Step ${STEP}a Inserted" "$plan_path" | head -1 | cut -d: -f1)
  tail_line=$(grep -n "^### Step 9.9 Tail Step" "$plan_path" | head -1 | cut -d: -f1)
  if ! (( parent_line < new_line && new_line < tail_line )); then
    echo "Assertion failed: expected parent<new<tail, got $parent_line $new_line $tail_line" >&2
    cat "$plan_path" >&2
    exit 1
  fi
}

test_append_follow_up_requires_bullet() {
  local repo_dir plan_path
  repo_dir="$(new_repo append_no_bullet)"
  plan_path="$(seed_asdlc_repo_with_repo_heading "$repo_dir" "backend")"

  local out status
  out="$(cd "$repo_dir" && uv run python "$APPEND_FOLLOW_UP" \
    --runtime-plan "$plan_path" --parent-step "$STEP" \
    --worker-id "$WORKER_ID" --title "Anything" 2>&1)" && status=$? || status=$?
  # argparse exits 2 when a required arg is missing.
  if [[ "$status" -ne 2 ]]; then
    echo "Assertion failed: expected exit 2 for missing --bullet, got $status" >&2
    echo "$out" >&2
    exit 1
  fi
  assert_contains "$out" "--bullet"
}

# ─── Runner ────────────────────────────────────────────────────────────────

run_test() {
  local name="$1"
  printf '  - %s ... ' "$name"
  if ( "$name" ); then
    printf 'ok\n'
  else
    printf 'FAIL\n'
    exit 1
  fi
}

main() {
  echo "yasdef-worker-ai-audit tests"
  run_test test_entry_gate_all_present
  run_test test_entry_gate_missing_step_plan
  run_test test_entry_gate_missing_design
  run_test test_entry_gate_missing_user_review_branch
  run_test test_builder_happy_path_emits_required_sections
  run_test test_builder_rejects_filename_feature_mismatch
  run_test test_builder_rejects_title_without_step
  run_test test_builder_word_boundary_step_in_title
  run_test test_builder_derives_asdlc_root_with_projects_in_host_path
  run_test test_builder_rejects_runtime_plan_with_wrong_layout
  run_test test_closure_happy_path
  run_test test_closure_missing_disposition
  run_test test_closure_conflicting_disposition
  run_test test_closure_missing_follow_up_step
  run_test test_closure_missing_raised_question_file
  run_test test_closure_target_bullets_not_marked
  run_test test_closure_word_boundary_does_not_match_letter_suffix
  run_test test_closure_no_findings
  run_test test_closure_errors_go_to_stderr
  run_test test_append_follow_up_happy_path
  run_test test_append_follow_up_parent_missing
  run_test test_append_follow_up_parent_missing_repo
  run_test test_append_follow_up_picks_next_letter
  run_test test_append_follow_up_inserts_before_next_step
  run_test test_append_follow_up_requires_bullet
  echo "all yasdef-worker-ai-audit tests passed"
}

main "$@"
