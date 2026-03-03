#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_DESIGN_SRC="$SOURCE_ROOT/ai/scripts/ai_design.sh"
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

setup_repo() {
  local repo_dir="$1"

  mkdir -p "$repo_dir/ai/scripts" "$repo_dir/ai/templates" "$repo_dir/ai/step_designs"
  cp "$AI_DESIGN_SRC" "$repo_dir/ai/scripts/ai_design.sh"
  cp "$PROCESS_SRC" "$repo_dir/ai/AI_DEVELOPMENT_PROCESS.md"
  cp "$TEMPLATE_SRC" "$repo_dir/ai/templates/feature_design_TEMPLATE.md"
  chmod +x "$repo_dir/ai/scripts/ai_design.sh"

  cat >"$repo_dir/ai/implementation_plan.md" <<'EOF'
### Step 1.1 Demo
- [ ] Plan and discuss the step. [REQ-1]
- [ ] Implement design scope. [REQ-1]
- [ ] Review step implementation.
EOF

  cat >"$repo_dir/ai/blocker_log.md" <<'EOF'
## Step 1.1 Demo
- No blockers.
EOF

  cat >"$repo_dir/ai/open_questions.md" <<'EOF'
## Step 1.1 Demo
- No open questions.
EOF

  cat >"$repo_dir/ai/decisions.md" <<'EOF'
# ADRs
EOF

  cat >"$repo_dir/ai/user_review.md" <<'EOF'
# User review rules
EOF

  cat >"$repo_dir/reqirements_ears.md" <<'EOF'
### Requirement 1 Demo
- Demo requirement.
EOF

  cat >"$repo_dir/AGENTS.md" <<'EOF'
# AGENTS
- Demo constraint.
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
    ai/scripts/ai_design.sh --step 1.1 --design-out ai/step_designs/step-1.1-design.md "$@"
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

test_feature_rich_mode_block_is_opt_in

echo "All ai_design feature-rich mode tests passed."
