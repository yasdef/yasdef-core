#!/usr/bin/env bash
# Builds the model-runner argv for an ASDLC phase.
#
# Reads globals MODEL_CMD, MODEL_MODEL, MODEL_ARGS (set by load_model_config).
# Writes the resulting argv as a bash array to BUILD_PHASE_CMD.
#
# Dispatch:
#   MODEL_CMD == "claude" -> Claude Code shape (build_claude_cmd)
#   otherwise             -> Codex shape       (build_codex_cmd)
#
# Both branches pass MODEL_ARGS through verbatim. The only difference between
# them is the model-selection flag: codex uses `-m <model>`, claude uses
# `--model <model>`. The prompt is positional in both cases so claude can open
# its interactive UI (the orchestrator's run_with_output_log wraps claude in
# `script -q` to preserve a TTY while still capturing a log).
#
# The non-claude fallback preserves the pre-CRP-134 convention in which the
# `cmd` column of models.md was treated as the executable to invoke, so test
# fixtures that substitute `echo` or a path to a fake script keep working.

BUILD_PHASE_CMD=()

build_codex_cmd() {
  local prompt="$1"
  BUILD_PHASE_CMD=("$MODEL_CMD" -m "$MODEL_MODEL")
  if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
    BUILD_PHASE_CMD+=("${MODEL_ARGS[@]}")
  fi
  BUILD_PHASE_CMD+=("$prompt")
}

build_claude_cmd() {
  local prompt="$1"
  BUILD_PHASE_CMD=("$MODEL_CMD" --model "$MODEL_MODEL")
  if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
    BUILD_PHASE_CMD+=("${MODEL_ARGS[@]}")
  fi
  BUILD_PHASE_CMD+=("$prompt")
}

build_phase_cmd() {
  local prompt="$1"
  case "$MODEL_CMD" in
    claude)
      build_claude_cmd "$prompt"
      ;;
    *)
      build_codex_cmd "$prompt"
      ;;
  esac
}
