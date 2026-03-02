#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$(basename "$ROOT")"
PLAN="$ROOT/ai/implementation_plan.md"
PROCESS="$ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
DECISIONS="$ROOT/ai/decisions.md"
BLOCKER_LOG="$ROOT/ai/blocker_log.md"
OPEN_QUESTIONS="$ROOT/ai/open_questions.md"
REQUIREMENTS="$ROOT/reqirements_ears.md"
AGENTS="$ROOT/AGENTS.md"
STEP_PLAN_TEMPLATE="$ROOT/ai/templates/step_plan_TEMPLATE.md"
STEP_PLAN_GOLDEN="$ROOT/ai/golden_examples/step_plan_GOLDEN_EXAMPLE.md"

STEP=""
OUT=""
DESIGN_FILE=""
INCLUDE_AGENTS=0
BRANCH_NAME=""

usage() {
  cat <<'EOF'
Usage: ai/scripts/ai_plan.sh [--step 1.3] [--out file] [--design file] [--include-agents] [--branch-name name]

Defaults:
  - If --step is omitted, uses the first unchecked bullet in ai/implementation_plan.md.
  - If --out is omitted, uses ai/step_plans/step-<step>.md (created from ai/templates/step_plan_TEMPLATE.md if missing).
  - If --design is omitted, uses ai/step_designs/step-<step>-design.md (required; hard fail if missing).
  - ai/decisions.md is pointer-only by default.
  - AGENTS.md is referenced by default (pointer-only); use --include-agents to inline full contents.
  - Always creates/switches to branch step-<step>-plan unless --branch-name is provided.
EOF
}

confirm_start_planning_if_interactive() {
  local step="$1"
  local title="$2"
  local out="$3"
  local branch_name="$4"

  # If stdout is being captured (e.g., orchestrator redirects into a prompt file), do not prompt.
  if [[ ! -t 0 || ! -t 1 ]]; then
    return 0
  fi

  local answer=""
  while true; do
    printf 'Start planning phase for Step %s - %s\n' "$step" "$title" >&2
    printf 'This will create/switch to branch: %s\n' "$branch_name" >&2
    printf 'This will write/update: %s\n' "$out" >&2
    printf 'Proceed? [y/n] ' >&2
    IFS= read -r answer || answer=""
    case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
      y)
        return 0
        ;;
      n|'')
        return 1
        ;;
      *)
        echo "Please answer 'y' or 'n'." >&2
        ;;
    esac
  done
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

get_step_target_bullets() {
  local step="$1"
  awk -v step="$step" '
    BEGIN { step_re = step; gsub(/\./, "\\.", step_re) }
    $0 ~ "^### Step "step_re" " { in_step=1; next }
    in_step && $0 ~ "^## " { exit }
    in_step && $0 ~ "^### Step " { exit }
    in_step && $0 ~ /^- \[[ xX]\] / {
      line = $0
      sub(/^- \[[ xX]\] /, "- ", line)
      raw = line
      sub(/^- /, "", raw)
      if (raw ~ /^Plan and discuss the step([[:space:]\.]|$)/) next
      if (raw ~ /^Review step implementation([[:space:]\.]|$)/) next
      print line
    }
  ' "$PLAN"
}

get_step_section() {
  local step="$1"
  awk -v step="$step" '
    BEGIN { step_re = step; gsub(/\./, "\\.", step_re) }
    $0 ~ "^### Step "step_re" " { in_step=1 }
    in_step && $0 ~ "^## " && $0 !~ "^### Step "step_re" " { exit }
    in_step && $0 ~ "^### Step " && $0 !~ "^### Step "step_re" " { exit }
    in_step { print }
  ' "$PLAN"
}

get_design_target_bullets() {
  local file="$1"
  awk '
    /^## Target Bullets/ { in_section=1; next }
    in_section && /^## / { exit }
    in_section && /^- / { print }
  ' "$file"
}

get_blocker_log_section() {
  local step="$1"
  awk -v step="$step" '
    BEGIN { step_re = step; gsub(/\./, "\\.", step_re) }
    $0 ~ "^## Step "step_re" " { in_step=1 }
    in_step && $0 ~ "^## Step " && $0 !~ "^## Step "step_re" " { exit }
    in_step { print }
  ' "$BLOCKER_LOG"
}

get_open_questions_section() {
  local step="$1"
  awk -v step="$step" '
    BEGIN { step_re = step; gsub(/\./, "\\.", step_re) }
    $0 ~ "^## Step "step_re" " { in_step=1 }
    in_step && $0 ~ "^## Step " && $0 !~ "^## Step "step_re" " { exit }
    in_step { print }
  ' "$OPEN_QUESTIONS"
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

get_design_adr_heading() {
  local file="$1"
  if grep -Fq "## Applicable ADR Shortlist (from ai/decisions.md)" "$file"; then
    printf '## Applicable ADR Shortlist (from ai/decisions.md)'
    return 0
  fi
  if grep -Fq "## Applicable ADR Shortlist" "$file"; then
    printf '## Applicable ADR Shortlist'
    return 0
  fi
  return 1
}

get_design_ur_heading() {
  local file="$1"
  if grep -Fq "## Applicable UR Shortlist" "$file"; then
    printf '## Applicable UR Shortlist'
    return 0
  fi
  if grep -Fq "## Applicable User Review Rules" "$file"; then
    printf '## Applicable User Review Rules'
    return 0
  fi
  return 1
}

get_design_things_to_decide_heading() {
  local file="$1"
  if grep -Fq "## Things to Decide (for final planning discussion)" "$file"; then
    printf '## Things to Decide (for final planning discussion)'
    return 0
  fi
  if grep -Fq "## Things to Decide" "$file"; then
    printf '## Things to Decide'
    return 0
  fi
  return 1
}

open_questions_has_any() {
  local section="$1"
  printf '%s\n' "$section" | awk '
    /^- / {
      if ($0 !~ /^- No open questions\./) { found=1 }
    }
    END { exit(found ? 0 : 1) }
  '
}

list_accepted_adrs() {
  awk '
    function flush() {
      if (header != "" && status ~ /^Accepted/) {
        sub(/^## /, "", header)
        print "- " header
      }
    }
    /^## ADR-/ { flush(); header=$0; status=""; next }
    /^- \*\*Status\*\*: / { status=$0; sub(/^- \*\*Status\*\*: /, "", status); next }
    END { flush() }
  ' "$DECISIONS"
}

extract_requirement_section() {
  local req="$1"
  awk -v req="$req" '
    BEGIN { req_re = req; gsub(/\./, "\\.", req_re) }
    $0 ~ "^### Requirement "req_re" " { in_req=1 }
    in_req && $0 ~ "^### Requirement " && $0 !~ "^### Requirement "req_re" " { exit }
    in_req { print }
  ' "$REQUIREMENTS"
}

get_requirements_section() {
  local step_section="$1"
  local reqs
  reqs="$(printf '%s\n' "$step_section" | grep -oE "\\[REQ-[0-9]+(\\.[0-9]+)?\\]" | tr -d '[]' | sed 's/^REQ-//' | sort -u)"
  if [[ -z "$reqs" ]]; then
    echo "No requirement tags found. Add [REQ-<number>] to step bullets to include spec sections."
    return 0
  fi

  local output=""
  local req
  while IFS= read -r req; do
    [[ -z "$req" ]] && continue
    local section
    section="$(extract_requirement_section "$req")"
    if [[ -z "$section" && "$req" == *.* ]]; then
      section="$(extract_requirement_section "${req%%.*}")"
    fi
    if [[ -n "$section" ]]; then
      output+="$section"$'\n\n'
    else
      output+="Requirement $req not found in reqirements_ears.md"$'\n\n'
    fi
  done <<<"$reqs"

  printf '%s' "$output"
}

get_requirement_tags() {
  local step_section="$1"
  local req_tags
  req_tags="$(printf '%s\n' "$step_section" | grep -oE "\\[REQ-[0-9]+(\\.[0-9]+)?\\]" || true)"
  if [[ -z "$req_tags" ]]; then
    return 0
  fi
  printf '%s\n' "$req_tags" | tr -d '[]' | sort -u
}

get_process_planning_sections() {
  awk '
    /^### 2\)/ { in_scope=1 }
    /^### 3\)/ { exit }
    in_scope { print }
  ' "$PROCESS"
}

get_process_estimation_gates() {
  awk '
    /^## Estimation Gates/ { in_scope=1 }
    /^## Definition of Done/ { exit }
    in_scope { print }
  ' "$PROCESS"
}

extract_step_plan_template_body() {
  if [[ ! -f "$STEP_PLAN_TEMPLATE" ]]; then
    return 1
  fi
  awk '
    /^---[[:space:]]*$/ { in_body=1; next }
    in_body { print }
  ' "$STEP_PLAN_TEMPLATE"
}

ensure_planning_branch() {
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not a git repository: $ROOT" >&2
    exit 1
  fi

  local target
  target="$BRANCH_NAME"
  if [[ -z "$target" ]]; then
    target="step-$STEP-plan"
  fi

  local current
  current="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  if [[ "$current" == "$target" ]]; then
    return 0
  fi

  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$target"; then
    if ! git -C "$ROOT" checkout "$target" >/dev/null; then
      echo "Failed to switch to existing branch: $target" >&2
      exit 1
    fi
    echo "Switched to existing branch: $target" >&2
  else
    if ! git -C "$ROOT" checkout -b "$target" >/dev/null; then
      echo "Failed to create and switch to branch: $target" >&2
      exit 1
    fi
    echo "Created and switched to branch: $target" >&2
  fi
}

write_step_plan_from_template() {
  local date
  date="$(date +%Y-%m-%d)"
  local req_lines
  if [[ -n "$REQ_TAGS" ]]; then
    req_lines="$(printf '%s\n' "$REQ_TAGS" | sed 's/^/- /')"
  else
    req_lines="- (none)"
  fi

  local body
  if ! body="$(extract_step_plan_template_body)"; then
    echo "Step plan template not found: $STEP_PLAN_TEMPLATE" >&2
    exit 1
  fi

  local in_req_tags=0
  while IFS= read -r line; do
    case "$line" in
      "# Step Plan: <step> - <step title>")
        printf '# Step Plan: %s - %s\n' "$STEP" "$STEP_TITLE"
        ;;
      "Date: <YYYY-MM-DD>")
        printf 'Date: %s\n' "$date"
        ;;
      "- <bullet text>")
        if [[ -n "$TARGET_BULLETS" ]]; then
          printf '%s\n' "$TARGET_BULLETS"
        else
          printf '%s\n' "- (missing; extract from feature design)"
        fi
        ;;
      "## Requirement Tags")
        printf '%s\n' "$line"
        in_req_tags=1
        ;;
      "- <REQ tags from ai/implementation_plan.md (or (none))>")
        if [[ "$in_req_tags" -eq 1 ]]; then
          printf '%s\n' "$req_lines"
          in_req_tags=0
        else
          printf '%s\n' "$line"
        fi
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done <<<"$body" >"$OUT"
}

fail_ur_shortlist_validation() {
  local reason="$1"
  echo "Planning gate failed for step plan: $reason" >&2
  echo "Required section: ## Applicable UR Shortlist" >&2
  echo "Accepted content:" >&2
  echo "- exact: - None." >&2
  echo "- or curated bullets containing UR-xxxx IDs (recommended 3-8, max 8)." >&2
  exit 1
}

validate_applicable_ur_shortlist_section() {
  if ! grep -Fq "## Applicable UR Shortlist" "$OUT"; then
    fail_ur_shortlist_validation "missing section \`## Applicable UR Shortlist\`."
  fi

  local shortlist_section
  shortlist_section="$(get_markdown_section_body "$OUT" "## Applicable UR Shortlist")"
  if [[ -z "${shortlist_section//[[:space:]]/}" ]]; then
    fail_ur_shortlist_validation "section is empty."
  fi

  local -a shortlist_lines=()
  local line
  while IFS= read -r line; do
    if [[ -n "${line//[[:space:]]/}" ]]; then
      shortlist_lines+=("$line")
    fi
  done <<<"$shortlist_section"

  if [[ "${#shortlist_lines[@]}" -eq 0 ]]; then
    fail_ur_shortlist_validation "section has no shortlist entries."
  fi

  if [[ "${#shortlist_lines[@]}" -eq 1 && "${shortlist_lines[0]}" == "- None." ]]; then
    return 0
  fi

  local ur_count=0
  local matches match_count
  for line in "${shortlist_lines[@]}"; do
    if [[ "$line" == "- None." ]]; then
      fail_ur_shortlist_validation "mixed shortlist content is not allowed; use only \`- None.\` or only UR-ID bullets."
    fi
    if [[ ! "$line" =~ ^-[[:space:]]+ ]]; then
      fail_ur_shortlist_validation "non-bullet content found in shortlist: $line"
    fi

    matches="$(printf '%s\n' "$line" | grep -oE 'UR-[0-9]{4}' || true)"
    if [[ -z "$matches" ]]; then
      fail_ur_shortlist_validation "invalid shortlist entry (missing UR-xxxx): $line"
    fi

    match_count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
    ur_count=$((ur_count + match_count))
  done

  if [[ "$ur_count" -gt 8 ]]; then
    fail_ur_shortlist_validation "too many UR IDs ($ur_count). Prioritize to 8 or fewer IDs."
  fi
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
    --design)
      require_option_arg "--design" "${2:-}"
      DESIGN_FILE="$2"
      shift 2
      ;;
    --branch-name)
      require_option_arg "--branch-name" "${2:-}"
      BRANCH_NAME="$2"
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

if [[ -z "$STEP" ]]; then
  line="$(get_next_unchecked)"
  if [[ -z "$line" ]]; then
    echo "No unchecked bullets found in ai/implementation_plan.md." >&2
    exit 1
  fi
  IFS='|' read -r STEP STEP_TITLE BULLET <<<"$line"
else
  STEP_TITLE="$(get_step_title "$STEP")"
  if [[ -z "$STEP_TITLE" ]]; then
    echo "Step $STEP not found in ai/implementation_plan.md." >&2
    exit 1
  fi
  BULLET="$(get_step_first_unchecked "$STEP")"
  if [[ -z "$BULLET" ]]; then
    BULLET="(no unchecked bullets in step)"
  fi
fi

if [[ -z "$OUT" ]]; then
  OUT="$ROOT/ai/step_plans/step-$STEP.md"
fi

if [[ -z "$DESIGN_FILE" ]]; then
  DESIGN_FILE="$ROOT/ai/step_designs/step-$STEP-design.md"
fi

if [[ ! -f "$DESIGN_FILE" ]]; then
  echo "Feature design artifact not found at $DESIGN_FILE." >&2
  echo "Run ai/scripts/ai_design.sh --step $STEP first." >&2
  exit 1
fi

PLANNING_BRANCH="$BRANCH_NAME"
if [[ -z "$PLANNING_BRANCH" ]]; then
  PLANNING_BRANCH="step-$STEP-plan"
fi
if ! confirm_start_planning_if_interactive "$STEP" "$STEP_TITLE" "$OUT" "$PLANNING_BRANCH"; then
  echo "Aborted." >&2
  exit 1
fi

ensure_planning_branch

STEP_SECTION="$(get_step_section "$STEP")"
if [[ -z "$STEP_SECTION" ]]; then
  echo "Step $STEP section not found in ai/implementation_plan.md." >&2
  exit 1
fi

TARGET_BULLETS="$(get_design_target_bullets "$DESIGN_FILE")"
if [[ -z "$TARGET_BULLETS" ]]; then
  TARGET_BULLETS="$(get_step_target_bullets "$STEP")"
fi
if [[ -z "$TARGET_BULLETS" ]]; then
  TARGET_BULLETS="- (no execution bullets found)"
fi

BLOCKER_LOG_SECTION="$(get_blocker_log_section "$STEP")"
if [[ -z "$BLOCKER_LOG_SECTION" ]]; then
  BLOCKER_LOG_SECTION="## Step $STEP (missing)
- No blocker log section found."
fi

OPEN_QUESTIONS_SECTION="$(get_open_questions_section "$STEP")"
if [[ -z "$OPEN_QUESTIONS_SECTION" ]]; then
  OPEN_QUESTIONS_SECTION="## Step $STEP (missing)
- No open questions section found."
fi
OPEN_QUESTIONS_HAS_ANY=0
if open_questions_has_any "$OPEN_QUESTIONS_SECTION"; then
  OPEN_QUESTIONS_HAS_ANY=1
fi

REQ_SECTION="$(get_requirements_section "$STEP_SECTION")"
REQ_TAGS="$(get_requirement_tags "$STEP_SECTION")"
DESIGN_AGENTS_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "## Applicable AGENTS.md Constraints")"
if [[ -z "$DESIGN_AGENTS_SECTION" ]]; then
  DESIGN_AGENTS_SECTION="- (missing in design artifact; update ai/step_designs/step-$STEP-design.md)"
fi
if DESIGN_UR_HEADING="$(get_design_ur_heading "$DESIGN_FILE")"; then
  DESIGN_UR_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "$DESIGN_UR_HEADING")"
else
  DESIGN_UR_SECTION="- (missing in design artifact; update ai/step_designs/step-$STEP-design.md)"
fi
if [[ -z "$DESIGN_UR_SECTION" ]]; then
  DESIGN_UR_SECTION="- (missing in design artifact; update ai/step_designs/step-$STEP-design.md)"
fi
if DESIGN_ADR_HEADING="$(get_design_adr_heading "$DESIGN_FILE")"; then
  DESIGN_ADR_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "$DESIGN_ADR_HEADING")"
else
  DESIGN_ADR_SECTION="- (missing in design artifact; update ai/step_designs/step-$STEP-design.md)"
fi
if [[ -z "$DESIGN_ADR_SECTION" ]]; then
  DESIGN_ADR_SECTION="- (missing in design artifact; update ai/step_designs/step-$STEP-design.md)"
fi
if DESIGN_THINGS_TO_DECIDE_HEADING="$(get_design_things_to_decide_heading "$DESIGN_FILE")"; then
  DESIGN_THINGS_TO_DECIDE_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "$DESIGN_THINGS_TO_DECIDE_HEADING")"
else
  DESIGN_THINGS_TO_DECIDE_SECTION="- (missing in design artifact; derive plan-critical decisions from design trade-offs/risks as needed)"
fi
if [[ -z "$DESIGN_THINGS_TO_DECIDE_SECTION" ]]; then
  DESIGN_THINGS_TO_DECIDE_SECTION="- (empty in design artifact; derive plan-critical decisions from design trade-offs/risks as needed)"
fi

mkdir -p "$(dirname "$OUT")"
if [[ ! -f "$OUT" ]]; then
  write_step_plan_from_template
fi
validate_applicable_ur_shortlist_section

emit() {
  local out_label
  if [[ "$OUT" == "$ROOT/"* ]]; then
    out_label="${OUT#"$ROOT"/}"
  else
    out_label="$OUT"
  fi

  local design_label
  if [[ "$DESIGN_FILE" == "$ROOT/"* ]]; then
    design_label="${DESIGN_FILE#"$ROOT"/}"
  else
    design_label="$DESIGN_FILE"
  fi

  printf 'Planning phase for Step %s.\n' "$STEP"
  printf 'Use ai/AI_DEVELOPMENT_PROCESS.md (Section 2, Estimation Gates, Prompt governance) as the process rules for this phase.\n'
  printf 'Strict workflow: execute Section 2 in two mandatory sub-phases: 2.1) Planning draft and decision capture, then 2.2) Plan quality gates and closure.\n'
  printf 'Do not start 2.2 before finishing 2.1 outputs (draft plan sections, prerequisites, assumptions, risks, tests/docs, and `Decisions Needed` entries).\n'
  printf 'In 2.2, enforce all planning quality gates: open-questions gate, things-to-decide gate, and decision-confirmation gate.\n'
  printf 'Decision prompts (required for unresolved design decisions): for each unresolved item in design `## Things to Decide`, ask exactly two options (`1.` recommended, `2.` alternative) and accept numeric reply `1` or `2`.\n'
  printf 'If design `## Things to Decide` is missing or weak, derive concrete plan-critical decisions from design trade-offs/risks/prerequisites and ask two-option prompts when the choice impacts implementation path.\n'
  printf 'If no plan-critical trade-off remains, explicitly state why no additional decision prompt is needed before closing planning.\n'
  printf 'Do not mark planning complete while any gate is unresolved; continue planning discussion and update artifacts until all gates pass.\n'
  printf 'Use the feature design artifact as the primary input and convert it into an execution-focused step plan.\n'
  printf 'Execution scope must come from design target bullets (excluding planning/review bullets).\n'
  printf 'Derive non-negotiable invariants from design-extracted ADR shortlist + AGENTS constraints.\n'
  printf 'When planning phase is fully complete, end your final response with this exact last line: "Planning phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase."\n'
  printf 'Commit gate: when you commit planning artifacts, include both the step plan and the feature design artifact (do not commit only %s).\n' "$out_label"
  printf 'Minimum commit set (if changed): %s, %s\n' "$out_label" "$design_label"
  printf 'Write/update the step plan at: %s\n' "$OUT"
  printf 'Feature design artifact (required): %s\n' "$DESIGN_FILE"
  if [[ "$OPEN_QUESTIONS_HAS_ANY" -eq 1 ]]; then
    printf 'Open questions currently present for this step: YES.\n'
  else
    printf 'Open questions currently present for this step: NO.\n'
  fi
  printf 'Use golden examples from the context pack.\n'
  printf '\n'
  printf 'Context pack\n'
  printf '== ai/implementation_plan.md (Step %s - %s) ==\n' "$STEP" "$STEP_TITLE"
  printf '%s\n\n' "$STEP_SECTION"
  printf '== ai/step_designs/step-%s-design.md ==\n' "$STEP"
  cat "$DESIGN_FILE"
  printf '\n\n'
  printf '== Design-extracted target bullets ==\n'
  printf '%s\n\n' "$TARGET_BULLETS"
  printf '== Design-extracted AGENTS constraints ==\n'
  printf '%s\n\n' "$DESIGN_AGENTS_SECTION"
  printf '== Design-extracted user review rules ==\n'
  printf '%s\n\n' "$DESIGN_UR_SECTION"
  printf '== Design-extracted ADR shortlist ==\n'
  printf '%s\n\n' "$DESIGN_ADR_SECTION"
  printf '== Design-extracted things to decide ==\n'
  printf '%s\n\n' "$DESIGN_THINGS_TO_DECIDE_SECTION"
  printf '== %s ==\n' "$out_label"
  cat "$OUT"
  printf '\n\n'
  if [[ -f "$STEP_PLAN_GOLDEN" ]]; then
    printf '== ai/golden_examples/step_plan_GOLDEN_EXAMPLE.md ==\n'
    printf 'Read directly from repo as example reference.\n'
    printf 'Path: ai/golden_examples/step_plan_GOLDEN_EXAMPLE.md\n\n'
  fi
  printf '== reqirements_ears.md (linked requirements) ==\n'
  printf '%s\n\n' "$REQ_SECTION"
  printf '== ai/blocker_log.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$BLOCKER_LOG_SECTION"
  printf '== ai/open_questions.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$OPEN_QUESTIONS_SECTION"
  printf '== ai/decisions.md (Accepted ADRs) ==\n'
  printf 'Pointer-only by default: rely on design-extracted ADR shortlist above.\n'
  printf 'Path: ai/decisions.md\n\n'
  printf '== ai/AI_DEVELOPMENT_PROCESS.md (Planning + Estimation) ==\n'
  planning_sections="$(get_process_planning_sections)"
  estimation_gates="$(get_process_estimation_gates)"
  if [[ -n "$planning_sections" ]]; then
    printf '%s\n\n' "$planning_sections"
  else
    cat "$PROCESS"
    printf '\n\n'
  fi
  if [[ -n "$estimation_gates" ]]; then
    printf '%s\n' "$estimation_gates"
  fi
  if [[ "$INCLUDE_AGENTS" -eq 1 ]]; then
    printf '\n\n== AGENTS.md ==\n'
    cat "$AGENTS"
  else
    printf '\n\n== AGENTS.md ==\n'
    printf 'Read directly from repo and extract only constraints relevant to this step.\n'
    printf 'Path: AGENTS.md\n'
  fi
}

emit
