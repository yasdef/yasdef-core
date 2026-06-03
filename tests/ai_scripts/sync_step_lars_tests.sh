#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLAN_SKILL_DIR="$SOURCE_ROOT/ai/skills/yasdef-worker-plan"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export UV_CACHE_DIR="$TMP_ROOT/uv-cache"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Assertion failed: expected content to contain: $needle" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

setup_repo() {
  local repo_dir="$1"
  mkdir -p \
    "$repo_dir/.asdlc_worker/step_designs" \
    "$repo_dir/.asdlc_worker/step_plans" \
    "$repo_dir/.codex/skills"
  cp -R "$PLAN_SKILL_DIR" "$repo_dir/.codex/skills/yasdef-worker-plan"
}

test_helper_copies_design_lars_into_step_plan() {
  local repo_dir="$TMP_ROOT/repo-copy"
  setup_repo "$repo_dir"

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-demo-design.md" <<'EOF'
## Goal
- Demo.

## Linked Artifacts (in scope)
- LAR-002 | Figma | Menu Mockup | https://figma.com/file/abc/menu
EOF

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [ ] 1. Demo.
EOF

  (
    cd "$repo_dir"
    uv run python .codex/skills/yasdef-worker-plan/scripts/sync_step_lars.py \
      --design .asdlc_worker/step_designs/step-1.1-demo-design.md \
      --step-plan .asdlc_worker/step_plans/step-1.1-demo.md
  )

  local content
  content="$(cat "$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md")"
  assert_contains "$content" "## Linked Artifacts (in scope)"
  assert_contains "$content" "LAR-002 | Figma | Menu Mockup | https://figma.com/file/abc/menu"
}

test_helper_is_idempotent() {
  local repo_dir="$TMP_ROOT/repo-idempotent"
  setup_repo "$repo_dir"

  cat >"$repo_dir/.asdlc_worker/step_designs/step-1.1-demo-design.md" <<'EOF'
## Linked Artifacts (in scope)
- LAR-002 | Figma | Menu Mockup | https://figma.com/file/abc/menu
EOF

  cat >"$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md" <<'EOF'
# Step Plan: 1.1 - Demo
## Plan (ordered)
- [ ] 1. Demo.
EOF

  (
    cd "$repo_dir"
    uv run python .codex/skills/yasdef-worker-plan/scripts/sync_step_lars.py \
      --design .asdlc_worker/step_designs/step-1.1-demo-design.md \
      --step-plan .asdlc_worker/step_plans/step-1.1-demo.md
  )
  local first_run
  first_run="$(cat "$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md")"

  (
    cd "$repo_dir"
    uv run python .codex/skills/yasdef-worker-plan/scripts/sync_step_lars.py \
      --design .asdlc_worker/step_designs/step-1.1-demo-design.md \
      --step-plan .asdlc_worker/step_plans/step-1.1-demo.md
  )
  local second_run
  second_run="$(cat "$repo_dir/.asdlc_worker/step_plans/step-1.1-demo.md")"

  if [[ "$first_run" != "$second_run" ]]; then
    echo "Assertion failed: repeated helper runs should be byte-equivalent" >&2
    exit 1
  fi
}

test_helper_copies_design_lars_into_step_plan
test_helper_is_idempotent

echo "All sync_step_lars tests passed."
