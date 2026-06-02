#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/helpers/runtime_layout.sh"
. "$SCRIPT_DIR/helpers/build_phase_cmd.sh"
asdlc_worker_require_runtime_layout "${BASH_SOURCE[0]}"
ROOT="$WORKER_REPO_ROOT"
PROJECT="$(basename "$ROOT")"
MODELS="$ASDLC_MODELS_FILE"
HISTORY_FILE="$ASDLC_HISTORY_FILE"
DECISIONS_FILE="$ASDLC_DECISIONS_FILE"
BLOCKER_LOG_FILE="$ASDLC_BLOCKER_LOG_FILE"
OPEN_QUESTIONS_FILE="$ASDLC_OPEN_QUESTIONS_FILE"
USER_REVIEW_FILE="$ASDLC_USER_REVIEW_FILE"
IMPLEMENTATION_PLAN_PRIMARY=""
RUNTIME_REQUIREMENTS_PATH=""
PROJECT_BINDING_FILE="$ASDLC_BINDING_FILE"
FEATURE_META_SYNC_FILE="$ASDLC_WORKER_HOME/feature_meta_sync.yaml"
RUNTIME_BRANCH="overmind"

# Run all child commands from repository root for consistent sandbox/workspace resolution.
cd "$ROOT"

DRY_RUN=0
DEBUG_MODE=0
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
BOUND_PROJECT_SYNC_READY=0
RUNTIME_BRANCH_SYNC_READY=0
START_BRANCH_VALIDATED=0
CURRENT_FEATURE_SWITCH_FROM_ID=""
NEXT_PHASE_ALREADY_CONFIRMED=""
ORCHESTRATION_STOP_REQUESTED=0
ORCHESTRATION_STOP_REASON=""

usage() {
  cat <<'EOF'
Usage: .asdlc_worker/scripts/orchestrator.sh [--resume <step>] [--debug] [--dry-run] [--help] [-- <phase-script args>]

Default behavior:
  - Runs all phases in .asdlc_worker/setup/models.md, in order, then runs post_review.
  - design invokes Codex with a prompt that calls the yasdef-worker-design skill and generates/updates a feature-design artifact.
  - planning invokes Codex with a prompt that calls the yasdef-worker-plan skill and repeats until readiness plus per-step ledgers are clean.
  - implementation invokes Codex with a prompt that calls the yasdef-worker-implementation skill for the latest step plan.
  - user_review runs an orchestrator-owned implementation-readiness gate, creates/switches the user-review branch from implementation, then invokes the user_review model command once with an inline yasdef-worker-user-review prompt.
  - ai_audit creates/switches the review branch from user_review, then invokes the ai_audit model command once with an inline yasdef-worker-ai-audit prompt.
  - post_review runs .asdlc_worker/scripts/post_review.sh for the latest step plan and appends post-review metrics to .asdlc_worker/history.md.
  - --resume <step> evaluates phase completion for the step and runs from the first unfinished phase through post_review.
  - --debug enables per-step/per-phase log files.
  - Without --debug, logs use latest-per-phase filenames and are overwritten each run.
  - When running interactively, asks for confirmation before planning/implementation/user_review/ai_audit.
  - If interactive confirmation is denied for any phase, orchestration stops immediately and does not prompt downstream phases in that run.
  - Writes per-phase logs to .asdlc_worker/logs/<project>-<phase>-latest-log (or step-specific names with --debug).
  - post_review consolidates per-step token usage and metrics into .asdlc_worker/history.md.

Examples:
  .asdlc_worker/scripts/orchestrator.sh
  .asdlc_worker/scripts/orchestrator.sh -- --step 1.3
  .asdlc_worker/scripts/orchestrator.sh -- --step 1.3 --out .asdlc_worker/tmp/step-1.3.md
  .asdlc_worker/scripts/orchestrator.sh --resume 1.3
  .asdlc_worker/scripts/orchestrator.sh --resume 1.3 --dry-run
  .asdlc_worker/scripts/orchestrator.sh --debug -- --step 1.3
  .asdlc_worker/scripts/orchestrator.sh --dry-run
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
    die "Script is not executable: $(repo_relpath "$script"). Fix: chmod +x .asdlc_worker/scripts/*.sh"
  fi
}

ensure_history_file() {
  ensure_file_writable_if_missing "$HISTORY_FILE"
}

ensure_ai_context_files() {
  ensure_dir_writable "$ASDLC_WORKER_HOME"
  ensure_dir_writable "$ASDLC_STEP_DESIGNS_DIR"
  ensure_dir_writable "$ASDLC_STEP_PLANS_DIR"
  ensure_dir_writable "$ASDLC_STEP_REVIEW_RESULTS_DIR"
  ensure_dir_writable "$ASDLC_LOGS_DIR"

  # Skip file creation when the step plan branch already exists and we are not
  # on it — those files are tracked there, and creating them as untracked here
  # would block checkout to the existing step branch.
  local _skip_ctx_files=0
  if [[ -n "$SELECTED_STEP" ]]; then
    local _cb
    _cb="$(get_current_branch_name)"
    if [[ "$_cb" != "step-$SELECTED_STEP-$SELECTED_FEATURE_ID-"* ]] \
       && git -C "$ROOT" show-ref --verify --quiet "refs/heads/step-$SELECTED_STEP-$SELECTED_FEATURE_ID-plan" 2>/dev/null; then
      _skip_ctx_files=1
    fi
  fi

  if [[ "$_skip_ctx_files" -eq 0 ]]; then
    ensure_file_writable_if_missing "$DECISIONS_FILE"
    ensure_file_writable_if_missing "$BLOCKER_LOG_FILE"
    ensure_file_writable_if_missing "$OPEN_QUESTIONS_FILE"
    ensure_file_writable_if_missing "$USER_REVIEW_FILE"
    ensure_history_file
  fi
}

ensure_orchestrator_prereqs() {
  ensure_executable_script "$ASDLC_SCRIPTS_DIR/post_review.sh"
}

ensure_uv_available() {
  if ! command -v uv >/dev/null 2>&1; then
    die "ASDLC orchestrator requires 'uv' to be installed and available in PATH."
  fi
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
    printf '%s/.asdlc_worker/logs/%s-%s-%s-log' "$ROOT" "$PROJECT" "$phase_token" "$step_token"
  else
    printf '%s/.asdlc_worker/logs/%s-%s-latest-log' "$ROOT" "$PROJECT" "$phase_token"
  fi
}

run_with_output_log() {
  local phase="$1"
  local step="${2:-}"
  shift 2

  local log_dir log_path
  log_dir="$ASDLC_LOGS_DIR"
  ensure_dir_writable "$log_dir"
  log_path="$(resolve_log_path "$phase" "$step")"

  local status=0
  set +e
  if [[ "${1:-}" == "claude" ]]; then
    # Claude renders an interactive TUI; its log capture is ANSI noise that post_review
    # cannot summarize. Skip log capture entirely and clear any stale codex-era log for
    # this phase so post_review doesn't pull yesterday's numbers — claude phase contributes
    # 0 to the token sum.
    rm -f "$log_path"
    "$@"
    status=$?
    LAST_RUN_LOG=""
    set -e
    return "$status"
  fi

  local err=""
  if ! err="$( ( : >"$log_path" ) 2>&1 )"; then
    die "Failed to write log file: $(repo_relpath "$log_path"): ${err:-unknown error}"
  fi

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

  if [[ "$NEXT_PHASE_ALREADY_CONFIRMED" == "$phase_key" ]]; then
    NEXT_PHASE_ALREADY_CONFIRMED=""
    return 0
  fi

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

confirm_planning_followup_if_interactive() {
  local mode="$1"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    return 0
  fi

  local answer=""
  while true; do
    case "$mode" in
      rerun)
        printf 'we need one more round of planing\n' >&2
        ;;
      ready)
        printf 'we are ready to start next phase: implementation\n' >&2
        ;;
      *)
        die "Unsupported planning follow-up mode: $mode"
        ;;
    esac
    printf 'Proceed? [y/n] ' >&2
    IFS= read -r answer || answer=""
    case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
      y)
        if [[ "$mode" == "ready" ]]; then
          NEXT_PHASE_ALREADY_CONFIRMED="implementation"
        fi
        return 0
        ;;
      n|'')
        ORCHESTRATION_STOP_REQUESTED=1
        if [[ "$mode" == "rerun" ]]; then
          ORCHESTRATION_STOP_REASON="Execution stopped: user declined another planning round."
        else
          ORCHESTRATION_STOP_REASON="Execution stopped: user declined phase progression after planning."
        fi
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

ensure_phase_branch() {
  local target="$1"
  local current=""

  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "Phase execution requires a git repository."
  fi

  current="$(get_current_branch_name)"
  if [[ "$current" == "$target" ]]; then
    return 0
  fi

  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$target"; then
    if ! git -C "$ROOT" checkout "$target" >/dev/null; then
      die "Failed to switch to existing branch: $target"
    fi
    echo "Switched to existing branch: $target" >&2
  else
    if ! git -C "$ROOT" checkout -b "$target" >/dev/null; then
      die "Failed to create and switch to branch: $target"
    fi
    echo "Created and switched to branch: $target" >&2
  fi
}

ensure_user_review_branch() {
  local step="$1"
  local feature_id="$2"
  local implementation_branch target current
  implementation_branch="step-$step-$feature_id-implementation"
  target="step-$step-$feature_id-user-review"

  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "User review requires a git repository."
  fi

  current="$(get_current_branch_name)"
  if [[ "$current" == "$target" ]]; then
    return 0
  fi

  if [[ "$current" != "$implementation_branch" ]]; then
    if [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null || true)" ]]; then
      die "User review branch must be created from $implementation_branch to carry implementation changes."
    fi
    if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$implementation_branch"; then
      if ! git -C "$ROOT" checkout "$implementation_branch" >/dev/null; then
        die "Failed to switch to implementation branch: $implementation_branch"
      fi
      current="$implementation_branch"
      echo "Switched to implementation branch: $implementation_branch" >&2
    else
      die "Implementation branch not found: $implementation_branch"
    fi
  fi

  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$target"; then
    if ! git -C "$ROOT" checkout "$target" >/dev/null; then
      die "Failed to switch to existing branch: $target"
    fi
    echo "Switched to existing branch: $target" >&2
  else
    if ! git -C "$ROOT" checkout -b "$target" >/dev/null; then
      die "Failed to create and switch to branch: $target"
    fi
    echo "Created and switched to branch: $target (from $implementation_branch with implementation changes)." >&2
  fi
}

ensure_ai_audit_review_branch() {
  local step="$1"
  local feature_id="$2"
  local source_branch target current
  source_branch="step-$step-$feature_id-user-review"
  target="step-$step-$feature_id-review"

  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "ai_audit requires a git repository."
  fi

  current="$(get_current_branch_name)"
  if [[ "$current" == "$target" ]]; then
    return 0
  fi

  if ! git -C "$ROOT" show-ref --verify --quiet "refs/heads/$source_branch"; then
    die "Cannot start ai_audit for step $step: missing user_review branch $source_branch. Run user_review first."
  fi

  if [[ "$current" != "$source_branch" ]]; then
    if ! git -C "$ROOT" checkout "$source_branch" >/dev/null; then
      die "Failed to switch to user_review branch: $source_branch (working tree has conflicting uncommitted changes or branch is unavailable)."
    fi
    echo "Switched to user_review branch: $source_branch" >&2
  fi

  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$target"; then
    if ! git -C "$ROOT" checkout "$target" >/dev/null; then
      die "Failed to switch to existing branch: $target"
    fi
    echo "Switched to existing branch: $target" >&2
  else
    if ! git -C "$ROOT" checkout -b "$target" >/dev/null; then
      die "Failed to create and switch to branch: $target"
    fi
    echo "Created and switched to branch: $target (from $source_branch)." >&2
  fi
}

planning_ledger_has_entries() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 1
  fi

  awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    /^- None\.$/ { next }
    /^- No open questions\.$/ { next }
    /^- No blockers\.$/ { next }
    { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' "$path"
}

run_planning_phase() {
  load_model_config "planning"

  local step explicit_step
  step="$(resolve_step_for_phase_from_args "planning" "${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}")" || return 1
  explicit_step="$(find_explicit_step_arg "${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}" || true)"
  local branch_name="step-$SELECTED_STEP-$SELECTED_FEATURE_ID-plan"
  local design_file="$ASDLC_STEP_DESIGNS_DIR/step-$step-$SELECTED_FEATURE_ID-design.md"
  local step_plan_out="$ASDLC_STEP_PLANS_DIR/step-$step-$SELECTED_FEATURE_ID.md"
  local open_questions_file="$ASDLC_STEP_OPEN_QUESTIONS_DIR/step-$step-$SELECTED_FEATURE_ID-open-questions.md"
  local blockers_file="$ASDLC_STEP_BLOCKERS_DIR/step-$step-$SELECTED_FEATURE_ID-blockers.md"
  local planning_readiness_script="$ROOT/.codex/skills/yasdef-worker-plan/scripts/check_planning_readiness.py"

  if [[ ! -f "$design_file" ]]; then
    die "Planning requires the design artifact to exist first: $(repo_relpath "$design_file")"
  fi
  if [[ ! -f "$planning_readiness_script" ]]; then
    die "Planning requires the installed readiness script: $(repo_relpath "$planning_readiness_script")"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    build_phase_cmd "<inline yasdef-worker-plan prompt>"
    echo "dry-run log: $(repo_relpath "$(resolve_log_path "planning" "$step")")"
    echo "run yasdef-worker-plan for step $step: $(shell_join "${BUILD_PHASE_CMD[@]}")"
    return 0
  fi

  ensure_phase_branch "$branch_name"
  local iteration=1
  while true; do
    local prompt_arg
    prompt_arg=$(cat <<EOF
Use the \`yasdef-worker-plan\` skill to run one ASDLC worker planning iteration.

Inputs:
- Step: $step
- Feature id: $SELECTED_FEATURE_ID
- Branch: $branch_name
- Design artifact: $design_file
- Step plan output: $step_plan_out
- Runtime implementation plan: $ASDLC_RUNTIME_PLAN_PATH
- Open questions ledger: $open_questions_file
- Blockers ledger: $blockers_file
EOF
)

    build_phase_cmd "$prompt_arg"

    local status=0
    if run_with_output_log "planning" "$step" "${BUILD_PHASE_CMD[@]}"; then
      status=0
    else
      status=$?
    fi
    if [[ "$status" -ne 0 ]]; then
      return "$status"
    fi

    local readiness_output=""
    local readiness_status=0
    set +e
    readiness_output="$(
      uv run python "$planning_readiness_script" \
        --design "$design_file" \
        --step-plan "$step_plan_out" \
        --open-questions "$open_questions_file" \
        --blockers "$blockers_file" 2>&1
    )"
    readiness_status=$?
    set -e
    if [[ "$readiness_status" -ne 0 ]]; then
      printf '%s\n' "$readiness_output" >&2
    fi

    local ledgers_dirty=0
    if planning_ledger_has_entries "$open_questions_file" || planning_ledger_has_entries "$blockers_file"; then
      ledgers_dirty=1
    fi

    if [[ "$readiness_status" -eq 0 && "$ledgers_dirty" -eq 0 ]]; then
      if ! confirm_planning_followup_if_interactive "ready"; then
        return 0
      fi
      return 0
    fi

    if ! confirm_planning_followup_if_interactive "rerun"; then
      return 0
    fi

    iteration=$((iteration + 1))
    echo "orchestrator: re-running planning for step $step (readiness_status=$readiness_status, ledgers_dirty=$ledgers_dirty, iteration=$iteration)." >&2
  done
}

run_design_phase() {
  load_model_config "design"

  local step explicit_step
  step="$(resolve_step_for_phase_from_args "design" "${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}")" || return 1
  explicit_step="$(find_explicit_step_arg "${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}" || true)"

  local design_out=""
  if [[ -z "$explicit_step" ]]; then
    echo "orchestrator: resolved routed step '$step' for design skill prompt." >&2
  fi
  local _has_design_out=0
  local _pi=0
  while [[ $_pi -lt ${#PLAN_ARGS[@]} ]]; do
    case "${PLAN_ARGS[$_pi]:-}" in
      --design-out)
        if [[ $((_pi + 1)) -lt ${#PLAN_ARGS[@]} ]]; then
          design_out="${PLAN_ARGS[$((_pi + 1))]}"
          _has_design_out=1
        fi
        break
        ;;
      --design-out=*)
        design_out="${PLAN_ARGS[$_pi]#--design-out=}"
        _has_design_out=1
        break
        ;;
    esac
    _pi=$((_pi + 1))
  done
  if [[ "$_has_design_out" -eq 0 ]]; then
    design_out="$ASDLC_STEP_DESIGNS_DIR/step-$step-$SELECTED_FEATURE_ID-design.md"
  fi
  local branch_name="step-$SELECTED_STEP-$SELECTED_FEATURE_ID-plan"

  local prompt_arg
  prompt_arg=$(cat <<EOF
Use the \`yasdef-worker-design\` skill to run the ASDLC worker design phase.

Inputs:
- Step: $step
- Feature id: $SELECTED_FEATURE_ID
- Branch: $branch_name
- Design output: $design_out
- Runtime implementation plan: $ASDLC_RUNTIME_PLAN_PATH
- Runtime requirements EARS: $ASDLC_RUNTIME_EARS_PATH
EOF
)

  if [[ "$DRY_RUN" -eq 1 ]]; then
    build_phase_cmd "<inline yasdef-worker-design prompt>"
    echo "dry-run log: $(repo_relpath "$(resolve_log_path "design" "$step")")"
    echo "run yasdef-worker-design for step $step: $(shell_join "${BUILD_PHASE_CMD[@]}")"
    return 0
  fi

  ensure_phase_branch "$branch_name"

  build_phase_cmd "$prompt_arg"

  local status=0
  if run_with_output_log "design" "$step" "${BUILD_PHASE_CMD[@]}"; then
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
  local feature_id="$1"
  local dir="$ASDLC_STEP_PLANS_DIR"
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
    step="${step%%-*}"
    [[ -z "$step" ]] && continue
    local key
    key="$(make_sort_key "$step")"
    pairs+=("$key|$file")
  done < <(find "$dir" -maxdepth 1 -type f -name "step-*-${feature_id}.md" -print)

  if [[ ${#pairs[@]} -eq 0 ]]; then
    echo "No step plans found in $dir." >&2
    return 1
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

try_get_step_from_plan_path() {
  local file="$1"
  local base
  base="$(basename "$file")"
  if [[ "$base" =~ ^step-([0-9][0-9.]*)(-.*)?\.md$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

get_step_from_design_path() {
  local file="$1"
  local base stem step
  base="$(basename "$file")"
  if [[ "$base" =~ ^step-(.+)-design\.md$ ]]; then
    stem="${BASH_REMATCH[1]}"
    step="${stem%%-*}"
    printf '%s' "$step"
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

read_init_progress_project_id() {
  local def_file="$1"
  grep -m1 '^\s*project_id:' "$def_file" | sed "s/.*project_id:[[:space:]]*//;s/[\"']//g"
}

load_project_binding() {
  if [[ -n "$BINDING_WORKER_UUID" ]]; then
    return 0
  fi

  if [[ ! -f "$PROJECT_BINDING_FILE" ]]; then
    die "Required binding file is missing: $(repo_relpath "$PROJECT_BINDING_FILE"). Run .asdlc_worker/scripts/register_worker.sh first."
  fi

  BINDING_OVERMIND_SOURCE_PATH="$(yaml_get_scalar "$PROJECT_BINDING_FILE" "overmind_source_path" || true)"
  BINDING_PROJECT_ID="$(yaml_get_scalar "$PROJECT_BINDING_FILE" "project_id" || true)"
  BINDING_WORKER_UUID="$(yaml_get_scalar "$PROJECT_BINDING_FILE" "worker_uuid" || true)"
  BINDING_WORKER_CLASS="$(yaml_get_scalar "$PROJECT_BINDING_FILE" "class" || true)"
  BINDING_WORKER_STATUS="$(yaml_get_scalar "$PROJECT_BINDING_FILE" "status" || true)"

  if [[ -z "$BINDING_WORKER_UUID" ]]; then
    die "Binding file is invalid: missing worker_uuid in $(repo_relpath "$PROJECT_BINDING_FILE")."
  fi
  if ! is_valid_uuid "$BINDING_WORKER_UUID"; then
    die "Binding file is invalid: worker_uuid is not canonical UUID in $(repo_relpath "$PROJECT_BINDING_FILE")."
  fi

  if [[ -z "$BINDING_OVERMIND_SOURCE_PATH" ]]; then
    die "Binding file is invalid: missing overmind_source_path in $(repo_relpath "$PROJECT_BINDING_FILE")."
  fi
  if [[ -z "$BINDING_PROJECT_ID" ]]; then
    die "Binding file is invalid: missing project_id in $(repo_relpath "$PROJECT_BINDING_FILE")."
  fi
  if [[ ! -d "$BINDING_OVERMIND_SOURCE_PATH" ]]; then
    die "Bound overmind project repo does not exist: $BINDING_OVERMIND_SOURCE_PATH. Re-run .asdlc_worker/scripts/register_worker.sh."
  fi

  BOUND_PROJECT_PATH="$BINDING_OVERMIND_SOURCE_PATH"
  BOUND_FEATURES_ROOT="$BOUND_PROJECT_PATH"

  local _def_file="$BOUND_PROJECT_PATH/init_progress_definition.yaml"
  if [[ ! -f "$_def_file" ]]; then
    die "Bound overmind project repo is missing init_progress_definition.yaml: $BOUND_PROJECT_PATH. Re-run .asdlc_worker/scripts/register_worker.sh against the correct project repo."
  fi
  local _def_project_id=""
  _def_project_id="$(read_init_progress_project_id "$_def_file")"
  if [[ -z "$_def_project_id" ]]; then
    die "init_progress_definition.yaml in bound project repo is missing meta_info.project_id: $BOUND_PROJECT_PATH. Re-run .asdlc_worker/scripts/register_worker.sh."
  fi
  if [[ "$_def_project_id" != "$BINDING_PROJECT_ID" ]]; then
    die "Bound project_id '$BINDING_PROJECT_ID' does not match meta_info.project_id '$_def_project_id' in init_progress_definition.yaml. Re-run .asdlc_worker/scripts/register_worker.sh against the correct project repo."
  fi
}

ensure_runtime_branch_checked_out() {
  local current_branch=""

  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "Feature routing requires a git repository."
  fi

  ensure_start_branch_is_confirmed

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

  if [[ "$RUNTIME_BRANCH_SYNC_READY" -eq 1 ]]; then
    return 0
  fi

  current_branch="$(get_current_branch_name)"
  if [[ "$current_branch" != "$RUNTIME_BRANCH" ]]; then
    die "Failed to switch to runtime branch '$RUNTIME_BRANCH'."
  fi
  rebase_runtime_branch_onto_master_or_die
  RUNTIME_BRANCH_SYNC_READY=1
}

prompt_for_non_master_orchestrator_start() {
  local current_branch="$1"
  local answer=""

  echo "⚠️ overmind will merge (rebase) last master state and start work, but you start orchestrator NOT from master branch. Are you sure?" >&2
  echo "1. Yes I am sure, start from current branch" >&2
  echo "2. No, dont start I'll switch to master first (manually)" >&2

  if [[ ! -t 0 ]]; then
    die "Cannot start orchestrator from branch '$current_branch' in a non-interactive shell. Start from 'master' or rerun interactively."
  fi

  while true; do
    printf 'Choose 1 or 2: ' >&2
    IFS= read -r answer || answer=""
    answer="$(trim_whitespace "$answer")"
    case "$answer" in
      1)
        return 0
        ;;
      2|'')
        echo "Execution stopped: switch to 'master' manually and rerun orchestrator." >&2
        exit 1
        ;;
      *)
        echo "Please choose 1 or 2." >&2
        ;;
    esac
  done
}

ensure_start_branch_is_confirmed() {
  local current_branch=""

  if [[ "$START_BRANCH_VALIDATED" -eq 1 ]]; then
    return 0
  fi

  current_branch="$(get_current_branch_name)"
  if [[ -z "$current_branch" ]]; then
    die "Current HEAD is detached. Check out 'master' or another branch before running orchestrator."
  fi

  if [[ "$current_branch" != "master" && "$current_branch" != "$RUNTIME_BRANCH" ]]; then
    prompt_for_non_master_orchestrator_start "$current_branch"
  fi

  START_BRANCH_VALIDATED=1
}

rebase_runtime_branch_onto_master_or_die() {
  local err=""

  if ! git -C "$ROOT" show-ref --verify --quiet "refs/heads/master"; then
    die "Runtime branch '$RUNTIME_BRANCH' cannot be rebased because local branch 'master' does not exist."
  fi

  if ! err="$(git -C "$ROOT" rebase --autostash master 2>&1)"; then
    echo "Failed to rebase runtime branch '$RUNTIME_BRANCH' onto 'master'." >&2
    printf '%s\n' "$err" >&2
    echo "Resolve the rebase issue on branch '$RUNTIME_BRANCH' and rerun orchestrator." >&2
    exit 1
  fi
}

bound_project_repo_relpath() {
  local path="$1"
  local abs_path abs_bound
  abs_path="$(realpath "$path" 2>/dev/null)" || abs_path="$path"
  abs_bound="$(realpath "$BOUND_PROJECT_PATH" 2>/dev/null)" || abs_bound="$BOUND_PROJECT_PATH"
  if [[ "$abs_path" == "$abs_bound/"* ]]; then
    printf '%s' "${abs_path#"$abs_bound"/}"
    return 0
  fi
  if [[ "$abs_path" == "$abs_bound" ]]; then
    printf '.'
    return 0
  fi
  return 1
}

ensure_bound_project_git_ready() {
  local err=""
  local default_branch=""
  local current_branch=""

  if [[ -z "$BOUND_PROJECT_PATH" ]]; then
    die "Default mode requires a bound ASDLC project repo path."
  fi

  if ! err="$(git -C "$BOUND_PROJECT_PATH" rev-parse --is-inside-work-tree 2>&1)"; then
    die "Default mode requires the bound ASDLC project path to be a Git worktree: $BOUND_PROJECT_PATH. Fix the repo checkout."
  fi

  default_branch="$(git -C "$BOUND_PROJECT_PATH" symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|^origin/||' || true)"
  if [[ -z "$default_branch" ]]; then
    default_branch="master"
  fi

  current_branch="$(git -C "$BOUND_PROJECT_PATH" branch --show-current 2>/dev/null || true)"
  if [[ "$current_branch" != "$default_branch" ]]; then
    if ! err="$(git -C "$BOUND_PROJECT_PATH" checkout "$default_branch" 2>&1)"; then
      die "Failed to checkout '$default_branch' in bound ASDLC project repo $BOUND_PROJECT_PATH: $err"
    fi
  fi
}

run_bound_project_pull_rebase_or_die() {
  local sync_reason="$1"
  local err=""

  ensure_bound_project_git_ready
  if ! err="$(git -C "$BOUND_PROJECT_PATH" pull --rebase 2>&1)"; then
    local dirty_plan=""
    dirty_plan="$(git -C "$BOUND_PROJECT_PATH" diff --name-only HEAD -- '*/implementation_plan.md' 2>/dev/null | head -1 || true)"
    if [[ -n "$dirty_plan" ]]; then
      echo "Bound-source plan is dirty: $BOUND_PROJECT_PATH/$dirty_plan" >&2
      echo "Commit, stash, or restore the plan before rerunning: git -C '$BOUND_PROJECT_PATH' restore -- '$dirty_plan'" >&2
      exit 1
    fi
    echo "Failed to sync the bound ASDLC project repo $sync_reason: $BOUND_PROJECT_PATH" >&2
    printf '%s\n' "$err" >&2
    echo "Resolve the ASDLC repo rebase conflict or dirty state in $BOUND_PROJECT_PATH and rerun orchestrator." >&2
    exit 1
  fi
}

ensure_bound_project_synced_for_default_mode() {
  if [[ "$BOUND_PROJECT_SYNC_READY" -eq 1 ]]; then
    return 0
  fi

  run_bound_project_pull_rebase_or_die "before default-mode feature discovery and artifact mirroring"
  BOUND_PROJECT_SYNC_READY=1
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
      step_count = 0
      assigned_any = 0
      requested_match = 0
      step_num = ""
    }
    /^### Step / {
      line = $0
      sub(/^### Step /, "", line)
      split(line, parts, " ")
      step_num = parts[1]
      step_order[step_count++] = step_num
      dep_list[step_num] = ""
      has_dep_line[step_num] = 0
      bullet_count[step_num] = 0
      unchecked_count[step_num] = 0
      assigned_to_worker[step_num] = 0
      next
    }
    /^#### Depends on:[[:space:]]*/ {
      if (step_num != "") {
        line = $0
        sub(/^#### Depends on:[[:space:]]*/, "", line)
        dep_list[step_num] = trim(line)
        has_dep_line[step_num] = 1
      }
      next
    }
    /^#### Assigned:[[:space:]]*/ {
      line = $0
      sub(/^#### Assigned:[[:space:]]*/, "", line)
      uuid = trim(line)
      if (step_num != "" && uuid == target_uuid) {
        assigned_any = 1
        assigned_to_worker[step_num] = 1
        if (requested_step != "" && step_num == requested_step) {
          requested_match = 1
        }
      }
      next
    }
    /^- \[ \]/ {
      if (step_num != "") {
        bullet_count[step_num]++
        unchecked_count[step_num]++
      }
      next
    }
    /^- \[x\]/ {
      if (step_num != "") {
        bullet_count[step_num]++
      }
      next
    }
    END {
      first_unchecked = ""
      blocked_by = ""

      for (i = 0; i < step_count; i++) {
        s = step_order[i]
        if (!assigned_to_worker[s] || unchecked_count[s] == 0) continue

        if (!has_dep_line[s] || dep_list[s] == "" || dep_list[s] == "none") {
          first_unchecked = s
          break
        }

        n = split(dep_list[s], deps, ",")
        dep_ok = 1
        this_blocked_by = ""
        for (j = 1; j <= n; j++) {
          d = trim(deps[j])
          if (d == "") continue
          found = 0
          for (k = 0; k < step_count; k++) {
            if (step_order[k] == d) { found = 1; break }
          }
          if (!found) {
            print "plan error: step " s " depends on " d " which does not exist in the plan" > "/dev/stderr"
            exit 2
          }
          if (bullet_count[d] == 0) {
            print "plan error: dep step " d " has zero bullets and cannot be considered complete" > "/dev/stderr"
            exit 2
          }
          if (unchecked_count[d] > 0) {
            dep_ok = 0
            this_blocked_by = d
            break
          }
        }

        if (dep_ok) {
          first_unchecked = s
          break
        } else if (blocked_by == "") {
          blocked_by = this_blocked_by
        }
      }

      printf "%d|%d|%s|%s", assigned_any, requested_match, first_unchecked, blocked_by
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

  # Build display list, reordering to place CURRENT_FEATURE_SWITCH_FROM_ID first if found.
  local -a display_ids=()
  local -a orig_indices=()
  local current_found_at=-1
  local _pfi_i=0
  while [[ $_pfi_i -lt ${#feature_ids[@]} ]]; do
    if [[ -n "$CURRENT_FEATURE_SWITCH_FROM_ID" && "${feature_ids[$_pfi_i]}" == "$CURRENT_FEATURE_SWITCH_FROM_ID" ]]; then
      current_found_at="$_pfi_i"
    fi
    _pfi_i=$((_pfi_i + 1))
  done

  if [[ "$current_found_at" -ge 0 ]]; then
    display_ids+=("${feature_ids[$current_found_at]} (CURRENT)")
    orig_indices+=("$current_found_at")
    local _pfi_j=0
    while [[ $_pfi_j -lt ${#feature_ids[@]} ]]; do
      if [[ "$_pfi_j" -ne "$current_found_at" ]]; then
        display_ids+=("${feature_ids[$_pfi_j]}")
        orig_indices+=("$_pfi_j")
      fi
      _pfi_j=$((_pfi_j + 1))
    done
  else
    local _pfi_k=0
    while [[ $_pfi_k -lt ${#feature_ids[@]} ]]; do
      display_ids+=("${feature_ids[$_pfi_k]}")
      orig_indices+=("$_pfi_k")
      _pfi_k=$((_pfi_k + 1))
    done
  fi

  if [[ ! -t 0 ]]; then
    die "Multiple candidate features were found for worker '$BINDING_WORKER_UUID'. Run in an interactive terminal to choose a feature."
  fi

  echo "Multiple candidate features found under project '$BINDING_PROJECT_ID' for worker '$BINDING_WORKER_UUID':" >&2
  local _pfi_d=0
  while [[ $_pfi_d -lt ${#display_ids[@]} ]]; do
    printf '  %d) %s\n' "$((_pfi_d + 1))" "${display_ids[$_pfi_d]}" >&2
    _pfi_d=$((_pfi_d + 1))
  done

  while true; do
    printf 'Select feature number: ' >&2
    IFS= read -r selected || selected=""
    selected="$(trim_whitespace "$selected")"
    if [[ "$selected" =~ ^[0-9]+$ ]] && [[ "$selected" -ge 1 ]] && [[ "$selected" -le "${#display_ids[@]}" ]]; then
      printf '%s' "${orig_indices[$((selected - 1))]}"
      return 0
    fi
    echo "Invalid selection. Enter a number between 1 and ${#display_ids[@]}." >&2
  done
}

write_feature_meta_sync_metadata() {
  local selected_step="$1"
  local tmp_path="${FEATURE_META_SYNC_FILE}.tmp"

  ensure_dir_writable "$(dirname "$FEATURE_META_SYNC_FILE")"
  {
    printf "project_id: '%s'\n" "$(yaml_quote_single "$BINDING_PROJECT_ID")"
    printf "worker_uuid: '%s'\n" "$(yaml_quote_single "$BINDING_WORKER_UUID")"
    printf "feature_id: '%s'\n" "$(yaml_quote_single "$SELECTED_FEATURE_ID")"
    printf "selected_step: '%s'\n" "$(yaml_quote_single "$selected_step")"
  } >"$tmp_path"
  mv "$tmp_path" "$FEATURE_META_SYNC_FILE"
}

try_reuse_feature_meta_sync_for_resume() {
  local requested_step="$1"
  local feature_project_id=""
  local feature_worker_uuid=""
  local feature_id=""
  local selected_step=""
  local source_plan=""
  local source_ears=""

  if [[ ! -f "$FEATURE_META_SYNC_FILE" ]]; then
    return 1
  fi

  feature_project_id="$(yaml_get_scalar "$FEATURE_META_SYNC_FILE" "project_id" || true)"
  feature_worker_uuid="$(yaml_get_scalar "$FEATURE_META_SYNC_FILE" "worker_uuid" || true)"
  feature_id="$(yaml_get_scalar "$FEATURE_META_SYNC_FILE" "feature_id" || true)"
  selected_step="$(yaml_get_scalar "$FEATURE_META_SYNC_FILE" "selected_step" || true)"

  if [[ "$feature_project_id" != "$BINDING_PROJECT_ID" ]]; then
    return 1
  fi
  if [[ "$feature_worker_uuid" != "$BINDING_WORKER_UUID" ]]; then
    return 1
  fi
  if [[ -z "$feature_id" ]]; then
    return 1
  fi

  source_plan="$BOUND_FEATURES_ROOT/$feature_id/implementation_plan.md"
  source_ears="$BOUND_FEATURES_ROOT/$feature_id/requirements_ears.md"

  if [[ ! -f "$source_plan" || ! -f "$source_ears" ]]; then
    return 1
  fi
  if ! grep -q '[^[:space:]]' "$source_ears"; then
    return 1
  fi
  if [[ -n "$requested_step" ]] && ! plan_has_assigned_step_for_worker "$source_plan" "$BINDING_WORKER_UUID" "$requested_step"; then
    return 1
  fi

  SELECTED_FEATURE_ID="$feature_id"
  SELECTED_FEATURE_PATH="$BOUND_FEATURES_ROOT/$feature_id"
  SELECTED_SOURCE_PLAN_PATH="$source_plan"
  SELECTED_SOURCE_EARS_PATH="$source_ears"
  SELECTED_SELECTION_MODE="resume_reuse"
  SELECTED_REQUESTED_STEP="$requested_step"
  if [[ -n "$requested_step" ]]; then
    SELECTED_STEP="$requested_step"
  elif [[ -n "$selected_step" ]]; then
    SELECTED_STEP="$selected_step"
  fi
  return 0
}

setup_feature_plan_paths() {
  local selected_step="$1"
  local plan_rel=""
  local plan_status=""

  if [[ ! -f "$SELECTED_SOURCE_PLAN_PATH" ]]; then
    die "Selected feature plan is missing: $SELECTED_SOURCE_PLAN_PATH"
  fi
  if [[ ! -f "$SELECTED_SOURCE_EARS_PATH" ]]; then
    die "Selected feature requirements_ears.md is missing: $SELECTED_SOURCE_EARS_PATH"
  fi
  if ! grep -q '[^[:space:]]' "$SELECTED_SOURCE_EARS_PATH"; then
    die "Selected feature requirements_ears.md is unusable (empty): $SELECTED_SOURCE_EARS_PATH"
  fi

  if plan_rel="$(bound_project_repo_relpath "$SELECTED_SOURCE_PLAN_PATH" 2>/dev/null)"; then
    if plan_status="$(git -C "$BOUND_PROJECT_PATH" status --short -- "$plan_rel" 2>/dev/null)"; then
      if [[ -n "$plan_status" ]]; then
        echo "orchestrator: bound-source plan has uncommitted changes: $SELECTED_SOURCE_PLAN_PATH" >&2
        echo "Commit, stash, or restore the file in the bound project repo before rerunning:" >&2
        echo "  git -C '$BOUND_PROJECT_PATH' commit -m 'save' -- '$plan_rel'" >&2
        echo "  git -C '$BOUND_PROJECT_PATH' stash" >&2
        echo "  git -C '$BOUND_PROJECT_PATH' restore -- '$plan_rel'" >&2
        die "Bound-source plan is dirty: $SELECTED_SOURCE_PLAN_PATH"
      fi
    fi
  fi

  IMPLEMENTATION_PLAN_PRIMARY="$SELECTED_SOURCE_PLAN_PATH"
  RUNTIME_REQUIREMENTS_PATH="$SELECTED_SOURCE_EARS_PATH"
  IMPLEMENTATION_PLAN_FILE="$IMPLEMENTATION_PLAN_PRIMARY"
  export ASDLC_RUNTIME_PLAN_PATH="$SELECTED_SOURCE_PLAN_PATH"
  export ASDLC_RUNTIME_EARS_PATH="$SELECTED_SOURCE_EARS_PATH"

  write_feature_meta_sync_metadata "$selected_step"
}


_prompt_exhausted_feature_cleanup() {
  printf '\nFeature '\''%s'\'' is exhausted — all assigned bullets are complete.\n' "$SELECTED_FEATURE_ID" >&2
  printf 'To start a new feature, .asdlc_worker/feature_meta_sync.yaml must be removed.\n\n' >&2
  printf '  1. Yes, delete it for me\n' >&2
  printf '  2. Dismissed, I'\''ll do it myself\n\n' >&2
  local choice
  while true; do
    printf 'Choose 1 or 2: ' >&2
    IFS= read -r choice
    case "$choice" in
      1)
        rm -f "$FEATURE_META_SYNC_FILE"
        echo "feature_meta_sync.yaml deleted. Re-run orchestrator to select a new feature." >&2
        exit 0
        ;;
      2)
        echo "Remove .asdlc_worker/feature_meta_sync.yaml when ready, then re-run orchestrator." >&2
        exit 0
        ;;
      *)
        printf 'Invalid choice. ' >&2
        ;;
    esac
  done
}

_try_fast_path_feature_context() {
  local requested_step="$1"
  local resume_mode="$2"

  if ! try_reuse_feature_meta_sync_for_resume "$requested_step"; then
    return 1
  fi

  if [[ -z "$requested_step" ]]; then
    local _fa _ri _fu _bb _analysis
    _analysis="$(analyze_feature_plan_for_worker "$SELECTED_SOURCE_PLAN_PATH" "$BINDING_WORKER_UUID" "")"
    IFS='|' read -r _fa _ri _fu _bb <<<"$_analysis"
    if [[ -n "$_fu" ]]; then
      SELECTED_STEP="$_fu"
      if [[ "$resume_mode" -eq 0 && -t 0 ]]; then
        printf '\nCurrent feature: '\''%s'\'' (step %s)\n\n' "$SELECTED_FEATURE_ID" "$_fu" >&2
        printf '  1. Proceed with current feature\n' >&2
        printf '  2. Change feature\n\n' >&2
        local _choice
        while true; do
          printf 'Choose 1 or 2: ' >&2
          IFS= read -r _choice
          case "$_choice" in
            1) break ;;
            2)
              CURRENT_FEATURE_SWITCH_FROM_ID="$SELECTED_FEATURE_ID"
              SELECTED_FEATURE_ID=""
              SELECTED_FEATURE_PATH=""
              SELECTED_SOURCE_PLAN_PATH=""
              SELECTED_SOURCE_EARS_PATH=""
              SELECTED_STEP=""
              return 1
              ;;
            *) printf 'Invalid choice. ' >&2 ;;
          esac
        done
      fi
    elif [[ -n "$_bb" ]]; then
      die "Feature '$SELECTED_FEATURE_ID' is blocked: assigned step is gated by step '$_bb'."
    else
      if [[ -t 0 ]]; then
        _prompt_exhausted_feature_cleanup
      else
        die "Feature '$SELECTED_FEATURE_ID' is exhausted — all assigned bullets are complete. Remove .asdlc_worker/feature_meta_sync.yaml to select a new feature."
      fi
    fi
  fi

  setup_feature_plan_paths "$SELECTED_STEP"
  FEATURE_CONTEXT_READY=1
  FEATURE_CONTEXT_REQUESTED_STEP="$requested_step"
  FEATURE_CONTEXT_RESUME_MODE="$resume_mode"
  echo "orchestrator: selected feature '$SELECTED_FEATURE_ID' (mode=$SELECTED_SELECTION_MODE, project=$BINDING_PROJECT_ID, step=$SELECTED_STEP)." >&2
  return 0
}

ensure_feature_runtime_context() {
  local requested_step="${1:-}"
  local resume_mode="${2:-0}"
  local start_branch=""

  if [[ "$FEATURE_CONTEXT_READY" -eq 1 ]] && [[ "$FEATURE_CONTEXT_REQUESTED_STEP" == "$requested_step" ]] && [[ "$FEATURE_CONTEXT_RESUME_MODE" -eq "$resume_mode" ]]; then
    return 0
  fi

  start_branch="$(get_current_branch_name)"

  # Fast path: reuse existing feature meta sync without switching to the runtime branch.
  # Only attempted when the binding file is accessible on the current branch.
  # Handles --resume runs and re-invocations on an already-started feature.
  # Starting from master must still reach overmind first so step branches fork
  # from the runtime branch instead of from master.
  if [[ -n "$start_branch" ]] && [[ "$start_branch" != "master" ]] && [[ -f "$PROJECT_BINDING_FILE" ]]; then
    load_project_binding
    ensure_bound_project_synced_for_default_mode

    if _try_fast_path_feature_context "$requested_step" "$resume_mode"; then
      return 0
    fi
  fi

  # Slow path: switch to runtime branch first (where the binding file lives),
  # then load binding and discover the feature.
  ensure_runtime_branch_checked_out
  load_project_binding
  ensure_bound_project_synced_for_default_mode

  if [[ "$start_branch" == "master" ]] && _try_fast_path_feature_context "$requested_step" "$resume_mode"; then
    return 0
  fi

  local -a candidate_feature_ids=()
  local -a candidate_feature_paths=()
  local -a candidate_plan_paths=()
  local -a candidate_ears_paths=()
  local -a candidate_first_steps=()
  local features_dir=""
  local assigned_feature_count=0
  local assigned_with_unchecked_count=0
  local last_blocked_by=""

  while IFS= read -r features_dir; do
    [[ -n "$features_dir" ]] || continue
    local feature_id=""
    local plan_path=""
    local ears_path=""
    local analysis=""
    local assigned_any=0
    local requested_match=0
    local first_unchecked=""
    local blocked_by=""

    feature_id="$(basename "$features_dir")"
    plan_path="$features_dir/implementation_plan.md"
    ears_path="$features_dir/requirements_ears.md"
    [[ -f "$plan_path" ]] || continue

    analysis="$(analyze_feature_plan_for_worker "$plan_path" "$BINDING_WORKER_UUID" "$requested_step")"
    IFS='|' read -r assigned_any requested_match first_unchecked blocked_by <<<"$analysis"

    if [[ "$assigned_any" -eq 1 ]]; then
      assigned_feature_count=$((assigned_feature_count + 1))
      if [[ -n "$first_unchecked" ]]; then
        assigned_with_unchecked_count=$((assigned_with_unchecked_count + 1))
      elif [[ -n "$blocked_by" ]]; then
        last_blocked_by="$blocked_by"
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
  done < <(find "$BOUND_FEATURES_ROOT" -mindepth 1 -maxdepth 1 -type d -not -name '.git' -print | LC_ALL=C sort)

  if [[ "$assigned_feature_count" -eq 0 ]]; then
    die "No feature under bound project '$BINDING_PROJECT_ID' contains assigned steps for worker UUID '$BINDING_WORKER_UUID'."
  fi

  if [[ ${#candidate_feature_ids[@]} -eq 0 ]]; then
    if [[ -n "$requested_step" ]]; then
      die "No candidate features under project '$BINDING_PROJECT_ID' contain requested step '$requested_step' assigned to worker '$BINDING_WORKER_UUID'."
    fi
    if [[ "$assigned_with_unchecked_count" -eq 0 ]]; then
      if [[ -n "$last_blocked_by" ]]; then
        die "Assigned step for worker '$BINDING_WORKER_UUID' is blocked by step '$last_blocked_by' under project '$BINDING_PROJECT_ID'."
      fi
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

  setup_feature_plan_paths "$SELECTED_STEP"
  FEATURE_CONTEXT_READY=1
  FEATURE_CONTEXT_REQUESTED_STEP="$requested_step"
  FEATURE_CONTEXT_RESUME_MODE="$resume_mode"
  CURRENT_FEATURE_SWITCH_FROM_ID=""
  echo "orchestrator: selected feature '$SELECTED_FEATURE_ID' (mode=$SELECTED_SELECTION_MODE, project=$BINDING_PROJECT_ID, step=$SELECTED_STEP)." >&2
}

ensure_runtime_context() {
  local requested_step="${1:-}"
  local resume_mode="${2:-0}"
  ensure_feature_runtime_context "$requested_step" "$resume_mode"
}

get_first_unchecked_step() {
  ensure_runtime_context "" "${RESUME_MODE:-0}"
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
  if [[ "$branch" =~ ^step-([0-9]+([.][0-9]+)*)-[^-].*-(plan|implementation|user-review|review|ai-audit)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

get_preferred_step_plan() {
  local branch step plan latest
  branch="$(get_current_branch_name)"
  if step="$(get_step_from_branch_name "$branch")"; then
    plan="$ASDLC_STEP_PLANS_DIR/step-$step-$SELECTED_FEATURE_ID.md"
    if [[ -f "$plan" ]]; then
      printf '%s' "$plan"
      return 0
    fi
  fi
  if latest="$(get_latest_step_plan "$SELECTED_FEATURE_ID" 2>/dev/null)"; then
    printf '%s' "$latest"
    return 0
  fi
  if [[ -n "$SELECTED_STEP" ]]; then
    printf '%s' "$ASDLC_STEP_PLANS_DIR/step-$SELECTED_STEP-$SELECTED_FEATURE_ID.md"
    return 0
  fi
  echo "No step plans found for feature '$SELECTED_FEATURE_ID'." >&2
  return 1
}

run_implementation_phase() {
  load_model_config "implementation"

  local latest_plan step design_file branch_name implementation_context_script implementation_readiness_script
  if [[ -n "$RESUME_STEP" ]]; then
    step="$RESUME_STEP"
    latest_plan="$ASDLC_STEP_PLANS_DIR/step-$step-$SELECTED_FEATURE_ID.md"
  else
    latest_plan="$(get_preferred_step_plan)"
    step="$(get_step_from_plan_path "$latest_plan")"
  fi

  if [[ ! -f "$latest_plan" ]]; then
    if [[ "$DRY_RUN" -eq 1 && "$RESUME_MODE" -eq 0 ]]; then
      return 0
    fi
    echo "Step plan not found: $latest_plan" >&2
    exit 1
  fi

  if [[ -z "$step" ]]; then
    echo "Could not determine step from plan file: $latest_plan" >&2
    exit 1
  fi

  design_file="$ASDLC_STEP_DESIGNS_DIR/step-$step-$SELECTED_FEATURE_ID-design.md"
  branch_name="step-$step-$SELECTED_FEATURE_ID-implementation"
  implementation_context_script="$ROOT/.codex/skills/yasdef-worker-implementation/scripts/build_implementation_context.py"
  implementation_readiness_script="$ROOT/.codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py"

  if [[ ! -f "$design_file" ]]; then
    die "Implementation requires the design artifact to exist first: $(repo_relpath "$design_file")"
  fi
  if [[ ! -f "$implementation_context_script" ]]; then
    die "Implementation requires the installed context script: $(repo_relpath "$implementation_context_script")"
  fi
  if [[ ! -f "$implementation_readiness_script" ]]; then
    die "Implementation requires the installed readiness script: $(repo_relpath "$implementation_readiness_script")"
  fi

  local prompt_arg
  prompt_arg=$(cat <<EOF
Use the \`yasdef-worker-implementation\` skill to run the ASDLC worker implementation phase.

Inputs:
- Step: $step
- Feature id: $SELECTED_FEATURE_ID
- Branch: $branch_name
- Step plan: $latest_plan
- Design artifact: $design_file
- Runtime implementation plan: $ASDLC_RUNTIME_PLAN_PATH
EOF
)

  if [[ "$DRY_RUN" -eq 1 ]]; then
    build_phase_cmd "<inline yasdef-worker-implementation prompt>"
    echo "dry-run log: $(repo_relpath "$(resolve_log_path "implementation" "$step")")"
    echo "run yasdef-worker-implementation for step $step: $(shell_join "${BUILD_PHASE_CMD[@]}")"
    return 0
  fi

  ensure_phase_branch "$branch_name"
  build_phase_cmd "$prompt_arg"
  local status=0
  if run_with_output_log "implementation" "$step" "${BUILD_PHASE_CMD[@]}"; then
    status=0
  else
    status=$?
  fi

  return "$status"
}

run_user_review_phase() {
  load_model_config "user_review"

  local latest_plan step design_file branch_name user_review_skill
  if [[ -n "$RESUME_STEP" ]]; then
    step="$RESUME_STEP"
    latest_plan="$ASDLC_STEP_PLANS_DIR/step-$step-$SELECTED_FEATURE_ID.md"
  else
    latest_plan="$(get_preferred_step_plan)"
    step="$(get_step_from_plan_path "$latest_plan")"
  fi

  if [[ ! -f "$latest_plan" ]]; then
    if [[ "$DRY_RUN" -eq 1 && "$RESUME_MODE" -eq 0 ]]; then
      return 0
    fi
    echo "Step plan not found: $latest_plan" >&2
    exit 1
  fi

  if [[ -z "$step" ]]; then
    echo "Could not determine step from plan file: $latest_plan" >&2
    exit 1
  fi

  design_file="$ASDLC_STEP_DESIGNS_DIR/step-$step-$SELECTED_FEATURE_ID-design.md"
  branch_name="step-$step-$SELECTED_FEATURE_ID-user-review"
  user_review_skill="$ROOT/.codex/skills/yasdef-worker-user-review/SKILL.md"

  if [[ ! -f "$design_file" ]]; then
    die "User review requires the design artifact to exist first: $(repo_relpath "$design_file")"
  fi
  if [[ ! -f "$user_review_skill" ]]; then
    die "User review requires the installed skill: $(repo_relpath "$user_review_skill")"
  fi

  local prompt_arg
  prompt_arg=$(cat <<EOF
Use the \`yasdef-worker-user-review\` skill to run the ASDLC worker user review phase.

Inputs:
- Step: $step
- Feature id: $SELECTED_FEATURE_ID
- Branch: $branch_name
- Step plan: $latest_plan
- Design artifact: $design_file
- Runtime implementation plan: $ASDLC_RUNTIME_PLAN_PATH
EOF
)

  if [[ "$DRY_RUN" -eq 1 ]]; then
    build_phase_cmd "<inline yasdef-worker-user-review prompt>"
    echo "dry-run log: $(repo_relpath "$(resolve_log_path "user_review" "$step")")"
    echo "run yasdef-worker-user-review for step $step: $(shell_join "${BUILD_PHASE_CMD[@]}")"
    return 0
  fi

  local implementation_readiness_script="$ROOT/.codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py"
  if [[ -f "$implementation_readiness_script" ]]; then
    local readiness_output readiness_status=0
    readiness_output="$(uv run python "$implementation_readiness_script" --step "$step" --step-plan "$latest_plan" 2>&1)" || readiness_status=$?
    if [[ "$readiness_status" -ne 0 ]]; then
      echo "User review precheck failed for step $step." >&2
      printf '%s\n' "$readiness_output" >&2
      echo "Implementation was not finished correctly." >&2
      exit 1
    fi
  fi

  ensure_user_review_branch "$step" "$SELECTED_FEATURE_ID"
  build_phase_cmd "$prompt_arg"
  local status=0
  if run_with_output_log "user_review" "$step" "${BUILD_PHASE_CMD[@]}"; then
    status=0
  else
    status=$?
  fi

  return "$status"
}

run_ai_audit_phase() {
  load_model_config "ai_audit"

  local latest_plan step design_file branch_name
  if [[ -n "$RESUME_STEP" ]]; then
    step="$RESUME_STEP"
    latest_plan="$ASDLC_STEP_PLANS_DIR/step-$step-$SELECTED_FEATURE_ID.md"
  else
    latest_plan="$(get_preferred_step_plan)"
    step="$(get_step_from_plan_path "$latest_plan")"
  fi

  if [[ ! -f "$latest_plan" ]]; then
    if [[ "$DRY_RUN" -eq 1 && "$RESUME_MODE" -eq 0 ]]; then
      return 0
    fi
    echo "Step plan not found: $latest_plan" >&2
    exit 1
  fi

  if [[ -z "$step" ]]; then
    echo "Could not determine step from plan file: $latest_plan" >&2
    exit 1
  fi

  if [[ "$DRY_RUN" -eq 0 ]] && ! user_review_branch_exists_for_step "$step"; then
    echo "Cannot start ai_audit for step $step: user_review phase is incomplete." >&2
    echo "Run: .asdlc_worker/scripts/orchestrator.sh --resume $step" >&2
    exit 1
  fi

  design_file="$ASDLC_STEP_DESIGNS_DIR/step-$step-$SELECTED_FEATURE_ID-design.md"
  branch_name="step-$step-$SELECTED_FEATURE_ID-review"
  local audit_skill="$ROOT/.codex/skills/yasdef-worker-ai-audit/SKILL.md"
  local audit_entry_script="$ROOT/.codex/skills/yasdef-worker-ai-audit/scripts/check_ai_audit_entry.py"
  local audit_context_script="$ROOT/.codex/skills/yasdef-worker-ai-audit/scripts/build_ai_audit_context.py"
  local audit_closure_script="$ROOT/.codex/skills/yasdef-worker-ai-audit/scripts/check_ai_audit_closure.py"

  if [[ ! -f "$design_file" ]]; then
    die "ai_audit requires the design artifact to exist first: $(repo_relpath "$design_file")"
  fi
  if [[ ! -f "$audit_skill" || ! -f "$audit_entry_script" || ! -f "$audit_context_script" || ! -f "$audit_closure_script" ]]; then
    die "ai_audit requires the installed yasdef-worker-ai-audit skill and scripts under .codex/skills/yasdef-worker-ai-audit/"
  fi

  local prompt_arg
  prompt_arg=$(cat <<EOF
Use the \`yasdef-worker-ai-audit\` skill to run the ASDLC worker ai_audit phase.

Inputs:
- Step: $step
- Feature id: $SELECTED_FEATURE_ID
- Branch: $branch_name
- Step plan: $latest_plan
- Design artifact: $design_file
- Runtime implementation plan: $ASDLC_RUNTIME_PLAN_PATH
- Worker id: $BINDING_WORKER_UUID
EOF
)

  if [[ "$DRY_RUN" -eq 1 ]]; then
    build_phase_cmd "<inline yasdef-worker-ai-audit prompt>"
    echo "dry-run log: $(repo_relpath "$(resolve_log_path "ai_audit" "$step")")"
    echo "run yasdef-worker-ai-audit for step $step: $(shell_join "${BUILD_PHASE_CMD[@]}")"
    return 0
  fi

  ensure_ai_audit_review_branch "$step" "$SELECTED_FEATURE_ID"
  build_phase_cmd "$prompt_arg"
  local status=0
  if run_with_output_log "ai_audit" "$step" "${BUILD_PHASE_CMD[@]}"; then
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
    latest_plan="$ASDLC_STEP_PLANS_DIR/step-$step-$SELECTED_FEATURE_ID.md"
  else
    latest_plan="$(get_preferred_step_plan)"
    step="$(get_step_from_plan_path "$latest_plan")"
  fi

  if [[ ! -f "$latest_plan" ]]; then
    if [[ "$DRY_RUN" -eq 1 && "$RESUME_MODE" -eq 0 ]]; then
      return 0
    fi
    echo "Step plan not found: $latest_plan" >&2
    exit 1
  fi

  if [[ -z "$step" ]]; then
    echo "Could not determine step from plan file: $latest_plan" >&2
    exit 1
  fi

  if [[ "$DRY_RUN" -eq 0 ]]; then
    local review_artifact="$ASDLC_STEP_REVIEW_RESULTS_DIR/review_result-$step-$SELECTED_FEATURE_ID.md"
    if [[ ! -f "$review_artifact" ]]; then
      echo "Cannot start post_review for step $step: ai_audit phase is incomplete." >&2
      echo "Run: .asdlc_worker/scripts/orchestrator.sh --resume $step" >&2
      exit 1
    fi
  fi

  local cmd=("$ASDLC_SCRIPTS_DIR/post_review.sh" --step "$step" --feature-id "$SELECTED_FEATURE_ID")
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

commit_selected_source_plan_update_if_needed() {
  local step="$1"
  local plan_rel=""
  local raised_questions_dir=""
  local raised_questions_rel=""
  local has_changes=0
  local err=""
  local commit_message=""

  ensure_bound_project_git_ready

  if ! plan_rel="$(bound_project_repo_relpath "$SELECTED_SOURCE_PLAN_PATH")"; then
    echo "Global implementation-plan sync failed because the selected feature source plan is outside the bound ASDLC project repo." >&2
    echo "Selected feature source plan: $SELECTED_SOURCE_PLAN_PATH" >&2
    echo "Bound ASDLC project repo: $BOUND_PROJECT_PATH" >&2
    return 1
  fi

  if ! err="$(git -C "$BOUND_PROJECT_PATH" add -- "$plan_rel" 2>&1)"; then
    echo "Global implementation-plan sync failed while staging $SELECTED_SOURCE_PLAN_PATH in $BOUND_PROJECT_PATH." >&2
    printf '%s\n' "$err" >&2
    return 1
  fi

  raised_questions_dir="$(dirname "$SELECTED_SOURCE_PLAN_PATH")/raised_questions"
  if [[ -d "$raised_questions_dir" ]] \
     && raised_questions_rel="$(bound_project_repo_relpath "$raised_questions_dir" 2>/dev/null)"; then
    # raised_questions/ is optional — the audit skill creates it only when a
    # finding is raised to coordinator. Stage it only when it actually exists
    # on disk; the previous `git ls-tree HEAD -- <path>` check always exited 0
    # (even on a missing pathspec), so `git add` ran every time and failed
    # with "pathspec did not match any files" when no findings were raised.
    if ! err="$(git -C "$BOUND_PROJECT_PATH" add -- "$raised_questions_rel" 2>&1)"; then
      echo "Global implementation-plan sync failed while staging raised questions at $raised_questions_dir in $BOUND_PROJECT_PATH." >&2
      printf '%s\n' "$err" >&2
      return 1
    fi
  else
    # No raised_questions/ this round — make sure later diff and commit
    # paths don't reference a relpath that never got staged.
    raised_questions_rel=""
  fi

  if ! git -C "$BOUND_PROJECT_PATH" diff --cached --quiet -- "$plan_rel"; then
    has_changes=1
  fi
  if [[ -n "$raised_questions_rel" ]] && ! git -C "$BOUND_PROJECT_PATH" diff --cached --quiet -- "$raised_questions_rel"; then
    has_changes=1
  fi
  if [[ "$has_changes" -eq 0 ]]; then
    return 2
  fi

  commit_message="ASDLC plan sync: ${SELECTED_FEATURE_ID:-selected-feature} step $step"
  if [[ -n "$raised_questions_rel" ]]; then
    if ! err="$(git -C "$BOUND_PROJECT_PATH" commit -m "$commit_message" -- "$plan_rel" "$raised_questions_rel" 2>&1)"; then
      echo "Global implementation-plan sync failed while creating an ASDLC sync commit for $SELECTED_SOURCE_PLAN_PATH." >&2
      printf '%s\n' "$err" >&2
      return 1
    fi
  elif ! err="$(git -C "$BOUND_PROJECT_PATH" commit -m "$commit_message" -- "$plan_rel" 2>&1)"; then
    echo "Global implementation-plan sync failed while creating an ASDLC sync commit for $SELECTED_SOURCE_PLAN_PATH." >&2
    printf '%s\n' "$err" >&2
    return 1
  fi

  return 0
}

run_bound_project_pull_rebase_for_outbound_sync() {
  ensure_bound_project_git_ready
  local err=""
  if ! err="$(git -C "$BOUND_PROJECT_PATH" pull --rebase 2>&1)"; then
    echo "Global implementation-plan sync failed while rebasing the bound ASDLC project repo: $BOUND_PROJECT_PATH" >&2
    echo "Selected feature source plan: $SELECTED_SOURCE_PLAN_PATH" >&2
    printf '%s\n' "$err" >&2
    return 1
  fi
  return 0
}

push_selected_source_plan_sync_commit() {
  local err=""
  if ! err="$(git -C "$BOUND_PROJECT_PATH" push 2>&1)"; then
    echo "Global implementation-plan sync failed while pushing the ASDLC sync commit from $BOUND_PROJECT_PATH." >&2
    echo "Selected feature source plan: $SELECTED_SOURCE_PLAN_PATH" >&2
    echo "The ASDLC plan sync commit exists locally but could not be pushed." >&2
    printf '%s\n' "$err" >&2
    return 1
  fi
  return 0
}

prompt_for_outbound_sync_failure_action() {
  local answer=""

  echo "1. retry" >&2
  echo "2. finish" >&2

  if [[ ! -t 0 ]]; then
    echo "Global implementation-plan sync failed in a non-interactive shell. Rerun interactively and choose one of the two options above." >&2
    return 1
  fi

  while true; do
    printf 'Choose 1 or 2: ' >&2
    IFS= read -r answer || answer=""
    answer="$(trim_whitespace "$answer")"
    case "$answer" in
      1)
        printf 'retry'
        return 0
        ;;
      2)
        printf 'finish'
        return 0
        ;;
      *)
        echo "Please choose 1 or 2." >&2
        ;;
    esac
  done
}

run_global_plan_sync_attempt() {
  local step="$1"
  local commit_status=0

  if [[ -z "$SELECTED_SOURCE_PLAN_PATH" ]]; then
    echo "Global implementation-plan sync failed because the selected feature source plan path is unknown." >&2
    return 1
  fi

  if commit_selected_source_plan_update_if_needed "$step"; then
    commit_status=0
  else
    commit_status=$?
    if [[ "$commit_status" -ne 2 ]]; then
      return 1
    fi
  fi

  if ! run_bound_project_pull_rebase_for_outbound_sync; then
    return 1
  fi

  if ! push_selected_source_plan_sync_commit; then
    return 1
  fi

  return 0
}

get_post_review_target_step() {
  local latest_plan=""
  local step=""

  if [[ -n "$RESUME_STEP" ]]; then
    printf '%s' "$RESUME_STEP"
    return 0
  fi

  latest_plan="$(get_preferred_step_plan)"
  step="$(get_step_from_plan_path "$latest_plan")"
  if [[ -z "$step" ]]; then
    die "Could not determine step from plan file: $latest_plan"
  fi
  printf '%s' "$step"
}

run_global_plan_sync_before_post_review() {
  local step="$1"
  local review_artifact="$ASDLC_STEP_REVIEW_RESULTS_DIR/review_result-$step-$SELECTED_FEATURE_ID.md"
  local action=""

  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  if [[ ! -f "$review_artifact" ]]; then
    return 0
  fi

  echo "orchestrator: work for step '$step' is finished, and orchestrator is trying to sync implementation-plan/raised-questions updates with the bound ASDLC repo." >&2
  while true; do
    if run_global_plan_sync_attempt "$step"; then
      return 0
    fi
    if ! action="$(prompt_for_outbound_sync_failure_action)"; then
      exit 1
    fi
    if [[ "$action" == "finish" ]]; then
      echo "orchestrator: skipping global implementation-plan sync for step '$step' and continuing to post_review." >&2
      return 0
    fi
  done
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

evaluate_design_phase() {
  local step="$1"
  local design_file="$ASDLC_STEP_DESIGNS_DIR/step-$step-$SELECTED_FEATURE_ID-design.md"
  if [[ ! -f "$design_file" ]]; then
    phase_eval_set "design" "incomplete" "missing .asdlc_worker/step_designs/step-$step-$SELECTED_FEATURE_ID-design.md"
    return 0
  fi

  phase_eval_set "design" "complete" "design artifact present"
}

evaluate_planning_phase() {
  local step="$1"
  local counts="$2"
  local plan_checked have_review review_checked impl_total impl_checked
  local step_plan="$ASDLC_STEP_PLANS_DIR/step-$step-$SELECTED_FEATURE_ID.md"

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
  local branch="step-$step-$SELECTED_FEATURE_ID-implementation"
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi
  git -C "$ROOT" show-ref --verify --quiet "refs/heads/$branch"
}

is_implementation_complete_for_step() {
  local step="$1"
  local review_file="$ASDLC_STEP_REVIEW_RESULTS_DIR/review_result-$step-$SELECTED_FEATURE_ID.md"

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
  local step_plan="$ASDLC_STEP_PLANS_DIR/step-$step-$SELECTED_FEATURE_ID.md"

  if [[ ! -f "$step_plan" ]]; then
    phase_eval_set "implementation" "invalid" "missing .asdlc_worker/step_plans/step-$step-$SELECTED_FEATURE_ID.md"
    return 0
  fi

  if is_implementation_complete_for_step "$step"; then
    phase_eval_set "implementation" "complete" "implementation marker detected (branch step-$step-$SELECTED_FEATURE_ID-implementation or later-phase artifact present)"
  else
    phase_eval_set "implementation" "incomplete" "missing implementation marker (expected branch step-$step-$SELECTED_FEATURE_ID-implementation)"
  fi
}

user_review_branch_exists_for_step() {
  local step="$1"
  local branch="step-$step-$SELECTED_FEATURE_ID-user-review"
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi
  git -C "$ROOT" show-ref --verify --quiet "refs/heads/$branch"
}

is_user_review_complete_for_step() {
  local step="$1"
  local review_file="$ASDLC_STEP_REVIEW_RESULTS_DIR/review_result-$step-$SELECTED_FEATURE_ID.md"

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
    phase_eval_set "user_review" "incomplete" "missing user_review marker (expected branch step-$step-$SELECTED_FEATURE_ID-user-review)"
  fi
}

evaluate_ai_audit_phase() {
  local step="$1"
  local review_file="$ASDLC_STEP_REVIEW_RESULTS_DIR/review_result-$step-$SELECTED_FEATURE_ID.md"
  if [[ ! -f "$review_file" ]]; then
    phase_eval_set "ai_audit" "incomplete" "missing .asdlc_worker/step_review_results/review_result-$step-$SELECTED_FEATURE_ID.md"
    return 0
  fi

  phase_eval_set "ai_audit" "complete" "review artifact present (disposition semantics enforced by ai_audit skill/post_review gate)"
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

  local history_file="$ASDLC_HISTORY_FILE"
  if [[ ! -f "$history_file" ]]; then
    phase_eval_set "post_review" "incomplete" "missing .asdlc_worker/history.md"
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

ensure_uv_available

REQUESTED_STEP_FOR_FEATURE_CONTEXT=""
if [[ "$RESUME_MODE" -eq 1 ]]; then
  REQUESTED_STEP_FOR_FEATURE_CONTEXT="$RESUME_STEP"
else
  REQUESTED_STEP_FOR_FEATURE_CONTEXT="$(find_explicit_step_arg "${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}" || true)"
fi
echo "orchestrator: default mode active; reading and writing plan/ears directly at bound-source paths." >&2
ensure_runtime_context "$REQUESTED_STEP_FOR_FEATURE_CONTEXT" "$RESUME_MODE"

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
  phase_key="$(canonicalize_phase_name "$phase")"
  if confirm_phase_if_interactive "$phase"; then
    if [[ "$phase_key" == "post_review" ]]; then
      run_global_plan_sync_before_post_review "$(get_post_review_target_step)"
    fi
    run_phase "$phase"
    if [[ "$ORCHESTRATION_STOP_REQUESTED" -eq 1 ]]; then
      if [[ -n "$ORCHESTRATION_STOP_REASON" ]]; then
        echo "$ORCHESTRATION_STOP_REASON" >&2
      fi
      break
    fi
    if [[ "$phase_key" == "ai_audit" ]]; then
      RAN_AI_AUDIT=1
    fi
    if [[ "$phase_key" == "post_review" ]]; then
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
      echo "  .asdlc_worker/scripts/orchestrator.sh --resume $step" >&2
    else
      echo "ai_audit phase completed." >&2
      echo "Run to continue this step:" >&2
      echo "  .asdlc_worker/scripts/orchestrator.sh" >&2
    fi
  else
    if [[ -n "$step" ]]; then
      echo "ai_audit + post_review completed for step $step." >&2
    else
      echo "ai_audit + post_review completed." >&2
    fi
  fi
  if [[ "$DEBUG_MODE" -eq 1 ]]; then
    echo "Logs: .asdlc_worker/logs (<project>-<phase>-<step>-log)." >&2
  else
    echo "Logs: .asdlc_worker/logs (<project>-<phase>-latest-log, overwritten each run)." >&2
  fi
  if [[ "$RAN_POST_REVIEW" -eq 1 ]]; then
    echo "History: .asdlc_worker/history.md (single consolidated step record updated)." >&2
  else
    echo "History: .asdlc_worker/history.md (no update; run post_review to consolidate step metrics)." >&2
  fi
fi
