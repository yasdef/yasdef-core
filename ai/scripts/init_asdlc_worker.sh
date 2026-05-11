#!/usr/bin/env bash
set -euo pipefail

GENERATED_DIRS=(
  "scripts"
  "golden_examples"
  "setup"
  "templates"
  "logs"
  "prompts"
)
ROOT_RUNTIME_FILES=(
  "AI_DEVELOPMENT_PROCESS.md"
  "blocker_log.md"
  "decisions.md"
  "history.md"
  "open_questions.md"
  "user_review.md"
)
GENERATED_EXCLUDE_PATHS=(
  ".asdlc_worker/scripts"
  ".asdlc_worker/scripts/helpers"
  ".asdlc_worker/golden_examples"
  ".asdlc_worker/setup"
  ".asdlc_worker/templates"
  ".asdlc_worker/logs"
  ".asdlc_worker/prompts"
  ".asdlc_worker/AI_DEVELOPMENT_PROCESS.md"
)

SOURCE_ROOT=""
SOURCE_AI_DIR=""
TARGET_INPUT=""
TARGET_REPO_ROOT=""
TARGET_RUNTIME_DIR=""
MODE="install"

usage() {
  cat <<'EOF'
Usage: ai/scripts/init_asdlc_worker.sh [--help]

Bootstraps or updates the repo-local ASDLC worker runtime by:
  1) prompting for a target repository path
  2) validating the target before any mutation
  3) running git init when the target is not already a git repository
  4) installing or updating <target-repo>/.asdlc_worker

Options:
  -h, --help       Show this help message
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

prompt_non_empty() {
  local prompt="$1"
  local out_var="$2"
  local value=""

  printf '%s' "$prompt"
  if ! IFS= read -r value; then
    die "Failed to read input."
  fi

  value="$(trim "$value")"
  if [[ -z "$value" ]]; then
    die "Input cannot be empty."
  fi

  printf -v "$out_var" '%s' "$value"
}

require_git() {
  if ! command -v git >/dev/null 2>&1; then
    die "git is not installed or not available in PATH."
  fi
}

resolve_source_root() {
  local script_dir=""
  local ai_dir=""
  local root=""

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  ai_dir="$(dirname "$script_dir")"
  root="$(dirname "$ai_dir")"

  if [[ "$(basename "$ai_dir")" != "ai" || ! -d "$root/ai/scripts" ]]; then
    die "Unsupported source layout: expected init_asdlc_worker.sh to run from the YASDEF source checkout under ai/scripts."
  fi

  printf '%s' "$root"
}

resolve_target_repo_root() {
  local input_path="$1"
  local resolved=""
  local repo_root=""

  if [[ ! -e "$input_path" ]]; then
    die "Target repository path does not exist: $input_path"
  fi

  if [[ ! -d "$input_path" ]]; then
    die "Target repository path is not a directory: $input_path"
  fi

  if ! resolved="$(cd "$input_path" && pwd -P)"; then
    die "Unable to resolve target repository path: $input_path"
  fi

  repo_root="$(git -C "$resolved" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$repo_root" ]]; then
    repo_root="$(cd "$repo_root" && pwd -P)"
    if [[ "$repo_root" != "$resolved" ]]; then
      die "Target repository path must be the git repository root, not a nested path inside '$repo_root'."
    fi
    printf '%s' "$resolved"
    return 0
  fi

  if ! git -C "$resolved" init >/dev/null 2>&1; then
    die "Failed to initialize git repository at: $resolved"
  fi

  printf '%s' "$resolved"
}

remove_generated_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    rm -rf "$path"
  fi
}

copy_dir_contents() {
  local source_dir="$1"
  local target_dir="$2"

  mkdir -p "$target_dir"
  cp -R "$source_dir/." "$target_dir/"
}

install_root_runtime_files() {
  local file=""
  for file in "${ROOT_RUNTIME_FILES[@]}"; do
    cp "$SOURCE_AI_DIR/$file" "$TARGET_RUNTIME_DIR/$file"
  done
}

install_generated_dirs() {
  local dir=""
  for dir in "${GENERATED_DIRS[@]}"; do
    remove_generated_path "$TARGET_RUNTIME_DIR/$dir"
    if [[ -d "$SOURCE_AI_DIR/$dir" ]]; then
      copy_dir_contents "$SOURCE_AI_DIR/$dir" "$TARGET_RUNTIME_DIR/$dir"
    else
      mkdir -p "$TARGET_RUNTIME_DIR/$dir"
    fi
  done
}

ensure_runtime_support_dirs() {
  mkdir -p \
    "$TARGET_RUNTIME_DIR/overmind" \
    "$TARGET_RUNTIME_DIR/step_designs" \
    "$TARGET_RUNTIME_DIR/step_plans" \
    "$TARGET_RUNTIME_DIR/step_review_results"
}

yaml_quote_single() {
  printf '%s' "$1" | sed "s/'/''/g"
}

write_worker_root_binding() {
  local binding_file="$TARGET_RUNTIME_DIR/asdlc_worker.yaml"
  local tmp_file="${binding_file}.tmp"

  {
    printf "worker_repo_root: '%s'\n" "$(yaml_quote_single "$TARGET_REPO_ROOT")"
  } >"$tmp_file"
  mv "$tmp_file" "$binding_file"
}

ensure_exclude_entries() {
  local exclude_file="$TARGET_REPO_ROOT/.git/info/exclude"
  local entry=""

  mkdir -p "$(dirname "$exclude_file")"
  touch "$exclude_file"

  for entry in "${GENERATED_EXCLUDE_PATHS[@]}"; do
    if ! grep -Fqx "$entry" "$exclude_file"; then
      printf '%s\n' "$entry" >>"$exclude_file"
    fi
  done
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  die "Unknown argument: $1"
fi

require_git
SOURCE_ROOT="$(resolve_source_root)"
SOURCE_AI_DIR="$SOURCE_ROOT/ai"

prompt_non_empty "Enter target repository path: " TARGET_INPUT
TARGET_REPO_ROOT="$(resolve_target_repo_root "$TARGET_INPUT")"
TARGET_RUNTIME_DIR="$TARGET_REPO_ROOT/.asdlc_worker"

if [[ -d "$TARGET_RUNTIME_DIR" ]]; then
  MODE="update"
else
  mkdir -p "$TARGET_RUNTIME_DIR"
fi

install_generated_dirs
if [[ "$MODE" == "install" ]]; then
  install_root_runtime_files
else
  cp "$SOURCE_AI_DIR/AI_DEVELOPMENT_PROCESS.md" "$TARGET_RUNTIME_DIR/AI_DEVELOPMENT_PROCESS.md"
fi
ensure_runtime_support_dirs
write_worker_root_binding
ensure_exclude_entries

echo "ASDLC worker runtime $MODE complete."
echo "Target repo root: $TARGET_REPO_ROOT"
echo "Runtime home: $TARGET_RUNTIME_DIR"
echo "Registration command: .asdlc_worker/scripts/register_worker.sh"
