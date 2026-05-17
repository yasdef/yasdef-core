#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/helpers/runtime_layout.sh"
asdlc_worker_require_runtime_layout "${BASH_SOURCE[0]}"
ROOT="$WORKER_REPO_ROOT"
PLAN="$ASDLC_RUNTIME_PLAN_PATH"
PROCESS="$ASDLC_PROCESS_FILE"
BLOCKER_LOG="$ASDLC_BLOCKER_LOG_FILE"
OPEN_QUESTIONS="$ASDLC_OPEN_QUESTIONS_FILE"
REQUIREMENTS="$ASDLC_RUNTIME_EARS_PATH"
AGENTS="$ROOT/AGENTS.md"
AI_AUDIT_DISPOSITION_HELPER="$ASDLC_HELPERS_DIR/check_ai_audit_disposition_readiness.sh"

STEP=""
OUT=""
STEP_PLAN=""
DESIGN_FILE=""
FEATURE_ID=""
INCLUDE_AGENTS=1
DESIGN_UR_HEADING=""
DESIGN_ADR_HEADING=""

usage() {
  cat <<'EOF'
Usage: .asdlc_worker/scripts/ai_audit.sh [--step 1.3] [--step-plan file] [--design file] [--out file] [--feature-id <id>] [--no-include-agents]

Defaults:
  - If --step-plan is omitted, uses the latest .asdlc_worker/step_plans/step-*.md.
  - If --step is omitted, derives it from --step-plan filename.
  - If --design is omitted, uses .asdlc_worker/step_designs/step-<step>-design.md (required).
  - .asdlc_worker/decisions.md is pointer-only by default; rely on design-extracted ADR shortlist.
  - AGENTS.md is included by default; use --no-include-agents to omit.
  - Always creates/switches to branch step-<step>-<feature-id>-review from step-<step>-<feature-id>-user-review when available, otherwise step-<step>-<feature-id>-implementation.
EOF
}

ensure_review_branch() {
  local implementation_branch user_review_branch source_branch target
  implementation_branch="step-$STEP-$FEATURE_ID-implementation"
  user_review_branch="step-$STEP-$FEATURE_ID-user-review"
  source_branch="$implementation_branch"
  target="step-$STEP-$FEATURE_ID-review"

  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$user_review_branch"; then
    source_branch="$user_review_branch"
  fi

  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not a git repository: $ROOT" >&2
    exit 1
  fi

  local current
  current="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  if [[ "$current" == "$target" ]]; then
    return 0
  fi

  if [[ "$current" != "$source_branch" ]]; then
    if [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null || true)" ]]; then
      echo "Review branch must be created from $source_branch to carry step changes." >&2
      echo "Current branch has uncommitted changes: ${current:-<detached>}." >&2
      echo "Switch to $source_branch and rerun .asdlc_worker/scripts/ai_audit.sh." >&2
      exit 1
    fi
    if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$source_branch"; then
      if ! git -C "$ROOT" checkout "$source_branch" >/dev/null; then
        echo "Failed to switch to source branch: $source_branch" >&2
        exit 1
      fi
      current="$source_branch"
      echo "Switched to source branch: $source_branch" >&2
    else
      echo "Source branch not found: $source_branch" >&2
      if [[ "$source_branch" == "$user_review_branch" ]]; then
        echo "Run .asdlc_worker/scripts/ai_user_review.sh for step $STEP first." >&2
      else
        echo "Run .asdlc_worker/scripts/ai_implementation.sh for step $STEP first." >&2
      fi
      exit 1
    fi
  fi

  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$target"; then
    if ! git -C "$ROOT" checkout "$target" >/dev/null; then
      echo "Failed to switch to existing branch: $target" >&2
      echo "Existing review branch may have diverged from $source_branch, and uncommitted changes cannot be carried safely." >&2
      exit 1
    fi
    echo "Switched to existing branch: $target" >&2
  else
    if ! git -C "$ROOT" checkout -b "$target" >/dev/null; then
      echo "Failed to create and switch to branch: $target" >&2
      exit 1
    fi
    echo "Created and switched to branch: $target (from $source_branch with step changes)." >&2
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
  local dir="$ASDLC_STEP_PLANS_DIR"
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
  step="${step%%-*}"
  printf '%s' "$step"
}

get_current_branch_name() {
  git -C "$ROOT" branch --show-current 2>/dev/null || true
}

get_step_from_branch_name() {
  local branch="$1"
  if [[ "$branch" =~ ^step-([0-9]+([.][0-9]+)*)-[^-].*-(plan|implementation|user-review|review)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

get_preferred_step_plan() {
  local branch step plan
  branch="$(get_current_branch_name)"
  if step="$(get_step_from_branch_name "$branch")"; then
    plan="$ASDLC_STEP_PLANS_DIR/step-$step.md"
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

get_step_target_bullets() {
  local step="$1"
  awk -v step="$step" '
    BEGIN { step_re = step; gsub(/\./, "\\.", step_re) }
    $0 ~ "^### Step "step_re" " { in_step=1; next }
    in_step && $0 ~ "^### Step " { exit }
    in_step && $0 ~ /^- \[[ xX]\][[:space:]]+/ {
      line = $0
      sub(/^- \[[ xX]\][[:space:]]+/, "", line)
      gate = tolower(line)
      while (gate ~ /^\[[^]]+\][[:space:]]*/) {
        sub(/^\[[^]]+\][[:space:]]*/, "", gate)
      }
      if (gate ~ /^plan and discuss the step([[:space:]\.]|$)/) next
      if (gate ~ /^review step implementation([[:space:]\.]|$)/) next
      print "- " line
      count++
    }
    END {
      if (count == 0) {
        print "- (no non-review implementation bullets found in plan step section)"
      }
    }
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

get_design_ur_heading() {
  local file="$1"
  if grep -Fqx "## Applicable UR Shortlist" "$file"; then
    printf '## Applicable UR Shortlist'
    return 0
  fi
  if grep -Fqx "## Applicable User Review Rules" "$file"; then
    printf '## Applicable User Review Rules'
    return 0
  fi
  return 1
}

get_design_adr_heading() {
  local file="$1"
  if grep -Fqx "## Applicable ADR Shortlist (from .asdlc_worker/decisions.md)" "$file"; then
    printf '## Applicable ADR Shortlist (from .asdlc_worker/decisions.md)'
    return 0
  fi
  if grep -Fqx "## Applicable ADR Shortlist (from ai/decisions.md)" "$file"; then
    printf '## Applicable ADR Shortlist (from ai/decisions.md)'
    return 0
  fi
  if grep -Fqx "## Applicable ADR Shortlist" "$file"; then
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
      output+="Requirement $req not found in $REQUIREMENTS"$'\n\n'
    fi
  done <<<"$reqs"

  printf '%s' "$output"
}

extract_process_section() {
  local heading="$1"
  awk -v heading="$heading" '
    $0 == heading { in_section=1 }
    in_section && /^## / { exit }
    in_section && /^### [0-9]+\)/ && $0 != heading { exit }
    in_section { print }
  ' "$PROCESS"
}

get_git_status() {
  git -C "$ROOT" status --short 2>/dev/null
}

get_git_diff_name_status() {
  git -C "$ROOT" diff --name-status 2>/dev/null
}

get_git_diff_stat() {
  git -C "$ROOT" diff --stat 2>/dev/null
}

get_git_current_branch() {
  git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null
}

get_git_last_commit() {
  git -C "$ROOT" log -1 --oneline 2>/dev/null
}

get_step_delta_file_list() {
  local status
  status="$(git -C "$ROOT" status --short --untracked-files=all 2>/dev/null || true)"
  if [[ -z "$status" ]]; then
    printf '%s' '- (none)'
    return 0
  fi
  printf '%s\n' "$status"
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
    --feature-id)
      require_option_arg "--feature-id" "${2:-}"
      FEATURE_ID="$2"
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
  DESIGN_FILE="$ASDLC_STEP_DESIGNS_DIR/step-$STEP-$FEATURE_ID-design.md"
fi

if [[ ! -f "$DESIGN_FILE" ]]; then
  echo "Feature design not found at $DESIGN_FILE." >&2
  echo "Run .asdlc_worker/scripts/ai_design.sh --step $STEP first." >&2
  exit 1
fi

ensure_review_branch

STEP_TITLE="$(get_step_title "$STEP")"
if [[ -z "$STEP_TITLE" ]]; then
  echo "Step $STEP not found in $PLAN." >&2
  exit 1
fi

BULLET="$(get_step_first_unchecked "$STEP")"
if [[ -z "$BULLET" ]]; then
  BULLET="Review step implementation."
fi

STEP_SECTION="$(get_step_section "$STEP")"
if [[ -z "$STEP_SECTION" ]]; then
  echo "Step $STEP section not found in $PLAN." >&2
  exit 1
fi
TARGET_PROOF_BULLETS="$(get_step_target_bullets "$STEP")"
if [[ -z "$TARGET_PROOF_BULLETS" ]]; then
  TARGET_PROOF_BULLETS="- (no non-review implementation bullets found in plan step section)"
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
  DESIGN_ADR_HEADING="## Applicable ADR Shortlist (from .asdlc_worker/decisions.md)"
  DESIGN_ADR_SECTION="- (missing in design artifact)"
fi
if [[ -z "$DESIGN_ADR_SECTION" ]]; then
  DESIGN_ADR_SECTION="- (missing in design artifact)"
fi
STEP_DELTA_FILE_LIST="$(get_step_delta_file_list)"
REVIEW_RESULT_PATH="$ASDLC_STEP_REVIEW_RESULTS_DIR/review_result-$STEP-$FEATURE_ID.md"

emit() {
  printf 'ai_audit phase for Step %s - %s\n' "$STEP" "$STEP_TITLE"
  printf 'Follow `.asdlc_worker/AI_DEVELOPMENT_PROCESS.md` (Sections 6.0-6.4, Prompt governance) and `AGENTS.md` as the authoritative rules for this phase.\n'
  printf 'Primary context is the inline audit context below.\n'
  printf 'Read these artifacts directly from the repo:\n'
  printf -- '- Step plan: %s\n' "$STEP_PLAN"
  printf -- '- Feature design: %s\n' "$DESIGN_FILE"
  printf -- '- Review result artifact: %s\n' "$REVIEW_RESULT_PATH"
  printf 'Optional references (open only if needed):\n'
  printf -- '- Implementation plan: %s\n' "$PLAN"
  printf -- '- Requirements: %s\n' "$REQUIREMENTS"
  printf -- '- Audit result template: %s\n' "$ASDLC_TEMPLATES_DIR/audit_result_TEMPLATE.md"
  printf -- '- Audit result example: %s\n' "$ASDLC_GOLDEN_EXAMPLES_DIR/audit_result_GOLDEN_EXAMPLE.md"
  printf -- '- Blocker log: %s\n' "$BLOCKER_LOG"
  printf -- '- Open questions: %s\n' "$OPEN_QUESTIONS"
  printf -- '- Decisions: %s\n' "$ASDLC_DECISIONS_FILE"
  if [[ "$INCLUDE_AGENTS" -eq 1 ]]; then
    printf -- '- Project constraints: %s\n' "$AGENTS"
  fi
  printf -- '- Disposition helper: %s\n' "$AI_AUDIT_DISPOSITION_HELPER"
  printf 'Run Section 6.0 first as the mandatory ai_audit entry proof-gate against `%s` target bullets, then continue Sections 6.1-6.4.\n' "$PLAN"
  printf 'Audit-loop rule: after each disposition or plan update, continue Sections 6.2-6.4 until every ai_audit gate passes; do not stop early because the user approved a follow-up bullet change.\n'
  printf "Before ending the ai_audit phase, ensure all bullets in the current step section of \`%s\` are checklist bullets and marked \`[x]\`, then run \`.asdlc_worker/scripts/helpers/check_ai_audit_disposition_readiness.sh %s\`.\n" "$PLAN" "$STEP"
  printf 'If that readiness check fails, keep iterating Section 6: finish dispositions and/or close remaining current-step bullets in `%s`, then rerun the helper.\n' "$PLAN"
  printf 'Extended completion-line gate: output the ai_audit completion line only after all current-step bullets are `[x]` in `%s`, the readiness helper passes, and the commit gate is satisfied (clean working tree).\n' "$PLAN"
  printf 'Only after the commit gate, current-step bullet closure, and readiness helper pass, end your final response with this exact last line: "ai_audit phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase."\n'
  printf '\n'
  printf 'Inline audit context\n'
  printf '== Step ==\n'
  printf 'Step %s - %s\n\n' "$STEP" "$STEP_TITLE"
  printf '== Target bullets (from %s) ==\n' "$PLAN"
  printf '%s\n\n' "$TARGET_PROOF_BULLETS"
  printf '== Linked EARS requirement blocks ==\n'
  printf '%s\n\n' "$REQ_SECTION"
  printf '== Design shortlist: Risks and mitigations ==\n'
  printf '%s\n\n' "$DESIGN_RISKS_SECTION"
  printf '== Design shortlist: AGENTS constraints ==\n'
  printf '%s\n\n' "$DESIGN_AGENTS_SECTION"
  printf '== Design shortlist: UR shortlist ==\n'
  printf '%s\n\n' "$DESIGN_UR_SECTION"
  printf '== Design shortlist: ADR shortlist ==\n'
  printf '%s\n\n' "$DESIGN_ADR_SECTION"
  printf '== Step delta file list ==\n'
  printf '%s\n' "$STEP_DELTA_FILE_LIST"
}

if [[ -n "$OUT" ]]; then
  mkdir -p "$(dirname "$OUT")"
  emit >"$OUT"
else
  emit
fi
