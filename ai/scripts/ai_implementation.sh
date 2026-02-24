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
SKIP_BRANCH=0
DESIGN_UR_HEADING=""
DESIGN_ADR_HEADING=""

usage() {
  cat <<'EOF'
Usage: ai/scripts/ai_implementation.sh [--step 1.3] [--step-plan file] [--design file] [--out file] [--include-agents] [--no-include-agents] [--no-branch]

Defaults:
  - If --step is omitted, uses the first unchecked bullet in ai/implementation_plan.md.
  - If --step-plan is omitted, uses ai/step_plans/step-<step>.md (required).
  - If --design is omitted, uses ai/step_designs/step-<step>-design.md (required).
  - If --out is omitted, writes to ai/prompts/impl_prompts/<project>-step-<step>.prompt.txt.
  - ai/decisions.md is pointer-only by default; rely on design-extracted ADR shortlist.
  - AGENTS.md is pointer-only by default; use --include-agents to inline full contents.
  - --no-include-agents is accepted for compatibility and keeps pointer-only behavior.
  - ai/user_review.md is pointer-only by default (use design-extracted shortlist in prompt context).
  - Always creates/switches to branch step-<step>-implementation.
  - Use --no-branch to skip git branch creation/switch (prompt generation only).
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

get_markdown_section_body() {
  local file="$1"
  local heading="$2"
  awk -v heading="$heading" '
    $0 == heading { in_section=1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$file"
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

get_target_bullets_from_design() {
  local file="$1"
  awk '
    /^## Target Bullets/ { in_section=1; next }
    in_section && /^## / { exit }
    in_section && /^- / {
      line = $0
      sub(/^- /, "", line)
      sub(/^\[[ xX]\][[:space:]]*/, "", line)
      print "- " line
    }
  ' "$file"
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

get_step_plan_section() {
  local heading="$1"
  get_markdown_section_body "$STEP_PLAN" "$heading"
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

if [[ -z "$DESIGN_FILE" ]]; then
  DESIGN_FILE="$ROOT/ai/step_designs/step-$STEP-design.md"
fi

if [[ -z "$OUT" ]]; then
  OUT="$ROOT/ai/prompts/impl_prompts/${PROJECT}-step-$STEP.prompt.txt"
fi

if [[ ! -f "$STEP_PLAN" ]]; then
  echo "Step plan not found at $STEP_PLAN." >&2
  echo "Run ai/scripts/ai_plan.sh --step $STEP --out $STEP_PLAN first." >&2
  exit 1
fi

if [[ ! -f "$DESIGN_FILE" ]]; then
  echo "Feature design not found at $DESIGN_FILE." >&2
  echo "Run ai/scripts/ai_design.sh --step $STEP first." >&2
  exit 1
fi

if [[ "$SKIP_BRANCH" -eq 0 ]]; then
  ensure_implementation_branch
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

DESIGN_TARGET_BULLETS="$(get_target_bullets_from_design "$DESIGN_FILE")"
if [[ -z "$DESIGN_TARGET_BULLETS" ]]; then
  DESIGN_TARGET_BULLETS="- (missing in design artifact)"
fi
DESIGN_PROPOSAL_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "## Proposal / Design Details")"
if [[ -z "$DESIGN_PROPOSAL_SECTION" ]]; then
  DESIGN_PROPOSAL_SECTION="- (missing in design artifact)"
fi
DESIGN_RISKS_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "## Risks and Mitigations")"
if [[ -z "$DESIGN_RISKS_SECTION" ]]; then
  DESIGN_RISKS_SECTION="- (missing in design artifact)"
fi
DESIGN_AGENTS_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "## Applicable AGENTS.md Constraints")"
if [[ -z "$DESIGN_AGENTS_SECTION" ]]; then
  DESIGN_AGENTS_SECTION="- (missing in design artifact)"
fi
if DESIGN_UR_HEADING="$(get_design_ur_heading "$DESIGN_FILE")"; then
  DESIGN_UR_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "$DESIGN_UR_HEADING")"
else
  DESIGN_UR_HEADING="## Applicable UR Shortlist"
  DESIGN_UR_SECTION="- (missing in design artifact)"
fi
if [[ -z "$DESIGN_UR_SECTION" ]]; then
  DESIGN_UR_SECTION="- (missing in design artifact)"
fi
if DESIGN_ADR_HEADING="$(get_design_adr_heading "$DESIGN_FILE")"; then
  DESIGN_ADR_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "$DESIGN_ADR_HEADING")"
else
  DESIGN_ADR_HEADING="## Applicable ADR Shortlist (from ai/decisions.md)"
  DESIGN_ADR_SECTION="- (missing in design artifact)"
fi
if [[ -z "$DESIGN_ADR_SECTION" ]]; then
  DESIGN_ADR_SECTION="- (missing in design artifact)"
fi
DESIGN_DECISIONS_SECTION="$(get_markdown_section_body "$DESIGN_FILE" "## Things to Decide (for final planning discussion)")"
if [[ -z "$DESIGN_DECISIONS_SECTION" ]]; then
  DESIGN_DECISIONS_SECTION="- None."
fi

STEP_PLAN_TARGET_BULLETS_SECTION="$(get_step_plan_section "## Target Bullets")"
if [[ -z "$STEP_PLAN_TARGET_BULLETS_SECTION" ]]; then
  STEP_PLAN_TARGET_BULLETS_SECTION="- (missing in step plan)"
fi
STEP_PLAN_DESIGN_ANCHOR_SECTION="$(get_step_plan_section "## Design Anchor (scope source of truth)")"
if [[ -z "$STEP_PLAN_DESIGN_ANCHOR_SECTION" ]]; then
  STEP_PLAN_DESIGN_ANCHOR_SECTION="- (missing in step plan)"
fi
STEP_PLAN_ORDERED_PLAN_SECTION="$(get_step_plan_section "## Plan (ordered)")"
if [[ -z "$STEP_PLAN_ORDERED_PLAN_SECTION" ]]; then
  STEP_PLAN_ORDERED_PLAN_SECTION="- (missing in step plan)"
fi
STEP_PLAN_IMPLEMENTATION_NOTES_SECTION="$(get_step_plan_section "## Implementation Notes / Constraints")"
if [[ -z "$STEP_PLAN_IMPLEMENTATION_NOTES_SECTION" ]]; then
  STEP_PLAN_IMPLEMENTATION_NOTES_SECTION="- (missing in step plan)"
fi
STEP_PLAN_TESTS_SECTION="$(get_step_plan_section "## Tests")"
if [[ -z "$STEP_PLAN_TESTS_SECTION" ]]; then
  STEP_PLAN_TESTS_SECTION="- (missing in step plan)"
fi
STEP_PLAN_DOCS_SECTION="$(get_step_plan_section "## Docs / Artifacts")"
if [[ -z "$STEP_PLAN_DOCS_SECTION" ]]; then
  STEP_PLAN_DOCS_SECTION="- (missing in step plan)"
fi
STEP_PLAN_RISKS_SECTION="$(get_step_plan_section "## Risks / Edge Cases")"
if [[ -z "$STEP_PLAN_RISKS_SECTION" ]]; then
  STEP_PLAN_RISKS_SECTION="- (missing in step plan)"
fi
STEP_PLAN_DECISIONS_NEEDED_SECTION="$(get_step_plan_section "## Decisions Needed")"
if [[ -z "$STEP_PLAN_DECISIONS_NEEDED_SECTION" ]]; then
  STEP_PLAN_DECISIONS_NEEDED_SECTION="- (missing in step plan)"
fi

emit() {
  printf 'Implementation phase for Step %s\n' "$STEP"
  printf 'Use ai/AI_DEVELOPMENT_PROCESS.md (Sections 3-5, Verification gates, Definition of Done, Prompt governance) as authoritative process rules.\n'
  printf 'First rule (execution order, required): within the implementation phase, execute step plan `## Plan (ordered)` end-to-end as one implementation batch for the current step. Use unchecked implementation bullets in `ai/implementation_plan.md` only as tracking boundaries (up to but excluding `Review step implementation.`), and enter Section 5 only after Sections 4 and 4.1 are complete.\n'
  printf 'Run AI_DEVELOPMENT_PROCESS Section 4 verification gate after implementation is complete for this step (single mandatory end-of-step gate).\n'
  printf 'Before Section 5, ensure step-plan `## Target Bullets` and current-step non-review implementation bullets represent the same scope; if not, resolve alignment first.\n'
  printf 'Before Section 5, execute AI_DEVELOPMENT_PROCESS Section 4.1 (Tracking closure): mark non-review implementation bullets `[x]` only for implemented and verified work; if any remain `[ ]`, return to Sections 3-4.\n'
  printf 'Before any implementation bullet `[ ]` -> `[x]`, apply the proof gate in ai/AI_DEVELOPMENT_PROCESS.md Section 4.1 and keep bullets `[ ]` when proof is missing.\n'
  printf 'Use step plan `## Target Bullets` only as the Section 5 user-review checklist.\n'
  printf 'Before the first Section 5 feedback request, emit the brief three-part human-review explanation mode defined in ai/AI_DEVELOPMENT_PROCESS.md Section 5.\n'
  printf 'After implementation + verification gate, follow AI_DEVELOPMENT_PROCESS ### 5) User review until user confirms completion - no more comments about implementation from user side.\n'
  printf 'When user confirms completion of implementation phase, end your final response with this exact last line: "Implementation phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase."\n'
  printf 'Use step plan + feature design as primary execution context.\n'
  printf 'Feature design artifact: %s\n' "$DESIGN_FILE"
  printf 'Step plan artifact: %s\n' "$STEP_PLAN"
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
  printf '== ai/implementation_plan.md (tracking summary) ==\n'
  printf 'Step: %s - %s\n' "$STEP" "$STEP_TITLE"
  printf 'Path: ai/implementation_plan.md\n\n'
  printf '== ai/step_plans/step-%s.md (execution + review excerpts) ==\n' "$STEP"
  printf 'Path: ai/step_plans/step-%s.md\n\n' "$STEP"
  printf '== ## Design Anchor (scope source of truth) ==\n'
  printf '%s\n\n' "$STEP_PLAN_DESIGN_ANCHOR_SECTION"
  printf '== ## Plan (ordered) ==\n'
  printf '%s\n\n' "$STEP_PLAN_ORDERED_PLAN_SECTION"
  printf '== Step plan implementation constraints (`## Implementation Notes / Constraints`) ==\n'
  printf '%s\n\n' "$STEP_PLAN_IMPLEMENTATION_NOTES_SECTION"
  printf '== Step plan tests (`## Tests`) ==\n'
  printf '%s\n\n' "$STEP_PLAN_TESTS_SECTION"
  printf '== Step plan docs/artifacts (`## Docs / Artifacts`) ==\n'
  printf '%s\n\n' "$STEP_PLAN_DOCS_SECTION"
  printf '== Step plan risks (`## Risks / Edge Cases`) ==\n'
  printf '%s\n\n' "$STEP_PLAN_RISKS_SECTION"
  printf '== Step plan decisions (`## Decisions Needed`) ==\n'
  printf '%s\n\n' "$STEP_PLAN_DECISIONS_NEEDED_SECTION"
  printf '== User review checklist only (`## Target Bullets`) ==\n'
  printf 'Use this checklist in Section 5; do not use it as the primary execution list.\n'
  printf '%s\n\n' "$STEP_PLAN_TARGET_BULLETS_SECTION"
  printf '== ai/step_designs/step-%s-design.md ==\n' "$STEP"
  printf 'Read directly from repo (authoritative design artifact).\n'
  printf 'Path: ai/step_designs/step-%s-design.md\n\n' "$STEP"
  printf '== Design-extracted target bullets ==\n'
  printf '%s\n\n' "$DESIGN_TARGET_BULLETS"
  printf '== Design-extracted proposal/design details ==\n'
  printf '%s\n\n' "$DESIGN_PROPOSAL_SECTION"
  printf '== Design-extracted risks and mitigations ==\n'
  printf '%s\n\n' "$DESIGN_RISKS_SECTION"
  printf '== Design-extracted AGENTS constraints ==\n'
  printf '%s\n\n' "$DESIGN_AGENTS_SECTION"
  printf '== Design-extracted UR shortlist ==\n'
  printf '%s\n\n' "$DESIGN_UR_SECTION"
  printf '== Design-extracted ADR shortlist ==\n'
  printf '%s\n\n' "$DESIGN_ADR_SECTION"
  printf '== Design decisions to confirm (must be resolved in plan) ==\n'
  printf '%s\n\n' "$DESIGN_DECISIONS_SECTION"
  printf '== reqirements_ears.md (linked requirements) ==\n'
  printf '%s\n\n' "$REQ_SECTION"
  printf '== ai/blocker_log.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$BLOCKER_LOG_SECTION"
  printf '== ai/open_questions.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$OPEN_QUESTIONS_SECTION"
  printf '== ai/decisions.md (Accepted ADRs) ==\n'
  printf 'Pointer-only by default: rely on design-extracted ADR shortlist above.\n'
  printf 'Path: ai/decisions.md\n\n'
  printf '== ai/user_review.md ==\n'
  printf 'Pointer-only by default: rely on design-extracted UR shortlist above.\n'
  printf 'Path: ai/user_review.md\n\n'
  printf '== ai/AI_DEVELOPMENT_PROCESS.md ==\n'
  printf 'Read directly from repo; apply Sections 3-5 for this phase.\n'
  printf 'Path: ai/AI_DEVELOPMENT_PROCESS.md\n'
  if [[ "$INCLUDE_AGENTS" -eq 1 ]]; then
    printf '\n\n== AGENTS.md ==\n'
    cat "$AGENTS"
  else
    printf '\n\n== AGENTS.md ==\n'
    printf 'Pointer-only by default; rely on design-extracted AGENTS constraints above.\n'
    printf 'Path: AGENTS.md\n'
  fi
}

mkdir -p "$(dirname "$OUT")"
emit >"$OUT"
