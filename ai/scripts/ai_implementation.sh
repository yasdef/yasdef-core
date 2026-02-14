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

STEP=""
OUT=""
STEP_PLAN=""
FULL_DECISIONS=0
INCLUDE_AGENTS=1

usage() {
  cat <<'EOF'
Usage: ai/scripts/ai_implementation.sh [--step 1.3] [--step-plan file] [--out file] [--full-decisions] [--no-include-agents]

Defaults:
  - If --step is omitted, uses the first unchecked bullet in ai/implementation_plan.md.
  - If --step-plan is omitted, uses ai/step_plans/step-<step>.md (required).
  - If --out is omitted, writes to ai/prompts/impl_prompts/<project>-step-<step>.prompt.txt.
  - ai/decisions.md is summarized to Accepted ADR titles unless --full-decisions is set.
  - AGENTS.md is included by default; use --no-include-agents to omit.
  - Always creates/switches to branch step-<step>-implementation.
EOF
}

ensure_implementation_branch() {
  local target
  target="step-$STEP-implementation"

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

get_last_review_actuals() {
  awk '
    /^### Step / {
      step=$0
      sub(/^### Step /, "", step)
    }
    /^- \[x\] Review step implementation\./ {
      if ($0 ~ /Actuals:/) { last_step=step; last_line=$0 }
    }
    END {
      if (last_line != "") {
        print last_step "|" last_line
      }
    }
  ' "$PLAN"
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

get_git_status() {
  git -C "$ROOT" status --short 2>/dev/null
}

get_git_last_commit() {
  git -C "$ROOT" log -1 --oneline 2>/dev/null
}

get_process_implementation_sections() {
  awk '
    /^### 2\)/ { in_scope=1 }
    /^### 5\)/ { exit }
    in_scope { print }
  ' "$PROCESS"
}

get_unchecked_implementation_bullets() {
  local step_section="$1"
  printf '%s\n' "$step_section" | awk '
    /^- \[[ xX]\] / {
      done_flag = substr($0, 4, 1)
      line = $0
      sub(/^- \[[ xX]\] /, "", line)
      if (line ~ /^Plan and discuss the step\./) { next }
      if (line ~ /^Review step implementation\./) { exit }
      if (done_flag == " ") {
        print "- " line
      }
    }
  '
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

if [[ -z "$STEP_PLAN" ]]; then
  STEP_PLAN="$ROOT/ai/step_plans/step-$STEP.md"
fi

if [[ -z "$OUT" ]]; then
  OUT="$ROOT/ai/prompts/impl_prompts/${PROJECT}-step-$STEP.prompt.txt"
fi

ensure_implementation_branch

if [[ ! -f "$STEP_PLAN" ]]; then
  echo "Step plan not found at $STEP_PLAN." >&2
  echo "Run ai/scripts/ai_plan.sh --step $STEP --out $STEP_PLAN first." >&2
  exit 1
fi

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

STEP_TOTAL_LINE="$(printf '%s\n' "$STEP_SECTION" | sed -n '2p')"
if [[ "$STEP_TOTAL_LINE" != Est.*step\ total:* ]]; then
  STEP_TOTAL_LINE=""
fi
if [[ -z "$STEP_TOTAL_LINE" ]]; then
  STEP_TOTAL_LINE="$(awk -v step="$STEP" '
    BEGIN { step_re = step; gsub(/\./, "\\.", step_re) }
    $0 ~ "^### Step "step_re" " { in_step=1; next }
    in_step && $0 ~ "^### Step " { exit }
    in_step && $0 ~ /^[[:space:]]*Est\\. step total:/ { sub(/^[[:space:]]*/, "", $0); print; exit }
  ' "$PLAN")"
fi
LAST_REVIEW_ACTUALS="$(get_last_review_actuals)"
LAST_REVIEW_STEP=""
LAST_REVIEW_LINE=""
if [[ -n "$LAST_REVIEW_ACTUALS" ]]; then
  IFS='|' read -r LAST_REVIEW_STEP LAST_REVIEW_LINE <<<"$LAST_REVIEW_ACTUALS"
fi

REQ_SECTION="$(get_requirements_section "$STEP_SECTION")"
GIT_STATUS="$(get_git_status)"
GIT_LAST_COMMIT="$(get_git_last_commit)"
PROCESS_IMPLEMENTATION_SECTIONS="$(get_process_implementation_sections)"
IMPLEMENTATION_SCOPE_BULLETS="$(get_unchecked_implementation_bullets "$STEP_SECTION")"
if [[ -z "$IMPLEMENTATION_SCOPE_BULLETS" ]]; then
  IMPLEMENTATION_SCOPE_BULLETS="- (none found; verify ai/implementation_plan.md step bullets)"
fi

if [[ "$FULL_DECISIONS" -eq 1 ]]; then
  DECISIONS_SECTION="$(cat "$DECISIONS")"
else
  DECISIONS_SECTION="$(list_accepted_adrs)"
  if [[ -z "$DECISIONS_SECTION" ]]; then
    DECISIONS_SECTION="- (none)"
  fi
fi

emit() {
  printf 'Implementation phase for Step %s\n' "$STEP"
  printf 'First unchecked bullet: %s\n' "$BULLET"
  printf 'Use ai/AI_DEVELOPMENT_PROCESS.md (Sections 2-4, Verification gates, Definition of Done, Prompt governance) and AGENTS.md as the authoritative rules for this phase.\n'
  printf 'Use the step plan and context pack as execution context.\n'
  printf 'Unchecked implementation bullets currently in scope (before review bullet):\n%s\n' "$IMPLEMENTATION_SCOPE_BULLETS"
  printf '\n'
  printf 'Context pack\n'
  printf '== estimation summary ==\n'
  if [[ -n "$STEP_TOTAL_LINE" ]]; then
    printf 'Current step total: %s\n' "$STEP_TOTAL_LINE"
  else
    printf 'Current step total: (missing)\n'
  fi
  if [[ -n "$LAST_REVIEW_LINE" ]]; then
    printf 'Last completed step actuals (%s): %s\n' "$LAST_REVIEW_STEP" "$LAST_REVIEW_LINE"
    if printf '%s' "$LAST_REVIEW_LINE" | grep -q 'est_error='; then
      est_error="$(printf '%s' "$LAST_REVIEW_LINE" | sed -n 's/.*est_error=\\([^,)]*\\).*/\\1/p')"
      if [[ -n "$est_error" ]]; then
        printf 'Estimation action: if est_error > 2x, split the next step.\n'
      fi
    fi
  else
    printf 'Last completed step actuals: (none recorded yet)\n'
  fi
  printf '\n'
  printf '== repo snapshot ==\n'
  if [[ -n "$GIT_LAST_COMMIT" ]]; then
    printf 'Last commit: %s\n' "$GIT_LAST_COMMIT"
  else
    printf 'Last commit: (unavailable)\n'
  fi
  if [[ -n "$GIT_STATUS" ]]; then
    printf 'Working tree:\n%s\n' "$GIT_STATUS"
  else
    printf 'Working tree: clean or unavailable\n'
  fi
  printf '\n'
  printf '== ai/implementation_plan.md (Step %s - %s) ==\n' "$STEP" "$STEP_TITLE"
  printf '%s\n\n' "$STEP_SECTION"
  printf '== ai/step_plans/step-%s.md ==\n' "$STEP"
  cat "$STEP_PLAN"
  printf '\n\n'
  printf '== reqirements_ears.md (linked requirements) ==\n'
  printf '%s\n\n' "$REQ_SECTION"
  printf '== ai/blocker_log.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$BLOCKER_LOG_SECTION"
  printf '== ai/open_questions.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$OPEN_QUESTIONS_SECTION"
  printf '== ai/decisions.md (Accepted ADRs) ==\n'
  printf '%s\n\n' "$DECISIONS_SECTION"
  if [[ -f "$USER_REVIEW" ]]; then
    printf '== ai/user_review.md ==\n'
    cat "$USER_REVIEW"
    printf '\n\n'
  fi
  printf '== ai/AI_DEVELOPMENT_PROCESS.md (Sections 2-4) ==\n'
  if [[ -n "$PROCESS_IMPLEMENTATION_SECTIONS" ]]; then
    printf '%s\n' "$PROCESS_IMPLEMENTATION_SECTIONS"
  else
    cat "$PROCESS"
  fi
  if [[ "$INCLUDE_AGENTS" -eq 1 ]]; then
    printf '\n\n== AGENTS.md ==\n'
    cat "$AGENTS"
  fi
}

mkdir -p "$(dirname "$OUT")"
emit >"$OUT"
