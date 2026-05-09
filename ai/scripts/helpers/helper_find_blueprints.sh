#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BINDING_FILE="$ROOT/ai/project_overmind.yaml"
FEATURE_SYNC_FILE="$ROOT/ai/feature_sync.yaml"

usage() {
  cat <<'EOF'
Usage: ai/scripts/helpers/helper_find_blueprints.sh

Run this helper from an ASDLC feature folder that contains:
  - implementation_plan.md
  - requirements_ears.md

The helper searches the parent project-level directory for
project_stack_blueprint_*.md files and filters them using the bound project
class from ai/project_overmind.yaml.
EOF
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

read_yaml_scalar() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  awk -v key="$key" '
    function trim(str) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", str)
      return str
    }
    $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
      line = $0
      sub("^[[:space:]]*" key ":[[:space:]]*", "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      line = trim(line)
      if ((line ~ /^".*"$/) || (line ~ /^'\''.*'\''$/)) {
        line = substr(line, 2, length(line) - 2)
      }
      print line
      exit
    }
  ' "$file"
}

normalize_project_class() {
  local raw
  raw="$(to_lower "$(trim "${1:-}")")"
  case "$raw" in
    back|backend|api|server)
      printf 'back'
      ;;
    front|frontend|front-end|web|ui)
      printf 'front'
      ;;
    mobile|ios|android|react-native)
      printf 'mobile'
      ;;
    *)
      printf ''
      ;;
  esac
}

matches_class() {
  local normalized_class="$1"
  local path_lower
  path_lower="$(to_lower "$2")"

  case "$normalized_class" in
    back)
      [[ "$path_lower" == *back* || "$path_lower" == *backend* ]]
      ;;
    front)
      [[ "$path_lower" == *front* || "$path_lower" == *frontend* || "$path_lower" == *web* ]]
      ;;
    mobile)
      [[ "$path_lower" == *mobile* || "$path_lower" == *ios* || "$path_lower" == *android* ]]
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_feature_dir() {
  local cwd="$PWD"
  local sync_feature_path=""

  if [[ -f "$cwd/implementation_plan.md" && ( -f "$cwd/requirements_ears.md" || -f "$cwd/reqirements_ears.md" ) ]]; then
    printf '%s' "$cwd"
    return 0
  fi

  sync_feature_path="$(read_yaml_scalar "$FEATURE_SYNC_FILE" "source_feature_path" || true)"
  if [[ -n "$sync_feature_path" && -d "$sync_feature_path" ]]; then
    printf '%s' "$sync_feature_path"
    return 0
  fi

  return 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 0 ]]; then
  usage >&2
  exit 2
fi

FEATURE_DIR="$(resolve_feature_dir || true)"
if [[ -z "$FEATURE_DIR" ]]; then
  echo "Blueprint lookup failed: run this helper from an ASDLC feature folder with implementation_plan.md and requirements_ears.md, or provide ai/feature_sync.yaml with source_feature_path." >&2
  exit 1
fi

PROJECT_DIR="$(cd "$FEATURE_DIR/.." && pwd)"
RAW_CLASS="$(read_yaml_scalar "$BINDING_FILE" "class" || true)"
PROJECT_CLASS="$(normalize_project_class "$RAW_CLASS")"

printf 'Blueprint helper result\n'
printf 'Feature folder: %s\n' "$FEATURE_DIR"
printf 'Project-level search root: %s\n' "$PROJECT_DIR"
if [[ -f "$BINDING_FILE" ]]; then
  printf 'Binding file: %s\n' "$BINDING_FILE"
else
  printf 'Binding file: missing (%s)\n' "$BINDING_FILE"
fi

if [[ -n "$RAW_CLASS" ]]; then
  printf 'Raw project class: %s\n' "$RAW_CLASS"
else
  printf 'Raw project class: unresolved\n'
fi

if [[ -n "$PROJECT_CLASS" ]]; then
  printf 'Normalized project class: %s\n' "$PROJECT_CLASS"
else
  printf 'Normalized project class: unresolved\n'
fi

ALL_BLUEPRINTS=()
while IFS= read -r blueprint; do
  [[ -n "$blueprint" ]] || continue
  ALL_BLUEPRINTS+=("$blueprint")
done < <(find "$PROJECT_DIR" -maxdepth 1 -type f -name 'project_stack_blueprint_*.md' | sort)

if [[ ${#ALL_BLUEPRINTS[@]} -eq 0 ]]; then
  printf 'Blueprint search result: no blueprint files found under project-level root.\n'
  exit 0
fi

printf 'All blueprint candidates:\n'
for blueprint in "${ALL_BLUEPRINTS[@]}"; do
  printf -- '- %s\n' "$blueprint"
done

if [[ -z "$PROJECT_CLASS" ]]; then
  printf 'Relevant blueprint result: unresolved because project class is missing or unsupported. Ask the user to choose the stack/scaffold direction.\n'
  exit 0
fi

MATCHED=()
IRRELEVANT=()
for blueprint in "${ALL_BLUEPRINTS[@]}"; do
  if matches_class "$PROJECT_CLASS" "$(basename "$blueprint")"; then
    MATCHED+=("$blueprint")
  else
    IRRELEVANT+=("$blueprint")
  fi
done

if [[ ${#MATCHED[@]} -gt 0 ]]; then
  printf 'Relevant blueprint candidates for class %s:\n' "$PROJECT_CLASS"
  for blueprint in "${MATCHED[@]}"; do
    printf -- '- %s\n' "$blueprint"
  done
fi

if [[ ${#IRRELEVANT[@]} -gt 0 ]]; then
  printf 'Irrelevant blueprint candidates for class %s:\n' "$PROJECT_CLASS"
  for blueprint in "${IRRELEVANT[@]}"; do
    printf -- '- %s\n' "$blueprint"
  done
fi

if [[ ${#MATCHED[@]} -eq 0 ]]; then
  printf 'Relevant blueprint result: no class-matching blueprint found. Ask the user to choose the stack/scaffold direction.\n'
else
  printf 'Relevant blueprint result: found %d class-matching blueprint candidate(s).\n' "${#MATCHED[@]}"
fi
