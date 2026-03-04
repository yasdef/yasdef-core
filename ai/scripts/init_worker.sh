#!/usr/bin/env bash
set -euo pipefail

REMOTE_NAME="origin"
ORCHESTRATOR_BRANCH="overmind"
RETURN_BRANCH="master"
REGISTRY_FILE="worker_registry.yaml"
WORKER_ID_FILE="ai/worker_id_dont_change_or_remove.txt"
RESTORE_BRANCH_ON_EXIT=0
REGISTRY_UPDATED=0
WORKER_ID_CREATED=0
REGISTRY_COMMIT_SHA=""

usage() {
  cat <<'EOF'
Usage: ai/scripts/init_worker.sh [--help]

Initializes a worker for Overmind coordination by:
  1) ensuring local worker ID file exists under ai/
  2) validating orchestrator branch overmind exists remotely
  3) checking out overmind and registering worker ID in worker_registry.yaml
  4) committing and pushing registration changes
  5) switching back to master

Options:
  -h, --help       Show this help message
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

die_no_orchestrator() {
  echo "no orchestrator detected, unable to proceed" >&2
  exit 1
}

cleanup() {
  if [[ "$RESTORE_BRANCH_ON_EXIT" -eq 1 ]]; then
    git checkout "$RETURN_BRANCH" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

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

ensure_return_branch() {
  if ! git show-ref --verify --quiet "refs/heads/$RETURN_BRANCH"; then
    die "Required return branch '$RETURN_BRANCH' does not exist."
  fi
}

ensure_orchestrator_branch() {
  local remote="$1"
  if ! git fetch "$remote" "$ORCHESTRATOR_BRANCH" >/dev/null 2>&1; then
    die_no_orchestrator
  fi
}

ensure_local_overmind_branch() {
  local remote="$1"
  if git show-ref --verify --quiet "refs/heads/$ORCHESTRATOR_BRANCH"; then
    git checkout "$ORCHESTRATOR_BRANCH" >/dev/null
  else
    git checkout -b "$ORCHESTRATOR_BRANCH" --track "$remote/$ORCHESTRATOR_BRANCH" >/dev/null
  fi
}

sync_overmind_branch() {
  local remote="$1"
  if ! git pull --ff-only "$remote" "$ORCHESTRATOR_BRANCH" >/dev/null 2>&1; then
    die "Failed to pull '$ORCHESTRATOR_BRANCH' from remote '$remote'."
  fi
}

generate_worker_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  printf '%s-%s-%s' "$(date +%s)" "$RANDOM" "$RANDOM"
}

ensure_worker_id() {
  local path="$1"
  local value=""
  mkdir -p "$(dirname "$path")"

  if [[ -f "$path" ]]; then
    value="$(head -n 1 "$path" | tr -d '[:space:]')"
    if [[ -z "$value" ]]; then
      die "Worker ID file exists but is empty: $WORKER_ID_FILE"
    fi
    WORKER_ID="$value"
    echo "Using existing worker ID from $WORKER_ID_FILE."
    return 0
  fi

  value="$(generate_worker_id)"
  printf '%s\n' "$value" >"$path"
  WORKER_ID="$value"
  WORKER_ID_CREATED=1
  echo "Created worker ID file: $WORKER_ID_FILE"
}

ensure_registry_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    die "Registry file '$REGISTRY_FILE' not found on branch '$ORCHESTRATOR_BRANCH'. Run coordinator bootstrap first."
  fi
}

register_worker_if_needed() {
  local path="$1"
  local escaped_worker_id=""
  escaped_worker_id="$(printf '%s' "$WORKER_ID" | sed 's/[][\\/.*^$]/\\&/g')"

  if grep -Eq "^[[:space:]]*-[[:space:]]*${escaped_worker_id}[[:space:]]*$" "$path"; then
    echo "Worker already registered in $REGISTRY_FILE."
    return 0
  fi

  if grep -Eq '^[[:space:]]*workers:[[:space:]]*\[[[:space:]]*\][[:space:]]*$' "$path"; then
    awk -v wid="$WORKER_ID" '
      /^[[:space:]]*workers:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/ {
        print "workers:"
        print "  - " wid
        next
      }
      { print }
    ' "$path" >"$path.tmp"
    mv "$path.tmp" "$path"
    REGISTRY_UPDATED=1
    echo "Registered worker ID in $REGISTRY_FILE."
    return 0
  fi

  if grep -Eq '^[[:space:]]*workers:[[:space:]]*$' "$path"; then
    printf '  - %s\n' "$WORKER_ID" >>"$path"
    REGISTRY_UPDATED=1
    echo "Registered worker ID in $REGISTRY_FILE."
    return 0
  fi

  die "Unsupported '$REGISTRY_FILE' format: expected 'workers: []' or 'workers:' key."
}

commit_registry_changes_if_any() {
  local registry_path="$1"
  local id_path="$2"

  git add -- "$registry_path" "$id_path"

  if git diff --cached --quiet -- "$registry_path" "$id_path"; then
    if [[ "$REGISTRY_UPDATED" -eq 1 || "$WORKER_ID_CREATED" -eq 1 ]]; then
      die "Registration state changed but no staged diff was detected."
    fi
    echo "No changes detected for worker registration; skipping commit."
    return 0
  fi

  if ! git commit -m "Register worker ${WORKER_ID} in overmind registry" -- "$registry_path" "$id_path"; then
    die "Failed to commit worker registration changes."
  fi

  REGISTRY_COMMIT_SHA="$(git rev-parse --short HEAD)"
}

push_registration_changes() {
  local remote="$1"
  if ! git push -u "$remote" "$ORCHESTRATOR_BRANCH"; then
    die "Failed to push registration to remote '$remote'."
  fi
}

announce_commit_and_push_plan() {
  if [[ ("$REGISTRY_UPDATED" -eq 1 || "$WORKER_ID_CREATED" -eq 1) && -z "$REGISTRY_COMMIT_SHA" ]]; then
    die "Registration changed but no local commit was created; refusing to push."
  fi

  if [[ -n "$REGISTRY_COMMIT_SHA" ]]; then
    echo "Committed local overmind changes: $REGISTRY_COMMIT_SHA"
    echo "Pushing local overmind commit to remote '$REMOTE_NAME/$ORCHESTRATOR_BRANCH'..."
  else
    echo "No local overmind commit needed; worker already registered."
    echo "Pushing local overmind branch to confirm remote sync..."
  fi
}

checkout_return_branch() {
  if ! git checkout "$RETURN_BRANCH" >/dev/null; then
    die "Failed to checkout '$RETURN_BRANCH' after registration."
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
ensure_return_branch
ensure_orchestrator_branch "$REMOTE_NAME"
ensure_local_overmind_branch "$REMOTE_NAME"
RESTORE_BRANCH_ON_EXIT=1
sync_overmind_branch "$REMOTE_NAME"
ensure_registry_file_exists "$REPO_ROOT/$REGISTRY_FILE"
ensure_worker_id "$REPO_ROOT/$WORKER_ID_FILE"
register_worker_if_needed "$REPO_ROOT/$REGISTRY_FILE"
commit_registry_changes_if_any "$REPO_ROOT/$REGISTRY_FILE" "$REPO_ROOT/$WORKER_ID_FILE"
announce_commit_and_push_plan
push_registration_changes "$REMOTE_NAME"
checkout_return_branch
RESTORE_BRANCH_ON_EXIT=0

echo "Worker init complete."
echo "Remote: $REMOTE_NAME"
echo "Branch: $ORCHESTRATOR_BRANCH"
echo "Worker ID file: $WORKER_ID_FILE"
if [[ -n "$REGISTRY_COMMIT_SHA" ]]; then
  echo "Local overmind commit: $REGISTRY_COMMIT_SHA"
else
  echo "Local overmind commit: none (worker already registered)"
fi
