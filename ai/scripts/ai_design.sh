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
USER_REVIEW="$ROOT/ai/user_review.md"
DESIGN_TEMPLATE="$ROOT/ai/templates/feature_design_TEMPLATE.md"
DESIGN_GOLDEN="$ROOT/ai/golden_examples/feature_design_GOLDEN_EXAMPLE.md"

STEP=""
DESIGN_OUT=""
INCLUDE_AGENTS=0
BRANCH_NAME=""
TARGET_BULLETS=""

usage() {
  cat <<'EOF'
Usage: ai/scripts/ai_design.sh [--step 1.3] [--design-out file] [--branch-name name] [--include-agents]

Defaults:
  - If --step is omitted, uses the first unchecked bullet in ai/implementation_plan.md.
  - If --design-out is omitted, uses ai/step_designs/step-<step>-design.md (created from ai/templates/feature_design_TEMPLATE.md if missing).
  - ai/decisions.md is pointer-only by default.
  - AGENTS.md is referenced by default (not inlined); use --include-agents to inline.
  - Creates/switches to branch step-<step>-plan unless --branch-name is provided.

Compatibility:
  - Accepts --out/--include-models/--no-include-models and ignores them, so orchestrator planning args can be reused.
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
    in_step && $0 ~ "^## " && $0 !~ "^### Step "step_re" " { exit }
    in_step && $0 ~ "^### Step " && $0 !~ "^### Step "step_re" " { exit }
    in_step { print }
  ' "$PLAN"
}

get_step_design_bullets() {
  local step_section="$1"
  printf '%s\n' "$step_section" | awk '
    /^- \[[ xX]\] / {
      line = $0
      sub(/^- \[[ xX]\] /, "", line)
      if (line ~ /^Plan and discuss the step([[:space:]\.]|$)/) { next }
      if (line ~ /^Review step implementation([[:space:]\.]|$)/) { next }
      print "- [ ] " line
    }
  '
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

get_process_design_section() {
  awk '
    /^### 1\)/ { in_scope=1 }
    /^### 2\)/ { exit }
    in_scope { print }
  ' "$PROCESS"
}

extract_feature_design_template_body() {
  if [[ ! -f "$DESIGN_TEMPLATE" ]]; then
    return 1
  fi
  awk '
    /^---[[:space:]]*$/ { in_body=1; next }
    in_body { print }
  ' "$DESIGN_TEMPLATE"
}

ensure_design_branch() {
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

write_design_from_template() {
  local date
  date="$(date +%Y-%m-%d)"

  local body
  if ! body="$(extract_feature_design_template_body)"; then
    echo "Feature design template not found: $DESIGN_TEMPLATE" >&2
    exit 1
  fi

  while IFS= read -r line; do
    case "$line" in
      "# Feature Design: <step> - <step title>")
        printf '# Feature Design: %s - %s\n' "$STEP" "$STEP_TITLE"
        ;;
      "Date: <YYYY-MM-DD>")
        printf 'Date: %s\n' "$date"
        ;;
      "- <target bullets from step (excluding planning/review)>")
        if [[ -n "$TARGET_BULLETS" ]]; then
          printf '%s\n' "$TARGET_BULLETS"
        else
          printf -- '- (none found; verify ai/implementation_plan.md step bullets)\n'
        fi
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done <<<"$body" >"$DESIGN_OUT"
}

ensure_applicable_adr_shortlist_section() {
  if grep -Fq "## Applicable ADR Shortlist (from ai/decisions.md)" "$DESIGN_OUT"; then
    return 0
  fi
  if grep -Fq "## Applicable ADR Shortlist" "$DESIGN_OUT"; then
    return 0
  fi

  local today
  today="$(date +%Y-%m-%d)"

  local tmp_dir tmp
  tmp_dir="$ROOT/ai/tmp"
  mkdir -p "$tmp_dir"
  tmp="$tmp_dir/${PROJECT}-step-${STEP}.adr-shortlist.$$.tmp"

  awk -v today="$today" '
    BEGIN { inserted = 0 }
    /^## Applicable AGENTS\.md Constraints/ && inserted == 0 {
      print "## Applicable ADR Shortlist (from ai/decisions.md)"
      print "- None applicable for this feature. (reviewed on " today ")"
      print ""
      inserted = 1
    }
    { print }
    END {
      if (inserted == 0) {
        print ""
        print "## Applicable ADR Shortlist (from ai/decisions.md)"
        print "- None applicable for this feature. (reviewed on " today ")"
      }
    }
  ' "$DESIGN_OUT" >"$tmp"

  mv "$tmp" "$DESIGN_OUT"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)
      require_option_arg "--step" "${2:-}"
      STEP="$2"
      shift 2
      ;;
    --design-out)
      require_option_arg "--design-out" "${2:-}"
      DESIGN_OUT="$2"
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
    --out)
      require_option_arg "--out" "${2:-}"
      shift 2
      ;;
    --include-models|--no-include-models)
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

if [[ -z "$DESIGN_OUT" ]]; then
  DESIGN_OUT="$ROOT/ai/step_designs/step-$STEP-design.md"
fi

ensure_design_branch

STEP_SECTION="$(get_step_section "$STEP")"
if [[ -z "$STEP_SECTION" ]]; then
  echo "Step $STEP section not found in ai/implementation_plan.md." >&2
  exit 1
fi
TARGET_BULLETS="$(get_step_design_bullets "$STEP_SECTION")"

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

REQ_SECTION="$(get_requirements_section "$STEP_SECTION")"

mkdir -p "$(dirname "$DESIGN_OUT")"
if [[ ! -f "$DESIGN_OUT" ]]; then
  write_design_from_template
fi
ensure_applicable_adr_shortlist_section

emit() {
  local design_label
  if [[ "$DESIGN_OUT" == "$ROOT/"* ]]; then
    design_label="${DESIGN_OUT#"$ROOT"/}"
  else
    design_label="$DESIGN_OUT"
  fi

  printf 'Feature design phase for Step %s\n' "$STEP"
  printf 'Target bullets (excluding planning/review):\n%s\n' "${TARGET_BULLETS:-- (none found; verify step bullets)}"
  printf 'Use ai/AI_DEVELOPMENT_PROCESS.md (Section 1) as process rules.\n'
  printf 'Create/update feature design at: %s\n' "$DESIGN_OUT"
  printf 'This design artifact is mandatory input for planning and implementation phases.\n'
  printf 'Shortlist relevant accepted ADRs into design section "Applicable ADR Shortlist (from ai/decisions.md)".\n'
  printf '\n'
  printf 'Context pack\n'
  printf '== ai/implementation_plan.md (Step %s - %s) ==\n' "$STEP" "$STEP_TITLE"
  printf '%s\n\n' "$STEP_SECTION"
  printf '== %s ==\n' "$design_label"
  cat "$DESIGN_OUT"
  printf '\n\n'
  if [[ -f "$DESIGN_GOLDEN" ]]; then
    printf '== ai/golden_examples/feature_design_GOLDEN_EXAMPLE.md ==\n'
    cat "$DESIGN_GOLDEN"
    printf '\n\n'
  fi
  printf '== reqirements_ears.md (linked requirements) ==\n'
  printf '%s\n\n' "$REQ_SECTION"
  printf '== ai/blocker_log.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$BLOCKER_LOG_SECTION"
  printf '== ai/open_questions.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$OPEN_QUESTIONS_SECTION"
  printf '== ai/decisions.md (Accepted ADRs) ==\n'
  printf 'Read directly from repo and shortlist only relevant accepted ADRs for this step/feature.\n'
  printf 'Path: ai/decisions.md\n\n'
  printf '== ai/user_review.md ==\n'
  printf 'Read directly from repo and shortlist only relevant rules for this feature.\n'
  printf 'Path: ai/user_review.md\n\n'
  printf '== ai/AI_DEVELOPMENT_PROCESS.md (Section 1) ==\n'
  process_design_section="$(get_process_design_section)"
  if [[ -n "$process_design_section" ]]; then
    printf '%s\n' "$process_design_section"
  else
    printf 'Section 1 not found; read ai/AI_DEVELOPMENT_PROCESS.md directly.\n'
  fi
  if [[ "$INCLUDE_AGENTS" -eq 1 ]]; then
    printf '\n\n== AGENTS.md ==\n'
    cat "$AGENTS"
  else
    printf '\n\n== AGENTS.md ==\n'
    printf 'Read directly from repo and include only relevant constraints in the design.\n'
    printf 'Path: AGENTS.md\n'
  fi
}

emit
