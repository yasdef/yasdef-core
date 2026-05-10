#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$(basename "$ROOT")"
PLAN="$ROOT/overmind/implementation_plan.md"
PROCESS="$ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
AGENTS="$ROOT/AGENTS.md"
PLANNING_READINESS_HELPER="$ROOT/ai/scripts/helpers/check_planning_readiness.sh"
IMPLEMENTATION_READINESS_HELPER="$ROOT/ai/scripts/helpers/check_implementation_readiness.sh"

STEP=""
OUT=""
STEP_PLAN=""
DESIGN_FILE=""
INCLUDE_AGENTS=0
SKIP_BRANCH=0

usage() {
  cat <<'USAGE'
Usage: ai/scripts/ai_implementation.sh [--step 1.3] [--step-plan file] [--design file] [--out file] [--include-agents] [--no-include-agents] [--no-branch]

Defaults:
  - If --step is omitted, uses the first unchecked bullet in overmind/implementation_plan.md.
  - If --step-plan is omitted, uses ai/step_plans/step-<step>.md (required).
  - If --design is omitted, uses ai/step_designs/step-<step>-design.md (required).
  - If --out is omitted, writes to ai/prompts/impl_prompts/<project>-step-<step>.prompt.txt.
  - ai/decisions.md and ai/user_review.md are pointer-only by default; rely on design/step-plan extracted sections.
  - AGENTS.md is pointer-only by default; use --include-agents to inline full contents.
  - --no-include-agents is accepted for compatibility and keeps pointer-only behavior.
  - Always creates/switches to branch step-<step>-implementation.
  - Use --no-branch to skip git branch creation/switch (prompt generation only).
USAGE
}

require_option_arg() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 1
  fi
}

ensure_implementation_branch() {
  local target="step-$STEP-implementation"

  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not a git repository: $ROOT" >&2
    exit 1
  fi

  local current
  current="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  if [[ "$current" == "$target" ]]; then
    return 0
  fi

  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$target"; then
    git -C "$ROOT" checkout "$target" >/dev/null
    echo "Switched to existing branch: $target" >&2
  else
    git -C "$ROOT" checkout -b "$target" >/dev/null
    echo "Created and switched to branch: $target" >&2
  fi
}

normalize_bullet_line() {
  local line="$1"
  line="${line#- }"
  line="${line#*] }"
  printf '%s' "$line"
}

is_none_marker_line() {
  local line="$1"
  local trimmed
  trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]-]+//; s/[[:space:]]+$//')"
  [[ "$trimmed" =~ ^(None\.?|No\ .*|\(missing.*\))$ ]]
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

get_first_existing_section_body() {
  local file="$1"
  shift
  local heading
  for heading in "$@"; do
    if grep -Fqx "$heading" "$file"; then
      get_markdown_section_body "$file" "$heading"
      return 0
    fi
  done
  return 1
}

cap_first_n_lines() {
  local text="$1"
  local max_lines="$2"
  if [[ -z "$text" ]]; then
    return 0
  fi
  printf '%s\n' "$text" | sed -n "1,${max_lines}p"
}

cap_top_n_bullets() {
  local text="$1"
  local max_bullets="$2"
  if [[ -z "$text" ]]; then
    return 0
  fi

  local count=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^-\  ]]; then
      if (( count >= max_bullets )); then
        break
      fi
      count=$((count + 1))
      printf '%s\n' "$line"
      continue
    fi

    if (( count == 0 )); then
      printf '%s\n' "$line"
    fi
  done <<<"$text"
}

derive_step_from_step_plan_path() {
  local file="$1"
  local base step
  base="$(basename "$file")"
  if [[ "$base" =~ ^step-(.+)\.md$ ]]; then
    step="${BASH_REMATCH[1]}"
    printf '%s' "$step"
    return 0
  fi
  return 1
}

get_next_unchecked() {
  awk '
    /^### Step / {
      line = $0
      sub(/^### Step /, "", line)
      split(line, parts, " ")
      step_num = parts[1]
      step_title = substr(line, length(step_num) + 2)
      next
    }
    /^- \[ \]/ {
      bullet = $0
      sub(/^- \[ \] /, "", bullet)
      print step_num "|" step_title "|" bullet
      exit
    }
  ' "$PLAN"
}

get_step_title() {
  local step="$1"
  awk -v step="$step" '
    BEGIN { step_re = step; gsub(/\./, "\\.", step_re) }
    $0 ~ "^### Step "step_re" " {
      sub("^### Step "step_re" ", "", $0)
      print
      exit
    }
  ' "$PLAN"
}

get_step_first_unchecked() {
  local step="$1"
  awk -v step="$step" '
    BEGIN { step_re = step; gsub(/\./, "\\.", step_re) }
    $0 ~ "^### Step "step_re" " { in_step=1; next }
    in_step && $0 ~ "^### Step " { exit }
    in_step && $0 ~ /^- \[ \]/ {
      sub(/^- \[ \] /, "", $0)
      print
      exit
    }
  ' "$PLAN"
}

get_step_plan_section() {
  local heading="$1"
  get_markdown_section_body "$STEP_PLAN" "$heading"
}

get_step_plan_functional_requirements_section() {
  local section
  section="$(get_step_plan_section "## Functional Requirements (translated from design EARS)")"
  if [[ -n "${section//[[:space:]]/}" ]]; then
    printf '%s' "$section"
    return 0
  fi
  section="$(get_step_plan_section "## Functional Requirements")"
  if [[ -n "${section//[[:space:]]/}" ]]; then
    printf '%s' "$section"
    return 0
  fi
  return 1
}

extract_accepted_decisions() {
  local decisions="$1"
  if [[ -z "$decisions" ]]; then
    return 0
  fi

  local accepted
  accepted="$(printf '%s\n' "$decisions" | awk '
    /^- / { prev=$0; if (tolower($0) ~ /accepted/) print $0; next }
    /^  - / { if (tolower(prev) ~ /accepted/) print $0 }
  ')"
  printf '%s' "$accepted"
}

extract_ur_bullets() {
  local section="$1"
  if [[ -z "$section" ]]; then
    return 0
  fi
  printf '%s\n' "$section" | awk '/^- / { print }'
}

build_anti_regression_checklist() {
  local primary_ur="$1"
  local design_ur_rules="$2"
  local combined
  combined="$(
    extract_ur_bullets "$primary_ur"
    extract_ur_bullets "$design_ur_rules"
  )"

  if [[ -z "$combined" ]]; then
    echo "- None."
    return 0
  fi

  local out=()
  local seen_ids=()
  local seen_lines=()
  local line normalized ur_id already_seen_id already_seen_line

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if is_none_marker_line "$line"; then
      continue
    fi

    normalized="$line"
    ur_id="$(printf '%s\n' "$line" | grep -oE 'UR-[A-Za-z0-9_-]+' | head -n 1 || true)"

    if [[ -n "$ur_id" ]]; then
      already_seen_id=0
      local id
      for id in "${seen_ids[@]:-}"; do
        if [[ "$id" == "$ur_id" ]]; then
          already_seen_id=1
          break
        fi
      done
      if (( already_seen_id == 1 )); then
        continue
      fi
      seen_ids+=("$ur_id")
    else
      already_seen_line=0
      local existing
      for existing in "${seen_lines[@]:-}"; do
        if [[ "$existing" == "$normalized" ]]; then
          already_seen_line=1
          break
        fi
      done
      if (( already_seen_line == 1 )); then
        continue
      fi
      seen_lines+=("$normalized")
    fi

    out+=("$line")
    if (( ${#out[@]} >= 8 )); then
      break
    fi
  done <<<"$combined"

  if (( ${#out[@]} == 0 )); then
    echo "- None."
    return 0
  fi

  printf '%s\n' "${out[@]}"
}

get_design_ur_heading() {
  local file="$1"
  if grep -Fqx "## Applicable User Review Rules" "$file"; then
    printf '## Applicable User Review Rules'
    return 0
  fi
  if grep -Fqx "## Applicable UR Shortlist" "$file"; then
    printf '## Applicable UR Shortlist'
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
    [[ -z "$trimmed" ]] && continue
    if normalized="$(normalize_ordered_plan_item "$trimmed")"; then
      printf '%s\n' "$normalized"
    fi
  done <<<"$section"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)
      require_option_arg "--step" "${2:-}"
      STEP="$2"
      shift 2
      ;;
    --out)
      require_option_arg "--out" "${2:-}"
      OUT="$2"
      shift 2
      ;;
    --step-plan)
      require_option_arg "--step-plan" "${2:-}"
      STEP_PLAN="$2"
      shift 2
      ;;
    --design)
      require_option_arg "--design" "${2:-}"
      DESIGN_FILE="$2"
      shift 2
      ;;
    --include-agents)
      INCLUDE_AGENTS=1
      shift
      ;;
    --no-include-agents)
      INCLUDE_AGENTS=0
      shift
      ;;
    --no-branch)
      SKIP_BRANCH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$STEP" ]]; then
        STEP="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$STEP" && -n "$STEP_PLAN" ]]; then
  derived_step="$(derive_step_from_step_plan_path "$STEP_PLAN" || true)"
  if [[ -n "$derived_step" ]]; then
    STEP="$derived_step"
  fi
fi

if [[ -z "$STEP" ]]; then
  line="$(get_next_unchecked)"
  if [[ -z "$line" ]]; then
    echo "No unchecked bullets found in overmind/implementation_plan.md." >&2
    exit 1
  fi
  IFS='|' read -r STEP STEP_TITLE BULLET <<<"$line"
else
  STEP_TITLE="$(get_step_title "$STEP")"
  if [[ -z "$STEP_TITLE" ]]; then
    echo "Step $STEP not found in overmind/implementation_plan.md." >&2
    exit 1
  fi
  BULLET="$(get_step_first_unchecked "$STEP")"
  if [[ -z "$BULLET" ]]; then
    BULLET="(no unchecked bullets in step)"
  fi
fi

if [[ -z "$STEP_PLAN" ]]; then
  STEP_PLAN="$ROOT/ai/step_plans/step-$STEP.md"
fi
if [[ -z "$DESIGN_FILE" ]]; then
  DESIGN_FILE="$ROOT/ai/step_designs/step-$STEP-design.md"
fi
if [[ -z "$OUT" ]]; then
  OUT="$ROOT/ai/prompts/impl_prompts/${PROJECT}-step-$STEP.prompt.txt"
fi

if [[ ! -f "$DESIGN_FILE" ]]; then
  echo "Feature design not found at $DESIGN_FILE." >&2
  echo "Run ai/scripts/ai_design.sh --step $STEP first." >&2
  exit 1
fi

if [[ "$SKIP_BRANCH" -eq 0 ]]; then
  ensure_implementation_branch
fi

if [[ ! -r "$PLANNING_READINESS_HELPER" ]]; then
  echo "Planning readiness helper not found or not readable: $PLANNING_READINESS_HELPER" >&2
  exit 1
fi

PLANNING_READINESS_STATUS=0
PLANNING_READINESS_OUTPUT=""
set +e
PLANNING_READINESS_OUTPUT="$(bash "$PLANNING_READINESS_HELPER" "$STEP" 2>&1)"
PLANNING_READINESS_STATUS=$?
set -e

if [[ "$PLANNING_READINESS_STATUS" -ne 0 ]]; then
  printf '%s\n' "$PLANNING_READINESS_OUTPUT" >&2
  exit "$PLANNING_READINESS_STATUS"
fi

if [[ ! -r "$IMPLEMENTATION_READINESS_HELPER" ]]; then
  echo "Implementation readiness helper not found or not readable: $IMPLEMENTATION_READINESS_HELPER" >&2
  exit 1
fi

STEP_PLAN_ORDERED_PLAN_SECTION_RAW="$(get_step_plan_section "## Plan (ordered)")"
STEP_PLAN_ORDERED_PLAN_SECTION="$(list_normalized_ordered_plan_items "$STEP_PLAN_ORDERED_PLAN_SECTION_RAW")"
if [[ -z "$STEP_PLAN_ORDERED_PLAN_SECTION" ]]; then
  STEP_PLAN_ORDERED_PLAN_SECTION="- (missing in step plan)"
fi

STEP_PLAN_LAR_SECTION="$(get_step_plan_section "## Linked Artifacts (in scope)")"

STEP_PLAN_UR_SHORTLIST_SECTION="$(get_step_plan_section "## Applicable UR Shortlist")"
if [[ -z "$STEP_PLAN_UR_SHORTLIST_SECTION" ]]; then
  STEP_PLAN_UR_SHORTLIST_SECTION="- None."
fi

STEP_PLAN_IMPLEMENTATION_NOTES_SECTION="$(get_step_plan_section "## Implementation Notes / Constraints")"
if [[ -z "$STEP_PLAN_IMPLEMENTATION_NOTES_SECTION" ]]; then
  STEP_PLAN_IMPLEMENTATION_NOTES_SECTION="- (missing in step plan)"
fi
STEP_PLAN_IMPLEMENTATION_NOTES_SECTION="$(cap_first_n_lines "$STEP_PLAN_IMPLEMENTATION_NOTES_SECTION" 12)"

STEP_PLAN_TESTS_SECTION="$(get_step_plan_section "## Tests")"
if [[ -z "$STEP_PLAN_TESTS_SECTION" ]]; then
  STEP_PLAN_TESTS_SECTION="- (missing in step plan)"
fi

STEP_PLAN_RISKS_SECTION="$(get_step_plan_section "## Risks / Edge Cases")"
if [[ -z "$STEP_PLAN_RISKS_SECTION" ]]; then
  STEP_PLAN_RISKS_SECTION="- (missing in step plan)"
else
  STEP_PLAN_RISKS_SECTION="$(cap_top_n_bullets "$STEP_PLAN_RISKS_SECTION" 8)"
fi

STEP_PLAN_DECISIONS_NEEDED_SECTION="$(get_step_plan_section "## Decisions Needed")"
if [[ -z "$STEP_PLAN_DECISIONS_NEEDED_SECTION" ]]; then
  STEP_PLAN_DECISIONS_NEEDED_SECTION="- (missing in step plan)"
fi
STEP_PLAN_ACCEPTED_DECISIONS_SECTION="$(extract_accepted_decisions "$STEP_PLAN_DECISIONS_NEEDED_SECTION")"
if [[ -z "$STEP_PLAN_ACCEPTED_DECISIONS_SECTION" ]]; then
  STEP_PLAN_ACCEPTED_DECISIONS_SECTION="- None explicitly marked as Accepted."
fi

DESIGN_GOAL_SECTION="$(get_first_existing_section_body "$DESIGN_FILE" "## Goal")"
if [[ -z "$DESIGN_GOAL_SECTION" ]]; then
  DESIGN_GOAL_SECTION="- (missing in design artifact)"
else
  DESIGN_GOAL_SECTION="$(cap_first_n_lines "$DESIGN_GOAL_SECTION" 10)"
fi

DESIGN_IN_SCOPE_SECTION="$(get_first_existing_section_body "$DESIGN_FILE" "## In Scope")"
if [[ -z "$DESIGN_IN_SCOPE_SECTION" ]]; then
  DESIGN_IN_SCOPE_SECTION="- (missing in design artifact)"
else
  DESIGN_IN_SCOPE_SECTION="$(cap_first_n_lines "$DESIGN_IN_SCOPE_SECTION" 10)"
fi

DESIGN_OUT_OF_SCOPE_SECTION="$(get_first_existing_section_body "$DESIGN_FILE" "## Out of Scope")"
if [[ -z "$DESIGN_OUT_OF_SCOPE_SECTION" ]]; then
  DESIGN_OUT_OF_SCOPE_SECTION="- (missing in design artifact)"
else
  DESIGN_OUT_OF_SCOPE_SECTION="$(cap_first_n_lines "$DESIGN_OUT_OF_SCOPE_SECTION" 10)"
fi

DESIGN_NON_GOALS_SECTION="$(get_first_existing_section_body "$DESIGN_FILE" "## Non-goals" "## Non-Goals")"
if [[ -z "$DESIGN_NON_GOALS_SECTION" ]]; then
  DESIGN_NON_GOALS_SECTION="- (missing in design artifact)"
else
  DESIGN_NON_GOALS_SECTION="$(cap_first_n_lines "$DESIGN_NON_GOALS_SECTION" 10)"
fi

DESIGN_PROPOSAL_SECTION="$(get_first_existing_section_body "$DESIGN_FILE" "## Proposal / Design Details")"
if [[ -z "$DESIGN_PROPOSAL_SECTION" ]]; then
  DESIGN_PROPOSAL_SECTION="- (missing in design artifact)"
else
  DESIGN_PROPOSAL_SECTION="$(cap_first_n_lines "$DESIGN_PROPOSAL_SECTION" 20)"
fi

DESIGN_RISKS_SECTION="$(get_first_existing_section_body "$DESIGN_FILE" "## Risks and Mitigations")"
if [[ -z "$DESIGN_RISKS_SECTION" ]]; then
  DESIGN_RISKS_SECTION="- (missing in design artifact)"
else
  DESIGN_RISKS_SECTION="$(cap_top_n_bullets "$DESIGN_RISKS_SECTION" 10)"
fi

DESIGN_ADR_SECTION="$(get_first_existing_section_body "$DESIGN_FILE" "## Applicable ADR Shortlist (from ai/decisions.md)" "## Applicable ADR Shortlist")"
if [[ -z "$DESIGN_ADR_SECTION" ]]; then
  DESIGN_ADR_SECTION="- (missing in design artifact)"
else
  DESIGN_ADR_SECTION="$(cap_first_n_lines "$DESIGN_ADR_SECTION" 10)"
fi

DESIGN_AGENTS_SECTION="$(get_first_existing_section_body "$DESIGN_FILE" "## Applicable AGENTS.md Constraints")"
if [[ -z "$DESIGN_AGENTS_SECTION" ]]; then
  DESIGN_AGENTS_SECTION="- (missing in design artifact)"
else
  DESIGN_AGENTS_SECTION="$(cap_first_n_lines "$DESIGN_AGENTS_SECTION" 12)"
fi

DESIGN_REFERENCES_SECTION="$(get_first_existing_section_body "$DESIGN_FILE" "## References in Current Codebase")"
if [[ -z "$DESIGN_REFERENCES_SECTION" ]]; then
  DESIGN_REFERENCES_SECTION="- (missing in design artifact)"
fi

DESIGN_UR_RULES_SECTION=""
if DESIGN_UR_HEADING="$(get_design_ur_heading "$DESIGN_FILE" 2>/dev/null || true)"; then
  if [[ -n "$DESIGN_UR_HEADING" ]]; then
    DESIGN_UR_RULES_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "$DESIGN_UR_HEADING")"
  fi
fi
if [[ -z "$DESIGN_UR_RULES_SECTION" ]]; then
  DESIGN_UR_RULES_SECTION="- None."
fi

STEP_PLAN_FUNCTIONAL_REQUIREMENTS_SECTION="$(get_step_plan_functional_requirements_section || true)"
if [[ -z "$STEP_PLAN_FUNCTIONAL_REQUIREMENTS_SECTION" ]]; then
  STEP_PLAN_FUNCTIONAL_REQUIREMENTS_SECTION="- (missing in step plan; add translated functional requirements before implementation closure)"
fi

ANTI_REGRESSION_CHECKLIST="$(build_anti_regression_checklist "$STEP_PLAN_UR_SHORTLIST_SECTION" "$DESIGN_UR_RULES_SECTION")"

emit() {
  printf 'Implementation phase for Step %s\n' "$STEP"
  printf '\n'
  printf 'Phase contract (read first)\n'
  printf '%s\n' '- Authoritative rules: ai/AI_DEVELOPMENT_PROCESS.md (Sections 3-4, verification gates, Definition of Done, prompt governance).'
  printf '%s\n' '- Artifact precedence: step plan (`ai/step_plans/step-<N>.md`) is primary execution source; feature design (`ai/step_designs/step-<N>-design.md`) supplies scope/design constraints.'
  printf '%s\n' '- Execution state machine: step plan `## Plan (ordered)` only; preserve order and checkbox semantics.'
  printf '%s\n' '- Execution requirements: implement against step-plan `## Functional Requirements (translated from design EARS)` and keep requirement-to-plan linkage intact.'
  printf '%s\n' '- Update `ai/step_plans/step-<N>.md` checklist state during implementation: mark each ordered bullet `[x]` only when that bullet is proven complete.'
  printf '%s\n' '- Update `ai/step_plans/step-<N>.md` functional requirement checklist: mark each FR line `[x]` only when implemented and verified; keep `[ ]` otherwise.'
  printf '%s\n' '- Verification strategy: targeted checks as needed per bullet; run full AGENTS.md verification once after all ordered bullets are `[x]`, before Section 5/User Review.'
  printf '%s\n' '- Section 4 gate requirement: before Section 5, all translated functional requirement checklist lines must be `[x]` with supporting evidence/tests.'
  printf '%s\n' '- Completion protocol: report progress against ordered bullets only; do not use `overmind/implementation_plan.md` target bullets as implementation-phase gating.'
  printf '%s\n' "- Before ending the implementation phase, run \`ai/scripts/helpers/check_implementation_readiness.sh $STEP\`."
  printf '%s\n' '- If that readiness check fails, do not emit the final completion line. Follow the Implementation Readiness Gate rules in `ai/AI_DEVELOPMENT_PROCESS.md`.'
  printf '%s\n' '- The `implementation_plan.md` target-bullet proof-check runs first in ai_audit entry gate.'
  printf '%s\n' '- Only after the Implementation Readiness Gate is satisfied, end your final response with: "Implementation phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase."'
  if [[ -n "$STEP_PLAN_LAR_SECTION" ]]; then
    printf '%s\n' '- Fetch rule (implementation): before implementing any FR that references a LAR-NNN, fetch the locator using available web/MCP tooling and use the fetched content as source of truth for whatever the artifact represents — UI details (spacing, icons, hover states, micro-interactions, breakpoints), schema structure (field names, types, constraints), API contracts (endpoints, payloads, error codes), architecture diagrams, or any other artifact-specific detail that FR text cannot fully encode. Stop and ask the user instead of inventing content when fetch fails or fetched content is ambiguous.'
  fi
  printf '\n'

  printf 'Anti-regression checklist (max 8)\n'
  printf '%s\n' "$ANTI_REGRESSION_CHECKLIST"
  printf '\n'

  printf 'Execution list (step plan `## Plan (ordered)`)\n'
  printf '%s\n\n' "$STEP_PLAN_ORDERED_PLAN_SECTION"

  printf 'Step-plan execution context\n'
  if [[ -n "$STEP_PLAN_LAR_SECTION" ]]; then
    printf '## Linked Artifacts (in scope)\n'
    printf '%s\n\n' "$STEP_PLAN_LAR_SECTION"
  fi
  printf '## Functional Requirements (translated from design EARS)\n'
  printf '%s\n\n' "$STEP_PLAN_FUNCTIONAL_REQUIREMENTS_SECTION"
  printf '## Applicable UR Shortlist\n'
  printf '%s\n\n' "$STEP_PLAN_UR_SHORTLIST_SECTION"
  printf '## Implementation Notes / Constraints\n'
  printf '%s\n\n' "$STEP_PLAN_IMPLEMENTATION_NOTES_SECTION"
  printf '## Tests\n'
  printf '%s\n\n' "$STEP_PLAN_TESTS_SECTION"
  printf '## Risks / Edge Cases\n'
  printf '%s\n\n' "$STEP_PLAN_RISKS_SECTION"
  printf '## Accepted Decisions (from `## Decisions Needed`)\n'
  printf '%s\n\n' "$STEP_PLAN_ACCEPTED_DECISIONS_SECTION"
  printf '## Decisions Needed (full section)\n'
  printf '%s\n\n' "$STEP_PLAN_DECISIONS_NEEDED_SECTION"

  printf 'Scope contract (design)\n'
  printf '## Goal\n'
  printf '%s\n\n' "$DESIGN_GOAL_SECTION"
  printf '## In Scope\n'
  printf '%s\n\n' "$DESIGN_IN_SCOPE_SECTION"
  printf '## Out of Scope\n'
  printf '%s\n\n' "$DESIGN_OUT_OF_SCOPE_SECTION"
  printf '## Non-goals\n'
  printf '%s\n\n' "$DESIGN_NON_GOALS_SECTION"

  printf 'Key design details (excerpt)\n'
  printf '## Proposal / Design Details\n'
  printf '%s\n\n' "$DESIGN_PROPOSAL_SECTION"
  printf '## Risks and Mitigations\n'
  printf '%s\n\n' "$DESIGN_RISKS_SECTION"
  printf '## Applicable ADR Shortlist\n'
  printf '%s\n\n' "$DESIGN_ADR_SECTION"
  printf '## Applicable AGENTS.md Constraints\n'
  printf '%s\n\n' "$DESIGN_AGENTS_SECTION"

  printf 'Codebase entrypoints (design references)\n'
  printf '## References in Current Codebase\n'
  printf '%s\n\n' "$DESIGN_REFERENCES_SECTION"

  printf 'Process pointers\n'
  printf -- '- Process rules: %s\n' "$PROCESS"
  if [[ "$INCLUDE_AGENTS" -eq 1 ]]; then
    printf -- '- AGENTS.md (inlined below)\n\n'
    printf '== AGENTS.md ==\n'
    cat "$AGENTS"
  else
    printf -- '- AGENTS.md pointer: %s\n' "$AGENTS"
  fi
}

mkdir -p "$(dirname "$OUT")"
emit >"$OUT"
