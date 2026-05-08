#!/usr/bin/env bash
set -euo pipefail

BINDING_FILE="ai/project_overmind.yaml"
ORCHESTRATOR_BRANCH="overmind"

WORKER_UUID=""
OVERMIND_SOURCE_PATH=""
PROJECT_ID=""
WORKER_CLASS=""
WORKER_STATUS=""
WORKER_MATCH_FILE=""
START_BRANCH=""
BINDING_COMMIT_SHA=""

declare -a MATCH_FILES=()
declare -a MATCH_CLASSES=()
declare -a MATCH_STATUSES=()

usage() {
  cat <<'EOF'
Usage: ai/scripts/init_worker.sh [--help]

Initializes local worker binding for Overmind coordination by:
  1) prompting for worker UUID
  2) prompting for the path to the single ASDLC project repo
  3) validating <project_repo>/workers.yaml exists and reading project_id from <project_repo>/init_progress_definition.yaml
  4) validating exactly one UUID match in workers.yaml
  5) writing ai/project_overmind.yaml deterministically

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

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_valid_uuid() {
  local value="$1"
  [[ "$value" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
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

resolve_overmind_source_path() {
  local input_path="$1"
  local resolved=""

  if [[ ! -e "$input_path" ]]; then
    die "Overmind repo path not found: $input_path"
  fi

  if [[ ! -d "$input_path" ]]; then
    die "Overmind repo path is not a directory: $input_path"
  fi

  if ! resolved="$(cd "$input_path" && pwd -P)"; then
    die "Unable to resolve overmind repo path: $input_path"
  fi

  printf '%s' "$resolved"
}

check_root_workers_yaml() {
  local workers_file="$OVERMIND_SOURCE_PATH/workers.yaml"
  if [[ ! -f "$workers_file" ]]; then
    die "Project repo does not contain a root workers.yaml: $OVERMIND_SOURCE_PATH"
  fi
}

read_project_id_from_definition() {
  local def_file="$OVERMIND_SOURCE_PATH/init_progress_definition.yaml"

  if [[ ! -f "$def_file" ]]; then
    die "Project repo is missing init_progress_definition.yaml: $OVERMIND_SOURCE_PATH"
  fi

  local project_id=""
  project_id="$(grep -m1 '^\s*project_id:' "$def_file" | sed "s/.*project_id:[[:space:]]*//;s/[\"']//g")"

  if [[ -z "$project_id" ]]; then
    die "meta_info.project_id is missing or empty in init_progress_definition.yaml of the bound overmind project repo"
  fi

  printf '%s' "$project_id"
}

parse_registry_matches_from_file() {
  local file="$1"
  local target_uuid="$2"
  local parsed=""
  local line=""
  local match_class=""
  local match_status=""

  if ! grep -Eq '^[[:space:]]*workers:[[:space:]]*(\[[[:space:]]*\])?[[:space:]]*$' "$file"; then
    die "Unusable overmind worker registry data in '$file': missing 'workers:' key."
  fi

  parsed="$(
    awk -v target_uuid="$target_uuid" '
      function trim(str) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", str)
        return str
      }
      function unquote(str, first, last, sq) {
        str = trim(str)
        sub(/[[:space:]]+#.*$/, "", str)
        str = trim(str)
        if (length(str) >= 2) {
          first = substr(str, 1, 1)
          last = substr(str, length(str), 1)
          sq = sprintf("%c", 39)
          if ((first == "\"" && last == "\"") || (first == sq && last == sq)) {
            str = substr(str, 2, length(str) - 2)
          }
        }
        return str
      }
      function flush_entry() {
        if (!in_entry) {
          return
        }

        if (entry_uuid == target_uuid) {
          if (entry_class == "" || entry_status == "") {
            print "TARGET_MISSING_FIELDS"
          } else {
            print "MATCH\t" entry_class "\t" entry_status
          }
        }

        in_entry = 0
        entry_uuid = ""
        entry_class = ""
        entry_status = ""
      }
      function start_entry(rest) {
        flush_entry()
        in_entry = 1
        rest = trim(rest)

        if (rest == "") {
          return
        }

        if (match(rest, /^uuid:[[:space:]]*/)) {
          entry_uuid = tolower(unquote(substr(rest, RLENGTH + 1)))
          return
        }
        if (match(rest, /^class:[[:space:]]*/)) {
          entry_class = unquote(substr(rest, RLENGTH + 1))
          return
        }
        if (match(rest, /^status:[[:space:]]*/)) {
          entry_status = unquote(substr(rest, RLENGTH + 1))
          return
        }

        malformed = 1
      }
      BEGIN {
        in_workers = 0
        workers_indent = -1
        in_entry = 0
        entry_uuid = ""
        entry_class = ""
        entry_status = ""
        malformed = 0
      }
      {
        line = $0
        sub(/\r$/, "", line)

        if (line ~ /^[[:space:]]*workers:[[:space:]]*(\[[[:space:]]*\])?[[:space:]]*$/) {
          flush_entry()
          in_workers = 1
          match(line, /^[[:space:]]*/)
          workers_indent = RLENGTH
          if (line ~ /^[[:space:]]*workers:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/) {
            in_workers = 0
            workers_indent = -1
          }
          next
        }

        if (!in_workers) {
          next
        }

        if (line ~ /^[[:space:]]*$/ || line ~ /^[[:space:]]*#/) {
          next
        }

        match(line, /^[[:space:]]*/)
        current_indent = RLENGTH
        if (current_indent <= workers_indent) {
          flush_entry()
          in_workers = 0
          workers_indent = -1
          next
        }

        if (match(line, /^[[:space:]]*-[[:space:]]*/)) {
          start_entry(substr(line, RLENGTH + 1))
          next
        }

        if (!in_entry) {
          malformed = 1
          next
        }

        if (match(line, /^[[:space:]]*uuid:[[:space:]]*/)) {
          entry_uuid = tolower(unquote(substr(line, RLENGTH + 1)))
          next
        }
        if (match(line, /^[[:space:]]*class:[[:space:]]*/)) {
          entry_class = unquote(substr(line, RLENGTH + 1))
          next
        }
        if (match(line, /^[[:space:]]*status:[[:space:]]*/)) {
          entry_status = unquote(substr(line, RLENGTH + 1))
          next
        }
      }
      END {
        if (in_workers) {
          flush_entry()
        }
        if (malformed) {
          print "PARSE_MALFORMED"
        }
      }
    ' "$file"
  )"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      MATCH$'\t'*)
        IFS=$'\t' read -r _ match_class match_status <<<"$line"
        MATCH_FILES+=("$file")
        MATCH_CLASSES+=("$match_class")
        MATCH_STATUSES+=("$match_status")
        ;;
      TARGET_MISSING_FIELDS)
        die "Unusable overmind worker registry data in '$file': matched worker UUID '$target_uuid' is missing required 'class' or 'status'."
        ;;
      PARSE_MALFORMED)
        die "Unusable overmind worker registry data in '$file': malformed workers list."
        ;;
      *)
        die "Unusable overmind worker registry data in '$file': parser produced unexpected output."
        ;;
    esac
  done <<<"$parsed"
}

resolve_single_worker_match() {
  local target_uuid="$1"
  local match_count="${#MATCH_FILES[@]}"

  if [[ "$match_count" -eq 0 ]]; then
    die "No registered worker found for UUID '$target_uuid' in project repo workers.yaml: $OVERMIND_SOURCE_PATH/workers.yaml"
  fi

  if [[ "$match_count" -gt 1 ]]; then
    die "Worker UUID '$target_uuid' resolved to multiple entries in $OVERMIND_SOURCE_PATH/workers.yaml. Ensure the UUID appears exactly once."
  fi

  WORKER_MATCH_FILE="${MATCH_FILES[0]}"
  WORKER_CLASS="${MATCH_CLASSES[0]}"
  WORKER_STATUS="${MATCH_STATUSES[0]}"
}

yaml_quote_single() {
  printf '%s' "$1" | sed "s/'/''/g"
}

write_project_binding_file() {
  local output_path="$1"
  local tmp_path="${output_path}.tmp"

  mkdir -p "$(dirname "$output_path")"
  {
    printf "overmind_source_path: '%s'\n" "$(yaml_quote_single "$OVERMIND_SOURCE_PATH")"
    printf "project_id: '%s'\n" "$(yaml_quote_single "$PROJECT_ID")"
    printf "worker_uuid: '%s'\n" "$(yaml_quote_single "$WORKER_UUID")"
    printf "class: '%s'\n" "$(yaml_quote_single "$WORKER_CLASS")"
    printf "status: '%s'\n" "$(yaml_quote_single "$WORKER_STATUS")"
  } >"$tmp_path"
  mv "$tmp_path" "$output_path"
}

capture_start_branch() {
  START_BRANCH="$(git branch --show-current 2>/dev/null || true)"
  if [[ -z "$START_BRANCH" ]]; then
    START_BRANCH="DETACHED_HEAD"
  fi
}

checkout_or_create_overmind_branch() {
  local current_branch=""
  current_branch="$(git branch --show-current 2>/dev/null || true)"

  if [[ "$current_branch" == "$ORCHESTRATOR_BRANCH" ]]; then
    return 0
  fi

  if git show-ref --verify --quiet "refs/heads/$ORCHESTRATOR_BRANCH"; then
    if ! git checkout "$ORCHESTRATOR_BRANCH" >/dev/null 2>&1; then
      die "Failed to checkout '$ORCHESTRATOR_BRANCH' branch."
    fi
  else
    if ! git checkout -b "$ORCHESTRATOR_BRANCH" >/dev/null 2>&1; then
      die "Failed to create '$ORCHESTRATOR_BRANCH' branch."
    fi
  fi

}

commit_binding_if_needed() {
  local binding_path="$1"

  git add -- "$binding_path"
  if git diff --cached --quiet -- "$binding_path"; then
    echo "No changes detected for '$BINDING_FILE'; skipping commit."
    return 0
  fi

  if ! git commit -m "Bind worker ${WORKER_UUID} to overmind source" -- "$binding_path" >/dev/null; then
    die "Failed to commit '$BINDING_FILE' on '$ORCHESTRATOR_BRANCH'."
  fi

  BINDING_COMMIT_SHA="$(git rev-parse --short HEAD)"
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

capture_start_branch

prompt_non_empty "Enter worker UUID: " WORKER_UUID
WORKER_UUID="$(to_lower "$WORKER_UUID")"
if ! is_valid_uuid "$WORKER_UUID"; then
  die "Worker UUID must use canonical format xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx."
fi

prompt_non_empty "Enter ASDLC project repo path: " OVERMIND_SOURCE_PATH
OVERMIND_SOURCE_PATH="$(resolve_overmind_source_path "$OVERMIND_SOURCE_PATH")"

check_root_workers_yaml
PROJECT_ID="$(read_project_id_from_definition)"
parse_registry_matches_from_file "$OVERMIND_SOURCE_PATH/workers.yaml" "$WORKER_UUID"
resolve_single_worker_match "$WORKER_UUID"

checkout_or_create_overmind_branch
write_project_binding_file "$REPO_ROOT/$BINDING_FILE"
commit_binding_if_needed "$REPO_ROOT/$BINDING_FILE"

echo "Worker init complete."
echo "Binding file: $BINDING_FILE"
echo "Project repo path: $OVERMIND_SOURCE_PATH"
echo "Project ID: $PROJECT_ID"
echo "Worker UUID: $WORKER_UUID"
echo "Worker class: $WORKER_CLASS"
echo "Worker status: $WORKER_STATUS"
echo "Registry file: $WORKER_MATCH_FILE"
echo "Starting branch: $START_BRANCH"
if [[ -n "$BINDING_COMMIT_SHA" ]]; then
  echo "Overmind binding commit: $BINDING_COMMIT_SHA"
else
  echo "Overmind binding commit: none (already up to date)"
fi
echo "Current branch: $ORCHESTRATOR_BRANCH"
echo "=========================="
echo "you are in overmind branch now, if you need this changes in main/master you can merge it manually"
echo "=========================="
