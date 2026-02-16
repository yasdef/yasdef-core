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
MODELS="$ROOT/ai/setup/models.md"
STEP_PLAN_TEMPLATE="$ROOT/ai/templates/step_plan_TEMPLATE.md"
STEP_PLAN_GOLDEN="$ROOT/ai/golden_examples/step_plan_GOLDEN_EXAMPLE.md"

STEP=""
OUT=""
FULL_DECISIONS=0
INCLUDE_AGENTS=1
INCLUDE_MODELS=1
BRANCH_NAME=""

usage() {
  cat <<'EOF'
Usage: ai/scripts/ai_plan.sh [--step 1.3] [--out file] [--full-decisions] [--no-include-agents] [--no-include-models] [--branch-name name]

Defaults:
  - If --step is omitted, uses the first unchecked bullet in ai/implementation_plan.md.
  - If --out is omitted, uses ai/step_plans/step-<step>.md (created from ai/templates/step_plan_TEMPLATE.md if missing).
  - ai/decisions.md is summarized to Accepted ADR titles unless --full-decisions is set.
  - AGENTS.md is included by default; use --no-include-agents to omit.
  - ai/setup/models.md is included by default; use --no-include-models to omit.
  - Implementation run command uses ai/setup/models.md (phase | command | model | extra args optional).
  - Always creates/switches to branch step-<step>-plan unless --branch-name is provided.
EOF
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

shell_join() {
  local joined=""
  local arg
  for arg in "$@"; do
    joined+=$(printf '%q ' "$arg")
  done
  printf '%s' "${joined% }"
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

get_step_section() {
  local step="$1"
  awk -v step="$step" '
    BEGIN { step_re = step; gsub(/\./, "\\.", step_re) }
    $0 ~ "^### Step "step_re" " { in_step=1 }
    in_step && $0 ~ "^### Step " && $0 !~ "^### Step "step_re" " { exit }
    in_step { print }
  ' "$PLAN"
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

get_model_entry() {
  local phase="$1"
  if [[ ! -f "$MODELS" ]]; then
    echo "Models file not found: $MODELS" >&2
    exit 1
  fi
  awk -F'|' -v phase="$phase" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[[:space:]]*#/ { next }
    NF < 3 { next }
    {
      key = trim($1)
      cmd = trim($2)
      model = trim($3)
      if (tolower(key) == tolower(phase)) {
        print cmd
        print model
        for (i = 4; i <= NF; i++) {
          arg = trim($i)
          if (arg != "") { print arg }
        }
        exit
      }
    }
  ' "$MODELS"
}

ensure_run_command() {
  local fields=()
  local field
  while IFS= read -r field; do
    fields+=("$field")
  done < <(get_model_entry "implementation")

  if [[ ${#fields[@]} -lt 2 ]]; then
    echo "Implementation model not found in $MODELS. Add: implementation | <command> | <model>" >&2
    exit 1
  fi

  local run_cmd run_model
  run_cmd="${fields[0]}"
  run_model="${fields[1]}"
  if [[ -z "$run_cmd" || -z "$run_model" ]]; then
    echo "Invalid implementation model entry in $MODELS (expected: implementation | <command> | <model>)." >&2
    exit 1
  fi
  local run_args_parts=()
  if [[ ${#fields[@]} -gt 2 ]]; then
    run_args_parts=("${fields[@]:2}")
  fi

  local plan_path
  if [[ "$OUT" == "$ROOT/"* ]]; then
    plan_path="${OUT#"$ROOT"/}"
  else
    plan_path="$OUT"
  fi
  local prompt_out
  prompt_out="ai/prompts/impl_prompts/${PROJECT}-step-$STEP.prompt.txt"

  local prompt_cmd
  prompt_cmd="$(shell_join ai/scripts/ai_implementation.sh --step-plan "$plan_path" --out "$prompt_out")"

  local run_line
  run_line="$(printf '%q' "$run_cmd") -m $(printf '%q' "$run_model")"
  local run_arg
  for run_arg in "${run_args_parts[@]}"; do
    run_line+=" $(printf '%q' "$run_arg")"
  done
  run_line+=" $(printf '%q' "run $prompt_out")"
  run_line="$prompt_cmd && $run_line"

  local block
  block="$(cat <<EOF

## User Command (manual only - do not execute in assistant)
This command is for the human operator to run locally if needed.
AI_RUN_COMMAND_VERSION: 2
AI_RUN_KIND: implementation
AI_STEP_PLAN: $plan_path
AI_PROMPT_OUT: $prompt_out
AI_IMPL_RUN_CMD: $run_cmd
AI_IMPL_MODEL: $run_model
$(for run_arg in "${run_args_parts[@]}"; do printf 'AI_IMPL_ARG: %s\n' "$run_arg"; done)
AI_RUN_COMMAND: $run_line
\`$run_line\`
EOF
)"

  if grep -Fq "## User Command (manual only - do not execute in assistant)" "$OUT"; then
    local tmp_dir tmp
    tmp_dir="$ROOT/ai/tmp"
    mkdir -p "$tmp_dir"
    tmp="$tmp_dir/${PROJECT}-step-${STEP}.plan.$$.tmp"
    awk '
      /^## User Command \(manual only - do not execute in assistant\)/ { exit }
      { print }
    ' "$OUT" >"$tmp"
    printf '%s\n' "$block" >>"$tmp"
    mv "$tmp" "$OUT"
  else
    printf '%s\n' "$block" >>"$OUT"
  fi
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
    /^### 1\)/ { in_scope=1 }
    /^### 2\)/ { exit }
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
        printf -- '- %s\n' "$BULLET"
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

ensure_applicable_ur_shortlist_section() {
  if grep -Fq "## Applicable UR Shortlist" "$OUT"; then
    return 0
  fi

  local today
  today="$(date +%Y-%m-%d)"

  local tmp_dir tmp
  tmp_dir="$ROOT/ai/tmp"
  mkdir -p "$tmp_dir"
  tmp="$tmp_dir/${PROJECT}-step-${STEP}.ur-shortlist.$$.tmp"

  awk -v today="$today" '
    BEGIN { inserted = 0 }
    /^## Plan \(ordered\)/ && inserted == 0 {
      print "## Applicable UR Shortlist"
      print "- None applicable for this step/bullet. (reviewed on " today ")"
      print ""
      inserted = 1
    }
    { print }
    END {
      if (inserted == 0) {
        print ""
        print "## Applicable UR Shortlist"
        print "- None applicable for this step/bullet. (reviewed on " today ")"
      }
    }
  ' "$OUT" >"$tmp"

  mv "$tmp" "$OUT"
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
    --branch-name)
      require_option_arg "--branch-name" "${2:-}"
      BRANCH_NAME="$2"
      shift 2
      ;;
    --full-decisions)
      FULL_DECISIONS=1
      shift
      ;;
    --include-agents)
      INCLUDE_AGENTS=1
      shift
      ;;
    --no-include-agents)
      INCLUDE_AGENTS=0
      shift
      ;;
    --include-models)
      INCLUDE_MODELS=1
      shift
      ;;
    --no-include-models)
      INCLUDE_MODELS=0
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

ensure_planning_branch

STEP_SECTION="$(get_step_section "$STEP")"
if [[ -z "$STEP_SECTION" ]]; then
  echo "Step $STEP section not found in ai/implementation_plan.md." >&2
  exit 1
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

if [[ "$FULL_DECISIONS" -eq 1 ]]; then
  DECISIONS_SECTION="$(cat "$DECISIONS")"
else
  DECISIONS_SECTION="$(list_accepted_adrs)"
  if [[ -z "$DECISIONS_SECTION" ]]; then
    DECISIONS_SECTION="- (none)"
  fi
fi

mkdir -p "$(dirname "$OUT")"
if [[ ! -f "$OUT" ]]; then
  write_step_plan_from_template
fi
ensure_applicable_ur_shortlist_section
ensure_run_command

emit() {
  local out_label
  if [[ "$OUT" == "$ROOT/"* ]]; then
    out_label="${OUT#"$ROOT"/}"
  else
    out_label="$OUT"
  fi

  printf 'Planning phase for Step %s bullet: %s\n' "$STEP" "$BULLET"
  printf 'Use ai/AI_DEVELOPMENT_PROCESS.md (Section 1, Estimation Gates, Prompt governance) and AGENTS.md as the authoritative rules for this phase.\n'
  printf 'Write/update the step plan at: %s\n' "$OUT"
  if [[ "$OPEN_QUESTIONS_HAS_ANY" -eq 1 ]]; then
    printf 'Open questions currently present for this step: YES.\n'
  else
    printf 'Open questions currently present for this step: NO.\n'
  fi
  printf 'Use templates/golden examples from the context pack.\n'
  printf '\n'
  printf 'Context pack\n'
  printf '== ai/implementation_plan.md (Step %s - %s) ==\n' "$STEP" "$STEP_TITLE"
  printf '%s\n\n' "$STEP_SECTION"
  printf '== %s ==\n' "$out_label"
  cat "$OUT"
  printf '\n\n'
  if [[ -f "$STEP_PLAN_TEMPLATE" ]]; then
    printf '== ai/templates/step_plan_TEMPLATE.md ==\n'
    cat "$STEP_PLAN_TEMPLATE"
    printf '\n\n'
  fi
  if [[ -f "$STEP_PLAN_GOLDEN" ]]; then
    printf '== ai/golden_examples/step_plan_GOLDEN_EXAMPLE.md ==\n'
    cat "$STEP_PLAN_GOLDEN"
    printf '\n\n'
  fi
  if [[ "$INCLUDE_MODELS" -eq 1 && -f "$MODELS" ]]; then
    printf '== ai/setup/models.md ==\n'
    cat "$MODELS"
    printf '\n\n'
  fi
  printf '== reqirements_ears.md (linked requirements) ==\n'
  printf '%s\n\n' "$REQ_SECTION"
  printf '== ai/blocker_log.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$BLOCKER_LOG_SECTION"
  printf '== ai/open_questions.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$OPEN_QUESTIONS_SECTION"
  printf '== ai/decisions.md (Accepted ADRs) ==\n'
  printf '%s\n\n' "$DECISIONS_SECTION"
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
  fi
}

emit
