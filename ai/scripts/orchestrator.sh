#!/usr/bin/env bash
set -euo pipefail

resolve_root_from_ai_scripts() {
  local script_dir ai_dir root expected_scripts
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ai_dir="$(dirname "$script_dir")"
  root="$(dirname "$ai_dir")"
  expected_scripts="$root/ai/scripts"

  if [[ "$(basename "$ai_dir")" != "ai" ]]; then
    echo "Invalid layout: expected script path under <repo>/ai/scripts, got: $script_dir" >&2
    exit 1
  fi

  if [[ ! -d "$expected_scripts" ]]; then
    echo "Invalid layout: expected directory missing: $expected_scripts" >&2
    exit 1
  fi

  if [[ "$(cd "$expected_scripts" && pwd)" != "$script_dir" ]]; then
    echo "Invalid layout: ai/scripts is not located under the computed repo root: $root" >&2
    exit 1
  fi

  printf '%s' "$root"
}

ROOT="$(resolve_root_from_ai_scripts)"
PROJECT="$(basename "$ROOT")"
MODELS="$ROOT/ai/setup/models.md"
HISTORY_FILE="$ROOT/ai/history.md"
DECISIONS_FILE="$ROOT/ai/decisions.md"
BLOCKER_LOG_FILE="$ROOT/ai/blocker_log.md"
OPEN_QUESTIONS_FILE="$ROOT/ai/open_questions.md"
USER_REVIEW_FILE="$ROOT/ai/user_review.md"

# Run all child commands from repository root for consistent sandbox/workspace resolution.
cd "$ROOT"

DRY_RUN=0
REQUESTED_PHASES=()
PLAN_ARGS=()
RAN_REVIEW=0
RAN_POST_REVIEW=0

usage() {
  cat <<'EOF'
Usage: ai/scripts/orchestrator.sh [--phase planning|implementation|review|post_review] [--dry-run] [--help] [-- <ai_plan.sh args>]

Default behavior:
  - Runs all phases in ai/setup/models.md, in order, then runs post_review.
  - planning runs ai/scripts/ai_plan.sh using the planning model entry.
  - implementation runs ai/scripts/ai_implementation.sh for the latest step plan, then runs the implementation model command (includes user review per AI_DEVELOPMENT_PROCESS.md section 4).
  - review runs ai/scripts/ai_review.sh for the latest step plan (post-step audit prompt), then runs the review model command.
  - post_review runs ai/scripts/post_review.sh for the latest step plan and appends post-review metrics to ai/history.md.
  - When running interactively, asks for confirmation before implementation/review.
  - Writes per-phase logs to ai/tmp/orchestrator_logs/<project>-<phase>.latest.log (overwritten each run; safe to delete).
  - post_review consolidates per-step token usage and metrics into ai/history.md.

Examples:
  ai/scripts/orchestrator.sh
  ai/scripts/orchestrator.sh --phase planning -- --step 1.3 --out ai/tmp/step-1.3.md
  ai/scripts/orchestrator.sh --phase implementation
  ai/scripts/orchestrator.sh --phase review
  ai/scripts/orchestrator.sh --phase post_review
  ai/scripts/orchestrator.sh --dry-run
EOF
}

shell_join() {
  local joined=""
  local part
  for part in "$@"; do
    joined+=$(printf '%q ' "$part")
  done
  printf '%s' "${joined% }"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

repo_relpath() {
  local path="$1"
  if [[ "$path" == "$ROOT/"* ]]; then
    printf '%s' "${path#"$ROOT"/}"
  else
    printf '%s' "$path"
  fi
}

ensure_dir_writable() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    if [[ ! -w "$dir" ]]; then
      die "Directory is not writable: $(repo_relpath "$dir")"
    fi
    return 0
  fi
  local err=""
  if ! err="$(mkdir -p "$dir" 2>&1)"; then
    die "Failed to create directory: $(repo_relpath "$dir"): ${err:-unknown error}"
  fi
  if [[ ! -w "$dir" ]]; then
    die "Directory is not writable after creation: $(repo_relpath "$dir")"
  fi
}

ensure_file_writable_if_missing() {
  local file="$1"
  local dir
  dir="$(dirname "$file")"
  ensure_dir_writable "$dir"

  if [[ -f "$file" ]]; then
    if [[ ! -w "$file" ]]; then
      die "File exists but is not writable: $(repo_relpath "$file")"
    fi
    return 0
  fi

  local err=""
  if ! err="$( ( : >"$file" ) 2>&1 )"; then
    die "Failed to create file: $(repo_relpath "$file"): ${err:-unknown error}"
  fi
}

ensure_executable_script() {
  local script="$1"
  if [[ ! -f "$script" ]]; then
    die "Required script not found: $(repo_relpath "$script")"
  fi
  if [[ ! -x "$script" ]]; then
    die "Script is not executable: $(repo_relpath "$script"). Fix: chmod +x ai/scripts/*.sh"
  fi
}

ensure_history_file() {
  ensure_file_writable_if_missing "$HISTORY_FILE"
}

ensure_ai_context_files() {
  ensure_dir_writable "$ROOT/ai"
  ensure_dir_writable "$ROOT/ai/step_plans"
  ensure_dir_writable "$ROOT/ai/step_review_results"
  ensure_dir_writable "$ROOT/ai/tmp/orchestrator_logs"
  ensure_dir_writable "$ROOT/ai/prompts/plan_prompts"
  ensure_dir_writable "$ROOT/ai/prompts/impl_prompts"
  ensure_dir_writable "$ROOT/ai/prompts/review_prompts"

  ensure_file_writable_if_missing "$DECISIONS_FILE"
  ensure_file_writable_if_missing "$BLOCKER_LOG_FILE"
  ensure_file_writable_if_missing "$OPEN_QUESTIONS_FILE"
  ensure_file_writable_if_missing "$USER_REVIEW_FILE"

  ensure_history_file
}

ensure_orchestrator_prereqs() {
  ensure_executable_script "$ROOT/ai/scripts/ai_plan.sh"
  ensure_executable_script "$ROOT/ai/scripts/ai_implementation.sh"
  ensure_executable_script "$ROOT/ai/scripts/ai_review.sh"
  ensure_executable_script "$ROOT/ai/scripts/post_review.sh"
}

extract_step_and_title_from_plan() {
  local plan_path="$1"
  local header=""

  if [[ ! -f "$plan_path" ]]; then
    printf '||'
    return 0
  fi

  header="$(grep -m 1 -E '^# Step Plan:' "$plan_path" 2>/dev/null || true)"
  # Expected: "# Step Plan: 1.6c - Redemption after resolution (public redeem)"
  if [[ "$header" =~ ^#\ Step\ Plan:\ ([^[:space:]]+)\ -\ (.*)$ ]]; then
    printf '%s|%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  printf '||'
}

extract_token_usage_line() {
  local log_path="$1"
  if [[ ! -f "$log_path" ]]; then
    return 0
  fi

  # Codex output format is "Token usage: ...". When captured via `script`, the line may be prefixed
  # by ANSI escapes, so do not anchor to start-of-line and strip everything before the marker.
  local line
  line="$(grep -aE 'Token usage:' "$log_path" 2>/dev/null | tail -n 1 || true)"
  if [[ -z "$line" ]]; then
    return 0
  fi
  printf '%s' "${line#*Token usage:}" | tr -d '\r' | sed -E 's/^[[:space:]]+//'
}

append_token_usage_history() {
  local phase="$1"
  local step_plan="$2"
  local log_path="$3"

  local token_usage
  token_usage="$(extract_token_usage_line "$log_path")"
  if [[ -z "$token_usage" ]]; then
    return 0
  fi

  ensure_history_file

  local step_and_title step title
  step_and_title="$(extract_step_and_title_from_plan "$step_plan")"
  step="${step_and_title%%|*}"
  title="${step_and_title#*|}"

  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  {
    printf '## %s\n' "$ts"
    if [[ -n "$step" && -n "$title" ]]; then
      printf -- '- Step: %s - %s\n' "$step" "$title"
    elif [[ -n "$step" ]]; then
      printf -- '- Step: %s\n' "$step"
    else
      printf -- '- Step: (unknown)\n'
    fi
    printf -- '- Phase: %s\n' "$phase"
    printf -- '- Token usage: %s\n' "$token_usage"
    if [[ -n "$step_plan" ]]; then
      printf -- '- Step plan: %s\n' "${step_plan#"$ROOT"/}"
    fi
    printf '\n'
  } >>"$HISTORY_FILE"
}

run_with_output_log() {
  local phase="$1"
  shift

  local log_dir log_path
  log_dir="$ROOT/ai/tmp/orchestrator_logs"
  ensure_dir_writable "$log_dir"
  log_path="$log_dir/${PROJECT}-${phase}.latest.log"
  local err=""
  if ! err="$( ( : >"$log_path" ) 2>&1 )"; then
    die "Failed to write log file: $(repo_relpath "$log_path"): ${err:-unknown error}"
  fi

  local status=0
  set +e
  if [[ "${1:-}" == "codex" ]] && [[ -t 1 ]] && command -v script >/dev/null 2>&1; then
    # Preserve a TTY for interactive Codex while still capturing a log.
    script -q "$log_path" "$@"
    status=$?
  else
    "$@" 2>&1 | tee "$log_path"
    status="${PIPESTATUS[0]}"
  fi
  set -e

  LAST_RUN_LOG="$log_path"
  return "$status"
}

confirm_phase_if_interactive() {
  local phase="$1"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  case "$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]')" in
    implementation|review)
      ;;
    *)
      return 0
      ;;
  esac

  if [[ ! -t 0 ]]; then
    return 0
  fi

  local answer=""
  while true; do
    printf 'I am going to run next stage: %s\n' "$phase" >&2
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

load_model_config() {
  local phase="$1"
  local fields=()
  local field

  if [[ ! -f "$MODELS" ]]; then
    die "Models file not found: $(repo_relpath "$MODELS")"
  fi

  while IFS= read -r field; do
    fields+=("$field")
  done < <(
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
  )

  if [[ ${#fields[@]} -lt 2 || -z "${fields[0]}" || -z "${fields[1]}" ]]; then
    die "Invalid or missing '$phase' entry in $(repo_relpath "$MODELS") (expected: $phase | <command> | <model> | <args... optional>)"
  fi

  MODEL_CMD="${fields[0]}"
  MODEL_MODEL="${fields[1]}"
  MODEL_ARGS=()
  if [[ ${#fields[@]} -gt 2 ]]; then
    MODEL_ARGS=("${fields[@]:2}")
  fi
}

list_phases() {
  if [[ ! -f "$MODELS" ]]; then
    die "Models file not found: $(repo_relpath "$MODELS")"
  fi
  awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[[:space:]]*#/ { next }
    NF < 3 { next }
    {
      key = trim($1)
      if (key != "") { print key }
    }
  ' "$MODELS"
}

run_planning_phase() {
  load_model_config "planning"

  local planning_prompt_out
  planning_prompt_out="$ROOT/ai/prompts/plan_prompts/${PROJECT}.planning.prompt.txt"

  local plan_cmd=("$ROOT/ai/scripts/ai_plan.sh")
  if [[ ${#PLAN_ARGS[@]} -gt 0 ]]; then
    plan_cmd+=("${PLAN_ARGS[@]}")
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    local dry_planning_cmd=("$MODEL_CMD" -m "$MODEL_MODEL")
    if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
      dry_planning_cmd+=("${MODEL_ARGS[@]}")
    fi
    if [[ "$MODEL_CMD" == "codex" ]]; then
      dry_planning_cmd+=("<contents of $planning_prompt_out>")
    else
      dry_planning_cmd+=("run $planning_prompt_out")
    fi
    echo "$(shell_join "${plan_cmd[@]}") > $(printf '%q' "$planning_prompt_out") && $(shell_join "${dry_planning_cmd[@]}")"
    return 0
  fi

  mkdir -p "$(dirname "$planning_prompt_out")"
  "${plan_cmd[@]}" >"$planning_prompt_out"

  local prompt_arg
  prompt_arg="$(build_model_prompt_arg "$MODEL_CMD" "$planning_prompt_out")"

  local cmd=("$MODEL_CMD" -m "$MODEL_MODEL")
  if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
    cmd+=("${MODEL_ARGS[@]}")
  fi
  cmd+=("$prompt_arg")

  local status=0
  if run_with_output_log "planning" "${cmd[@]}"; then
    status=0
  else
    status=$?
  fi
  return "$status"
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
    local base step
    base="$(basename "$file")"
    step="${base#step-}"
    step="${step%.md}"
    [[ -z "$step" ]] && continue
    local key
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

build_model_prompt_arg() {
  local model_cmd="$1"
  local prompt_path="$2"

  if [[ "$model_cmd" == "codex" ]]; then
    if [[ ! -f "$prompt_path" ]]; then
      echo "Prompt file not found: $prompt_path" >&2
      exit 1
    fi
    cat "$prompt_path"
  else
    printf 'run %s' "$prompt_path"
  fi
}

extract_implementation_metadata() {
  local file="$1"
  local line value

  META_VERSION=""
  META_STEP_PLAN=""
  META_PROMPT_OUT=""
  META_IMPL_CMD=""
  META_IMPL_MODEL=""
  META_IMPL_ARGS=()

  while IFS= read -r line; do
    case "$line" in
      AI_RUN_COMMAND_VERSION:*)
        value="${line#AI_RUN_COMMAND_VERSION: }"
        META_VERSION="$value"
        ;;
      AI_STEP_PLAN:*)
        value="${line#AI_STEP_PLAN: }"
        META_STEP_PLAN="$value"
        ;;
      AI_PROMPT_OUT:*)
        value="${line#AI_PROMPT_OUT: }"
        META_PROMPT_OUT="$value"
        ;;
      AI_IMPL_RUN_CMD:*)
        value="${line#AI_IMPL_RUN_CMD: }"
        META_IMPL_CMD="$value"
        ;;
      AI_IMPL_MODEL:*)
        value="${line#AI_IMPL_MODEL: }"
        META_IMPL_MODEL="$value"
        ;;
      AI_IMPL_ARG:*)
        value="${line#AI_IMPL_ARG: }"
        META_IMPL_ARGS+=("$value")
        ;;
    esac
  done < "$file"

  if [[ "$META_VERSION" != "2" ]]; then
    return 1
  fi
  if [[ -n "$META_STEP_PLAN" ]]; then
    local meta_base current_base
    meta_base="$(basename "$META_STEP_PLAN")"
    current_base="$(basename "$file")"
    if [[ "$meta_base" != "$current_base" ]]; then
      return 1
    fi
  fi
  if [[ -n "$META_IMPL_CMD" && -n "$META_IMPL_MODEL" && -n "$META_PROMPT_OUT" ]]; then
    return 0
  fi
  return 1
}

run_implementation_phase() {
  local latest_plan
  latest_plan="$(get_preferred_step_plan)"

  local step prompt_out
  step="$(get_step_from_plan_path "$latest_plan")"
  if [[ -z "$step" ]]; then
    echo "Could not determine step from plan file: $latest_plan" >&2
    exit 1
  fi

  if extract_implementation_metadata "$latest_plan"; then
    prompt_out="$META_PROMPT_OUT"
    if [[ "$prompt_out" != /* ]]; then
      prompt_out="$ROOT/$prompt_out"
    fi
    MODEL_CMD="$META_IMPL_CMD"
    MODEL_MODEL="$META_IMPL_MODEL"
    MODEL_ARGS=("${META_IMPL_ARGS[@]}")
  else
    echo "Latest step plan is missing required implementation metadata (AI_RUN_COMMAND_VERSION: 2): $latest_plan" >&2
    echo "Regenerate the step plan with ai/scripts/ai_plan.sh before running implementation." >&2
    exit 1
  fi

  local prompt_cmd=("$ROOT/ai/scripts/ai_implementation.sh" --step-plan "$latest_plan" --out "$prompt_out")

  if [[ "$DRY_RUN" -eq 1 ]]; then
    local dry_impl_cmd=("$MODEL_CMD" -m "$MODEL_MODEL")
    if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
      dry_impl_cmd+=("${MODEL_ARGS[@]}")
    fi
    if [[ "$MODEL_CMD" == "codex" ]]; then
      dry_impl_cmd+=("<contents of $prompt_out>")
    else
      dry_impl_cmd+=("run $prompt_out")
    fi
    echo "$(shell_join "${prompt_cmd[@]}") && $(shell_join "${dry_impl_cmd[@]}")"
    return 0
  fi

  mkdir -p "$(dirname "$prompt_out")"
  "${prompt_cmd[@]}"
  local prompt_arg
  prompt_arg="$(build_model_prompt_arg "$MODEL_CMD" "$prompt_out")"
  local impl_cmd=("$MODEL_CMD" -m "$MODEL_MODEL")
  if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
    impl_cmd+=("${MODEL_ARGS[@]}")
  fi
  impl_cmd+=("$prompt_arg")
  local status=0
  if run_with_output_log "implementation" "${impl_cmd[@]}"; then
    status=0
  else
    status=$?
  fi
  return "$status"
}

run_review_phase() {
  load_model_config "review"

  local latest_plan step prompt_out
  latest_plan="$(get_preferred_step_plan)"
  step="$(get_step_from_plan_path "$latest_plan")"
  if [[ -z "$step" ]]; then
    echo "Could not determine step from plan file: $latest_plan" >&2
    exit 1
  fi

  prompt_out="$ROOT/ai/prompts/review_prompts/${PROJECT}-step-$step.review.prompt.txt"
  local prompt_cmd=("$ROOT/ai/scripts/ai_review.sh" --step-plan "$latest_plan" --out "$prompt_out")

  if [[ "$DRY_RUN" -eq 1 ]]; then
    local dry_review_cmd=("$MODEL_CMD" -m "$MODEL_MODEL")
    if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
      dry_review_cmd+=("${MODEL_ARGS[@]}")
    fi
    if [[ "$MODEL_CMD" == "codex" ]]; then
      dry_review_cmd+=("<contents of $prompt_out>")
    else
      dry_review_cmd+=("run $prompt_out")
    fi
    echo "$(shell_join "${prompt_cmd[@]}") && $(shell_join "${dry_review_cmd[@]}")"
    return 0
  fi

  mkdir -p "$(dirname "$prompt_out")"
  "${prompt_cmd[@]}"
  local prompt_arg
  prompt_arg="$(build_model_prompt_arg "$MODEL_CMD" "$prompt_out")"
  local review_cmd=("$MODEL_CMD" -m "$MODEL_MODEL")
  if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
    review_cmd+=("${MODEL_ARGS[@]}")
  fi
  review_cmd+=("$prompt_arg")
  local status=0
  if run_with_output_log "review" "${review_cmd[@]}"; then
    status=0
  else
    status=$?
  fi
  return "$status"
}

run_post_review_phase() {
  local latest_plan step
  latest_plan="$(get_preferred_step_plan)"
  step="$(get_step_from_plan_path "$latest_plan")"
  if [[ -z "$step" ]]; then
    echo "Could not determine step from plan file: $latest_plan" >&2
    exit 1
  fi

  local cmd=("$ROOT/ai/scripts/post_review.sh" --step "$step")
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "$(shell_join "${cmd[@]}")"
    return 0
  fi

  local status=0
  if run_with_output_log "post_review" "${cmd[@]}"; then
    status=0
  else
    status=$?
  fi
  return "$status"
}

run_phase() {
  local phase="$1"

  case "$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]')" in
    planning)
      run_planning_phase
      ;;
    implementation)
      run_implementation_phase
      ;;
    review)
      run_review_phase
      ;;
    post_review)
      run_post_review_phase
      ;;
    *)
      echo "Unsupported phase: $phase" >&2
      exit 1
      ;;
  esac
}

array_contains_ci() {
  local needle="$1"
  shift

  local needle_lower value_lower value
  needle_lower="$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')"
  for value in "$@"; do
    value_lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
    if [[ "$value_lower" == "$needle_lower" ]]; then
      return 0
    fi
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      if [[ -z "${2:-}" ]]; then
        echo "--phase requires a value." >&2
        usage >&2
        exit 1
      fi
      REQUESTED_PHASES+=("$2")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      if [[ $# -gt 0 ]]; then
        PLAN_ARGS+=("$@")
      fi
      break
      ;;
    *)
      PLAN_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#REQUESTED_PHASES[@]} -eq 0 ]]; then
  while IFS= read -r phase; do
    [[ -n "$phase" ]] && REQUESTED_PHASES+=("$phase")
  done < <(list_phases)
  if ! array_contains_ci "post_review" "${REQUESTED_PHASES[@]+"${REQUESTED_PHASES[@]}"}"; then
    REQUESTED_PHASES+=("post_review")
  fi
fi

if [[ ${#REQUESTED_PHASES[@]} -eq 0 ]]; then
  die "No phases found in $(repo_relpath "$MODELS")"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  ensure_orchestrator_prereqs
  ensure_ai_context_files
fi

for phase in "${REQUESTED_PHASES[@]+"${REQUESTED_PHASES[@]}"}"; do
  if confirm_phase_if_interactive "$phase"; then
    run_phase "$phase"
    if [[ "$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]')" == "review" ]]; then
      RAN_REVIEW=1
    fi
    if [[ "$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]')" == "post_review" ]]; then
      RAN_POST_REVIEW=1
    fi
  else
    echo "Skipping stage: $phase" >&2
  fi
done

if [[ "$DRY_RUN" -eq 0 && "$RAN_REVIEW" -eq 1 ]]; then
  latest_plan="$(get_preferred_step_plan || true)"
  step="$(get_step_from_plan_path "$latest_plan" 2>/dev/null || true)"
  if [[ -n "$step" ]]; then
    echo "Review phase completed for step $step." >&2
    echo "If tests already passed and you approve the result, the next manual step is to commit on step-$step-review." >&2
  else
    echo "Review phase completed." >&2
    echo "If tests already passed and you approve the result, the next manual step is to commit on the review branch." >&2
  fi
  echo "Logs: ai/tmp/orchestrator_logs (overwritten each run; safe to delete)." >&2
  if [[ "$RAN_POST_REVIEW" -eq 1 ]]; then
    echo "History: ai/history.md (single consolidated step record updated)." >&2
  else
    echo "History: ai/history.md (no update; run post_review to consolidate step metrics)." >&2
  fi
fi
