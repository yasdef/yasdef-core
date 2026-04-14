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
IMPLEMENTATION_PLAN_PRIMARY="$ROOT/overmind/implementation_plan.md"
RUNTIME_REQUIREMENTS_PATH="$ROOT/overmind/reqirements_ears.md"
PROJECT_BINDING_FILE="$ROOT/ai/project_overmind.yaml"
FEATURE_SYNC_FILE="$ROOT/ai/feature_sync.yaml"
RUNTIME_BRANCH="overmind"

# Run all child commands from repository root for consistent sandbox/workspace resolution.
cd "$ROOT"

DRY_RUN=0
DEBUG_MODE=0
FEATURE_RICH_DESIGN_PLANNING=0
REQUESTED_PHASES=()
PLAN_ARGS=()
RAN_AI_AUDIT=0
RAN_POST_REVIEW=0
RESUME_STEP=""
RESUME_MODE=0
RESUME_START_PHASE=""
RESUME_ALL_DONE=0
RESUME_BLOCKED=0
RESUME_BLOCK_REASON=""
PHASE_EVAL_PHASES=()
PHASE_EVAL_STATES=()
PHASE_EVAL_DETAILS=()
IMPLEMENTATION_PLAN_FILE="$IMPLEMENTATION_PLAN_PRIMARY"
CANONICAL_PHASES=(design planning implementation user_review ai_audit post_review)

BINDING_OVERMIND_SOURCE_PATH=""
BINDING_PROJECT_ID=""
BINDING_WORKER_UUID=""
BINDING_WORKER_CLASS=""
BINDING_WORKER_STATUS=""
BOUND_PROJECT_PATH=""
BOUND_FEATURES_ROOT=""

SELECTED_FEATURE_ID=""
SELECTED_FEATURE_PATH=""
SELECTED_SOURCE_PLAN_PATH=""
SELECTED_SOURCE_EARS_PATH=""
SELECTED_STEP=""
SELECTED_SELECTION_MODE=""
SELECTED_REQUESTED_STEP=""

FEATURE_CONTEXT_READY=0
FEATURE_CONTEXT_REQUESTED_STEP=""
FEATURE_CONTEXT_RESUME_MODE=0

usage() {
  cat <<'EOF'
Usage: ai/scripts/orchestrator.sh [--resume <step>] [--debug] [--feature-rich-design-planning] [--dry-run] [--help] [-- <phase-script args>]

Default behavior:
  - Runs all phases in ai/setup/models.md, in order, then runs post_review.
  - design runs ai/scripts/ai_design.sh and generates/updates a feature-design artifact.
  - planning runs ai/scripts/ai_plan.sh using the planning model entry.
  - implementation runs ai/scripts/ai_implementation.sh for the latest step plan, then runs the implementation model command.
  - user_review runs ai/scripts/ai_user_review.sh for the latest step plan, validates entry gate markers, then runs the user_review model command.
  - ai_audit runs ai/scripts/ai_audit.sh for the latest step plan (post-step audit prompt), then runs the ai_audit model command.
  - post_review runs ai/scripts/post_review.sh for the latest step plan and appends post-review metrics to ai/history.md.
  - --resume <step> evaluates phase completion for the step and runs from the first unfinished phase through post_review.
  - --debug enables per-step/per-phase artifact files for logs and prompts.
  - --feature-rich-design-planning enables an opt-in richer contract for design/planning prompts only.
  - --feature-rich-design-planning does not change implementation/user_review/ai_audit/post_review behavior.
  - Without --debug, logs/prompts use latest-per-phase filenames and are overwritten each run.
  - When running interactively, asks for confirmation before planning/implementation/user_review/ai_audit.
  - If interactive confirmation is denied for any phase, orchestration stops immediately and does not prompt downstream phases in that run.
  - Writes per-phase logs to ai/logs/<project>-<phase>-latest-log (or step-specific names with --debug).
  - post_review consolidates per-step token usage and metrics into ai/history.md.

Examples:
  ai/scripts/orchestrator.sh
  ai/scripts/orchestrator.sh -- --step 1.3
  ai/scripts/orchestrator.sh -- --step 1.3 --out ai/tmp/step-1.3.md
  ai/scripts/orchestrator.sh --resume 1.3
  ai/scripts/orchestrator.sh --resume 1.3 --dry-run
  ai/scripts/orchestrator.sh --feature-rich-design-planning -- --step 1.3
  ai/scripts/orchestrator.sh --debug -- --step 1.3
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
  ensure_dir_writable "$ROOT/ai/step_designs"
  ensure_dir_writable "$ROOT/ai/step_plans"
  ensure_dir_writable "$ROOT/ai/step_review_results"
  ensure_dir_writable "$ROOT/ai/logs"
  ensure_dir_writable "$ROOT/ai/prompts/design_prompts"
  ensure_dir_writable "$ROOT/ai/prompts/plan_prompts"
  ensure_dir_writable "$ROOT/ai/prompts/impl_prompts"
  ensure_dir_writable "$ROOT/ai/prompts/user_review_prompts"
  ensure_dir_writable "$ROOT/ai/prompts/ai_audit_prompts"

  ensure_file_writable_if_missing "$DECISIONS_FILE"
  ensure_file_writable_if_missing "$BLOCKER_LOG_FILE"
  ensure_file_writable_if_missing "$OPEN_QUESTIONS_FILE"
  ensure_file_writable_if_missing "$USER_REVIEW_FILE"

  ensure_history_file
}

ensure_orchestrator_prereqs() {
  ensure_executable_script "$ROOT/ai/scripts/ai_design.sh"
  ensure_executable_script "$ROOT/ai/scripts/ai_plan.sh"
  ensure_executable_script "$ROOT/ai/scripts/ai_implementation.sh"
  ensure_executable_script "$ROOT/ai/scripts/ai_user_review.sh"
  ensure_executable_script "$ROOT/ai/scripts/ai_audit.sh"
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

normalize_phase_token() {
  local phase="$1"
  printf '%s' "$phase" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

canonicalize_phase_name() {
  local phase_raw="${1:-}"
  local phase
  phase="$(printf '%s' "$phase_raw" | tr '[:upper:]' '[:lower:]')"
  case "$phase" in
    ai-audit)
      printf 'ai_audit'
      ;;
    user-review)
      printf 'user_review'
      ;;
    *)
      printf '%s' "$phase"
      ;;
  esac
}

normalize_step_token() {
  local step="${1:-}"
  if [[ -z "$step" ]]; then
    printf 'unknown-step'
    return 0
  fi
  printf '%s' "$step" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

resolve_log_path() {
  local phase="$1"
  local step="${2:-}"
  local phase_token step_token
  phase_token="$(normalize_phase_token "$phase")"
  step_token="$(normalize_step_token "$step")"

  if [[ "$DEBUG_MODE" -eq 1 ]]; then
    printf '%s/ai/logs/%s-%s-%s-log' "$ROOT" "$PROJECT" "$phase_token" "$step_token"
  else
    printf '%s/ai/logs/%s-%s-latest-log' "$ROOT" "$PROJECT" "$phase_token"
  fi
}

resolve_prompt_output_path() {
  local phase="$1"
  local step="${2:-}"
  local base_dir=""
  local file_name=""

  phase="$(canonicalize_phase_name "$phase")"

  case "$phase" in
    design)
      base_dir="$ROOT/ai/prompts/design_prompts"
      if [[ "$DEBUG_MODE" -eq 1 ]]; then
        if [[ -n "$step" ]]; then
          file_name="${PROJECT}-step-$step.design.prompt.txt"
        else
          file_name="${PROJECT}.design.prompt.txt"
        fi
      else
        file_name="${PROJECT}-latest-design-prompt.txt"
      fi
      ;;
    planning)
      base_dir="$ROOT/ai/prompts/plan_prompts"
      if [[ "$DEBUG_MODE" -eq 1 ]]; then
        if [[ -n "$step" ]]; then
          file_name="${PROJECT}-step-$step.planning.prompt.txt"
        else
          file_name="${PROJECT}.planning.prompt.txt"
        fi
      else
        file_name="${PROJECT}-latest-planning-prompt.txt"
      fi
      ;;
    implementation)
      base_dir="$ROOT/ai/prompts/impl_prompts"
      if [[ "$DEBUG_MODE" -eq 1 ]]; then
        file_name="${PROJECT}-step-$step.prompt.txt"
      else
        file_name="${PROJECT}-latest-implementation-prompt.txt"
      fi
      ;;
    user_review)
      base_dir="$ROOT/ai/prompts/user_review_prompts"
      if [[ "$DEBUG_MODE" -eq 1 ]]; then
        file_name="${PROJECT}-step-$step.user-review.prompt.txt"
      else
        file_name="${PROJECT}-latest-user-review-prompt.txt"
      fi
      ;;
    ai_audit)
      base_dir="$ROOT/ai/prompts/ai_audit_prompts"
      if [[ "$DEBUG_MODE" -eq 1 ]]; then
        file_name="${PROJECT}-step-$step.ai-audit.prompt.txt"
      else
        file_name="${PROJECT}-latest-ai-audit-prompt.txt"
      fi
      ;;
    *)
      die "Unsupported phase for prompt output path: $phase"
      ;;
  esac

  printf '%s/%s' "$base_dir" "$file_name"
}

run_with_output_log() {
  local phase="$1"
  local step="${2:-}"
  shift 2

  local log_dir log_path
  log_dir="$ROOT/ai/logs"
  ensure_dir_writable "$log_dir"
  log_path="$(resolve_log_path "$phase" "$step")"
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
  local phase_key=""

  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  phase_key="$(canonicalize_phase_name "$phase")"

  if ! phase_requires_interactive_confirmation "$phase_key"; then
    return 0
  fi

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

phase_requires_interactive_confirmation() {
  local phase="$1"
  case "$phase" in
    planning|implementation|user_review|ai_audit)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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
    function canonical(s, key_l) {
      key_l = tolower(s)
      if (key_l == "ai-audit") return "ai_audit"
      if (key_l == "user-review") return "user_review"
      return s
    }
    /^[[:space:]]*#/ { next }
    NF < 3 { next }
    {
      key = trim($1)
      if (key != "") {
        key = canonical(key)
        key_l = tolower(key)
        if (!(key_l in seen)) {
          seen[key_l] = 1
          print key
        }
      }
    }
  ' "$MODELS"
}

run_planning_phase() {
  load_model_config "planning"

  local step planning_prompt_out explicit_step
  step="$(resolve_step_for_phase_from_args "planning" "${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}")" || return 1
  explicit_step="$(find_explicit_step_arg "${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}" || true)"
  planning_prompt_out="$(resolve_prompt_output_path "planning" "$step")"

  local plan_cmd=("$ROOT/ai/scripts/ai_plan.sh")
  if [[ ${#PLAN_ARGS[@]} -gt 0 ]]; then
    plan_cmd+=("${PLAN_ARGS[@]}")
  fi
  if [[ -z "$explicit_step" ]]; then
    echo "orchestrator: resolved routed step '$step' for planning; injecting --step into ai_plan.sh." >&2
    plan_cmd+=(--step "$step")
  fi
  if [[ "$FEATURE_RICH_DESIGN_PLANNING" -eq 1 ]]; then
    plan_cmd+=(--feature-rich-design-planning)
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
    echo "dry-run prompt: $(repo_relpath "$planning_prompt_out")"
    echo "dry-run log: $(repo_relpath "$(resolve_log_path "planning" "$step")")"
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
  if run_with_output_log "planning" "$step" "${cmd[@]}"; then
    status=0
  else
    status=$?
  fi
  return "$status"
}

run_design_phase() {
  load_model_config "design"

  local step design_prompt_out explicit_step
  step="$(resolve_step_for_phase_from_args "design" "${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}")" || return 1
  explicit_step="$(find_explicit_step_arg "${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}" || true)"
  design_prompt_out="$(resolve_prompt_output_path "design" "$step")"

  local design_cmd=("$ROOT/ai/scripts/ai_design.sh")
  if [[ ${#PLAN_ARGS[@]} -gt 0 ]]; then
    design_cmd+=("${PLAN_ARGS[@]}")
  fi
  if [[ -z "$explicit_step" ]]; then
    echo "orchestrator: resolved routed step '$step' for design; injecting --step into ai_design.sh." >&2
    design_cmd+=(--step "$step")
  fi
  if [[ "$FEATURE_RICH_DESIGN_PLANNING" -eq 1 ]]; then
    design_cmd+=(--feature-rich-design-planning)
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    local dry_design_cmd=("$MODEL_CMD" -m "$MODEL_MODEL")
    if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
      dry_design_cmd+=("${MODEL_ARGS[@]}")
    fi
    if [[ "$MODEL_CMD" == "codex" ]]; then
      dry_design_cmd+=("<contents of $design_prompt_out>")
    else
      dry_design_cmd+=("run $design_prompt_out")
    fi
    echo "dry-run prompt: $(repo_relpath "$design_prompt_out")"
    echo "dry-run log: $(repo_relpath "$(resolve_log_path "design" "$step")")"
    echo "$(shell_join "${design_cmd[@]}") > $(printf '%q' "$design_prompt_out") && $(shell_join "${dry_design_cmd[@]}")"
    return 0
  fi

  mkdir -p "$(dirname "$design_prompt_out")"
  "${design_cmd[@]}" >"$design_prompt_out"

  local prompt_arg
  prompt_arg="$(build_model_prompt_arg "$MODEL_CMD" "$design_prompt_out")"

  local cmd=("$MODEL_CMD" -m "$MODEL_MODEL")
  if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
    cmd+=("${MODEL_ARGS[@]}")
  fi
  cmd+=("$prompt_arg")

  local status=0
  if run_with_output_log "design" "$step" "${cmd[@]}"; then
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

try_get_step_from_plan_path() {
  local file="$1"
  local base
  base="$(basename "$file")"
  if [[ "$base" =~ ^step-(.+)\.md$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

get_step_from_design_path() {
  local file="$1"
  local base
  base="$(basename "$file")"
  if [[ "$base" =~ ^step-(.+)-design\.md$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

is_valid_uuid() {
  local value="$1"
  [[ "$value" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

trim_whitespace() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

yaml_quote_single() {
  printf '%s' "$1" | sed "s/'/''/g"
}

yaml_get_scalar() {
  local file="$1"
  local key="$2"
  local raw=""
  local value=""

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  raw="$(grep -E "^[[:space:]]*$key:[[:space:]]*" "$file" | head -n 1 || true)"
  if [[ -z "$raw" ]]; then
    return 1
  fi

  value="${raw#*:}"
  value="$(trim_whitespace "$value")"
  if [[ -z "$value" ]]; then
    return 1
  fi

  if [[ "$value" == "'"* && "$value" == *"'" ]]; then
    value="${value:1:${#value}-2}"
    value="${value//\'\'/\'}"
  elif [[ "$value" == "\""* && "$value" == *"\"" ]]; then
    value="${value:1:${#value}-2}"
  fi

  printf '%s' "$value"
}

load_project_binding() {
  if [[ -n "$BINDING_WORKER_UUID" ]]; then
    return 0
  fi

  if [[ ! -f "$PROJECT_BINDING_FILE" ]]; then
    die "Required binding file is missing: $(repo_relpath "$PROJECT_BINDING_FILE"). Run ai/scripts/init_worker.sh first."
  fi

  BINDING_OVERMIND_SOURCE_PATH="$(yaml_get_scalar "$PROJECT_BINDING_FILE" "overmind_source_path" || true)"
  BINDING_PROJECT_ID="$(yaml_get_scalar "$PROJECT_BINDING_FILE" "project_id" || true)"
  BINDING_WORKER_UUID="$(yaml_get_scalar "$PROJECT_BINDING_FILE" "worker_uuid" || true)"
  BINDING_WORKER_CLASS="$(yaml_get_scalar "$PROJECT_BINDING_FILE" "class" || true)"
  BINDING_WORKER_STATUS="$(yaml_get_scalar "$PROJECT_BINDING_FILE" "status" || true)"

  if [[ -z "$BINDING_OVERMIND_SOURCE_PATH" ]]; then
    die "Binding file is invalid: missing overmind_source_path in $(repo_relpath "$PROJECT_BINDING_FILE")."
  fi
  if [[ -z "$BINDING_PROJECT_ID" ]]; then
    die "Binding file is invalid: missing project_id in $(repo_relpath "$PROJECT_BINDING_FILE")."
  fi
  if [[ -z "$BINDING_WORKER_UUID" ]]; then
    die "Binding file is invalid: missing worker_uuid in $(repo_relpath "$PROJECT_BINDING_FILE")."
  fi
  if ! is_valid_uuid "$BINDING_WORKER_UUID"; then
    die "Binding file is invalid: worker_uuid is not canonical UUID in $(repo_relpath "$PROJECT_BINDING_FILE")."
  fi
  if [[ ! -d "$BINDING_OVERMIND_SOURCE_PATH" ]]; then
    die "Bound overmind source path does not exist: $BINDING_OVERMIND_SOURCE_PATH"
  fi

  if [[ -d "$BINDING_OVERMIND_SOURCE_PATH/projects/$BINDING_PROJECT_ID" ]]; then
    BOUND_PROJECT_PATH="$BINDING_OVERMIND_SOURCE_PATH/projects/$BINDING_PROJECT_ID"
  elif [[ -d "$BINDING_OVERMIND_SOURCE_PATH/$BINDING_PROJECT_ID" ]]; then
    BOUND_PROJECT_PATH="$BINDING_OVERMIND_SOURCE_PATH/$BINDING_PROJECT_ID"
  else
    die "Bound project path is missing for project_id '$BINDING_PROJECT_ID' under overmind source '$BINDING_OVERMIND_SOURCE_PATH'."
  fi
  BOUND_FEATURES_ROOT="$BOUND_PROJECT_PATH"
}

ensure_runtime_branch_checked_out() {
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "Feature routing requires a git repository."
  fi

  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$RUNTIME_BRANCH"; then
    if [[ "$(get_current_branch_name)" != "$RUNTIME_BRANCH" ]]; then
      if ! git -C "$ROOT" checkout "$RUNTIME_BRANCH" >/dev/null 2>&1; then
        die "Failed to checkout runtime branch '$RUNTIME_BRANCH'."
      fi
    fi
  else
    if ! git -C "$ROOT" checkout -b "$RUNTIME_BRANCH" >/dev/null 2>&1; then
      die "Failed to create runtime branch '$RUNTIME_BRANCH'."
    fi
  fi
}

analyze_feature_plan_for_worker() {
  local plan_path="$1"
  local worker_uuid="$2"
  local requested_step="${3:-}"

  awk -v target_uuid="$worker_uuid" -v requested_step="$requested_step" '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    BEGIN {
      step_num = ""
      assigned_uuid = ""
      assigned_any = 0
      requested_match = 0
      first_unchecked = ""
    }
    /^### Step / {
      line = $0
      sub(/^### Step /, "", line)
      split(line, parts, " ")
      step_num = parts[1]
      assigned_uuid = ""
      next
    }
    /^#### Assigned:[[:space:]]*/ {
      line = $0
      sub(/^#### Assigned:[[:space:]]*/, "", line)
      assigned_uuid = trim(line)
      if (assigned_uuid == target_uuid) {
        assigned_any = 1
        if (requested_step != "" && step_num == requested_step) {
          requested_match = 1
        }
      }
      next
    }
    /^- \[ \]/ {
      if (step_num != "" && assigned_uuid == target_uuid && first_unchecked == "") {
        first_unchecked = step_num
      }
      next
    }
    END {
      printf "%d|%d|%s", assigned_any, requested_match, first_unchecked
    }
  ' "$plan_path"
}

plan_has_assigned_step_for_worker() {
  local plan_path="$1"
  local worker_uuid="$2"
  local step="$3"

  awk -v target_uuid="$worker_uuid" -v step="$step" '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    /^### Step / {
      line = $0
      sub(/^### Step /, "", line)
      split(line, parts, " ")
      step_num = parts[1]
      assigned_uuid = ""
      next
    }
    /^#### Assigned:[[:space:]]*/ {
      line = $0
      sub(/^#### Assigned:[[:space:]]*/, "", line)
      assigned_uuid = trim(line)
      if (step_num == step && assigned_uuid == target_uuid) {
        found = 1
        exit 0
      }
      next
    }
    END { exit(found ? 0 : 1) }
  ' "$plan_path"
}

prompt_for_feature_selection_index() {
  local feature_ids=("$@")
  local selected=""

  if [[ ! -t 0 ]]; then
    die "Multiple candidate features were found for worker '$BINDING_WORKER_UUID'. Run in an interactive terminal to choose a feature."
  fi

  echo "Multiple candidate features found under project '$BINDING_PROJECT_ID' for worker '$BINDING_WORKER_UUID':" >&2
  local i=0
  while [[ $i -lt ${#feature_ids[@]} ]]; do
    printf '  %d) %s\n' "$((i + 1))" "${feature_ids[$i]}" >&2
    i=$((i + 1))
  done

  while true; do
    printf 'Select feature number: ' >&2
    IFS= read -r selected || selected=""
    selected="$(trim_whitespace "$selected")"
    if [[ "$selected" =~ ^[0-9]+$ ]] && [[ "$selected" -ge 1 ]] && [[ "$selected" -le "${#feature_ids[@]}" ]]; then
      printf '%s' "$((selected - 1))"
      return 0
    fi
    echo "Invalid selection. Enter a number between 1 and ${#feature_ids[@]}." >&2
  done
}

write_feature_sync_metadata() {
  local selected_step="$1"
  local tmp_path="${FEATURE_SYNC_FILE}.tmp"

  ensure_dir_writable "$(dirname "$FEATURE_SYNC_FILE")"
  {
    printf "project_id: '%s'\n" "$(yaml_quote_single "$BINDING_PROJECT_ID")"
    printf "feature_id: '%s'\n" "$(yaml_quote_single "$SELECTED_FEATURE_ID")"
    printf "worker_uuid: '%s'\n" "$(yaml_quote_single "$BINDING_WORKER_UUID")"
    printf "overmind_source_path: '%s'\n" "$(yaml_quote_single "$BINDING_OVERMIND_SOURCE_PATH")"
    printf "bound_project_path: '%s'\n" "$(yaml_quote_single "$BOUND_PROJECT_PATH")"
    printf "source_feature_path: '%s'\n" "$(yaml_quote_single "$SELECTED_FEATURE_PATH")"
    printf "source_implementation_plan_path: '%s'\n" "$(yaml_quote_single "$SELECTED_SOURCE_PLAN_PATH")"
    printf "source_requirements_ears_path: '%s'\n" "$(yaml_quote_single "$SELECTED_SOURCE_EARS_PATH")"
    printf "runtime_implementation_plan_path: '%s'\n" "$(yaml_quote_single "$IMPLEMENTATION_PLAN_PRIMARY")"
    printf "runtime_requirements_ears_path: '%s'\n" "$(yaml_quote_single "$RUNTIME_REQUIREMENTS_PATH")"
    printf "runtime_branch: '%s'\n" "$(yaml_quote_single "$RUNTIME_BRANCH")"
    printf "selection_mode: '%s'\n" "$(yaml_quote_single "$SELECTED_SELECTION_MODE")"
    printf "requested_step: '%s'\n" "$(yaml_quote_single "$SELECTED_REQUESTED_STEP")"
    printf "selected_step: '%s'\n" "$(yaml_quote_single "$selected_step")"
  } >"$tmp_path"
  mv "$tmp_path" "$FEATURE_SYNC_FILE"
}

try_reuse_feature_sync_for_resume() {
  local requested_step="$1"
  local feature_project_id=""
  local feature_id=""
  local feature_worker_uuid=""
  local source_plan=""
  local source_ears=""
  local runtime_branch=""
  local selection_mode=""

  if [[ ! -f "$FEATURE_SYNC_FILE" ]]; then
    return 1
  fi

  feature_project_id="$(yaml_get_scalar "$FEATURE_SYNC_FILE" "project_id" || true)"
  feature_id="$(yaml_get_scalar "$FEATURE_SYNC_FILE" "feature_id" || true)"
  feature_worker_uuid="$(yaml_get_scalar "$FEATURE_SYNC_FILE" "worker_uuid" || true)"
  source_plan="$(yaml_get_scalar "$FEATURE_SYNC_FILE" "source_implementation_plan_path" || true)"
  source_ears="$(yaml_get_scalar "$FEATURE_SYNC_FILE" "source_requirements_ears_path" || true)"
  runtime_branch="$(yaml_get_scalar "$FEATURE_SYNC_FILE" "runtime_branch" || true)"
  selection_mode="$(yaml_get_scalar "$FEATURE_SYNC_FILE" "selection_mode" || true)"

  if [[ "$feature_project_id" != "$BINDING_PROJECT_ID" ]]; then
    return 1
  fi
  if [[ "$feature_worker_uuid" != "$BINDING_WORKER_UUID" ]]; then
    return 1
  fi
  if [[ "$runtime_branch" != "$RUNTIME_BRANCH" ]]; then
    return 1
  fi
  if [[ -z "$feature_id" || -z "$source_plan" || -z "$source_ears" ]]; then
    return 1
  fi
  if [[ ! -f "$source_plan" || ! -f "$source_ears" ]]; then
    return 1
  fi
  if ! plan_has_assigned_step_for_worker "$source_plan" "$BINDING_WORKER_UUID" "$requested_step"; then
    return 1
  fi

  SELECTED_FEATURE_ID="$feature_id"
  SELECTED_FEATURE_PATH="$(dirname "$source_plan")"
  SELECTED_SOURCE_PLAN_PATH="$source_plan"
  SELECTED_SOURCE_EARS_PATH="$source_ears"
  SELECTED_SELECTION_MODE="resume_reuse"
  if [[ -n "$selection_mode" ]]; then
    SELECTED_SELECTION_MODE="resume_reuse:$selection_mode"
  fi
  SELECTED_REQUESTED_STEP="$requested_step"
  SELECTED_STEP="$requested_step"
  return 0
}

mirror_selected_feature_to_runtime() {
  local selected_step="$1"

  if [[ ! -f "$SELECTED_SOURCE_PLAN_PATH" ]]; then
    die "Selected feature plan is missing: $SELECTED_SOURCE_PLAN_PATH"
  fi
  if [[ ! -f "$SELECTED_SOURCE_EARS_PATH" ]]; then
    die "Selected feature requirements_ears.md is missing: $SELECTED_SOURCE_EARS_PATH"
  fi
  if ! grep -q '[^[:space:]]' "$SELECTED_SOURCE_EARS_PATH"; then
    die "Selected feature requirements_ears.md is unusable (empty): $SELECTED_SOURCE_EARS_PATH"
  fi

  ensure_dir_writable "$ROOT/overmind"
  cp "$SELECTED_SOURCE_PLAN_PATH" "$IMPLEMENTATION_PLAN_PRIMARY"
  cp "$SELECTED_SOURCE_EARS_PATH" "$RUNTIME_REQUIREMENTS_PATH"
  IMPLEMENTATION_PLAN_FILE="$IMPLEMENTATION_PLAN_PRIMARY"

  write_feature_sync_metadata "$selected_step"
}

ensure_feature_runtime_context() {
  local requested_step="${1:-}"
  local resume_mode="${2:-0}"

  if [[ "$FEATURE_CONTEXT_READY" -eq 1 ]] && [[ "$FEATURE_CONTEXT_REQUESTED_STEP" == "$requested_step" ]] && [[ "$FEATURE_CONTEXT_RESUME_MODE" -eq "$resume_mode" ]]; then
    return 0
  fi

  load_project_binding
  ensure_runtime_branch_checked_out

  local -a candidate_feature_ids=()
  local -a candidate_feature_paths=()
  local -a candidate_plan_paths=()
  local -a candidate_ears_paths=()
  local -a candidate_first_steps=()
  local features_dir=""
  local assigned_feature_count=0
  local assigned_with_unchecked_count=0

  if [[ "$resume_mode" -eq 1 && -n "$requested_step" ]]; then
    if try_reuse_feature_sync_for_resume "$requested_step"; then
      mirror_selected_feature_to_runtime "$requested_step"
      FEATURE_CONTEXT_READY=1
      FEATURE_CONTEXT_REQUESTED_STEP="$requested_step"
      FEATURE_CONTEXT_RESUME_MODE="$resume_mode"
      echo "orchestrator: selected feature '$SELECTED_FEATURE_ID' (mode=$SELECTED_SELECTION_MODE, project=$BINDING_PROJECT_ID, step=$SELECTED_STEP)." >&2
      return 0
    fi
  fi

  while IFS= read -r features_dir; do
    [[ -n "$features_dir" ]] || continue
    local feature_id=""
    local plan_path=""
    local ears_path=""
    local analysis=""
    local assigned_any=0
    local requested_match=0
    local first_unchecked=""

    feature_id="$(basename "$features_dir")"
    plan_path="$features_dir/implementation_plan.md"
    ears_path="$features_dir/requirements_ears.md"
    [[ -f "$plan_path" ]] || continue

    analysis="$(analyze_feature_plan_for_worker "$plan_path" "$BINDING_WORKER_UUID" "$requested_step")"
    IFS='|' read -r assigned_any requested_match first_unchecked <<<"$analysis"

    if [[ "$assigned_any" -eq 1 ]]; then
      assigned_feature_count=$((assigned_feature_count + 1))
      if [[ -n "$first_unchecked" ]]; then
        assigned_with_unchecked_count=$((assigned_with_unchecked_count + 1))
      fi
    fi

    if [[ -n "$requested_step" ]]; then
      if [[ "$requested_match" -eq 1 ]]; then
        candidate_feature_ids+=("$feature_id")
        candidate_feature_paths+=("$features_dir")
        candidate_plan_paths+=("$plan_path")
        candidate_ears_paths+=("$ears_path")
        candidate_first_steps+=("$requested_step")
      fi
    else
      if [[ -n "$first_unchecked" ]]; then
        candidate_feature_ids+=("$feature_id")
        candidate_feature_paths+=("$features_dir")
        candidate_plan_paths+=("$plan_path")
        candidate_ears_paths+=("$ears_path")
        candidate_first_steps+=("$first_unchecked")
      fi
    fi
  done < <(find "$BOUND_FEATURES_ROOT" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)

  if [[ "$assigned_feature_count" -eq 0 ]]; then
    die "No feature under bound project '$BINDING_PROJECT_ID' contains assigned steps for worker UUID '$BINDING_WORKER_UUID'."
  fi

  if [[ ${#candidate_feature_ids[@]} -eq 0 ]]; then
    if [[ -n "$requested_step" ]]; then
      die "No candidate features under project '$BINDING_PROJECT_ID' contain requested step '$requested_step' assigned to worker '$BINDING_WORKER_UUID'."
    fi
    if [[ "$assigned_with_unchecked_count" -eq 0 ]]; then
      die "Assigned steps exist for worker '$BINDING_WORKER_UUID' but all assigned checklist bullets are complete under project '$BINDING_PROJECT_ID'."
    fi
    die "No candidate features remain after assignment filtering for worker '$BINDING_WORKER_UUID' under project '$BINDING_PROJECT_ID'."
  fi

  local selected_index=0
  if [[ ${#candidate_feature_ids[@]} -eq 1 ]]; then
    selected_index=0
    SELECTED_SELECTION_MODE="auto_single"
  else
    selected_index="$(prompt_for_feature_selection_index "${candidate_feature_ids[@]}")"
    SELECTED_SELECTION_MODE="user_prompt"
  fi

  SELECTED_FEATURE_ID="${candidate_feature_ids[$selected_index]}"
  SELECTED_FEATURE_PATH="${candidate_feature_paths[$selected_index]}"
  SELECTED_SOURCE_PLAN_PATH="${candidate_plan_paths[$selected_index]}"
  SELECTED_SOURCE_EARS_PATH="${candidate_ears_paths[$selected_index]}"
  SELECTED_REQUESTED_STEP="$requested_step"
  SELECTED_STEP="${candidate_first_steps[$selected_index]}"

  if [[ -z "$SELECTED_STEP" ]]; then
    die "Selected feature '$SELECTED_FEATURE_ID' has no runnable step for worker '$BINDING_WORKER_UUID'."
  fi

  mirror_selected_feature_to_runtime "$SELECTED_STEP"
  FEATURE_CONTEXT_READY=1
  FEATURE_CONTEXT_REQUESTED_STEP="$requested_step"
  FEATURE_CONTEXT_RESUME_MODE="$resume_mode"
  echo "orchestrator: selected feature '$SELECTED_FEATURE_ID' (mode=$SELECTED_SELECTION_MODE, project=$BINDING_PROJECT_ID, step=$SELECTED_STEP)." >&2
}

get_first_unchecked_step() {
  ensure_feature_runtime_context "" "${RESUME_MODE:-0}"
  if [[ -z "$SELECTED_STEP" ]]; then
    die "No selected step is available for worker '$BINDING_WORKER_UUID'."
  fi
  printf '%s' "$SELECTED_STEP"
}

resolve_step_for_phase_from_args() {
  local phase="$1"
  shift || true
  local args=("$@")
  local i=0

  while [[ $i -lt ${#args[@]} ]]; do
    local arg="${args[$i]}"
    case "$arg" in
      --step)
        if [[ $((i + 1)) -lt ${#args[@]} ]]; then
          printf '%s' "${args[$((i + 1))]}"
          return 0
        fi
        ;;
      --step=*)
        printf '%s' "${arg#--step=}"
        return 0
        ;;
      --design-out)
        if [[ $((i + 1)) -lt ${#args[@]} ]]; then
          local step=""
          step="$(get_step_from_design_path "${args[$((i + 1))]}" || true)"
          if [[ -n "$step" ]]; then
            printf '%s' "$step"
            return 0
          fi
          i=$((i + 1))
        fi
        ;;
      --design-out=*)
        local step=""
        step="$(get_step_from_design_path "${arg#--design-out=}" || true)"
        if [[ -n "$step" ]]; then
          printf '%s' "$step"
          return 0
        fi
        ;;
      --design)
        if [[ $((i + 1)) -lt ${#args[@]} ]]; then
          local step=""
          step="$(get_step_from_design_path "${args[$((i + 1))]}" || true)"
          if [[ -n "$step" ]]; then
            printf '%s' "$step"
            return 0
          fi
          i=$((i + 1))
        fi
        ;;
      --design=*)
        local step=""
        step="$(get_step_from_design_path "${arg#--design=}" || true)"
        if [[ -n "$step" ]]; then
          printf '%s' "$step"
          return 0
        fi
        ;;
      --out)
        if [[ $((i + 1)) -lt ${#args[@]} ]]; then
          if [[ "$phase" == "planning" ]]; then
            local step=""
            step="$(try_get_step_from_plan_path "${args[$((i + 1))]}" || true)"
            if [[ -n "$step" ]]; then
              printf '%s' "$step"
              return 0
            fi
          fi
          i=$((i + 1))
        fi
        ;;
      --out=*)
        if [[ "$phase" == "planning" ]]; then
          local step=""
          step="$(try_get_step_from_plan_path "${arg#--out=}" || true)"
          if [[ -n "$step" ]]; then
            printf '%s' "$step"
            return 0
          fi
        fi
        ;;
      --)
        break
        ;;
      --branch-name)
        if [[ $((i + 1)) -lt ${#args[@]} ]]; then
          i=$((i + 1))
        fi
        ;;
      --branch-name=*)
        ;;
      -*)
        ;;
      *)
        printf '%s' "$arg"
        return 0
        ;;
    esac
    i=$((i + 1))
  done

  local inferred=""
  if ! inferred="$(get_first_unchecked_step)"; then
    return 1
  fi
  if [[ -n "$inferred" ]]; then
    printf '%s' "$inferred"
  fi
}

get_current_branch_name() {
  git -C "$ROOT" branch --show-current 2>/dev/null || true
}

get_step_from_branch_name() {
  local branch="$1"
  if [[ "$branch" =~ ^step-(.+)-(plan|implementation|user-review|review|ai-audit)$ ]]; then
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

run_implementation_phase() {
  load_model_config "implementation"

  local latest_plan step prompt_out
  if [[ -n "$RESUME_STEP" ]]; then
    step="$RESUME_STEP"
    latest_plan="$ROOT/ai/step_plans/step-$step.md"
  else
    latest_plan="$(get_preferred_step_plan)"
    step="$(get_step_from_plan_path "$latest_plan")"
  fi

  if [[ ! -f "$latest_plan" ]]; then
    echo "Step plan not found: $latest_plan" >&2
    exit 1
  fi

  if [[ -z "$step" ]]; then
    echo "Could not determine step from plan file: $latest_plan" >&2
    exit 1
  fi

  prompt_out="$(resolve_prompt_output_path "implementation" "$step")"

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
    echo "dry-run prompt: $(repo_relpath "$prompt_out")"
    echo "dry-run log: $(repo_relpath "$(resolve_log_path "implementation" "$step")")"
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
  if run_with_output_log "implementation" "$step" "${impl_cmd[@]}"; then
    status=0
  else
    status=$?
  fi

  return "$status"
}

run_user_review_phase() {
  load_model_config "user_review"

  local latest_plan step prompt_out
  if [[ -n "$RESUME_STEP" ]]; then
    step="$RESUME_STEP"
    latest_plan="$ROOT/ai/step_plans/step-$step.md"
  else
    latest_plan="$(get_preferred_step_plan)"
    step="$(get_step_from_plan_path "$latest_plan")"
  fi

  if [[ ! -f "$latest_plan" ]]; then
    echo "Step plan not found: $latest_plan" >&2
    exit 1
  fi

  if [[ -z "$step" ]]; then
    echo "Could not determine step from plan file: $latest_plan" >&2
    exit 1
  fi

  prompt_out="$(resolve_prompt_output_path "user_review" "$step")"
  local prompt_cmd=("$ROOT/ai/scripts/ai_user_review.sh" --step-plan "$latest_plan" --out "$prompt_out")

  if [[ "$DRY_RUN" -eq 1 ]]; then
    local dry_user_review_cmd=("$MODEL_CMD" -m "$MODEL_MODEL")
    if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
      dry_user_review_cmd+=("${MODEL_ARGS[@]}")
    fi
    if [[ "$MODEL_CMD" == "codex" ]]; then
      dry_user_review_cmd+=("<contents of $prompt_out>")
    else
      dry_user_review_cmd+=("run $prompt_out")
    fi
    echo "dry-run prompt: $(repo_relpath "$prompt_out")"
    echo "dry-run log: $(repo_relpath "$(resolve_log_path "user_review" "$step")")"
    echo "$(shell_join "${prompt_cmd[@]}") && $(shell_join "${dry_user_review_cmd[@]}")"
    return 0
  fi

  mkdir -p "$(dirname "$prompt_out")"
  "${prompt_cmd[@]}"
  local prompt_arg
  prompt_arg="$(build_model_prompt_arg "$MODEL_CMD" "$prompt_out")"
  local user_review_cmd=("$MODEL_CMD" -m "$MODEL_MODEL")
  if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
    user_review_cmd+=("${MODEL_ARGS[@]}")
  fi
  user_review_cmd+=("$prompt_arg")
  local status=0
  if run_with_output_log "user_review" "$step" "${user_review_cmd[@]}"; then
    status=0
  else
    status=$?
  fi

  return "$status"
}

run_ai_audit_phase() {
  load_model_config "ai_audit"

  local latest_plan step prompt_out
  if [[ -n "$RESUME_STEP" ]]; then
    step="$RESUME_STEP"
    latest_plan="$ROOT/ai/step_plans/step-$step.md"
  else
    latest_plan="$(get_preferred_step_plan)"
    step="$(get_step_from_plan_path "$latest_plan")"
  fi

  if [[ ! -f "$latest_plan" ]]; then
    echo "Step plan not found: $latest_plan" >&2
    exit 1
  fi

  if [[ -z "$step" ]]; then
    echo "Could not determine step from plan file: $latest_plan" >&2
    exit 1
  fi

  if [[ "$DRY_RUN" -eq 0 ]] && ! is_user_review_complete_for_step "$step"; then
    echo "Cannot start ai_audit for step $step: user_review phase is incomplete." >&2
    echo "Run: ai/scripts/orchestrator.sh --resume $step" >&2
    exit 1
  fi

  prompt_out="$(resolve_prompt_output_path "ai_audit" "$step")"
  local prompt_cmd=("$ROOT/ai/scripts/ai_audit.sh" --step-plan "$latest_plan" --out "$prompt_out")

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
    echo "dry-run prompt: $(repo_relpath "$prompt_out")"
    echo "dry-run log: $(repo_relpath "$(resolve_log_path "ai_audit" "$step")")"
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
  if run_with_output_log "ai_audit" "$step" "${review_cmd[@]}"; then
    status=0
  else
    status=$?
  fi
  return "$status"
}

run_post_review_phase() {
  local latest_plan step
  if [[ -n "$RESUME_STEP" ]]; then
    step="$RESUME_STEP"
    latest_plan="$ROOT/ai/step_plans/step-$step.md"
  else
    latest_plan="$(get_preferred_step_plan)"
    step="$(get_step_from_plan_path "$latest_plan")"
  fi

  if [[ ! -f "$latest_plan" ]]; then
    echo "Step plan not found: $latest_plan" >&2
    exit 1
  fi

  if [[ -z "$step" ]]; then
    echo "Could not determine step from plan file: $latest_plan" >&2
    exit 1
  fi

  if [[ "$DRY_RUN" -eq 0 ]]; then
    local review_artifact="$ROOT/ai/step_review_results/review_result-$step.md"
    if [[ ! -f "$review_artifact" ]]; then
      echo "Cannot start post_review for step $step: ai_audit phase is incomplete." >&2
      echo "Run: ai/scripts/orchestrator.sh --resume $step" >&2
      exit 1
    fi
  fi

  local cmd=("$ROOT/ai/scripts/post_review.sh" --step "$step")
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "dry-run log: $(repo_relpath "$(resolve_log_path "post_review" "$step")")"
    echo "$(shell_join "${cmd[@]}")"
    return 0
  fi

  local status=0
  if run_with_output_log "post_review" "$step" "${cmd[@]}"; then
    status=0
  else
    status=$?
  fi
  return "$status"
}

run_phase() {
  local phase="$1"
  local phase_key=""
  phase_key="$(canonicalize_phase_name "$phase")"

  case "$phase_key" in
    design)
      run_design_phase
      ;;
    planning)
      run_planning_phase
      ;;
    implementation)
      run_implementation_phase
      ;;
    user_review)
      run_user_review_phase
      ;;
    ai_audit)
      run_ai_audit_phase
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

phase_requires_source_plan_sync() {
  local phase="$1"
  phase="$(canonicalize_phase_name "$phase")"
  case "$phase" in
    planning|ai_audit|post_review)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

compute_runtime_plan_digest() {
  local digest=""
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && git -C "$ROOT" show-ref --verify --quiet "refs/heads/$RUNTIME_BRANCH" \
    && git -C "$ROOT" cat-file -e "$RUNTIME_BRANCH:overmind/implementation_plan.md" 2>/dev/null; then
    digest="$(git -C "$ROOT" show "$RUNTIME_BRANCH:overmind/implementation_plan.md" | cksum | awk '{print $1 ":" $2}' || true)"
    if [[ -n "$digest" ]]; then
      printf '%s' "$digest"
      return 0
    fi
  fi

  if [[ -f "$IMPLEMENTATION_PLAN_PRIMARY" ]]; then
    cksum "$IMPLEMENTATION_PLAN_PRIMARY" | awk '{print $1 ":" $2}'
    return 0
  fi
  printf ''
}

copy_runtime_plan_to_file() {
  local target_file="$1"
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && git -C "$ROOT" show-ref --verify --quiet "refs/heads/$RUNTIME_BRANCH" \
    && git -C "$ROOT" cat-file -e "$RUNTIME_BRANCH:overmind/implementation_plan.md" 2>/dev/null; then
    git -C "$ROOT" show "$RUNTIME_BRANCH:overmind/implementation_plan.md" >"$target_file"
    return 0
  fi
  if [[ ! -f "$IMPLEMENTATION_PLAN_PRIMARY" ]]; then
    return 1
  fi
  cp "$IMPLEMENTATION_PLAN_PRIMARY" "$target_file"
}

sync_runtime_plan_back_to_selected_feature_source() {
  local phase="$1"
  local tmp_runtime=""

  if [[ -z "$SELECTED_SOURCE_PLAN_PATH" ]]; then
    die "Cannot sync runtime plan after phase '$phase': selected feature source plan path is unknown."
  fi

  ensure_dir_writable "$(dirname "$SELECTED_SOURCE_PLAN_PATH")"
  tmp_runtime="$(mktemp)"
  if ! copy_runtime_plan_to_file "$tmp_runtime"; then
    rm -f "$tmp_runtime"
    die "Cannot sync runtime plan after phase '$phase': overmind/implementation_plan.md is unavailable."
  fi

  if [[ -f "$SELECTED_SOURCE_PLAN_PATH" ]] && cmp -s "$tmp_runtime" "$SELECTED_SOURCE_PLAN_PATH"; then
    rm -f "$tmp_runtime"
    return 0
  fi

  mv "$tmp_runtime" "$SELECTED_SOURCE_PLAN_PATH"
}

run_phase_with_optional_feature_sync() {
  local phase="$1"
  local before_digest=""
  local after_digest=""
  local should_sync=0

  if [[ "$DRY_RUN" -eq 0 ]] && phase_requires_source_plan_sync "$phase"; then
    should_sync=1
    before_digest="$(compute_runtime_plan_digest)"
  fi

  run_phase "$phase"

  if [[ "$should_sync" -eq 1 ]]; then
    after_digest="$(compute_runtime_plan_digest)"
    if [[ "$before_digest" != "$after_digest" ]]; then
      sync_runtime_plan_back_to_selected_feature_source "$phase"
    fi
  fi
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

step_exists_in_implementation_plan() {
  local step="$1"
  if [[ ! -f "$IMPLEMENTATION_PLAN_FILE" ]]; then
    return 1
  fi

  awk -v target="$step" '
    /^### Step / {
      line = $0
      sub(/^### Step /, "", line)
      split(line, parts, " ")
      if (parts[1] == target) {
        found = 1
        exit
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$IMPLEMENTATION_PLAN_FILE"
}

find_explicit_step_arg() {
  local args=("$@")
  local i=0
  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      --step)
        if [[ $((i + 1)) -lt ${#args[@]} ]]; then
          printf '%s' "${args[$((i + 1))]}"
          return 0
        fi
        ;;
      --step=*)
        printf '%s' "${args[$i]#--step=}"
        return 0
        ;;
      --)
        break
        ;;
    esac
    i=$((i + 1))
  done
  return 1
}

ensure_resume_step_in_plan_args() {
  local explicit_step=""
  explicit_step="$(find_explicit_step_arg "${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}" || true)"
  if [[ -n "$explicit_step" && "$explicit_step" != "$RESUME_STEP" ]]; then
    die "Conflicting step arguments: --resume $RESUME_STEP and --step $explicit_step"
  fi

  if [[ -z "$explicit_step" ]]; then
    PLAN_ARGS+=(--step "$RESUME_STEP")
  fi
}

phase_eval_set() {
  local phase="$1"
  local state="$2"
  local detail="$3"
  PHASE_EVAL_PHASES+=("$phase")
  PHASE_EVAL_STATES+=("$state")
  PHASE_EVAL_DETAILS+=("$detail")
}

phase_eval_step_bullet_counts() {
  local step="$1"
  awk -v target="$step" '
    BEGIN {
      in_step=0
      have_plan=0
      plan_checked=0
      have_review=0
      review_checked=0
      impl_total=0
      impl_checked=0
    }
    /^### Step / {
      line = $0
      sub(/^### Step /, "", line)
      split(line, parts, " ")
      in_step = (parts[1] == target)
      next
    }
    in_step && /^### Step / { in_step=0 }
    in_step && /^- \[[ xX]\]/ {
      raw = $0
      checked = (raw ~ /^- \[[xX]\]/)
      text = raw
      sub(/^- \[[ xX]\][[:space:]]*/, "", text)
      text_l = tolower(text)
      gate_text = text_l

      # Allow gate bullets to be prefixed with tags like [REQ-1].
      while (gate_text ~ /^\[[^]]+\][[:space:]]*/) {
        sub(/^\[[^]]+\][[:space:]]*/, "", gate_text)
      }

      if (gate_text ~ /^plan and discuss the step([[:space:]\.]|$)/) {
        have_plan=1
        if (checked) plan_checked=1
        next
      }
      if (gate_text ~ /^review step implementation([[:space:]\.]|$)/) {
        have_review=1
        if (checked) review_checked=1
        next
      }

      impl_total++
      if (checked) impl_checked++
    }
    END {
      printf "%d|%d|%d|%d|%d|%d", have_plan, plan_checked, have_review, review_checked, impl_total, impl_checked
    }
  ' "$IMPLEMENTATION_PLAN_FILE"
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

normalize_ordered_plan_item() {
  local line="$1"

  if [[ "$line" =~ ^-[[:space:]]+\[[xX[:space:]]\][[:space:]]+ ]]; then
    printf '%s\n' "$line"
    return 0
  fi

  if [[ "$line" =~ ^-[[:space:]]+ ]]; then
    local body
    body="$(printf '%s' "$line" | sed -E 's/^-[[:space:]]+//')"
    printf '%s\n' "- [ ] $body"
    return 0
  fi

  return 1
}

list_normalized_ordered_plan_items() {
  local section="$1"
  local line trimmed normalized

  while IFS= read -r line; do
    trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//')"
    [[ -z "$trimmed" ]] && continue
    if normalized="$(normalize_ordered_plan_item "$trimmed")"; then
      printf '%s\n' "$normalized"
    fi
  done <<<"$section"
}

list_unchecked_ordered_plan_items() {
  local items="$1"
  local line
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ ! "$line" =~ ^-[[:space:]]+\[[xX]\][[:space:]]+ ]]; then
      printf '%s\n' "$line"
    fi
  done <<<"$items"
}

get_step_plan_functional_requirements_section_from_file() {
  local file="$1"
  local section
  section="$(get_markdown_section_body "$file" "## Functional Requirements (translated from design EARS)")"
  if [[ -n "${section//[[:space:]]/}" ]]; then
    printf '%s' "$section"
    return 0
  fi
  section="$(get_markdown_section_body "$file" "## Functional Requirements")"
  if [[ -n "${section//[[:space:]]/}" ]]; then
    printf '%s' "$section"
    return 0
  fi
  return 1
}

list_functional_requirement_entries() {
  local section="$1"
  printf '%s\n' "$section" | awk '
    function flush_current() {
      if (fr != "") {
        normalized = tolower(status)
        gsub(/[[:space:]]+/, "", normalized)
        gsub(/`/, "", normalized)
        if (normalized == "done") {
          print "- [x] " fr
        } else {
          print "- [ ] " fr
        }
      }
      fr = ""
      status = ""
    }
    /^###[[:space:]]+FR-[A-Za-z0-9._-]+/ {
      flush_current()
      fr = $0
      sub(/^### /, "", fr)
      next
    }
    /^-[[:space:]]+Status:[[:space:]]*/ {
      status = $0
      sub(/^- Status:[[:space:]]*/, "", status)
      next
    }
    /^-[[:space:]]+\[[xX[:space:]]\][[:space:]]+FR-[A-Za-z0-9._-]+[[:space:]]+/ {
      flush_current()
      print $0
      next
    }
    /^-?[[:space:]]*FR-[A-Za-z0-9._-]+[[:space:]]+/ {
      flush_current()
      line = $0
      sub(/^-?[[:space:]]*/, "", line)
      print line
      next
    }
    END { flush_current() }
  '
}

normalize_functional_requirement_item() {
  local line="$1"

  if [[ "$line" =~ ^-[[:space:]]+\[[xX[:space:]]\][[:space:]]+FR-[A-Za-z0-9._-]+([[:space:]]+.*)?$ ]]; then
    printf '%s\n' "$line"
    return 0
  fi
  if [[ "$line" =~ ^-[[:space:]]+FR-[A-Za-z0-9._-]+([[:space:]]+.*)?$ ]]; then
    local body
    body="$(printf '%s' "$line" | sed -E 's/^-[[:space:]]+//')"
    printf '%s\n' "- [ ] $body"
    return 0
  fi
  if [[ "$line" =~ ^FR-[A-Za-z0-9._-]+([[:space:]]+.*)?$ ]]; then
    printf '%s\n' "- [ ] $line"
    return 0
  fi
  return 1
}

list_normalized_functional_requirement_items() {
  local section="$1"
  local entries line normalized
  entries="$(list_functional_requirement_entries "$section")"
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if normalized="$(normalize_functional_requirement_item "$line")"; then
      printf '%s\n' "$normalized"
    fi
  done <<<"$entries"
}

list_unchecked_functional_requirement_items() {
  local items="$1"
  local line
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ ! "$line" =~ ^-[[:space:]]+\[[xX]\][[:space:]]+FR-[A-Za-z0-9._-]+([[:space:]]+.*)?$ ]]; then
      printf '%s\n' "$line"
    fi
  done <<<"$items"
}

phase_eval_functional_requirements_counts() {
  local step="$1"
  local step_plan="$ROOT/ai/step_plans/step-$step.md"
  local functional_section normalized_items
  local total=0
  local done=0

  if [[ ! -f "$step_plan" ]]; then
    printf 'missing_step_plan|%d|%d|%d' "$total" "$done" "$((total - done))"
    return 0
  fi

  functional_section="$(get_step_plan_functional_requirements_section_from_file "$step_plan" || true)"
  if [[ -z "${functional_section//[[:space:]]/}" ]]; then
    printf 'missing_section|%d|%d|%d' "$total" "$done" "$((total - done))"
    return 0
  fi

  normalized_items="$(list_normalized_functional_requirement_items "$functional_section")"
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    total=$((total + 1))
    if [[ "$line" =~ ^-[[:space:]]+\[[xX]\][[:space:]]+FR-[A-Za-z0-9._-]+([[:space:]]+.*)?$ ]]; then
      done=$((done + 1))
    fi
  done <<<"$normalized_items"

  if [[ "$total" -eq 0 ]]; then
    printf 'no_items|%d|%d|%d' "$total" "$done" "$((total - done))"
    return 0
  fi
  printf 'ok|%d|%d|%d' "$total" "$done" "$((total - done))"
}

ensure_implementation_phase_completion_gate() {
  local step="$1"
  local ordered_counts ordered_state ordered_total ordered_checked
  local functional_counts functional_state functional_total functional_done
  local rerun_cmd
  rerun_cmd="ai/scripts/orchestrator.sh --resume $step"
  ordered_counts="$(phase_eval_ordered_plan_counts "$step")"
  IFS='|' read -r ordered_state ordered_total ordered_checked _ <<<"$ordered_counts"
  functional_counts="$(phase_eval_functional_requirements_counts "$step")"
  IFS='|' read -r functional_state functional_total functional_done _ <<<"$functional_counts"

  if [[ "$ordered_state" == "missing_step_plan" ]]; then
    echo "Implementation exit gate failed for step $step." >&2
    echo "Step plan not found: $ROOT/ai/step_plans/step-$step.md" >&2
    echo "Implementation phase was not finished correctly because step plan is missing." >&2
    echo "Restart implementation with: $rerun_cmd" >&2
    return 1
  fi

  if [[ "$ordered_state" == "missing_section" ]]; then
    echo "Implementation exit gate failed for step $step." >&2
    echo "Step plan gate requires section '## Plan (ordered)' in ai/step_plans/step-$step.md." >&2
    echo "Implementation phase was not finished correctly because ordered checklist section is missing." >&2
    echo "Restart implementation with: $rerun_cmd" >&2
    return 1
  fi

  if [[ "$ordered_state" == "no_checklist_items" ]]; then
    echo "Implementation exit gate failed for step $step." >&2
    echo "No ordered plan checklist items were found under '## Plan (ordered)' in ai/step_plans/step-$step.md." >&2
    echo "Add ordered bullets as checklist items and mark them [x] only when each is proven complete." >&2
    echo "Implementation phase was not finished correctly because ordered checklist items are missing." >&2
    echo "Restart implementation with: $rerun_cmd" >&2
    return 1
  fi

  if [[ "$ordered_checked" -ne "$ordered_total" ]]; then
    local step_plan ordered_section normalized_items unchecked
    step_plan="$ROOT/ai/step_plans/step-$step.md"
    ordered_section="$(get_markdown_section_body "$step_plan" "## Plan (ordered)")"
    normalized_items="$(list_normalized_ordered_plan_items "$ordered_section")"
    unchecked="$(list_unchecked_ordered_plan_items "$normalized_items")"

    echo "Implementation exit gate failed for step $step." >&2
    echo "All items in step plan '## Plan (ordered)' must be [x] before finishing implementation phase." >&2
    echo "Unchecked ordered-plan items (normalized):" >&2
    if [[ -n "$unchecked" ]]; then
      printf '%s\n' "$unchecked" >&2
    fi
    echo "Implementation phase was not finished correctly because ordered checklist has unchecked items." >&2
    echo "Restart implementation with: $rerun_cmd" >&2
    return 1
  fi

  if [[ "$functional_state" == "missing_section" ]]; then
    echo "Implementation exit gate failed for step $step." >&2
    echo "Step plan gate requires section '## Functional Requirements (translated from design EARS)' in ai/step_plans/step-$step.md." >&2
    echo "Implementation phase was not finished correctly because functional requirements section is missing." >&2
    echo "Restart implementation with: $rerun_cmd" >&2
    return 1
  fi

  if [[ "$functional_state" == "no_items" ]]; then
    echo "Implementation exit gate failed for step $step." >&2
    echo "No translated functional requirements were found in ai/step_plans/step-$step.md." >&2
    echo "Add entries like: - [ ] FR-$step-001 The system SHALL ... EARS[REQ-...]." >&2
    echo "Implementation phase was not finished correctly because functional requirements checklist is empty." >&2
    echo "Restart implementation with: $rerun_cmd" >&2
    return 1
  fi

  if [[ "$functional_done" -ne "$functional_total" ]]; then
    local step_plan functional_section normalized_fr unchecked_fr
    step_plan="$ROOT/ai/step_plans/step-$step.md"
    functional_section="$(get_step_plan_functional_requirements_section_from_file "$step_plan" || true)"
    normalized_fr="$(list_normalized_functional_requirement_items "$functional_section")"
    unchecked_fr="$(list_unchecked_functional_requirement_items "$normalized_fr")"
    echo "Implementation exit gate failed for step $step." >&2
    echo "All items in step plan '## Functional Requirements (translated from design EARS)' must be [x] before finishing implementation phase." >&2
    echo "Unchecked functional requirements (normalized):" >&2
    if [[ -n "${unchecked_fr//[[:space:]]/}" ]]; then
      printf '%s\n' "$unchecked_fr" >&2
    fi
    echo "Implementation phase was not finished correctly because functional requirements checklist has unchecked items." >&2
    echo "Restart implementation with: $rerun_cmd" >&2
    return 1
  fi

  return 0
}

phase_eval_ordered_plan_counts() {
  local step="$1"
  local step_plan="$ROOT/ai/step_plans/step-$step.md"
  local ordered_section normalized_items
  local total=0
  local checked=0

  if [[ ! -f "$step_plan" ]]; then
    printf 'missing_step_plan|%d|%d|%d' "$total" "$checked" "$((total - checked))"
    return 0
  fi

  ordered_section="$(get_markdown_section_body "$step_plan" "## Plan (ordered)")"
  if [[ -z "${ordered_section//[[:space:]]/}" ]]; then
    printf 'missing_section|%d|%d|%d' "$total" "$checked" "$((total - checked))"
    return 0
  fi

  normalized_items="$(list_normalized_ordered_plan_items "$ordered_section")"
  if [[ -z "${normalized_items//[[:space:]]/}" ]]; then
    printf 'no_checklist_items|%d|%d|%d' "$total" "$checked" "$((total - checked))"
    return 0
  fi

  local line
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    total=$((total + 1))
    if [[ "$line" =~ ^-[[:space:]]+\[[xX]\][[:space:]]+ ]]; then
      checked=$((checked + 1))
    fi
  done <<<"$normalized_items"

  printf 'ok|%d|%d|%d' "$total" "$checked" "$((total - checked))"
}

check_required_sections() {
  local file="$1"
  shift
  local required=("$@")
  local missing=()
  local section

  for section in "${required[@]}"; do
    if ! awk -v target="$section" '
      /^##[[:space:]]+/ {
        line = $0
        sub(/^##[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line == target) { found = 1; exit }
      }
      END { exit(found ? 0 : 1) }
    ' "$file"; then
      missing+=("$section")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    printf 'ok'
  else
    printf '%s' "${missing[*]}"
  fi
}

evaluate_design_phase() {
  local step="$1"
  local design_file="$ROOT/ai/step_designs/step-$step-design.md"
  if [[ ! -f "$design_file" ]]; then
    phase_eval_set "design" "incomplete" "missing ai/step_designs/step-$step-design.md"
    return 0
  fi

  phase_eval_set "design" "complete" "design artifact present"
}

evaluate_planning_phase() {
  local step="$1"
  local counts="$2"
  local plan_checked have_review review_checked impl_total impl_checked
  local step_plan="$ROOT/ai/step_plans/step-$step.md"

  IFS='|' read -r _ plan_checked have_review review_checked impl_total impl_checked <<<"$counts"

  if [[ "$plan_checked" -eq 1 && -f "$step_plan" ]]; then
    phase_eval_set "planning" "complete" "planning markers detected (step plan present and implementation-plan planning gate closed)"
  elif [[ "$impl_checked" -gt 0 || "$review_checked" -eq 1 ]]; then
    phase_eval_set "planning" "complete" "later-phase execution markers detected ($impl_checked/$impl_total implementation bullets checked)"
  else
    phase_eval_set "planning" "incomplete" "later-phase execution has not started yet"
  fi
}

implementation_branch_exists_for_step() {
  local step="$1"
  local branch="step-$step-implementation"
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi
  git -C "$ROOT" show-ref --verify --quiet "refs/heads/$branch"
}

is_implementation_complete_for_step() {
  local step="$1"
  local review_file="$ROOT/ai/step_review_results/review_result-$step.md"

  if [[ -f "$review_file" ]]; then
    return 0
  fi

  if user_review_branch_exists_for_step "$step"; then
    return 0
  fi

  if implementation_branch_exists_for_step "$step"; then
    return 0
  fi

  return 1
}

evaluate_implementation_phase() {
  local step="$1"
  local step_plan="$ROOT/ai/step_plans/step-$step.md"

  if [[ ! -f "$step_plan" ]]; then
    phase_eval_set "implementation" "invalid" "missing ai/step_plans/step-$step.md"
    return 0
  fi

  if is_implementation_complete_for_step "$step"; then
    phase_eval_set "implementation" "complete" "implementation marker detected (branch step-$step-implementation or later-phase artifact present)"
  else
    phase_eval_set "implementation" "incomplete" "missing implementation marker (expected branch step-$step-implementation)"
  fi
}

user_review_branch_exists_for_step() {
  local step="$1"
  local branch="step-$step-user-review"
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi
  git -C "$ROOT" show-ref --verify --quiet "refs/heads/$branch"
}

is_user_review_complete_for_step() {
  local step="$1"
  local review_file="$ROOT/ai/step_review_results/review_result-$step.md"

  if [[ -f "$review_file" ]]; then
    return 0
  fi

  if user_review_branch_exists_for_step "$step"; then
    return 0
  fi

  return 1
}

evaluate_user_review_phase() {
  local step="$1"
  if is_user_review_complete_for_step "$step"; then
    phase_eval_set "user_review" "complete" "user_review marker detected (step branch or review artifact present)"
  else
    phase_eval_set "user_review" "incomplete" "missing user_review marker (expected branch step-$step-user-review)"
  fi
}

evaluate_ai_audit_phase() {
  local step="$1"
  local review_file="$ROOT/ai/step_review_results/review_result-$step.md"
  if [[ ! -f "$review_file" ]]; then
    phase_eval_set "ai_audit" "incomplete" "missing ai/step_review_results/review_result-$step.md"
    return 0
  fi

  phase_eval_set "ai_audit" "complete" "review artifact present (disposition semantics enforced by ai_audit/post_review helper)"
}

evaluate_post_review_phase() {
  local step="$1"
  local counts="$2"
  local review_checked
  IFS='|' read -r _ _ _ review_checked _ _ <<<"$counts"

  if [[ "$review_checked" -ne 1 ]]; then
    phase_eval_set "post_review" "incomplete" "review gate 'Review step implementation' is not [x]"
    return 0
  fi

  local history_file="$ROOT/ai/history.md"
  if [[ ! -f "$history_file" ]]; then
    phase_eval_set "post_review" "incomplete" "missing ai/history.md"
    return 0
  fi

  if ! grep -Eq "^- Step:[[:space:]]+$step([[:space:]]|$)" "$history_file"; then
    phase_eval_set "post_review" "incomplete" "no history record found for step $step"
    return 0
  fi

  phase_eval_set "post_review" "complete" "review gate closed and history contains step record"
}

evaluate_resume_phase_states() {
  local step="$1"
  RESUME_BLOCKED=0
  RESUME_BLOCK_REASON=""
  PHASE_EVAL_PHASES=()
  PHASE_EVAL_STATES=()
  PHASE_EVAL_DETAILS=()

  if [[ ! -f "$IMPLEMENTATION_PLAN_FILE" ]]; then
    die "Required file not found: $(repo_relpath "$IMPLEMENTATION_PLAN_FILE")"
  fi

  local counts=""
  counts="$(phase_eval_step_bullet_counts "$step")"
  evaluate_design_phase "$step"
  evaluate_planning_phase "$step" "$counts"
  evaluate_implementation_phase "$step"
  evaluate_user_review_phase "$step"
  evaluate_ai_audit_phase "$step"
  evaluate_post_review_phase "$step" "$counts"

}

resolve_resume_start_phase() {
  local i=0
  RESUME_START_PHASE=""
  RESUME_ALL_DONE=1

  while [[ $i -lt ${#PHASE_EVAL_PHASES[@]} ]]; do
    if [[ "${PHASE_EVAL_STATES[$i]}" != "complete" ]]; then
      RESUME_START_PHASE="${PHASE_EVAL_PHASES[$i]}"
      RESUME_ALL_DONE=0
      return 0
    fi
    i=$((i + 1))
  done
}

build_resume_requested_phases() {
  REQUESTED_PHASES=()
  if [[ "$RESUME_ALL_DONE" -eq 1 ]]; then
    return 0
  fi

  local include=0
  local phase
  for phase in "${CANONICAL_PHASES[@]}"; do
    if [[ "$phase" == "$RESUME_START_PHASE" ]]; then
      include=1
    fi
    if [[ "$include" -eq 1 ]]; then
      REQUESTED_PHASES+=("$phase")
    fi
  done
}

print_resume_dry_run_report() {
  local step="$1"
  echo "Resume dry-run for step $step"
  local i=0
  while [[ $i -lt ${#PHASE_EVAL_PHASES[@]} ]]; do
    printf '  - %s: %s (%s)\n' \
      "${PHASE_EVAL_PHASES[$i]}" \
      "${PHASE_EVAL_STATES[$i]}" \
      "${PHASE_EVAL_DETAILS[$i]}"
    i=$((i + 1))
  done

  if [[ "$RESUME_BLOCKED" -eq 1 ]]; then
    echo "Selected start phase: none (resume blocked by invalid phase state)"
    echo "Skipped phases: design, planning, implementation, user_review, ai_audit, post_review"
    echo "Executed phases: (none)"
    echo "Block reason: $RESUME_BLOCK_REASON"
    return 0
  fi

  if [[ "$RESUME_ALL_DONE" -eq 1 ]]; then
    echo "Selected start phase: none (all phases complete)"
    echo "Skipped phases: design, planning, implementation, user_review, ai_audit, post_review"
    echo "Executed phases: (none)"
    return 0
  fi

  echo "Selected start phase: $RESUME_START_PHASE"

  local skipped=()
  local executed=()
  local include=0
  local phase
  for phase in "${CANONICAL_PHASES[@]}"; do
    if [[ "$phase" == "$RESUME_START_PHASE" ]]; then
      include=1
    fi
    if [[ "$include" -eq 1 ]]; then
      executed+=("$phase")
    else
      skipped+=("$phase")
    fi
  done

  if [[ ${#skipped[@]} -eq 0 ]]; then
    echo "Skipped phases: (none)"
  else
    echo "Skipped phases: ${skipped[*]}"
  fi
  echo "Executed phases: ${executed[*]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      if [[ $# -gt 1 && "${2:-}" != --* ]]; then
        shift 2
      else
        shift
      fi
      ;;
    --phase=*)
      shift
      ;;
    --resume)
      if [[ -z "${2:-}" ]]; then
        echo "--resume requires a value." >&2
        usage >&2
        exit 1
      fi
      RESUME_STEP="$2"
      RESUME_MODE=1
      shift 2
      ;;
    --resume=*)
      RESUME_STEP="${1#--resume=}"
      RESUME_MODE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --debug)
      DEBUG_MODE=1
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

REQUESTED_STEP_FOR_FEATURE_CONTEXT=""
if [[ "$RESUME_MODE" -eq 1 ]]; then
  REQUESTED_STEP_FOR_FEATURE_CONTEXT="$RESUME_STEP"
else
  REQUESTED_STEP_FOR_FEATURE_CONTEXT="$(find_explicit_step_arg "${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}" || true)"
fi
ensure_feature_runtime_context "$REQUESTED_STEP_FOR_FEATURE_CONTEXT" "$RESUME_MODE"

if [[ "$RESUME_MODE" -eq 1 ]]; then
  if [[ ! -f "$IMPLEMENTATION_PLAN_FILE" ]]; then
    die "Required file not found: $(repo_relpath "$IMPLEMENTATION_PLAN_FILE")"
  fi
  if ! step_exists_in_implementation_plan "$RESUME_STEP"; then
    die "Unknown step '$RESUME_STEP' in $(repo_relpath "$IMPLEMENTATION_PLAN_FILE")."
  fi

  ensure_resume_step_in_plan_args
  evaluate_resume_phase_states "$RESUME_STEP"
  resolve_resume_start_phase
  build_resume_requested_phases
  if [[ "$DRY_RUN" -eq 1 ]]; then
    print_resume_dry_run_report "$RESUME_STEP"
  fi
  if [[ "$RESUME_BLOCKED" -eq 1 ]]; then
    die "Resume blocked: $RESUME_BLOCK_REASON"
  fi
fi

if [[ "$RESUME_MODE" -eq 0 && ${#REQUESTED_PHASES[@]} -eq 0 ]]; then
  while IFS= read -r phase; do
    [[ -z "$phase" ]] && continue
    REQUESTED_PHASES+=("$phase")
  done < <(list_phases)
  if ! array_contains_ci "post_review" "${REQUESTED_PHASES[@]+"${REQUESTED_PHASES[@]}"}"; then
    REQUESTED_PHASES+=("post_review")
  fi
fi

if [[ ${#REQUESTED_PHASES[@]} -eq 0 ]]; then
  if [[ "$RESUME_MODE" -eq 1 && "$RESUME_ALL_DONE" -eq 1 ]]; then
    exit 0
  fi
  die "No phases found in $(repo_relpath "$MODELS")"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  ensure_orchestrator_prereqs
  ensure_ai_context_files
fi

for phase in "${REQUESTED_PHASES[@]+"${REQUESTED_PHASES[@]}"}"; do
  if confirm_phase_if_interactive "$phase"; then
    run_phase_with_optional_feature_sync "$phase"
    if [[ "$(canonicalize_phase_name "$phase")" == "ai_audit" ]]; then
      RAN_AI_AUDIT=1
    fi
    if [[ "$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]')" == "post_review" ]]; then
      RAN_POST_REVIEW=1
    fi
  else
    denied_phase="$(canonicalize_phase_name "$phase")"
    echo "Execution stopped: user denied phase progression at $denied_phase." >&2
    break
  fi
done

if [[ "$DRY_RUN" -eq 0 && "$RAN_AI_AUDIT" -eq 1 ]]; then
  latest_plan="$(get_preferred_step_plan || true)"
  step="$(get_step_from_plan_path "$latest_plan" 2>/dev/null || true)"
  if [[ "$RAN_POST_REVIEW" -eq 0 ]]; then
    if [[ -n "$step" ]]; then
      echo "ai_audit phase completed for step $step." >&2
      echo "Run to continue this step:" >&2
      echo "  ai/scripts/orchestrator.sh --resume $step" >&2
    else
      echo "ai_audit phase completed." >&2
      echo "Run to continue this step:" >&2
      echo "  ai/scripts/orchestrator.sh" >&2
    fi
  else
    if [[ -n "$step" ]]; then
      echo "ai_audit + post_review completed for step $step." >&2
    else
      echo "ai_audit + post_review completed." >&2
    fi
  fi
  if [[ "$DEBUG_MODE" -eq 1 ]]; then
    echo "Logs: ai/logs (<project>-<phase>-<step>-log)." >&2
  else
    echo "Logs: ai/logs (<project>-<phase>-latest-log, overwritten each run)." >&2
  fi
  if [[ "$RAN_POST_REVIEW" -eq 1 ]]; then
    echo "History: ai/history.md (single consolidated step record updated)." >&2
  else
    echo "History: ai/history.md (no update; run post_review to consolidate step metrics)." >&2
  fi
fi
