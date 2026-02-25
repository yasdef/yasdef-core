#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$(basename "$ROOT")"
PLAN="$ROOT/ai/implementation_plan.md"
PROCESS="$ROOT/ai/AI_DEVELOPMENT_PROCESS.md"
BLOCKER_LOG="$ROOT/ai/blocker_log.md"
OPEN_QUESTIONS="$ROOT/ai/open_questions.md"
REQUIREMENTS="$ROOT/reqirements_ears.md"
AGENTS="$ROOT/AGENTS.md"
USER_REVIEW="$ROOT/ai/user_review.md"

STEP=""
OUT=""
STEP_PLAN=""
DESIGN_FILE=""
INCLUDE_AGENTS=0
RESET_USER_REVIEW_BRANCH=0
DESIGN_UR_HEADING=""
DESIGN_ADR_HEADING=""

usage() {
  cat <<'EOF'
Usage: ai/scripts/ai_user_review.sh [--step 1.3] [--step-plan file] [--design file] [--out file] [--include-agents] [--no-include-agents] [--reset-user-review-branch]

Defaults:
  - If --step-plan is omitted, uses the latest ai/step_plans/step-*.md.
  - If --step is omitted, derives it from --step-plan filename.
  - If --design is omitted, uses ai/step_designs/step-<step>-design.md (required).
  - If --out is omitted, writes to ai/prompts/user_review_prompts/<project>-step-<step>.user-review.prompt.txt.
  - AGENTS.md is pointer-only by default; use --include-agents to inline full contents.
  - Always creates/switches to branch step-<step>-user-review from step-<step>-implementation.
  - --reset-user-review-branch: force-reset step-<step>-user-review to step-<step>-implementation before switching.
  - Hard gate (before prompt/model): all step bullets except "Review step implementation" must be marked [x].
EOF
}

ensure_user_review_branch() {
  local implementation_branch target
  implementation_branch="step-$STEP-implementation"
  target="step-$STEP-user-review"

  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not a git repository: $ROOT" >&2
    exit 1
  fi

  local current
  current="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  if [[ "$current" == "$target" ]]; then
    return 0
  fi

  if [[ "$current" != "$implementation_branch" ]]; then
    if [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null || true)" ]]; then
      echo "User review branch must be created from $implementation_branch to carry implementation changes." >&2
      echo "Current branch has uncommitted changes: ${current:-<detached>}." >&2
      echo "Switch to $implementation_branch and rerun ai/scripts/ai_user_review.sh." >&2
      exit 1
    fi
    if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$implementation_branch"; then
      if ! git -C "$ROOT" checkout "$implementation_branch" >/dev/null; then
        echo "Failed to switch to implementation branch: $implementation_branch" >&2
        exit 1
      fi
      current="$implementation_branch"
      echo "Switched to implementation branch: $implementation_branch" >&2
    else
      echo "Implementation branch not found: $implementation_branch" >&2
      echo "Run ai/scripts/ai_implementation.sh for step $STEP first." >&2
      exit 1
    fi
  fi

  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$target"; then
    if [[ "$RESET_USER_REVIEW_BRANCH" -eq 1 ]]; then
      if ! git -C "$ROOT" checkout -B "$target" "$implementation_branch" >/dev/null; then
        echo "Failed to reset and switch to user review branch: $target from $implementation_branch" >&2
        exit 1
      fi
      echo "Reset and switched to user review branch: $target (from $implementation_branch)." >&2
      return 0
    fi
    if ! git -C "$ROOT" checkout "$target" >/dev/null; then
      echo "Failed to switch to existing branch: $target" >&2
      echo "Existing user review branch may have diverged from $implementation_branch, and uncommitted changes cannot be carried safely." >&2
      echo "If you want to realign user review to implementation, rerun this command:" >&2
      echo "  ai/scripts/ai_user_review.sh --step $STEP --reset-user-review-branch" >&2
      exit 1
    fi
    echo "Switched to existing branch: $target" >&2
  else
    if ! git -C "$ROOT" checkout -b "$target" >/dev/null; then
      echo "Failed to create and switch to branch: $target" >&2
      exit 1
    fi
    echo "Created and switched to branch: $target (from $implementation_branch with implementation changes)." >&2
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

make_sort_key() {
  local step="$1"
  local key=""
  local part num suffix

  IFS='.' read -r -a parts <<<"$step"
  for part in "${parts[@]}"; do
    num="${part%%[!0-9]*}"
    suffix="${part#$num}"
    if [[ -z "$num" ]]; then
      num=0
    fi
    key+=$(printf '%010d' "$num")
    key+="$suffix"
    key+="."
  done

  printf '%s' "${key%.}"
}

get_latest_step_plan() {
  local dir="$ROOT/ai/step_plans"
  if [[ ! -d "$dir" ]]; then
    echo "Step plan directory not found: $dir" >&2
    exit 1
  fi

  local pairs=()
  local file
  while IFS= read -r file; do
    local base step key
    base="$(basename "$file")"
    step="${base#step-}"
    step="${step%.md}"
    [[ -z "$step" ]] && continue
    key="$(make_sort_key "$step")"
    pairs+=("$key|$file")
  done < <(find "$dir" -maxdepth 1 -type f -name 'step-*.md' -print)

  if [[ ${#pairs[@]} -eq 0 ]]; then
    echo "No step plans found in $dir." >&2
    exit 1
  fi

  local latest
  latest="$(printf '%s\n' "${pairs[@]}" | sort -t'|' -k1,1 -k2,2 | tail -n1)"
  printf '%s' "${latest#*|}"
}

get_step_from_plan_path() {
  local file="$1"
  local base step
  base="$(basename "$file")"
  step="${base#step-}"
  step="${step%.md}"
  printf '%s' "$step"
}

get_current_branch_name() {
  git -C "$ROOT" branch --show-current 2>/dev/null || true
}

get_step_from_branch_name() {
  local branch="$1"
  if [[ "$branch" =~ ^step-(.+)-(plan|implementation|user-review|review)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

get_preferred_step_plan() {
  local branch step plan
  branch="$(get_current_branch_name)"
  if step="$(get_step_from_branch_name "$branch")"; then
    plan="$ROOT/ai/step_plans/step-$step.md"
    if [[ -f "$plan" ]]; then
      printf '%s' "$plan"
      return 0
    fi
  fi
  get_latest_step_plan
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

get_step_plan_section() {
  local heading="$1"
  get_markdown_section_body "$STEP_PLAN" "$heading"
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

extract_process_user_review_section() {
  awk '
    /^### 5\) User review \(required before moving to the next step\)/ { in_scope=1 }
    in_scope && /^### [0-9]+\)/ && $0 !~ /^### 5\) / { exit }
    in_scope { print }
  ' "$PROCESS"
}

list_unchecked_non_review_bullets() {
  local step="$1"
  awk -v target="$step" '
    BEGIN { in_step=0 }
    /^### Step / {
      line=$0
      sub(/^### Step /, "", line)
      split(line, parts, " ")
      in_step=(parts[1] == target)
      next
    }
    in_step && /^### Step / { in_step=0 }
    in_step && /^- \[[ xX]\]/ {
      raw = $0
      checked = (raw ~ /^- \[[xX]\]/)
      text = raw
      sub(/^- \[[ xX]\][[:space:]]*/, "", text)

      gate_text = tolower(text)
      while (gate_text ~ /^\[[^]]+\][[:space:]]*/) {
        sub(/^\[[^]]+\][[:space:]]*/, "", gate_text)
      }

      if (gate_text ~ /^review step implementation([[:space:]\.]|$)/) {
        next
      }

      if (!checked) {
        print "- " text
      }
    }
  ' "$PLAN"
}

count_non_review_bullets() {
  local step="$1"
  awk -v target="$step" '
    BEGIN { in_step=0; c=0 }
    /^### Step / {
      line=$0
      sub(/^### Step /, "", line)
      split(line, parts, " ")
      in_step=(parts[1] == target)
      next
    }
    in_step && /^### Step / { in_step=0 }
    in_step && /^- \[[ xX]\]/ {
      text = $0
      sub(/^- \[[ xX]\][[:space:]]*/, "", text)
      gate_text = tolower(text)
      while (gate_text ~ /^\[[^]]+\][[:space:]]*/) {
        sub(/^\[[^]]+\][[:space:]]*/, "", gate_text)
      }
      if (gate_text ~ /^review step implementation([[:space:]\.]|$)/) {
        next
      }
      c++
    }
    END { print c+0 }
  ' "$PLAN"
}

ensure_user_review_entry_gate() {
  local step="$1"
  local total unchecked

  total="$(count_non_review_bullets "$step")"
  unchecked="$(list_unchecked_non_review_bullets "$step")"

  if [[ "$total" -eq 0 ]]; then
    echo "User review precheck failed for step $step: no non-review bullets found in ai/implementation_plan.md." >&2
    exit 1
  fi

  if [[ -n "$unchecked" ]]; then
    echo "User review precheck failed for step $step." >&2
    echo "All step bullets except 'Review step implementation' must be [x] before starting user review." >&2
    echo "Unchecked non-review bullets:" >&2
    printf '%s\n' "$unchecked" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)
      require_option_arg "--step" "${2:-}"
      STEP="$2"
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
    --out)
      require_option_arg "--out" "${2:-}"
      OUT="$2"
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
    --reset-user-review-branch)
      RESET_USER_REVIEW_BRANCH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$STEP_PLAN" ]]; then
  STEP_PLAN="$(get_preferred_step_plan)"
fi

if [[ ! -f "$STEP_PLAN" ]]; then
  echo "Step plan not found at $STEP_PLAN." >&2
  exit 1
fi

if [[ -z "$STEP" ]]; then
  STEP="$(get_step_from_plan_path "$STEP_PLAN")"
fi

if [[ -z "$STEP" ]]; then
  echo "Could not determine step from $STEP_PLAN." >&2
  exit 1
fi

if [[ -z "$DESIGN_FILE" ]]; then
  DESIGN_FILE="$ROOT/ai/step_designs/step-$STEP-design.md"
fi

if [[ ! -f "$DESIGN_FILE" ]]; then
  echo "Feature design not found at $DESIGN_FILE." >&2
  echo "Run ai/scripts/ai_design.sh --step $STEP first." >&2
  exit 1
fi

ensure_user_review_entry_gate "$STEP"
ensure_user_review_branch

STEP_TITLE="$(get_step_title "$STEP")"
if [[ -z "$STEP_TITLE" ]]; then
  echo "Step $STEP not found in ai/implementation_plan.md." >&2
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

REQ_SECTION="$(get_requirements_section "$STEP_SECTION")"
USER_REVIEW_PROCESS_SECTION="$(extract_process_user_review_section)"

if [[ -z "$USER_REVIEW_PROCESS_SECTION" ]]; then
  echo "Could not extract user review section from $PROCESS." >&2
  exit 1
fi

STEP_PLAN_TARGET_BULLETS_SECTION="$(get_step_plan_section "## Target Bullets")"
if [[ -z "$STEP_PLAN_TARGET_BULLETS_SECTION" ]]; then
  STEP_PLAN_TARGET_BULLETS_SECTION="- (missing in step plan)"
fi

STEP_PLAN_ORDERED_PLAN_SECTION="$(get_step_plan_section "## Plan (ordered)")"
if [[ -z "$STEP_PLAN_ORDERED_PLAN_SECTION" ]]; then
  STEP_PLAN_ORDERED_PLAN_SECTION="- (missing in step plan)"
fi

DESIGN_PROPOSAL_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "## Proposal / Design Details")"
if [[ -z "$DESIGN_PROPOSAL_SECTION" ]]; then
  DESIGN_PROPOSAL_SECTION="- (missing in design artifact)"
fi

DESIGN_RISKS_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "## Risks and Mitigations")"
if [[ -z "$DESIGN_RISKS_SECTION" ]]; then
  DESIGN_RISKS_SECTION="- (missing in design artifact)"
fi

if DESIGN_UR_HEADING="$(get_design_ur_heading "$DESIGN_FILE")"; then
  DESIGN_UR_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "$DESIGN_UR_HEADING")"
else
  DESIGN_UR_SECTION="- (missing in design artifact)"
fi
if [[ -z "$DESIGN_UR_SECTION" ]]; then
  DESIGN_UR_SECTION="- (missing in design artifact)"
fi

if DESIGN_ADR_HEADING="$(get_design_adr_heading "$DESIGN_FILE")"; then
  DESIGN_ADR_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "$DESIGN_ADR_HEADING")"
else
  DESIGN_ADR_SECTION="- (missing in design artifact)"
fi
if [[ -z "$DESIGN_ADR_SECTION" ]]; then
  DESIGN_ADR_SECTION="- (missing in design artifact)"
fi

emit() {
  printf 'User review phase for Step %s\n' "$STEP"
  printf 'Use ai/AI_DEVELOPMENT_PROCESS.md Section 5 as the authoritative workflow.\n'
  printf 'Entry gate already verified by script: every non-review step bullet in ai/implementation_plan.md is [x].\n'
  printf 'Do not start post-step audit/review in this phase.\n'
  printf 'When user review is fully complete, end your final response with this exact last line: "User review phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase."\n'
  printf '\n'
  printf 'Context pack\n'
  printf '== ai/implementation_plan.md (Step %s - %s) ==\n' "$STEP" "$STEP_TITLE"
  printf '%s\n\n' "$STEP_SECTION"
  printf '== %s ==\n' "$STEP_PLAN"
  printf '%s\n\n' "$STEP_PLAN_ORDERED_PLAN_SECTION"
  printf '== User review checklist (`## Target Bullets`) ==\n'
  printf '%s\n\n' "$STEP_PLAN_TARGET_BULLETS_SECTION"
  printf '== ai/step_designs/step-%s-design.md (key excerpts) ==\n' "$STEP"
  printf 'Proposal / Design Details:\n%s\n\n' "$DESIGN_PROPOSAL_SECTION"
  printf 'Risks and Mitigations:\n%s\n\n' "$DESIGN_RISKS_SECTION"
  printf 'Applicable UR shortlist:\n%s\n\n' "$DESIGN_UR_SECTION"
  printf 'Applicable ADR shortlist:\n%s\n\n' "$DESIGN_ADR_SECTION"
  printf '== ai/AI_DEVELOPMENT_PROCESS.md (Section 5) ==\n'
  printf '%s\n\n' "$USER_REVIEW_PROCESS_SECTION"
  printf '== reqirements_ears.md (linked requirements) ==\n'
  printf '%s\n\n' "$REQ_SECTION"
  printf '== ai/blocker_log.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$BLOCKER_LOG_SECTION"
  printf '== ai/open_questions.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$OPEN_QUESTIONS_SECTION"
  printf '== ai/user_review.md ==\n'
  printf 'Path: ai/user_review.md\n\n'
  if [[ "$INCLUDE_AGENTS" -eq 1 ]]; then
    printf '== AGENTS.md ==\n'
    cat "$AGENTS"
  else
    printf '== AGENTS.md ==\n'
    printf 'Pointer-only by default.\n'
    printf 'Path: AGENTS.md\n'
  fi
}

if [[ -z "$OUT" ]]; then
  OUT="$ROOT/ai/prompts/user_review_prompts/${PROJECT}-step-$STEP.user-review.prompt.txt"
fi

mkdir -p "$(dirname "$OUT")"
emit >"$OUT"
