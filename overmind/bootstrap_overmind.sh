#!/usr/bin/env bash
set -euo pipefail

BRANCH_NAME="overmind"
REGISTRY_FILE="worker_registry.yaml"
REMOTE_NAME="origin"

usage() {
  cat <<'EOF'
Usage: overmind/bootstrap_overmind.sh [--help]

Bootstraps local Overmind coordination by:
  1) creating/checking out branch "overmind"
  2) creating worker_registry.yaml scaffold when missing
  3) committing worker_registry.yaml changes when present
  4) pushing branch to remote with upstream tracking

Options:
  -h, --help       Show this help message
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_git() {
  if ! command -v git >/dev/null 2>&1; then
    die "git is not installed or not available in PATH."
  fi
}

resolve_repo_root() {
  local root=""
  if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    die "Not a git repository. Run this script inside a git repository."
  fi
  printf '%s' "$root"
}

ensure_remote_available() {
  local remote="$1"

  if [[ -z "$(git remote 2>/dev/null)" ]]; then
    die "No git remote configured. Add a remote (for example: git remote add origin <url>) and retry."
  fi

  if ! git remote get-url "$remote" >/dev/null 2>&1; then
    die "Remote '$remote' is not configured."
  fi
}

ensure_overmind_branch() {
  if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    git checkout "$BRANCH_NAME" >/dev/null
    echo "Checked out existing branch '$BRANCH_NAME'."
  else
    git checkout -b "$BRANCH_NAME" >/dev/null
    echo "Created and checked out branch '$BRANCH_NAME'."
  fi
}

scaffold_registry_if_missing() {
  local registry_path="$1"

  if [[ -f "$registry_path" ]]; then
    echo "Registry already exists: $REGISTRY_FILE (preserved)."
    REGISTRY_CREATED=0
    return 0
  fi

  local ts=""
  ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  cat >"$registry_path" <<EOF
version: 1
generated_at: "$ts"
description: "Local worker registry for Overmind git-based coordination."
workers: []
EOF
  echo "Created registry scaffold: $REGISTRY_FILE"
  REGISTRY_CREATED=1
}

commit_registry_changes_if_present() {
  git add -- "$REGISTRY_FILE"

  if git diff --cached --quiet -- "$REGISTRY_FILE"; then
    echo "No changes detected in $REGISTRY_FILE; skipping commit."
    return 0
  fi

  local commit_message="Update overmind worker registry"
  if [[ "${REGISTRY_CREATED:-0}" -eq 1 ]]; then
    commit_message="Bootstrap overmind worker registry"
  fi

  if ! git commit -m "$commit_message" -- "$REGISTRY_FILE"; then
    die "Failed to commit '$REGISTRY_FILE'. Check git user configuration and repository state, then retry."
  fi
}

push_branch_with_upstream() {
  local remote="$1"

  if ! git push -u "$remote" "$BRANCH_NAME"; then
    die "Failed to push branch '$BRANCH_NAME' to remote '$remote'. Check remote access and network, then retry."
  fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  die "Unknown argument: $1"
fi

require_git
REPO_ROOT="$(resolve_repo_root)"
cd "$REPO_ROOT"

ensure_remote_available "$REMOTE_NAME"
ensure_overmind_branch
scaffold_registry_if_missing "$REPO_ROOT/$REGISTRY_FILE"
commit_registry_changes_if_present
push_branch_with_upstream "$REMOTE_NAME"

echo "Overmind bootstrap complete."
echo "Branch: $BRANCH_NAME"
echo "Registry: $REGISTRY_FILE"
echo "Remote: $REMOTE_NAME"
