#!/usr/bin/env bash
set -euo pipefail

GENERATED_DIRS=(
  "scripts"
  "golden_examples"
  "setup"
  "templates"
  "logs"
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
  ".asdlc_worker/AI_DEVELOPMENT_PROCESS.md"
  ".asdlc_worker/feature_meta_sync.yaml"
  ".codex/skills/yasdef-worker-plan"
  ".codex/skills/yasdef-worker-implementation"
  ".codex/skills/yasdef-worker-user-review"
  ".codex/skills/yasdef-worker-ai-audit"
  ".claude/skills/yasdef-worker-ai-audit"
  ".claude/skills/yasdef-worker-design"
  ".claude/skills/yasdef-worker-plan"
  ".claude/commands/yasdef"
)
DURABLE_COMMIT_PATHS=(
  ".codex/skills/yasdef-worker-design"
  ".codex/skills/yasdef-worker-plan"
  ".codex/skills/yasdef-worker-implementation"
  ".codex/skills/yasdef-worker-user-review"
  ".codex/skills/yasdef-worker-ai-audit"
  ".claude/skills/yasdef-worker-ai-audit"
  ".claude/skills/yasdef-worker-design"
  ".claude/skills/yasdef-worker-plan"
  ".claude/commands/yasdef/audit.md"
  ".claude/commands/yasdef/design.md"
  ".claude/commands/yasdef/plan.md"
  ".asdlc_worker/asdlc_worker.yaml"
  ".asdlc_worker/blocker_log.md"
  ".asdlc_worker/decisions.md"
  ".asdlc_worker/history.md"
  ".asdlc_worker/open_questions.md"
  ".asdlc_worker/user_review.md"
)

SOURCE_ROOT=""
SOURCE_AI_DIR=""
SOURCE_CODEX_SKILLS_DIR=""
SOURCE_CLAUDE_SKILLS_DIR=""
SOURCE_CLAUDE_COMMANDS_DIR=""
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

  remove_generated_path "$TARGET_RUNTIME_DIR/scripts/ai_plan.sh"
}

install_codex_skills() {
  local target_skills_dir="$TARGET_REPO_ROOT/.codex/skills"
  local skill_name=""

  mkdir -p "$target_skills_dir"
  for skill_name in yasdef-worker-design yasdef-worker-plan yasdef-worker-implementation yasdef-worker-user-review yasdef-worker-ai-audit; do
    local source_skill_dir="$SOURCE_CODEX_SKILLS_DIR/$skill_name"
    local target_skill_dir="$target_skills_dir/$skill_name"

    if [[ ! -d "$source_skill_dir" ]]; then
      die "Required Codex skill source is missing: $source_skill_dir"
    fi

    remove_generated_path "$target_skill_dir"
    copy_dir_contents "$source_skill_dir" "$target_skill_dir"
  done
}

install_claude_skills() {
  local target_skills_dir="$TARGET_REPO_ROOT/.claude/skills"
  local skill_name=""

  mkdir -p "$target_skills_dir"
  for skill_name in yasdef-worker-ai-audit yasdef-worker-design yasdef-worker-plan; do
    local source_skill_dir="$SOURCE_CLAUDE_SKILLS_DIR/$skill_name"
    local target_skill_dir="$target_skills_dir/$skill_name"

    if [[ ! -d "$source_skill_dir" ]]; then
      die "Required Claude skill source is missing: $source_skill_dir"
    fi

    remove_generated_path "$target_skill_dir"
    copy_dir_contents "$source_skill_dir" "$target_skill_dir"
  done
}

install_claude_commands() {
  local source_commands_dir="$SOURCE_CLAUDE_COMMANDS_DIR/yasdef"
  local target_commands_dir="$TARGET_REPO_ROOT/.claude/commands/yasdef"

  if [[ ! -d "$source_commands_dir" ]]; then
    die "Required Claude commands source is missing: $source_commands_dir"
  fi

  mkdir -p "$TARGET_REPO_ROOT/.claude/commands"
  remove_generated_path "$target_commands_dir"
  copy_dir_contents "$source_commands_dir" "$target_commands_dir"
}

ensure_runtime_support_dirs() {
  mkdir -p \
    "$TARGET_RUNTIME_DIR/overmind" \
    "$TARGET_RUNTIME_DIR/step_designs" \
    "$TARGET_RUNTIME_DIR/step_plans" \
    "$TARGET_RUNTIME_DIR/step_open_questions" \
    "$TARGET_RUNTIME_DIR/step_blockers" \
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

commit_durable_runtime_files() {
  local path=""

  for path in "${DURABLE_COMMIT_PATHS[@]}"; do
    if [[ -e "$TARGET_REPO_ROOT/$path" ]]; then
      git -C "$TARGET_REPO_ROOT" add -f "$path"
    fi
  done

  if ! git -C "$TARGET_REPO_ROOT" diff --cached --quiet -- "${DURABLE_COMMIT_PATHS[@]}"; then
    if ! git -C "$TARGET_REPO_ROOT" commit -m "asdlc worker added" -- "${DURABLE_COMMIT_PATHS[@]}" >/dev/null 2>&1; then
      die "Failed to commit ASDLC worker state files. Configure git user.name/user.email and rerun."
    fi
  fi
}

stash_remaining_worktree_changes() {
  if [[ -z "$(git -C "$TARGET_REPO_ROOT" status --porcelain --untracked-files=all 2>/dev/null || true)" ]]; then
    return 0
  fi

  if ! git -C "$TARGET_REPO_ROOT" stash push --include-untracked -m "asdlc worker init unrelated changes" >/dev/null 2>&1; then
    die "Failed to stash unrelated worktree changes after ASDLC worker init."
  fi

  echo "Stashed unrelated worktree changes: asdlc worker init unrelated changes"
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
SOURCE_CODEX_SKILLS_DIR="$SOURCE_ROOT/ai/codex/skills"
SOURCE_CLAUDE_SKILLS_DIR="$SOURCE_ROOT/ai/claude/skills"
SOURCE_CLAUDE_COMMANDS_DIR="$SOURCE_ROOT/ai/claude/commands"

prompt_non_empty "Enter target repository path: " TARGET_INPUT
TARGET_REPO_ROOT="$(resolve_target_repo_root "$TARGET_INPUT")"
TARGET_RUNTIME_DIR="$TARGET_REPO_ROOT/.asdlc_worker"

if [[ -d "$TARGET_RUNTIME_DIR" ]]; then
  MODE="update"
else
  mkdir -p "$TARGET_RUNTIME_DIR"
fi

install_generated_dirs
install_codex_skills
install_claude_skills
install_claude_commands
if [[ "$MODE" == "install" ]]; then
  install_root_runtime_files
else
  cp "$SOURCE_AI_DIR/AI_DEVELOPMENT_PROCESS.md" "$TARGET_RUNTIME_DIR/AI_DEVELOPMENT_PROCESS.md"
fi
ensure_runtime_support_dirs
write_worker_root_binding
ensure_exclude_entries
commit_durable_runtime_files
if [[ "$MODE" == "install" ]]; then
  stash_remaining_worktree_changes
fi

echo "ASDLC worker runtime $MODE complete."
echo "Target repo root: $TARGET_REPO_ROOT"
echo "Runtime home: $TARGET_RUNTIME_DIR"
echo "Registration command: .asdlc_worker/scripts/register_worker.sh"
