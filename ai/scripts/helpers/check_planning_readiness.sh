#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/runtime_layout.sh"
asdlc_worker_require_runtime_layout "${BASH_SOURCE[0]}"
ROOT="$WORKER_REPO_ROOT"
PLAN_FILE="$ASDLC_RUNTIME_PLAN_PATH"
DESIGN_DIR="$ASDLC_STEP_DESIGNS_DIR"

usage() {
  cat <<'EOF'
Usage: .asdlc_worker/scripts/helpers/check_planning_readiness.sh <step>

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

get_bootstrap_heading() {
  local file="$1"
  if grep -Fq "## First-Feature Bootstrap (only if needed)" "$file"; then
    printf '## First-Feature Bootstrap (only if needed)'
    return 0
  fi
  if grep -Fq "## First-Feature Bootstrap" "$file"; then
    printf '## First-Feature Bootstrap'
    return 0
  fi
  if grep -Fq "## First-Feature Bootstrap Decision" "$file"; then
    printf '## First-Feature Bootstrap Decision'
    return 0
  fi
  return 1
}

extract_section_scalar() {
  local file="$1"
  local heading="$2"
  local label="$3"
  awk -v heading="$heading" -v label="$label" '
    $0 == heading { in_section=1; next }
    in_section && /^## / { exit }
    in_section {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      if (index(line, label ":") == 1) {
        value = substr(line, length(label) + 2)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  ' "$file"
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

STEP="$1"
STEP_PLAN_FILE="$(find "$ASDLC_STEP_PLANS_DIR" -maxdepth 1 -name "step-${STEP}-*.md" 2>/dev/null | head -1 || true)"
DESIGN_FILE="$(find "$DESIGN_DIR" -maxdepth 1 -name "step-${STEP}-*-design.md" 2>/dev/null | head -1 || true)"

if [[ -z "$STEP_PLAN_FILE" ]] || [[ ! -f "$STEP_PLAN_FILE" ]]; then
  echo "Planning readiness failed: step plan not found: .asdlc_worker/step_plans/step-$STEP-<feature-id>.md" >&2
  exit 1
fi

if ! grep -Eq '^##[[:space:]]+Plan \(ordered\)[[:space:]]*$' "$STEP_PLAN_FILE"; then
  echo "Planning readiness failed: missing required section '## Plan (ordered)' in .asdlc_worker/step_plans/step-$STEP.md" >&2
  exit 1
fi

FUNCTIONAL_SECTION="$(get_functional_requirements_section "$STEP_PLAN_FILE" || true)"
if [[ -z "${FUNCTIONAL_SECTION//[[:space:]]/}" ]]; then
  echo "Planning readiness failed: missing required section '## Functional Requirements (translated from design EARS)' in .asdlc_worker/step_plans/step-$STEP.md" >&2
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "Planning readiness failed: implementation plan not found: .asdlc_worker/overmind/implementation_plan.md" >&2
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
    echo "Planning readiness failed: 'Plan and discuss the step' is not marked [x] in .asdlc_worker/overmind/implementation_plan.md for step $STEP" >&2
    exit 1
    ;;
  *)
    echo "Planning readiness failed: implementation plan missing 'Plan and discuss the step' bullet for step $STEP" >&2
    exit 1
    ;;
esac

if [[ -f "$DESIGN_FILE" ]]; then
  BOOTSTRAP_HEADING="$(get_bootstrap_heading "$DESIGN_FILE" || true)"
  BOOTSTRAP_REQUIRED=""
  if [[ -n "$BOOTSTRAP_HEADING" ]]; then
    BOOTSTRAP_REQUIRED="$(extract_section_scalar "$DESIGN_FILE" "$BOOTSTRAP_HEADING" "Bootstrap required" | tr '[:upper:]' '[:lower:]')"
  fi
  if [[ "$BOOTSTRAP_REQUIRED" == "yes" ]]; then
    if ! grep -Eq '^##[[:space:]]+Scaffold Bootstrap Plan[[:space:]]*$' "$STEP_PLAN_FILE"; then
      echo "Planning readiness failed: bootstrap-required design needs section '## Scaffold Bootstrap Plan' in .asdlc_worker/step_plans/step-$STEP.md" >&2
      exit 1
    fi

    PLAN_SECTION="$(get_markdown_section_body "$STEP_PLAN_FILE" "## Plan (ordered)")"
    FIRST_PLAN_BULLET="$(printf '%s\n' "$PLAN_SECTION" | awk '/^- / { print; exit }')"
    if [[ -z "$FIRST_PLAN_BULLET" ]]; then
      echo "Planning readiness failed: bootstrap-required design needs ordered plan bullets in .asdlc_worker/step_plans/step-$STEP.md" >&2
      exit 1
    fi
    if ! printf '%s\n' "$FIRST_PLAN_BULLET" | grep -qiE 'scaffold|bootstrap|initialize'; then
      echo "Planning readiness failed: bootstrap-required planning must place scaffold creation first in '## Plan (ordered)'" >&2
      exit 1
    fi
  fi
fi

echo "Planning readiness check passed for step $STEP"
