#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/helpers/runtime_layout.sh"
asdlc_worker_require_runtime_layout "${BASH_SOURCE[0]}"
ROOT="$WORKER_REPO_ROOT"
PROJECT="$(basename "$ROOT")"
HISTORY_FILE="$ASDLC_HISTORY_FILE"
OVERMIND_BRANCH="overmind"
IMPLEMENTATION_PLAN_REL_PATH=".asdlc_worker/overmind/implementation_plan.md"  # standalone mode only

STEP=""
FEATURE_ID=""
BASE_BRANCH=""
REVIEW_BRANCH=""
IMPLEMENTATION_BRANCH=""
HISTORY_OUT="$HISTORY_FILE"
DRY_RUN=0
METRICS_FROM_REF=""
METRICS_TO_REF=""
METRICS_DIRECTION_NOTE=""
METRICS_USE_INDEX=0
METRICS_SNAPSHOT_INDEX=""

usage() {
  cat <<'EOF'
Usage: .asdlc_worker/scripts/post_review.sh [--step 1.6e] [--base-branch master] [--review-branch step-1.6e-review] [--implementation-branch step-1.6e-implementation] [--history-out file] [--dry-run]

Defaults:
  - If --step is omitted, uses the latest .asdlc_worker/step_plans/step-*.md.
  - --base-branch defaults to `master` when present, otherwise `main`.
  - --review-branch defaults to step-<step>-review.
  - --implementation-branch defaults to step-<step>-implementation.
  - --history-out defaults to .asdlc_worker/history.md.
  - Hard gate before history consolidation: review artifact must exist and every finding must have exactly one terminal state.
  - Captures post-review metrics before any auto-commit, including pending local changes via a temporary working-tree snapshot.
  - If uncommitted review changes exist, commits them as a review-completion guard before history update.
  - Then writes post-review history and commits remaining uncommitted changes on the current branch.
  - Then syncs only `.asdlc_worker/overmind/implementation_plan.md` from the review branch into local `overmind` branch and commits it there (if changed).
  - Keeps one consolidated history record per step with:
    - Aggregated token usage + per-phase subsection (design/planning/implementation/user_review/ai_audit).
    - New lines of code added (all files except .asdlc_worker/**), measured from the step delta to review (base..review when possible, otherwise merge-base..review). Pending local changes are included via a working-tree snapshot.
    - New files added (newly created files, excludes .asdlc_worker/**), measured from the same delta.
    - Files touched (modified existing files, excludes .asdlc_worker/**), measured from the same delta.
EOF
}

enforce_ai_audit_disposition_readiness() {
  local review_file=""
  local check_output=""

  if [[ -n "$FEATURE_ID" ]]; then
    review_file="$ASDLC_STEP_REVIEW_RESULTS_DIR/review_result-$STEP-$FEATURE_ID.md"
  else
    review_file="$ASDLC_STEP_REVIEW_RESULTS_DIR/review_result-$STEP.md"
  fi
  if [[ ! -f "$review_file" ]]; then
    echo "Post-review readiness failed for step $STEP." >&2
    echo "Review artifact not found: $review_file" >&2
    echo "ai_audit dispositions were not finished correctly. Complete the review artifact and rerun post_review." >&2
    exit 1
  fi

  if ! check_output="$(awk '
    BEGIN { in_finding=0; findings=0; errors=0; fid=""; follow=0; raised=0; rejected=0 }
    /^### F-[0-9]+/ {
      if (in_finding) {
        checked = follow + raised + rejected
        if (checked == 0) { print fid ": missing disposition state"; errors++ }
        else if (checked > 1) { print fid ": conflicting disposition states"; errors++ }
      }
      in_finding=1
      findings++
      fid=$2
      follow=0; raised=0; rejected=0
      next
    }
    in_finding && /^[[:space:]]*-[[:space:]]+\[[xX]\][[:space:]]+follow_up_created([[:space:]:]|$)/ { follow=1; next }
    in_finding && /^[[:space:]]*-[[:space:]]+\[[xX]\][[:space:]]+raised_to_coordinator([[:space:]:]|$)/ { raised=1; next }
    in_finding && /^[[:space:]]*-[[:space:]]+\[[xX]\][[:space:]]+rejected([[:space:]:]|$)/ { rejected=1; next }
    END {
      if (in_finding) {
        checked = follow + raised + rejected
        if (checked == 0) { print fid ": missing disposition state"; errors++ }
        else if (checked > 1) { print fid ": conflicting disposition states"; errors++ }
      }
      if (findings == 0) {
        print "No findings found in review artifact (expected `### F-NN` blocks)."
        errors++
      }
      if (errors > 0) exit 1
    }
  ' "$review_file")"; then
    echo "Post-review readiness failed for step $STEP." >&2
    printf '%s\n' "$check_output" >&2
    echo "ai_audit dispositions were not finished correctly. Complete the review artifact and rerun post_review." >&2
    exit 1
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
    plan="$ASDLC_STEP_PLANS_DIR/step-$step.md"
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
  merge_base="$(git -C "$ROOT" merge-base "$BASE_BRANCH" "$REVIEW_BRANCH" 2>/dev/null || true)"
  if [[ -z "$merge_base" ]]; then
    echo "Could not determine merge-base for $BASE_BRANCH and $REVIEW_BRANCH." >&2
    exit 1
  fi

  if git -C "$ROOT" merge-base --is-ancestor "$BASE_BRANCH" "$REVIEW_BRANCH"; then
    METRICS_FROM_REF="$BASE_BRANCH"
    METRICS_TO_REF="$REVIEW_BRANCH"
    METRICS_DIRECTION_NOTE="base..review (review ahead)"
    return 0
  fi

  METRICS_FROM_REF="$merge_base"
  METRICS_TO_REF="$REVIEW_BRANCH"
  if git -C "$ROOT" merge-base --is-ancestor "$REVIEW_BRANCH" "$BASE_BRANCH"; then
    METRICS_DIRECTION_NOTE="merge-base..review (base ahead; using review delta)"
  else
    METRICS_DIRECTION_NOTE="merge-base..review (branches diverged)"
  fi
}

cleanup_metrics_snapshot() {
  if [[ -n "$METRICS_SNAPSHOT_INDEX" && -f "$METRICS_SNAPSHOT_INDEX" ]]; then
    rm -f "$METRICS_SNAPSHOT_INDEX"
  fi
}

metrics_git() {
  if [[ "$METRICS_USE_INDEX" -eq 1 ]]; then
    GIT_INDEX_FILE="$METRICS_SNAPSHOT_INDEX" git -C "$ROOT" "$@"
  else
    git -C "$ROOT" "$@"
  fi
}

prepare_metrics_snapshot() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  local status_output=""
  status_output="$(git -C "$ROOT" status --porcelain --untracked-files=all)"
  if [[ -z "$status_output" ]]; then
    return 0
  fi

  METRICS_SNAPSHOT_INDEX="$(mktemp)"
  if [[ -f "$ROOT/.git/index" ]]; then
    cp "$ROOT/.git/index" "$METRICS_SNAPSHOT_INDEX"
  fi
  GIT_INDEX_FILE="$METRICS_SNAPSHOT_INDEX" git -C "$ROOT" add -A
  METRICS_USE_INDEX=1
  METRICS_DIRECTION_NOTE="$METRICS_DIRECTION_NOTE + working-tree snapshot"
}

ensure_current_branch_matches_review_branch() {
  local current_branch
  current_branch="$(get_current_branch)"
  if [[ "$current_branch" != "$REVIEW_BRANCH" ]]; then
    echo "Current branch '$current_branch' does not match review branch '$REVIEW_BRANCH'." >&2
    echo "Switch to $REVIEW_BRANCH and rerun post-review." >&2
    exit 1
  fi
}

count_loc_added_excluding_ai() {
  # Count added lines across the repo, excluding runtime artifacts under /.asdlc_worker.
  if [[ "$METRICS_USE_INDEX" -eq 1 ]]; then
    metrics_git diff --cached --numstat "$METRICS_FROM_REF" \
      | awk -F '\t' '($1 ~ /^[0-9]+$/ && $3 !~ /^\.asdlc_worker\//) { sum += $1 } END { print sum + 0 }'
  else
    metrics_git diff --numstat "$METRICS_FROM_REF..$METRICS_TO_REF" \
      | awk -F '\t' '($1 ~ /^[0-9]+$/ && $3 !~ /^\.asdlc_worker\//) { sum += $1 } END { print sum + 0 }'
  fi
}

count_new_files_added_excluding_ai() {
  # Count newly added files, excluding .asdlc_worker/.
  local diff_args=()
  if [[ "$METRICS_USE_INDEX" -eq 1 ]]; then
    diff_args=(diff --cached --name-only --diff-filter=A "$METRICS_FROM_REF")
  else
    diff_args=(diff --name-only --diff-filter=A "$METRICS_FROM_REF..$METRICS_TO_REF")
  fi
  metrics_git "${diff_args[@]}" \
    | awk '$0 !~ /^\.asdlc_worker\// { count++ } END { print count + 0 }'
}

count_touched_files_excluding_ai() {
  # Count modified (not newly added) files, excluding .asdlc_worker/.
  local diff_args=()
  if [[ "$METRICS_USE_INDEX" -eq 1 ]]; then
    diff_args=(diff --cached --name-only --diff-filter=M "$METRICS_FROM_REF")
  else
    diff_args=(diff --name-only --diff-filter=M "$METRICS_FROM_REF..$METRICS_TO_REF")
  fi
  metrics_git "${diff_args[@]}" \
    | awk '$0 !~ /^\.asdlc_worker\// { count++ } END { print count + 0 }'
}

ensure_history_file() {
  if [[ -f "$HISTORY_OUT" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$HISTORY_OUT")"
  cat >"$HISTORY_OUT" <<'EOF'
# AI Run History

This file is updated by `.asdlc_worker/scripts/post_review.sh` with one consolidated record per step.

EOF
}

extract_token_usage_from_log() {
  local phase="$1"
  local phase_token
  local step_token
  phase_token="$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  step_token="$(printf '%s' "$STEP_NUM" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  local candidates=(
    "$ASDLC_LOGS_DIR/${PROJECT}-${phase}-latest-log"
    "$ASDLC_LOGS_DIR/${PROJECT}-${phase_token}-latest-log"
    "$ASDLC_LOGS_DIR/${PROJECT}-${phase}-${STEP_NUM}-log"
    "$ASDLC_LOGS_DIR/${PROJECT}-${phase_token}-${STEP_NUM}-log"
    "$ASDLC_LOGS_DIR/${PROJECT}-${phase_token}-${step_token}-log"
  )
  local log_path line

  for log_path in "${candidates[@]}"; do
    if [[ ! -f "$log_path" ]]; then
      continue
    fi
    line="$(grep -aE 'Token usage:' "$log_path" 2>/dev/null | tail -n 1 || true)"
    if [[ -n "$line" ]]; then
      printf '%s' "${line#*Token usage:}" | tr -d '\r' | sed -E 's/^[[:space:]]+//'
      return 0
    fi
  done

  if [[ -z "${line:-}" ]]; then
    return 0
  fi
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
  local files_added="$5"
  local files_touched="$6"
  local design_usage="$7"
  local planning_usage="$8"
  local implementation_usage="$9"
  local user_review_usage="${10}"
  local ai_audit_usage="${11}"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  local total_sum=0
  local input_sum=0
  local cached_sum=0
  local output_sum=0
  local reasoning_sum=0

  local usage
  for usage in "$design_usage" "$planning_usage" "$implementation_usage" "$user_review_usage" "$ai_audit_usage"; do
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
    if [[ -n "$design_usage" ]]; then
      printf -- '  - Phase: design - %s\n' "$design_usage"
    fi
    if [[ -n "$planning_usage" ]]; then
      printf -- '  - Phase: planning - %s\n' "$planning_usage"
    fi
    if [[ -n "$implementation_usage" ]]; then
      printf -- '  - Phase: implementation - %s\n' "$implementation_usage"
    fi
    if [[ -n "$user_review_usage" ]]; then
      printf -- '  - Phase: user_review - %s\n' "$user_review_usage"
    fi
    if [[ -n "$ai_audit_usage" ]]; then
      printf -- '  - Phase: ai_audit - %s\n' "$ai_audit_usage"
    fi
    printf -- '- New lines of code added: %s\n' "$loc_added"
    printf -- '- New files added: %s\n' "$files_added"
    printf -- '- Files touched: %s\n' "$files_touched"
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

commit_pending_review_changes_guard() {
  local step="$1"
  local title="$2"
  local status_output commit_message
  status_output="$(git -C "$ROOT" status --porcelain --untracked-files=all)"
  if [[ -z "$status_output" ]]; then
    return 0
  fi

  git -C "$ROOT" add -A
  commit_message="Step $step review completion"
  if [[ -n "$title" ]]; then
    commit_message="$commit_message - $title"
  fi
  git -C "$ROOT" commit -m "$commit_message"
  printf 'Committed pending review-phase changes on branch %s before post-review history update (metrics were already captured).\n' "$(get_current_branch)"
}

sync_implementation_plan_to_overmind_branch() {
  local source_branch="$1"
  local step="$2"
  local title="$3"
  local switched_to_overmind=0
  local file_status=""
  local commit_message=""

  if ! git -C "$ROOT" show-ref --verify --quiet "refs/heads/$OVERMIND_BRANCH"; then
    echo "Required branch '$OVERMIND_BRANCH' is missing." >&2
    echo "Create local branch '$OVERMIND_BRANCH' and rerun post-review." >&2
    exit 1
  fi

  if ! git -C "$ROOT" cat-file -e "$source_branch:$IMPLEMENTATION_PLAN_REL_PATH" 2>/dev/null; then
    echo "Source file '$IMPLEMENTATION_PLAN_REL_PATH' not found on branch '$source_branch'." >&2
    exit 1
  fi

  cleanup_sync_branch() {
    if [[ "$switched_to_overmind" -eq 1 ]]; then
      git -C "$ROOT" checkout "$source_branch" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_sync_branch RETURN

  git -C "$ROOT" checkout "$OVERMIND_BRANCH" >/dev/null
  switched_to_overmind=1

  git -C "$ROOT" checkout "$source_branch" -- "$IMPLEMENTATION_PLAN_REL_PATH"
  file_status="$(git -C "$ROOT" status --porcelain --untracked-files=all -- "$IMPLEMENTATION_PLAN_REL_PATH")"
  if [[ -z "$file_status" ]]; then
    printf 'No changes to sync for %s on branch %s.\n' "$IMPLEMENTATION_PLAN_REL_PATH" "$OVERMIND_BRANCH"
  else
    git -C "$ROOT" add "$IMPLEMENTATION_PLAN_REL_PATH"
    commit_message="Post-review sync: step $step implementation plan"
    if [[ -n "$title" ]]; then
      commit_message="$commit_message - $title"
    fi
    git -C "$ROOT" commit -m "$commit_message"
    printf 'Synced %s from %s into branch %s.\n' "$IMPLEMENTATION_PLAN_REL_PATH" "$source_branch" "$OVERMIND_BRANCH"
  fi

  git -C "$ROOT" checkout "$source_branch" >/dev/null
  switched_to_overmind=0
  trap - RETURN
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)
      require_option_arg "--step" "${2:-}"
      STEP="$2"
      shift 2
      ;;
    --feature-id)
      require_option_arg "--feature-id" "${2:-}"
      FEATURE_ID="$2"
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
  if [[ -z "$FEATURE_ID" && -n "$STEP_PLAN" && -n "$STEP" ]]; then
    _plan_base="$(basename "$STEP_PLAN" .md)"
    _plan_rest="${_plan_base#step-$STEP-}"
    if [[ "$_plan_rest" != "$_plan_base" && -n "$_plan_rest" ]]; then
      FEATURE_ID="$_plan_rest"
    fi
    unset _plan_base _plan_rest
  fi
else
  if [[ -n "$FEATURE_ID" ]]; then
    STEP_PLAN="$ASDLC_STEP_PLANS_DIR/step-$STEP-$FEATURE_ID.md"
  else
    STEP_PLAN="$ASDLC_STEP_PLANS_DIR/step-$STEP.md"
  fi
fi

if [[ -z "$STEP" ]]; then
  echo "Could not determine step." >&2
  exit 1
fi

enforce_ai_audit_disposition_readiness

if [[ -z "$REVIEW_BRANCH" ]]; then
  if [[ -n "$FEATURE_ID" ]]; then
    REVIEW_BRANCH="step-$STEP-$FEATURE_ID-review"
  else
    REVIEW_BRANCH="step-$STEP-review"
  fi
fi

if [[ -z "$IMPLEMENTATION_BRANCH" ]]; then
  if [[ -n "$FEATURE_ID" ]]; then
    IMPLEMENTATION_BRANCH="step-$STEP-$FEATURE_ID-implementation"
  else
    IMPLEMENTATION_BRANCH="step-$STEP-implementation"
  fi
fi

if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH="$(detect_default_base_branch)"
fi

ensure_commit_ref_exists "$BASE_BRANCH"
ensure_commit_ref_exists "$REVIEW_BRANCH"
ensure_commit_ref_exists "$IMPLEMENTATION_BRANCH"
if [[ ! -f "$ASDLC_BINDING_FILE" ]]; then
  ensure_commit_ref_exists "$OVERMIND_BRANCH"
fi
ensure_current_branch_matches_review_branch
resolve_metrics_refs
trap cleanup_metrics_snapshot EXIT
prepare_metrics_snapshot

STEP_AND_TITLE="$(extract_step_and_title_from_plan "$STEP_PLAN")"
IFS='|' read -r STEP_NUM STEP_TITLE <<<"$STEP_AND_TITLE"
if [[ -z "$STEP_NUM" ]]; then
  STEP_NUM="$STEP"
fi
if [[ "$STEP_TITLE" == "$STEP_AND_TITLE" ]]; then
  STEP_TITLE=""
fi

LOC_ADDED="$(count_loc_added_excluding_ai)"
FILES_ADDED="$(count_new_files_added_excluding_ai)"
FILES_TOUCHED="$(count_touched_files_excluding_ai)"

DESIGN_USAGE="$(extract_token_usage_from_log design)"
PLANNING_USAGE="$(extract_token_usage_from_log planning)"
IMPLEMENTATION_USAGE="$(extract_token_usage_from_log implementation)"
USER_REVIEW_USAGE="$(extract_token_usage_from_log user_review)"
AI_AUDIT_USAGE="$(extract_token_usage_from_log ai_audit)"
LEGACY_REVIEW_USAGE="$(extract_token_usage_from_log review)"

if [[ -z "$DESIGN_USAGE" ]]; then
  DESIGN_USAGE="$(extract_phase_usage_from_history "$STEP_NUM" design)"
fi
if [[ -z "$PLANNING_USAGE" ]]; then
  PLANNING_USAGE="$(extract_phase_usage_from_history "$STEP_NUM" planning)"
fi
if [[ -z "$IMPLEMENTATION_USAGE" ]]; then
  IMPLEMENTATION_USAGE="$(extract_phase_usage_from_history "$STEP_NUM" implementation)"
fi
if [[ -z "$USER_REVIEW_USAGE" ]]; then
  USER_REVIEW_USAGE="$(extract_phase_usage_from_history "$STEP_NUM" user_review)"
fi
if [[ -z "$AI_AUDIT_USAGE" ]]; then
  AI_AUDIT_USAGE="$(extract_phase_usage_from_history "$STEP_NUM" ai_audit)"
fi
if [[ -z "$AI_AUDIT_USAGE" ]]; then
  # Backward compatibility for existing history records from pre-rename runs.
  AI_AUDIT_USAGE="$(extract_phase_usage_from_history "$STEP_NUM" review)"
fi
if [[ -z "$USER_REVIEW_USAGE" && -z "$AI_AUDIT_USAGE" ]]; then
  # Legacy runs may have only a single review phase without user_review/ai_audit split.
  if [[ -z "$LEGACY_REVIEW_USAGE" ]]; then
    LEGACY_REVIEW_USAGE="$(extract_phase_usage_from_history "$STEP_NUM" review)"
  fi
  if [[ -n "$LEGACY_REVIEW_USAGE" ]]; then
    AI_AUDIT_USAGE="$LEGACY_REVIEW_USAGE"
  fi
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
  printf 'overmind: %s\n' "$OVERMIND_BRANCH"
  printf 'metrics range: %s..%s (%s)\n' "$METRICS_FROM_REF" "$METRICS_TO_REF" "$METRICS_DIRECTION_NOTE"
  printf 'current branch: %s\n' "$dry_run_branch"
  printf 'uncommitted changes present: %s\n' "$dry_run_changes"
  printf 'design usage: %s\n' "${DESIGN_USAGE:-<none>}"
  printf 'planning usage: %s\n' "${PLANNING_USAGE:-<none>}"
  printf 'implementation usage: %s\n' "${IMPLEMENTATION_USAGE:-<none>}"
  printf 'user_review usage: %s\n' "${USER_REVIEW_USAGE:-<none>}"
  printf 'ai_audit usage: %s\n' "${AI_AUDIT_USAGE:-<none>}"
  printf 'new lines of code added: %s\n' "$LOC_ADDED"
  printf 'new files added: %s\n' "$FILES_ADDED"
  printf 'files touched: %s\n' "$FILES_TOUCHED"
  printf 'history out: %s\n' "$HISTORY_OUT"
  exit 0
fi

commit_pending_review_changes_guard "$STEP_NUM" "$STEP_TITLE"

ensure_history_file
remove_step_sections_from_history "$STEP_NUM"
append_consolidated_entry \
  "$STEP_NUM" \
  "$STEP_TITLE" \
  "$STEP_PLAN" \
  "$LOC_ADDED" \
  "$FILES_ADDED" \
  "$FILES_TOUCHED" \
  "$DESIGN_USAGE" \
  "$PLANNING_USAGE" \
  "$IMPLEMENTATION_USAGE" \
  "$USER_REVIEW_USAGE" \
  "$AI_AUDIT_USAGE"
commit_uncommitted_changes "$STEP_NUM" "$STEP_TITLE"
if [[ ! -f "$ASDLC_BINDING_FILE" ]]; then
  sync_implementation_plan_to_overmind_branch "$REVIEW_BRANCH" "$STEP_NUM" "$STEP_TITLE"
fi

printf 'Post-review history updated for step %s.\n' "$STEP_NUM"
printf 'Metrics diff: %s..%s (%s)\n' "$METRICS_FROM_REF" "$METRICS_TO_REF" "$METRICS_DIRECTION_NOTE"
printf 'New lines of code added: %s\n' "$LOC_ADDED"
printf 'New files added: %s\n' "$FILES_ADDED"
printf 'Files touched: %s\n' "$FILES_TOUCHED"
