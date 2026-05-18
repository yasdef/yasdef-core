#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/helpers/runtime_layout.sh"
asdlc_worker_require_runtime_layout "${BASH_SOURCE[0]}"
ROOT="$WORKER_REPO_ROOT"
PROJECT="$(basename "$ROOT")"
PLAN="$ASDLC_RUNTIME_PLAN_PATH"
PROCESS="$ASDLC_PROCESS_FILE"
DECISIONS="$ASDLC_DECISIONS_FILE"
BLOCKER_LOG="$ASDLC_BLOCKER_LOG_FILE"
OPEN_QUESTIONS="$ASDLC_OPEN_QUESTIONS_FILE"
REQUIREMENTS="$ASDLC_RUNTIME_EARS_PATH"
AGENTS="$ROOT/AGENTS.md"
USER_REVIEW="$ASDLC_USER_REVIEW_FILE"
DESIGN_TEMPLATE="$ASDLC_TEMPLATES_DIR/feature_design_TEMPLATE.md"
DESIGN_GOLDEN="$ASDLC_GOLDEN_EXAMPLES_DIR/feature_design_GOLDEN_EXAMPLE.md"
FEATURE_SYNC_FILE="$ASDLC_FEATURE_SYNC_FILE"
BLUEPRINT_HELPER="$ASDLC_HELPERS_DIR/helper_find_blueprints.sh"

STEP=""
DESIGN_OUT=""
INCLUDE_AGENTS=0
BRANCH_NAME=""
TARGET_BULLETS=""
FEATURE_RICH_DESIGN_PLANNING=0
LAR_SECTION=""

usage() {
  cat <<'EOF'
Usage: .asdlc_worker/scripts/ai_design.sh [--step 1.3] [--design-out file] [--branch-name name] [--include-agents] [--feature-rich-design-planning]

Defaults:
  - If --step is omitted, uses the first unchecked bullet in .asdlc_worker/overmind/implementation_plan.md.
  - If --design-out is omitted, uses .asdlc_worker/step_designs/step-<step>-design.md (created from .asdlc_worker/templates/feature_design_TEMPLATE.md if missing).
  - .asdlc_worker/decisions.md is pointer-only by default.
  - AGENTS.md is referenced by default (not inlined); use --include-agents to inline.
  - Creates/switches to branch step-<step>-plan unless --branch-name is provided.
  - --feature-rich-design-planning adds an opt-in richer design guidance block (bounded optional hardening capture).

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
    in_req && /^## [^#]/ { exit }
    in_req && $0 ~ "^### Requirement " && $0 !~ "^### Requirement "req_re" " { exit }
    in_req { print }
  ' "$REQUIREMENTS"
}

get_requirements_section() {
  local step_section="$1"
  local reqs
  reqs="$(printf '%s\n' "$step_section" | grep -oE "\\[REQ-[0-9]+(\\.[0-9]+)?\\]" | tr -d '[]' | sed 's/^REQ-//' | sort -u)"
  if [[ -z "$reqs" ]]; then
    echo "No REQ tags found in step bullets. Select EARS blocks manually in design `## Selected EARS Requirements (for planning translation)`."
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

collect_lar_ids() {
  local req_section="$1"
  [[ -z "$req_section" ]] && return 0

  printf '%s\n' "$req_section" | awk '
    function emit_ids(text, rest) {
      rest = text
      while (match(rest, /LAR-[0-9]+/)) {
        print substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
      }
    }

    /^\*\*Linked Artifacts:\*\*/ {
      in_linked=1
      next
    }

    in_linked && /^[[:space:]]*-[[:space:]]*/ {
      emit_ids($0)
      next
    }

    in_linked {
      if ($0 ~ /^[[:space:]]*$/ ||
          $0 ~ /^\*\*/ ||
          $0 ~ /^### / ||
          $0 ~ /^## / ||
          $0 ~ /^---[[:space:]]*$/) {
        in_linked=0
      }
    }
  ' | sort -t- -k2 -n | uniq
}

get_lar_registry_entries() {
  awk '
    function trim(str) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", str)
      return str
    }

    function unquote(str) {
      str = trim(str)
      if ((str ~ /^".*"$/) || (str ~ /^'\''.*'\''$/)) {
        str = substr(str, 2, length(str) - 2)
      }
      return str
    }

    function emit_yaml_entry() {
      if (current_id == "") {
        return
      }
      print current_id " | " current_type " | " current_title " | " current_locator
      current_id=""
      current_type=""
      current_title=""
      current_locator=""
    }

    /^## Linked Artifacts[[:space:]]*$/ {
      in_reg=1
      next
    }

    !in_reg { next }

    /^## / {
      emit_yaml_entry()
      exit
    }

    /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
      emit_yaml_entry()
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", line)
      current_id = unquote(line)
      next
    }

    current_id != "" && /^[[:space:]]+[[:alnum:]_-]+:[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      key = line
      sub(/:.*/, "", key)
      value = line
      sub(/^[^:]+:[[:space:]]*/, "", value)
      value = unquote(value)

      if (key == "id") current_id = value
      if (key == "type") current_type = value
      if (key == "title") current_title = value
      if (key == "locator") current_locator = value
      next
    }

    END {
      emit_yaml_entry()
    }
  ' "$REQUIREMENTS"
}

get_step_lar_section() {
  local req_section="$1"

  local lar_ids
  lar_ids="$(collect_lar_ids "$req_section")"

  [[ -z "$lar_ids" ]] && return 0

  local registry_entries
  registry_entries="$(get_lar_registry_entries)"
  [[ -z "$registry_entries" ]] && return 0

  local lar_id entry
  while IFS= read -r lar_id; do
    [[ -z "$lar_id" ]] && continue
    entry="$(printf '%s\n' "$registry_entries" | awk -F'[[:space:]]*\\|[[:space:]]*' -v id="$lar_id" '
      $1 == id {
        print
        exit
      }
    ')"
    [[ -n "$entry" ]] && printf '%s\n' "- $entry"
  done <<<"$lar_ids"
}

get_process_design_section() {
  awk '
    /^### 1\)/ { in_scope=1 }
    /^### 2\)/ { exit }
    in_scope { print }
  ' "$PROCESS"
}

read_yaml_scalar() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  awk -v key="$key" '
    function trim(str) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", str)
      return str
    }
    $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
      line = $0
      sub("^[[:space:]]*" key ":[[:space:]]*", "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      line = trim(line)
      if ((line ~ /^".*"$/) || (line ~ /^'\''.*'\''$/)) {
        line = substr(line, 2, length(line) - 2)
      }
      print line
      exit
    }
  ' "$file"
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
          printf -- '- (none found; verify %s step bullets)\n' "$PLAN"
        fi
        ;;
      "- <selected EARS requirement excerpts used to translate step-plan functional requirements>")
        if [[ -n "$REQ_SECTION" ]]; then
          printf '%s\n' "$REQ_SECTION"
        else
          printf -- '- (none found; add selected EARS blocks from %s)\n' "$REQUIREMENTS"
        fi
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done <<<"$body" >"$DESIGN_OUT"
}

ensure_applicable_adr_shortlist_section() {
  if grep -Fqx "## Applicable ADR Shortlist (from .asdlc_worker/decisions.md)" "$DESIGN_OUT"; then
    return 0
  fi
  if grep -Fqx "## Applicable ADR Shortlist (from ai/decisions.md)" "$DESIGN_OUT"; then
    return 0
  fi
  if grep -Fqx "## Applicable ADR Shortlist" "$DESIGN_OUT"; then
    return 0
  fi

  local today
  today="$(date +%Y-%m-%d)"

  local tmp_dir tmp
  tmp_dir="$ASDLC_WORKER_HOME/tmp"
  mkdir -p "$tmp_dir"
  tmp="$tmp_dir/${PROJECT}-step-${STEP}.adr-shortlist.$$.tmp"

  awk -v today="$today" '
    BEGIN { inserted = 0 }
    /^## Applicable AGENTS\.md Constraints/ && inserted == 0 {
      print "## Applicable ADR Shortlist (from .asdlc_worker/decisions.md)"
      print "- None applicable for this feature. (reviewed on " today ")"
      print ""
      inserted = 1
    }
    { print }
    END {
      if (inserted == 0) {
        print ""
        print "## Applicable ADR Shortlist (from .asdlc_worker/decisions.md)"
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
    --feature-rich-design-planning)
      FEATURE_RICH_DESIGN_PLANNING=1
      shift
      ;;
    --no-feature-rich-design-planning)
      FEATURE_RICH_DESIGN_PLANNING=0
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
    echo "No unchecked bullets found in $PLAN." >&2
    exit 1
  fi
  IFS='|' read -r STEP STEP_TITLE BULLET <<<"$line"
else
  STEP_TITLE="$(get_step_title "$STEP")"
  if [[ -z "$STEP_TITLE" ]]; then
    echo "Step $STEP not found in $PLAN." >&2
    exit 1
  fi
  BULLET="$(get_step_first_unchecked "$STEP")"
  if [[ -z "$BULLET" ]]; then
    BULLET="(no unchecked bullets in step)"
  fi
fi

if [[ -z "$DESIGN_OUT" ]]; then
  DESIGN_OUT="$ASDLC_STEP_DESIGNS_DIR/step-$STEP-design.md"
fi

ensure_design_branch

STEP_SECTION="$(get_step_section "$STEP")"
if [[ -z "$STEP_SECTION" ]]; then
  echo "Step $STEP section not found in $PLAN." >&2
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
LAR_SECTION="$(get_step_lar_section "$REQ_SECTION")"
FEATURE_SYNC_SOURCE_FEATURE_PATH="${ASDLC_RUNTIME_PLAN_PATH:+$(dirname "$ASDLC_RUNTIME_PLAN_PATH")}"

mkdir -p "$(dirname "$DESIGN_OUT")"
if [[ ! -f "$DESIGN_OUT" ]]; then
  write_design_from_template
fi
ensure_applicable_adr_shortlist_section

emit() {
  local design_label
  local helper_label
  if [[ "$DESIGN_OUT" == "$ROOT/"* ]]; then
    design_label="${DESIGN_OUT#"$ROOT"/}"
  else
    design_label="$DESIGN_OUT"
  fi
  if [[ "$BLUEPRINT_HELPER" == "$ROOT/"* ]]; then
    helper_label="${BLUEPRINT_HELPER#"$ROOT"/}"
  else
    helper_label="$BLUEPRINT_HELPER"
  fi

  printf 'Feature design phase for Step %s\n' "$STEP"
  printf 'Target bullets (excluding planning/review):\n%s\n' "${TARGET_BULLETS:-- (none found; verify step bullets)}"
  printf 'Use .asdlc_worker/AI_DEVELOPMENT_PROCESS.md (Section 1) as process rules.\n'
  printf 'Create/update feature design at: %s\n' "$DESIGN_OUT"
  printf 'Apply `#### Bootstrap decision algorithm` from Section 1 before design handoff.\n'
  printf 'Blueprint helper contract: when bootstrap is required and stack/architecture guidance is needed, run `%s` from the ASDLC feature folder context where `implementation_plan.md` and `requirements_ears.md` live; it searches the parent project-level directory for `project_stack_blueprint_*.md`.\n' "$helper_label"
  if [[ -n "$FEATURE_SYNC_SOURCE_FEATURE_PATH" ]]; then
    printf 'Suggested bootstrap lookup command for this run: `cd "%s" && "%s"`.\n' "$FEATURE_SYNC_SOURCE_FEATURE_PATH" "$BLUEPRINT_HELPER"
  else
    printf 'ASDLC source feature path is unavailable (ASDLC_RUNTIME_PLAN_PATH not set). If bootstrap is required, locate the source feature folder first or ask the user before inventing stack/scaffold details.\n'
  fi
  if [[ "$FEATURE_RICH_DESIGN_PLANNING" -eq 1 ]]; then
    printf 'Feature-rich design/planning mode: ENABLED (design-only add-on).\n'
    printf 'Add a concise "Optional Hardening Opportunities" shortlist (max 5 bullets) from risks/trade-offs.\n'
    printf 'Each optional bullet must state default decision intent (`Accepted` or `Deferred`) and why.\n'
    printf 'Keep required scope boundaries unchanged unless an optional item is explicitly accepted.\n'
  fi
  if [[ -n "$LAR_SECTION" ]]; then
    printf 'Linked Artifacts (in scope): after writing the design artifact, invoke `.asdlc_worker/scripts/helpers/sync_step_lars.sh %s %s` to sync the ## Linked Artifacts (in scope) section deterministically; do not echo the block textually into the artifact.\n' "$STEP" "$design_label"
  fi
  printf 'Before ending the design phase, run `.asdlc_worker/scripts/helpers/check_design_readiness.sh %s`.\n' "$design_label"
  printf 'If the readiness check fails, do not emit the final completion line yet. Either continue iterating and re-run the check, or ask exactly two options: `1.` continue iterating and re-check, `2.` force the design phase done and proceed.\n'
  printf 'If option `2` is chosen, record that forced-done outcome in the design artifact before using the completion line.\n'
  printf 'When design phase is fully complete, end your final response with this exact last line: "Design phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase."\n'
  printf '\n'
  printf 'Context pack\n'
  printf '== implementation_plan.md ($ASDLC_RUNTIME_PLAN_PATH, Step %s - %s) ==\n' "$STEP" "$STEP_TITLE"
  printf '%s\n\n' "$STEP_SECTION"
  printf '== %s ==\n' "$design_label"
  cat "$DESIGN_OUT"
  printf '\n\n'
  if [[ -f "$DESIGN_GOLDEN" ]]; then
    printf '== .asdlc_worker/golden_examples/feature_design_GOLDEN_EXAMPLE.md ==\n'
    cat "$DESIGN_GOLDEN"
    printf '\n\n'
  fi
  printf '== requirements_ears.md ($ASDLC_RUNTIME_EARS_PATH, selected EARS candidates for design translation) ==\n'
  printf '%s\n\n' "$REQ_SECTION"
  printf '== ## Linked Artifacts (in scope) ==\n'
  if [[ -n "$LAR_SECTION" ]]; then
    printf '%s\n\n' "$LAR_SECTION"
  else
    printf '(none — step requirements reference no LAR-tagged EARS)\n\n'
  fi
  printf '== .asdlc_worker/blocker_log.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$BLOCKER_LOG_SECTION"
  printf '== .asdlc_worker/open_questions.md (Step %s) ==\n' "$STEP"
  printf '%s\n\n' "$OPEN_QUESTIONS_SECTION"
  printf '== Bootstrap context ==\n'
  if [[ -f "$FEATURE_SYNC_FILE" ]]; then
    printf 'Feature meta sync file: .asdlc_worker/feature_meta_sync.yaml\n'
    cat "$FEATURE_SYNC_FILE"
    printf '\n\n'
  else
    printf 'Feature meta sync file missing: .asdlc_worker/feature_meta_sync.yaml\n\n'
  fi
  printf 'Blueprint helper path: %s\n\n' "$helper_label"
  printf '== .asdlc_worker/decisions.md (Accepted ADRs) ==\n'
  printf 'Read directly from repo and shortlist only relevant accepted ADRs for this step/feature.\n'
  printf 'Path: .asdlc_worker/decisions.md\n\n'
  printf '== .asdlc_worker/user_review.md ==\n'
  printf 'Read directly from repo and shortlist only relevant rules for this feature.\n'
  printf 'Path: .asdlc_worker/user_review.md\n\n'
  printf '== .asdlc_worker/AI_DEVELOPMENT_PROCESS.md (Section 1) ==\n'
  process_design_section="$(get_process_design_section)"
  if [[ -n "$process_design_section" ]]; then
    printf '%s\n' "$process_design_section"
  else
    printf 'Section 1 not found; read .asdlc_worker/AI_DEVELOPMENT_PROCESS.md directly.\n'
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
