#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ai/scripts/helpers/check_implementation_readiness.sh <step>

Exit codes:
  0  implementation handoff is ready
  1  implementation handoff is not ready
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

normalize_ordered_plan_item() {
  local line="$1"

  if [[ "$line" =~ ^-[[:space:]]+\[[xX[:space:]]\][[:space:]]+ ]]; then
    printf '%s\n' "$line"
    return 0
  fi

  if [[ "$line" =~ ^-[[:space:]]+ ]]; then
    local body
    body="$(printf '%s' "$line" | sed -E 's/^-[[:space:]]+//')"
    printf '%s\n' "- [ ] $body"
    return 0
  fi

  return 1
}

list_normalized_ordered_plan_items() {
  local section="$1"
  local line trimmed normalized

  while IFS= read -r line; do
    trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//')"
    [[ -z "${trimmed//[[:space:]]/}" ]] && continue
    if normalized="$(normalize_ordered_plan_item "$trimmed")"; then
      printf '%s\n' "$normalized"
    fi
  done <<<"$section"
}

list_unchecked_ordered_plan_items() {
  local items="$1"
  local line

  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ ! "$line" =~ ^-[[:space:]]+\[[xX]\][[:space:]]+ ]]; then
      printf '%s\n' "$line"
    fi
  done <<<"$items"
}

list_functional_requirement_entries() {
  local section="$1"
  printf '%s\n' "$section" | awk '
    function flush_current() {
      if (fr != "") {
        normalized = tolower(status)
        gsub(/[[:space:]]+/, "", normalized)
        gsub(/`/, "", normalized)
        if (normalized == "done") {
          print "- [x] " fr
        } else {
          print "- [ ] " fr
        }
      }
      fr = ""
      status = ""
    }
    /^###[[:space:]]+FR-[A-Za-z0-9._-]+/ {
      flush_current()
      fr = $0
      sub(/^### /, "", fr)
      next
    }
    /^-[[:space:]]+Status:[[:space:]]*/ {
      status = $0
      sub(/^- Status:[[:space:]]*/, "", status)
      next
    }
    /^-[[:space:]]+\[[xX[:space:]]\][[:space:]]+FR-[A-Za-z0-9._-]+[[:space:]]+/ {
      flush_current()
      print $0
      next
    }
    /^-?[[:space:]]*FR-[A-Za-z0-9._-]+[[:space:]]+/ {
      flush_current()
      line = $0
      sub(/^-?[[:space:]]*/, "", line)
      print line
      next
    }
    END { flush_current() }
  '
}

normalize_functional_requirement_item() {
  local line="$1"

  if [[ "$line" =~ ^-[[:space:]]+\[[xX[:space:]]\][[:space:]]+FR-[A-Za-z0-9._-]+([[:space:]]+.*)?$ ]]; then
    printf '%s\n' "$line"
    return 0
  fi

  if [[ "$line" =~ ^-[[:space:]]+FR-[A-Za-z0-9._-]+([[:space:]]+.*)?$ ]]; then
    local body
    body="$(printf '%s' "$line" | sed -E 's/^-[[:space:]]+//')"
    printf '%s\n' "- [ ] $body"
    return 0
  fi

  if [[ "$line" =~ ^FR-[A-Za-z0-9._-]+([[:space:]]+.*)?$ ]]; then
    printf '%s\n' "- [ ] $line"
    return 0
  fi

  return 1
}

list_normalized_functional_requirement_items() {
  local section="$1"
  local entries line normalized

  entries="$(list_functional_requirement_entries "$section")"
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if normalized="$(normalize_functional_requirement_item "$line")"; then
      printf '%s\n' "$normalized"
    fi
  done <<<"$entries"
}

list_unchecked_functional_requirement_items() {
  local items="$1"
  local line

  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ ! "$line" =~ ^-[[:space:]]+\[[xX]\][[:space:]]+FR-[A-Za-z0-9._-]+([[:space:]]+.*)?$ ]]; then
      printf '%s\n' "$line"
    fi
  done <<<"$items"
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

STEP="$1"
STEP_PLAN_FILE="$ROOT/ai/step_plans/step-$STEP.md"

if [[ ! -f "$STEP_PLAN_FILE" ]]; then
  echo "Implementation readiness failed for step $STEP." >&2
  echo "Step plan not found: ai/step_plans/step-$STEP.md" >&2
  echo "Implementation was not finished correctly because the canonical step plan is missing." >&2
  exit 1
fi

ORDERED_SECTION="$(get_markdown_section_body "$STEP_PLAN_FILE" "## Plan (ordered)")"
if [[ -z "${ORDERED_SECTION//[[:space:]]/}" ]]; then
  echo "Implementation readiness failed for step $STEP." >&2
  echo "Step plan gate requires section '## Plan (ordered)' in ai/step_plans/step-$STEP.md." >&2
  echo "Implementation was not finished correctly because ordered checklist section is missing." >&2
  exit 1
fi

NORMALIZED_ORDERED_ITEMS="$(list_normalized_ordered_plan_items "$ORDERED_SECTION")"
if [[ -z "${NORMALIZED_ORDERED_ITEMS//[[:space:]]/}" ]]; then
  echo "Implementation readiness failed for step $STEP." >&2
  echo "No ordered plan checklist items were found under '## Plan (ordered)' in ai/step_plans/step-$STEP.md." >&2
  echo "Add ordered bullets as checklist items and mark them [x] only when each is proven complete." >&2
  echo "Implementation was not finished correctly because ordered checklist items are missing." >&2
  exit 1
fi

UNCHECKED_ORDERED_ITEMS="$(list_unchecked_ordered_plan_items "$NORMALIZED_ORDERED_ITEMS")"
if [[ -n "${UNCHECKED_ORDERED_ITEMS//[[:space:]]/}" ]]; then
  echo "Implementation readiness failed for step $STEP." >&2
  echo "All items in step plan '## Plan (ordered)' must be [x] before handing off implementation." >&2
  echo "Unchecked ordered-plan items (normalized):" >&2
  printf '%s\n' "$UNCHECKED_ORDERED_ITEMS" >&2
  echo "Implementation was not finished correctly because ordered checklist has unchecked items." >&2
  exit 1
fi

FUNCTIONAL_SECTION="$(get_functional_requirements_section "$STEP_PLAN_FILE" || true)"
if [[ -z "${FUNCTIONAL_SECTION//[[:space:]]/}" ]]; then
  echo "Implementation readiness failed for step $STEP." >&2
  echo "Step plan gate requires section '## Functional Requirements (translated from design EARS)' in ai/step_plans/step-$STEP.md." >&2
  echo "Implementation was not finished correctly because translated functional requirements section is missing." >&2
  exit 1
fi

NORMALIZED_FUNCTIONAL_ITEMS="$(list_normalized_functional_requirement_items "$FUNCTIONAL_SECTION")"
if [[ -z "${NORMALIZED_FUNCTIONAL_ITEMS//[[:space:]]/}" ]]; then
  echo "Implementation readiness failed for step $STEP." >&2
  echo "No translated functional requirement entries were found in ai/step_plans/step-$STEP.md." >&2
  echo "Use canonical entries only: - [ ] FR-$STEP-001 The system SHALL ... EARS[REQ-...]." >&2
  echo "Implementation was not finished correctly because functional requirements checklist is empty." >&2
  exit 1
fi

UNCHECKED_FUNCTIONAL_ITEMS="$(list_unchecked_functional_requirement_items "$NORMALIZED_FUNCTIONAL_ITEMS")"
if [[ -n "${UNCHECKED_FUNCTIONAL_ITEMS//[[:space:]]/}" ]]; then
  echo "Implementation readiness failed for step $STEP." >&2
  echo "All items in step plan '## Functional Requirements (translated from design EARS)' must be [x] before handing off implementation." >&2
  echo "Unchecked functional requirements (normalized):" >&2
  printf '%s\n' "$UNCHECKED_FUNCTIONAL_ITEMS" >&2
  echo "Implementation was not finished correctly because functional requirements checklist has unchecked items." >&2
  exit 1
fi

echo "Implementation readiness check passed for step $STEP"
