#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PLAN_FILE="$ROOT/overmind/implementation_plan.md"

usage() {
  cat <<'EOF'
Usage: ai/scripts/helpers/check_planning_readiness.sh <step>

Exit codes:
  0  planning handoff is ready
  1  planning handoff is not ready
  2  invalid usage
EOF
}

get_markdown_section_body() {
  local file="$1"
  local heading="$2"
  awk -v heading="$heading" '
    $0 == heading { in_section=1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$file"
}

get_functional_requirements_section() {
  local file="$1"
  local section

  section="$(get_markdown_section_body "$file" "## Functional Requirements (translated from design EARS)")"
  if [[ -n "${section//[[:space:]]/}" ]]; then
    printf '%s' "$section"
    return 0
  fi

  section="$(get_markdown_section_body "$file" "## Functional Requirements")"
  if [[ -n "${section//[[:space:]]/}" ]]; then
    printf '%s' "$section"
    return 0
  fi

  return 1
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

STEP="$1"
STEP_PLAN_FILE="$ROOT/ai/step_plans/step-$STEP.md"

if [[ ! -f "$STEP_PLAN_FILE" ]]; then
  echo "Planning readiness failed: step plan not found: ai/step_plans/step-$STEP.md" >&2
  exit 1
fi

if ! grep -Eq '^##[[:space:]]+Plan \(ordered\)[[:space:]]*$' "$STEP_PLAN_FILE"; then
  echo "Planning readiness failed: missing required section '## Plan (ordered)' in ai/step_plans/step-$STEP.md" >&2
  exit 1
fi

FUNCTIONAL_SECTION="$(get_functional_requirements_section "$STEP_PLAN_FILE" || true)"
if [[ -z "${FUNCTIONAL_SECTION//[[:space:]]/}" ]]; then
  echo "Planning readiness failed: missing required section '## Functional Requirements (translated from design EARS)' in ai/step_plans/step-$STEP.md" >&2
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "Planning readiness failed: implementation plan not found: overmind/implementation_plan.md" >&2
  exit 1
fi

GATE_STATE="$(
  awk -v step="$STEP" '
    BEGIN {
      step_re = step
      gsub(/\./, "\\.", step_re)
    }
    $0 ~ "^### Step " step_re " " { in_step=1; next }
    in_step && /^### Step / { exit }
    in_step && /^- \[[ xX]\]/ {
      raw = $0
      checked = (raw ~ /^- \[[xX]\]/)
      text = raw
      sub(/^- \[[ xX]\][[:space:]]*/, "", text)
      gate_text = tolower(text)
      while (gate_text ~ /^\[[^]]+\][[:space:]]*/) {
        sub(/^\[[^]]+\][[:space:]]*/, "", gate_text)
      }
      if (gate_text ~ /^plan and discuss the step([[:space:]\.]|$)/) {
        if (checked) {
          print "checked"
        } else {
          print "unchecked"
        }
        found=1
        exit
      }
    }
    END {
      if (!found) {
        print "missing"
      }
    }
  ' "$PLAN_FILE"
)"

case "$GATE_STATE" in
  checked)
    ;;
  unchecked)
    echo "Planning readiness failed: 'Plan and discuss the step' is not marked [x] in overmind/implementation_plan.md for step $STEP" >&2
    exit 1
    ;;
  *)
    echo "Planning readiness failed: implementation plan missing 'Plan and discuss the step' bullet for step $STEP" >&2
    exit 1
    ;;
esac

echo "Planning readiness check passed for step $STEP"
