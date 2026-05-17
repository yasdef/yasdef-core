#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_DESIGN_SRC="$SOURCE_ROOT/ai/scripts/ai_design.sh"
HELPER_SRC="$SOURCE_ROOT/ai/scripts/helpers/check_design_readiness.sh"
BLUEPRINT_HELPER_SRC="$SOURCE_ROOT/ai/scripts/helpers/helper_find_blueprints.sh"
RUNTIME_LAYOUT_SRC="$SOURCE_ROOT/ai/scripts/helpers/runtime_layout.sh"
PROCESS_SRC="$SOURCE_ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
TEMPLATE_SRC="$SOURCE_ROOT/ai/templates/feature_design_TEMPLATE.md"

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

assert_not_equal() {
  local a="$1"
  local b="$2"
  if [[ "$a" == "$b" ]]; then
    echo "Assertion failed: values must differ" >&2
    exit 1
  fi
}

assert_order() {
  local haystack="$1"
  local first="$2"
  local second="$3"
  local first_line second_line
  first_line="$(printf '%s\n' "$haystack" | nl -ba | grep -F "$first" | head -n 1 | awk '{print $1}')"
  second_line="$(printf '%s\n' "$haystack" | nl -ba | grep -F "$second" | head -n 1 | awk '{print $1}')"
  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    echo "Assertion failed: expected first marker before second marker" >&2
    echo "First: $first" >&2
    echo "Second: $second" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"

  mkdir -p "$repo_dir/.asdlc_worker/scripts/helpers" "$repo_dir/.asdlc_worker/templates" "$repo_dir/.asdlc_worker/step_designs" "$repo_dir/.asdlc_worker/overmind"
  cp "$AI_DESIGN_SRC" "$repo_dir/.asdlc_worker/scripts/ai_design.sh"
  cp "$HELPER_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/check_design_readiness.sh"
  cp "$BLUEPRINT_HELPER_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/helper_find_blueprints.sh"
  cp "$RUNTIME_LAYOUT_SRC" "$repo_dir/.asdlc_worker/scripts/helpers/runtime_layout.sh"
  cp "$PROCESS_SRC" "$repo_dir/.asdlc_worker/AI_DEVELOPMENT_PROCESS.md"
  cp "$TEMPLATE_SRC" "$repo_dir/.asdlc_worker/templates/feature_design_TEMPLATE.md"
  chmod +x "$repo_dir/.asdlc_worker/scripts/ai_design.sh" "$repo_dir/.asdlc_worker/scripts/helpers/check_design_readiness.sh" "$repo_dir/.asdlc_worker/scripts/helpers/helper_find_blueprints.sh"

  cat >"$repo_dir/.asdlc_worker/blocker_log.md" <<'EOF'
## Step 1.1 Demo
- No blockers.
EOF

  cat >"$repo_dir/.asdlc_worker/open_questions.md" <<'EOF'
## Step 1.1 Demo
- No open questions.
EOF

  cat >"$repo_dir/.asdlc_worker/decisions.md" <<'EOF'
# ADRs
EOF

  cat >"$repo_dir/.asdlc_worker/user_review.md" <<'EOF'
# User review rules
EOF

  cat >"$repo_dir/AGENTS.md" <<'EOF'
# AGENTS
- Demo constraint.
EOF

  cat >"$repo_dir/.asdlc_worker/project_overmind.yaml" <<'EOF'
worker_uuid: 'worker-1'
class: 'backend'
status: 'active'
EOF

  mkdir -p "$repo_dir/source-project/feature-a"
  cat >"$repo_dir/source-project/feature-a/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [ ] Plan and discuss the step. [REQ-1]
- [ ] Implement design scope. [REQ-1]
- [ ] Review step implementation.
EOF
  cat >"$repo_dir/source-project/feature-a/requirements_ears.md" <<'EOF'
### Requirement 1 Demo
- Demo requirement.
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

run_design() {
  local repo_dir="$1"
  shift
  (
    cd "$repo_dir"
    ASDLC_RUNTIME_PLAN_PATH="$repo_dir/source-project/feature-a/implementation_plan.md" \
    ASDLC_RUNTIME_EARS_PATH="$repo_dir/source-project/feature-a/requirements_ears.md" \
    .asdlc_worker/scripts/ai_design.sh --step 1.1 --design-out .asdlc_worker/step_designs/step-1.1-design.md "$@"
  )
}

test_feature_rich_mode_block_is_opt_in() {
  local repo_dir="$TMP_ROOT/repo-design-feature-rich"
  setup_repo "$repo_dir"

  local rich_out
  rich_out="$(run_design "$repo_dir" --feature-rich-design-planning)"
  assert_contains "$rich_out" "Feature-rich design/planning mode: ENABLED (design-only add-on)."
  assert_contains "$rich_out" "\"Optional Hardening Opportunities\" shortlist (max 5 bullets)"

  local default_out
  default_out="$(run_design "$repo_dir")"
  assert_not_contains "$default_out" "Feature-rich design/planning mode: ENABLED (design-only add-on)."
}

test_bound_source_paths_are_used() {
  local repo_dir="$TMP_ROOT/repo-design-bound-source"
  setup_repo "$repo_dir"

  local out
  out="$(run_design "$repo_dir")"
  assert_contains "$out" "Step 1.1 - Demo"
  assert_contains "$out" "### Requirement 1 Demo"
}

test_design_prompt_includes_readiness_contract() {
  local repo_dir="$TMP_ROOT/repo-design-readiness-contract"
  setup_repo "$repo_dir"

  local out
  out="$(run_design "$repo_dir")"
  assert_contains "$out" 'Before ending the design phase, run `.asdlc_worker/scripts/helpers/check_design_readiness.sh .asdlc_worker/step_designs/step-1.1-design.md`.'
  assert_contains "$out" 'If the readiness check fails, do not emit the final completion line yet.'
  assert_contains "$out" 'ask exactly two options: `1.` continue iterating and re-check, `2.` force the design phase done and proceed.'
  assert_contains "$out" 'If option `2` is chosen, record that forced-done outcome in the design artifact before using the completion line.'
  assert_order "$out" 'Before ending the design phase, run `.asdlc_worker/scripts/helpers/check_design_readiness.sh .asdlc_worker/step_designs/step-1.1-design.md`.' 'When design phase is fully complete, end your final response with this exact last line: "Design phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase."'
}

test_design_prompt_includes_bootstrap_helper_contract() {
  local repo_dir="$TMP_ROOT/repo-design-bootstrap-contract"
  setup_repo "$repo_dir"
  local resolved_repo_dir
  resolved_repo_dir="$(cd "$repo_dir" && pwd -P)"

  local out
  out="$(run_design "$repo_dir")"
  assert_contains "$out" 'Apply `#### Bootstrap decision algorithm` from Section 1 before design handoff.'
  assert_contains "$out" 'Blueprint helper contract: when bootstrap is required and stack/architecture guidance is needed, run `.asdlc_worker/scripts/helpers/helper_find_blueprints.sh` from the ASDLC feature folder context where `implementation_plan.md` and `requirements_ears.md` live; it searches the parent project-level directory for `project_stack_blueprint_*.md`.'
  assert_contains "$out" "Suggested bootstrap lookup command for this run: \`cd \"$repo_dir/source-project/feature-a\" && \"$resolved_repo_dir/.asdlc_worker/scripts/helpers/helper_find_blueprints.sh\"\`."
}

test_design_prompt_includes_missing_discussion_points_gates() {
  local repo_dir="$TMP_ROOT/repo-design-missing-discussion-gates"
  setup_repo "$repo_dir"

  local out
  out="$(run_design "$repo_dir")"
  assert_contains "$out" "#### Missing discussion points gates"
  assert_contains "$out" "Before design handoff, run a lightweight missing-discussion-points ambiguity scan focused on planning-relevant gaps"
  assert_contains "$out" "Normalize all planning-relevant unresolved findings into design \`## Things to Decide (for final planning discussion)\`"
}

test_design_readiness_helper_exit_codes() {
  local repo_dir="$TMP_ROOT/repo-design-readiness-helper"
  setup_repo "$repo_dir"

  cat >"$repo_dir/.asdlc_worker/step_designs/ready.md" <<'EOF'
## Goal
- Ready.
## In Scope
- Ready.
## Out of Scope
- Ready.
EOF

  local ready_out
  ready_out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_design_readiness.sh .asdlc_worker/step_designs/ready.md)"
  assert_contains "$ready_out" "Design readiness check passed: .asdlc_worker/step_designs/ready.md"

  cat >"$repo_dir/.asdlc_worker/step_designs/not-ready.md" <<'EOF'
## Goal
- Missing scope sections.
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_design_readiness.sh .asdlc_worker/step_designs/not-ready.md 2>&1)"
  status=$?
  set -e
  assert_not_equal "$status" "0"
  assert_contains "$out" "Design readiness failed: missing required sections: In Scope Out of Scope"
}

test_design_readiness_helper_blocks_unresolved_bootstrap() {
  local repo_dir="$TMP_ROOT/repo-design-bootstrap-readiness"
  setup_repo "$repo_dir"

  cat >"$repo_dir/.asdlc_worker/step_designs/bootstrap-unresolved.md" <<'EOF'
## Goal
- Bootstrap the first backend feature.
## In Scope
- Create scaffold direction for the first implementation step.
## Out of Scope
- Downstream feature implementation.
## First-Feature Bootstrap (only if needed)
- Bootstrap required: yes
- Repo state rationale: Empty backend repo.
- Blueprint result: no relevant blueprint found
- Blueprint evidence: None
- User stack decision: None
- Planning handoff: Pending user direction.
EOF

  local status=0
  local out=""
  set +e
  out="$(cd "$repo_dir" && .asdlc_worker/scripts/helpers/check_design_readiness.sh .asdlc_worker/step_designs/bootstrap-unresolved.md 2>&1)"
  status=$?
  set -e
  assert_not_equal "$status" "0"
  assert_contains "$out" "Design readiness failed: bootstrap-required design must include a concrete planning handoff"
}

test_feature_rich_mode_block_is_opt_in
test_bound_source_paths_are_used
test_design_prompt_includes_readiness_contract
test_design_prompt_includes_bootstrap_helper_contract
test_design_prompt_includes_missing_discussion_points_gates
test_design_readiness_helper_exit_codes
test_design_readiness_helper_blocks_unresolved_bootstrap

echo "All ai_design feature-rich mode tests passed."
