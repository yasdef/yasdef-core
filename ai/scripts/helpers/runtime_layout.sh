#!/usr/bin/env bash

runtime_layout_die() {
  echo "ERROR: $*" >&2
  exit 1
}

asdlc_worker_require_runtime_layout() {
  local caller_path="${1:-}"
  local resolved_path=""
  local script_dir=""
  local scripts_dir=""
  local runtime_home=""
  local worker_repo_root=""

  if [[ -z "$caller_path" ]]; then
    runtime_layout_die "runtime layout resolver requires the caller script path."
  fi

  if ! resolved_path="$(cd "$(dirname "$caller_path")" && pwd -P)/$(basename "$caller_path")"; then
    runtime_layout_die "failed to resolve caller path: $caller_path"
  fi

  script_dir="$(dirname "$resolved_path")"
  case "$script_dir" in
    */.asdlc_worker/scripts)
      scripts_dir="$script_dir"
      ;;
    */.asdlc_worker/scripts/helpers)
      scripts_dir="$(dirname "$script_dir")"
      ;;
    *)
      runtime_layout_die "unsupported runtime layout for '$resolved_path'. Run the installed runtime from <repo>/.asdlc_worker/scripts, not from the YASDEF source checkout or a root ai/ copy."
      ;;
  esac

  runtime_home="$(dirname "$scripts_dir")"
  worker_repo_root="$(dirname "$runtime_home")"

  if [[ "$(basename "$runtime_home")" != ".asdlc_worker" ]]; then
    runtime_layout_die "unsupported runtime layout for '$resolved_path'. Expected the runtime home directory to be named .asdlc_worker."
  fi

  if [[ ! -d "$scripts_dir" ]]; then
    runtime_layout_die "runtime scripts directory is missing: $scripts_dir"
  fi

  export ASDLC_WORKER_HOME="$runtime_home"
  export WORKER_REPO_ROOT="$worker_repo_root"
  export ASDLC_SCRIPTS_DIR="$scripts_dir"
  export ASDLC_HELPERS_DIR="$scripts_dir/helpers"
  export ASDLC_PROCESS_FILE="$ASDLC_WORKER_HOME/AI_DEVELOPMENT_PROCESS.md"
  export ASDLC_MODELS_FILE="$ASDLC_WORKER_HOME/setup/models.md"
  export ASDLC_DECISIONS_FILE="$ASDLC_WORKER_HOME/decisions.md"
  export ASDLC_BLOCKER_LOG_FILE="$ASDLC_WORKER_HOME/blocker_log.md"
  export ASDLC_OPEN_QUESTIONS_FILE="$ASDLC_WORKER_HOME/open_questions.md"
  export ASDLC_USER_REVIEW_FILE="$ASDLC_WORKER_HOME/user_review.md"
  export ASDLC_HISTORY_FILE="$ASDLC_WORKER_HOME/history.md"
  export ASDLC_BINDING_FILE="$ASDLC_WORKER_HOME/project_overmind.yaml"
  export ASDLC_WORKER_BINDING_FILE="$ASDLC_WORKER_HOME/asdlc_worker.yaml"
  export ASDLC_FEATURE_SYNC_FILE="$ASDLC_WORKER_HOME/feature_meta_sync.yaml"
  export ASDLC_TEMPLATES_DIR="$ASDLC_WORKER_HOME/templates"
  export ASDLC_GOLDEN_EXAMPLES_DIR="$ASDLC_WORKER_HOME/golden_examples"
  export ASDLC_LOGS_DIR="$ASDLC_WORKER_HOME/logs"
  export ASDLC_PROMPTS_DIR="$ASDLC_WORKER_HOME/prompts"
  export ASDLC_STEP_DESIGNS_DIR="$ASDLC_WORKER_HOME/step_designs"
  export ASDLC_STEP_PLANS_DIR="$ASDLC_WORKER_HOME/step_plans"
  export ASDLC_STEP_REVIEW_RESULTS_DIR="$ASDLC_WORKER_HOME/step_review_results"
  export ASDLC_OVERMIND_DIR="$ASDLC_WORKER_HOME/overmind"
}
