#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$(basename "$ROOT")"
HISTORY_FILE="$ROOT/ai/history.md"

STEP=""
BASE_BRANCH=""
REVIEW_BRANCH=""
IMPLEMENTATION_BRANCH=""
HISTORY_OUT="$HISTORY_FILE"
DRY_RUN=0
METRICS_FROM_REF=""
METRICS_TO_REF=""
METRICS_DIRECTION_NOTE=""

usage() {
  cat <<'EOF'
Usage: ai/scripts/post_review.sh [--step 1.6e] [--base-branch master] [--review-branch step-1.6e-review] [--implementation-branch step-1.6e-implementation] [--history-out file] [--dry-run]

Defaults:
  - If --step is omitted, uses the latest ai/step_plans/step-*.md.
  - --base-branch defaults to `master` when present, otherwise `main`.
  - --review-branch defaults to step-<step>-review.
  - --implementation-branch defaults to step-<step>-implementation.
  - --history-out defaults to ai/history.md.
  - Stages and commits all uncommitted files on the current branch.
  - Keeps one consolidated history record per step with:
    - Aggregated token usage + per-phase subsection (planning/implementation/review).
    - New lines of code added (all files except ai/**), measured from an auto-selected base/implementation diff direction.
    - New classes added (new Java type files under src/main/java only; excludes ai/docs/scripts), measured from an auto-selected base/implementation diff direction.
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
  if [[ "$branch" =~ ^step-(.+)-(plan|implementation|review)$ ]]; then
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

extract_step_and_title_from_plan() {
  local plan_path="$1"
  local header=""

  if [[ ! -f "$plan_path" ]]; then
    printf '||'
    return 0
  fi

  header="$(grep -m 1 -E '^# Step Plan:' "$plan_path" 2>/dev/null || true)"
  if [[ "$header" =~ ^#\ Step\ Plan:\ ([^[:space:]]+)\ -\ (.*)$ ]]; then
    printf '%s|%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  printf '||'
}

ensure_commit_ref_exists() {
  local ref="$1"
  if ! git -C "$ROOT" rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
    echo "Git ref does not exist: $ref" >&2
    exit 1
  fi
}

get_current_branch() {
  local branch
  if ! branch="$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
    echo "Current HEAD is detached; post-review auto-commit requires a branch checkout." >&2
    exit 1
  fi
  printf '%s' "$branch"
}

detect_default_base_branch() {
  if git -C "$ROOT" show-ref --verify --quiet refs/heads/master; then
    printf 'master'
    return 0
  fi
  if git -C "$ROOT" show-ref --verify --quiet refs/heads/main; then
    printf 'main'
    return 0
  fi
  echo "Could not determine base branch: neither local 'master' nor 'main' exists." >&2
  exit 1
}

resolve_metrics_refs() {
  local merge_base=""
  merge_base="$(git -C "$ROOT" merge-base "$BASE_BRANCH" "$IMPLEMENTATION_BRANCH" 2>/dev/null || true)"
  if [[ -z "$merge_base" ]]; then
    echo "Could not determine merge-base for $BASE_BRANCH and $IMPLEMENTATION_BRANCH." >&2
    exit 1
  fi

  if git -C "$ROOT" merge-base --is-ancestor "$BASE_BRANCH" "$IMPLEMENTATION_BRANCH"; then
    METRICS_FROM_REF="$BASE_BRANCH"
    METRICS_TO_REF="$IMPLEMENTATION_BRANCH"
    METRICS_DIRECTION_NOTE="base..implementation (implementation ahead)"
    return 0
  fi

  if git -C "$ROOT" merge-base --is-ancestor "$IMPLEMENTATION_BRANCH" "$BASE_BRANCH"; then
    METRICS_FROM_REF="$IMPLEMENTATION_BRANCH"
    METRICS_TO_REF="$BASE_BRANCH"
    METRICS_DIRECTION_NOTE="implementation..base (base ahead)"
    return 0
  fi

  METRICS_FROM_REF="$merge_base"
  METRICS_TO_REF="$IMPLEMENTATION_BRANCH"
  METRICS_DIRECTION_NOTE="merge-base..implementation (branches diverged)"
}

count_loc_added_excluding_ai() {
  # Count added lines across the repo, excluding process artifacts under /ai.
  git -C "$ROOT" diff --numstat "$METRICS_FROM_REF..$METRICS_TO_REF" \
    | awk -F '\t' '($1 ~ /^[0-9]+$/ && $3 !~ /^ai\//) { sum += $1 } END { print sum + 0 }'
}

count_new_java_types_added() {
  # Intentionally count only new Java types under src/main/java.
  local count=0
  local path
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    case "$path" in
      *.java) ;;
      *) continue ;;
    esac
    case "$path" in
      */package-info.java|*/module-info.java)
        continue
        ;;
    esac
    if git -C "$ROOT" show "$METRICS_TO_REF:$path" 2>/dev/null \
      | grep -Eq '\<(class|interface|enum|record)\>[[:space:]]+[A-Za-z_][A-Za-z0-9_]*'; then
      count=$((count + 1))
    fi
  done < <(git -C "$ROOT" diff --name-only --diff-filter=A "$METRICS_FROM_REF..$METRICS_TO_REF" -- src/main/java)
  printf '%s' "$count"
}

ensure_history_file() {
  if [[ -f "$HISTORY_OUT" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$HISTORY_OUT")"
  cat >"$HISTORY_OUT" <<'EOF'
# AI Run History

This file is updated by `ai/scripts/post_review.sh` with one consolidated record per step.

EOF
}

extract_token_usage_from_log() {
  local phase="$1"
  local log_path="$ROOT/ai/tmp/orchestrator_logs/${PROJECT}-${phase}.latest.log"
  if [[ ! -f "$log_path" ]]; then
    return 0
  fi
  local line
  line="$(grep -aE 'Token usage:' "$log_path" 2>/dev/null | tail -n 1 || true)"
  if [[ -z "$line" ]]; then
    return 0
  fi
  printf '%s' "${line#*Token usage:}" | tr -d '\r' | sed -E 's/^[[:space:]]+//'
}

extract_phase_usage_from_history() {
  local step="$1"
  local phase="$2"
  if [[ ! -f "$HISTORY_OUT" ]]; then
    return 0
  fi

  awk -v target_step="$step" -v target_phase="$phase" '
    function flush() {
      if (sec_step == target_step) {
        if (sec_phase == target_phase && sec_usage != "") {
          latest = sec_usage
        }
      }
      sec_step=""
      sec_phase=""
      sec_usage=""
    }

    /^## [0-9]{4}-[0-9]{2}-[0-9]{2}T/ {
      flush()
      next
    }

    /^- Step: / {
      line = $0
      sub(/^- Step: /, "", line)
      split(line, parts, " ")
      sec_step = parts[1]
      next
    }

    /^- Phase: / {
      line = $0
      sub(/^- Phase: /, "", line)
      sec_phase = line
      next
    }

    /^- Token usage: / {
      line = $0
      sub(/^- Token usage: /, "", line)
      sec_usage = line
      next
    }

    /^  - Phase: / {
      if (sec_step != target_step) {
        next
      }
      line = $0
      sub(/^  - Phase: /, "", line)
      split(line, parts, " - ")
      p = parts[1]
      if (p == target_phase) {
        usage = line
        sub(/^[^ ]+ - /, "", usage)
        latest = usage
      }
      next
    }

    END {
      flush()
      if (latest != "") {
        print latest
      }
    }
  ' "$HISTORY_OUT"
}

extract_usage_value() {
  local usage="$1"
  local key="$2"
  local value=""

  case "$key" in
    total)
      value="$(printf '%s\n' "$usage" | sed -n 's/.*total=\([0-9,][0-9,]*\).*/\1/p' | head -n 1)"
      ;;
    input)
      value="$(printf '%s\n' "$usage" | sed -n 's/.*input=\([0-9,][0-9,]*\).*/\1/p' | head -n 1)"
      ;;
    cached)
      value="$(printf '%s\n' "$usage" | sed -n 's/.*(+ \([0-9,][0-9,]*\) cached).*/\1/p' | head -n 1)"
      ;;
    output)
      value="$(printf '%s\n' "$usage" | sed -n 's/.*output=\([0-9,][0-9,]*\).*/\1/p' | head -n 1)"
      ;;
    reasoning)
      value="$(printf '%s\n' "$usage" | sed -n 's/.*(reasoning \([0-9,][0-9,]*\)).*/\1/p' | head -n 1)"
      ;;
    *)
      value=""
      ;;
  esac

  if [[ -z "$value" ]]; then
    printf '0'
  else
    printf '%s' "${value//,/}"
  fi
}

format_int_with_commas() {
  local value="${1:-0}"
  local n="$value"
  local out=""
  local rem
  local chunk

  if [[ "$n" == "0" ]]; then
    printf '0'
    return 0
  fi

  while (( n > 0 )); do
    rem=$((n % 1000))
    n=$((n / 1000))
    if (( n > 0 )); then
      chunk="$(printf '%03d' "$rem")"
    else
      chunk="$rem"
    fi

    if [[ -z "$out" ]]; then
      out="$chunk"
    else
      out="$chunk,$out"
    fi
  done
  printf '%s' "$out"
}

remove_step_sections_from_history() {
  local step="$1"
  local tmp_file
  tmp_file="$(mktemp)"

  awk -v target_step="$step" '
    function flush_section() {
      if (section == "") {
        return
      }
      if (section_step != target_step) {
        printf "%s", section
      }
      section=""
      section_step=""
    }

    /^## [0-9]{4}-[0-9]{2}-[0-9]{2}T/ {
      flush_section()
      section = $0 ORS
      next
    }

    {
      if (section == "") {
        print
      } else {
        section = section $0 ORS
        if ($0 ~ /^- Step: /) {
          line = $0
          sub(/^- Step: /, "", line)
          split(line, parts, " ")
          section_step = parts[1]
        }
      }
    }

    END {
      flush_section()
    }
  ' "$HISTORY_OUT" >"$tmp_file"

  mv "$tmp_file" "$HISTORY_OUT"
}

append_consolidated_entry() {
  local step="$1"
  local title="$2"
  local step_plan="$3"
  local loc_added="$4"
  local classes_added="$5"
  local planning_usage="$6"
  local implementation_usage="$7"
  local review_usage="$8"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  local total_sum=0
  local input_sum=0
  local cached_sum=0
  local output_sum=0
  local reasoning_sum=0

  local usage
  for usage in "$planning_usage" "$implementation_usage" "$review_usage"; do
    [[ -z "$usage" ]] && continue
    total_sum=$((total_sum + $(extract_usage_value "$usage" total)))
    input_sum=$((input_sum + $(extract_usage_value "$usage" input)))
    cached_sum=$((cached_sum + $(extract_usage_value "$usage" cached)))
    output_sum=$((output_sum + $(extract_usage_value "$usage" output)))
    reasoning_sum=$((reasoning_sum + $(extract_usage_value "$usage" reasoning)))
  done

  local step_plan_rel
  if [[ "$step_plan" == "$ROOT/"* ]]; then
    step_plan_rel="${step_plan#"$ROOT"/}"
  else
    step_plan_rel="$step_plan"
  fi

  {
    printf '\n## %s\n' "$ts"
    if [[ -n "$step" && -n "$title" ]]; then
      printf -- '- Step: %s - %s\n' "$step" "$title"
    elif [[ -n "$step" ]]; then
      printf -- '- Step: %s\n' "$step"
    else
      printf -- '- Step: (unknown)\n'
    fi
    printf -- '- Token usage: total=%s input=%s (+ %s cached) output=%s (reasoning %s), including:\n' \
      "$(format_int_with_commas "$total_sum")" \
      "$(format_int_with_commas "$input_sum")" \
      "$(format_int_with_commas "$cached_sum")" \
      "$(format_int_with_commas "$output_sum")" \
      "$(format_int_with_commas "$reasoning_sum")"
    if [[ -n "$planning_usage" ]]; then
      printf -- '  - Phase: planning - %s\n' "$planning_usage"
    fi
    if [[ -n "$implementation_usage" ]]; then
      printf -- '  - Phase: implementation - %s\n' "$implementation_usage"
    fi
    if [[ -n "$review_usage" ]]; then
      printf -- '  - Phase: review - %s\n' "$review_usage"
    fi
    printf -- '- New lines of code added: %s\n' "$loc_added"
    printf -- '- New classes added: %s\n' "$classes_added"
    printf -- '- Step plan: %s\n' "$step_plan_rel"
  } >>"$HISTORY_OUT"
}

commit_uncommitted_changes() {
  local step="$1"
  local title="$2"
  local branch status_output commit_message
  branch="$(get_current_branch)"
  status_output="$(git -C "$ROOT" status --porcelain --untracked-files=all)"
  if [[ -z "$status_output" ]]; then
    printf 'No uncommitted changes found; skipped auto-commit.\n'
    return 0
  fi

  git -C "$ROOT" add -A

  commit_message="Post-review: step $step"
  if [[ -n "$title" ]]; then
    commit_message="$commit_message - $title"
  fi

  git -C "$ROOT" commit -m "$commit_message"
  printf 'Committed all uncommitted files on branch %s.\n' "$branch"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)
      require_option_arg "--step" "${2:-}"
      STEP="$2"
      shift 2
      ;;
    --base-branch)
      require_option_arg "--base-branch" "${2:-}"
      BASE_BRANCH="$2"
      shift 2
      ;;
    --review-branch)
      require_option_arg "--review-branch" "${2:-}"
      REVIEW_BRANCH="$2"
      shift 2
      ;;
    --implementation-branch)
      require_option_arg "--implementation-branch" "${2:-}"
      IMPLEMENTATION_BRANCH="$2"
      shift 2
      ;;
    --history-out)
      require_option_arg "--history-out" "${2:-}"
      HISTORY_OUT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository: $ROOT" >&2
  exit 1
fi

STEP_PLAN=""
if [[ -z "$STEP" ]]; then
  STEP_PLAN="$(get_preferred_step_plan)"
  STEP="$(get_step_from_plan_path "$STEP_PLAN")"
else
  STEP_PLAN="$ROOT/ai/step_plans/step-$STEP.md"
fi

if [[ -z "$STEP" ]]; then
  echo "Could not determine step." >&2
  exit 1
fi

if [[ -z "$REVIEW_BRANCH" ]]; then
  REVIEW_BRANCH="step-$STEP-review"
fi

if [[ -z "$IMPLEMENTATION_BRANCH" ]]; then
  IMPLEMENTATION_BRANCH="step-$STEP-implementation"
fi

if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH="$(detect_default_base_branch)"
fi

ensure_commit_ref_exists "$BASE_BRANCH"
ensure_commit_ref_exists "$REVIEW_BRANCH"
ensure_commit_ref_exists "$IMPLEMENTATION_BRANCH"
resolve_metrics_refs

STEP_AND_TITLE="$(extract_step_and_title_from_plan "$STEP_PLAN")"
IFS='|' read -r STEP_NUM STEP_TITLE <<<"$STEP_AND_TITLE"
if [[ -z "$STEP_NUM" ]]; then
  STEP_NUM="$STEP"
fi
if [[ "$STEP_TITLE" == "$STEP_AND_TITLE" ]]; then
  STEP_TITLE=""
fi

LOC_ADDED="$(count_loc_added_excluding_ai)"
CLASSES_ADDED="$(count_new_java_types_added)"

PLANNING_USAGE="$(extract_token_usage_from_log planning)"
IMPLEMENTATION_USAGE="$(extract_token_usage_from_log implementation)"
REVIEW_USAGE="$(extract_token_usage_from_log review)"

if [[ -z "$PLANNING_USAGE" ]]; then
  PLANNING_USAGE="$(extract_phase_usage_from_history "$STEP_NUM" planning)"
fi
if [[ -z "$IMPLEMENTATION_USAGE" ]]; then
  IMPLEMENTATION_USAGE="$(extract_phase_usage_from_history "$STEP_NUM" implementation)"
fi
if [[ -z "$REVIEW_USAGE" ]]; then
  REVIEW_USAGE="$(extract_phase_usage_from_history "$STEP_NUM" review)"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  dry_run_branch=""
  if dry_run_branch="$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
    :
  else
    dry_run_branch="<detached HEAD>"
  fi
  dry_run_status=""
  dry_run_status="$(git -C "$ROOT" status --porcelain --untracked-files=all)"
  dry_run_changes="no"
  if [[ -n "$dry_run_status" ]]; then
    dry_run_changes="yes"
  fi
  printf 'post_review dry-run\n'
  printf 'step: %s\n' "$STEP_NUM"
  printf 'base: %s\n' "$BASE_BRANCH"
  printf 'review: %s\n' "$REVIEW_BRANCH"
  printf 'implementation: %s\n' "$IMPLEMENTATION_BRANCH"
  printf 'metrics range: %s..%s (%s)\n' "$METRICS_FROM_REF" "$METRICS_TO_REF" "$METRICS_DIRECTION_NOTE"
  printf 'current branch: %s\n' "$dry_run_branch"
  printf 'uncommitted changes present: %s\n' "$dry_run_changes"
  printf 'planning usage: %s\n' "${PLANNING_USAGE:-<none>}"
  printf 'implementation usage: %s\n' "${IMPLEMENTATION_USAGE:-<none>}"
  printf 'review usage: %s\n' "${REVIEW_USAGE:-<none>}"
  printf 'new lines of code added: %s\n' "$LOC_ADDED"
  printf 'new classes added: %s\n' "$CLASSES_ADDED"
  printf 'history out: %s\n' "$HISTORY_OUT"
  exit 0
fi

ensure_history_file
remove_step_sections_from_history "$STEP_NUM"
append_consolidated_entry \
  "$STEP_NUM" \
  "$STEP_TITLE" \
  "$STEP_PLAN" \
  "$LOC_ADDED" \
  "$CLASSES_ADDED" \
  "$PLANNING_USAGE" \
  "$IMPLEMENTATION_USAGE" \
  "$REVIEW_USAGE"
commit_uncommitted_changes "$STEP_NUM" "$STEP_TITLE"

printf 'Post-review history updated for step %s.\n' "$STEP_NUM"
printf 'Metrics diff: %s..%s (%s)\n' "$METRICS_FROM_REF" "$METRICS_TO_REF" "$METRICS_DIRECTION_NOTE"
printf 'New lines of code added: %s\n' "$LOC_ADDED"
printf 'New classes added: %s\n' "$CLASSES_ADDED"
