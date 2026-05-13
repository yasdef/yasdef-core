#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: .asdlc_worker/scripts/helpers/check_design_readiness.sh <design-file>

Exit codes:
  0  design artifact is ready
  1  design artifact is not ready
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

extract_section_scalar() {
  local section_body="$1"
  local label="$2"
  printf '%s\n' "$section_body" | awk -v label="$label" '
    {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      if (index(line, label ":") == 1) {
        value = substr(line, length(label) + 2)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  '
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

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

DESIGN_FILE="$1"

if [[ ! -f "$DESIGN_FILE" ]]; then
  echo "Design readiness failed: file not found: $DESIGN_FILE" >&2
  exit 1
fi

missing_sections=()
for section in "Goal" "In Scope" "Out of Scope"; do
  if ! awk -v target="$section" '
    /^##[[:space:]]+/ {
      line = $0
      sub(/^##[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == target) { found = 1; exit }
    }
    END { exit(found ? 0 : 1) }
  ' "$DESIGN_FILE"; then
    missing_sections+=("$section")
  fi
done

if [[ ${#missing_sections[@]} -gt 0 ]]; then
  echo "Design readiness failed: missing required sections: ${missing_sections[*]}" >&2
  exit 1
fi

BOOTSTRAP_HEADING="$(get_bootstrap_heading "$DESIGN_FILE" || true)"
if [[ -n "$BOOTSTRAP_HEADING" ]]; then
  BOOTSTRAP_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "$BOOTSTRAP_HEADING")"
  if [[ -n "${BOOTSTRAP_SECTION//[[:space:]]/}" ]]; then
    BOOTSTRAP_REQUIRED="$(extract_section_scalar "$BOOTSTRAP_SECTION" "Bootstrap required" | tr '[:upper:]' '[:lower:]')"
    PLANNING_HANDOFF="$(extract_section_scalar "$BOOTSTRAP_SECTION" "Planning handoff" | tr '[:upper:]' '[:lower:]')"

    if [[ "$BOOTSTRAP_HEADING" == "## First-Feature Bootstrap Decision" ]]; then
      LEGACY_SCAFFOLD_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "## Scaffold Creation Handoff")"
      if [[ -n "${LEGACY_SCAFFOLD_SECTION//[[:space:]]/}" ]]; then
        PLANNING_HANDOFF="$(extract_section_scalar "$LEGACY_SCAFFOLD_SECTION" "Planning requirement" | tr '[:upper:]' '[:lower:]')"
      fi
    fi

    if [[ -n "$BOOTSTRAP_REQUIRED" && "$BOOTSTRAP_REQUIRED" != "yes" ]]; then
      echo "Design readiness failed: optional bootstrap section must use 'Bootstrap required: yes' when present" >&2
      exit 1
    fi

    if [[ "$BOOTSTRAP_REQUIRED" == "yes" ]]; then
      if [[ -z "$PLANNING_HANDOFF" || "$PLANNING_HANDOFF" == pending* || "$PLANNING_HANDOFF" == unresolved* ]]; then
        echo "Design readiness failed: bootstrap-required design must include a concrete planning handoff" >&2
        exit 1
      fi
    fi
  fi
fi

echo "Design readiness check passed: $DESIGN_FILE"
