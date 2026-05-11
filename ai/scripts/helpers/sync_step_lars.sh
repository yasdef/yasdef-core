#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/runtime_layout.sh"
asdlc_worker_require_runtime_layout "${BASH_SOURCE[0]}"
ROOT="$WORKER_REPO_ROOT"
PLAN="$ASDLC_RUNTIME_PLAN_PATH"
REQUIREMENTS="$ASDLC_RUNTIME_EARS_PATH"

usage() {
  cat <<'EOF'
Usage: .asdlc_worker/scripts/helpers/sync_step_lars.sh <step> <target-artifact-path>

Recomputes the per-step LAR funnel from .asdlc_worker/overmind/implementation_plan.md and
.asdlc_worker/overmind/reqirements_ears.md and idempotently writes/replaces the
## Linked Artifacts (in scope) section in the target artifact.

When no LARs are in scope the target artifact is left unchanged (no-op).

Exit codes:
  0  success (section written, replaced, or no-op)
  1  error
  2  invalid usage
EOF
}

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 2
fi

STEP="$1"
TARGET="$2"

if [[ ! -f "$PLAN" ]]; then
  echo "sync_step_lars: implementation plan not found: $PLAN" >&2
  exit 1
fi

if [[ ! -f "$REQUIREMENTS" ]]; then
  echo "sync_step_lars: requirements file not found: $REQUIREMENTS" >&2
  exit 1
fi

if [[ ! -f "$TARGET" ]]; then
  echo "sync_step_lars: target artifact not found: $TARGET" >&2
  exit 1
fi

get_step_section() {
  local step="$1"
  awk -v step="$step" '
    BEGIN { step_re = step; gsub(/\./, "\\.", step_re) }
    $0 ~ "^### Step "step_re" " { in_step=1 }
    in_step && $0 ~ "^## " && $0 !~ "^### Step "step_re" " { exit }
    in_step && $0 ~ "^### Step " && $0 !~ "^### Step "step_re" " { exit }
    in_step { print }
  ' "$PLAN"
}

extract_requirement_section() {
  local req="$1"
  awk -v req="$req" '
    BEGIN { req_re = req; gsub(/\./, "\\.", req_re) }
    $0 ~ "^### Requirement "req_re" " { in_req=1 }
    in_req && /^## [^#]/ { exit }
    in_req && $0 ~ "^### Requirement " && $0 !~ "^### Requirement "req_re" " { exit }
    in_req { print }
  ' "$REQUIREMENTS"
}

get_req_blocks() {
  local step_section="$1"
  local reqs
  reqs="$(printf '%s\n' "$step_section" | grep -oE "\\[REQ-[0-9]+(\\.[0-9]+)?\\]" | tr -d '[]' | sed 's/^REQ-//' | sort -u)"
  [[ -z "$reqs" ]] && return 0

  local req section
  while IFS= read -r req; do
    [[ -z "$req" ]] && continue
    section="$(extract_requirement_section "$req")"
    if [[ -z "$section" && "$req" == *.* ]]; then
      section="$(extract_requirement_section "${req%%.*}")"
    fi
    [[ -n "$section" ]] && printf '%s\n\n' "$section"
  done <<<"$reqs"
}

compute_lar_lines() {
  local req_blocks="$1"
  [[ -z "$req_blocks" ]] && return 0

  local lar_ids
  lar_ids="$(printf '%s\n' "$req_blocks" | \
    grep -E '\*\*Linked Artifacts:\*\*' | \
    grep -oE 'LAR-[0-9]+' | \
    sort -t- -k2 -n | \
    uniq)"

  [[ -z "$lar_ids" ]] && return 0

  local lar_id entry
  while IFS= read -r lar_id; do
    [[ -z "$lar_id" ]] && continue
    entry="$(awk -v id="$lar_id" '
      /^## Linked Artifacts[[:space:]]*$/ { in_reg=1; next }
      in_reg && /^## / { exit }
      in_reg && $0 ~ ("^[[:space:]]*- " id "[[:space:]|]") {
        sub(/^[[:space:]]*-[[:space:]]*/, "")
        print
        exit
      }
    ' "$REQUIREMENTS")"
    [[ -n "$entry" ]] && printf '%s\n' "- $entry"
  done <<<"$lar_ids"
}

STEP_SECTION="$(get_step_section "$STEP")"
if [[ -z "$STEP_SECTION" ]]; then
  echo "sync_step_lars: step $STEP not found in $PLAN" >&2
  exit 1
fi

REQ_BLOCKS="$(get_req_blocks "$STEP_SECTION")"
LAR_LINES="$(compute_lar_lines "$REQ_BLOCKS")"

if [[ -z "$LAR_LINES" ]]; then
  exit 0
fi

# Idempotently write/replace the ## Linked Artifacts (in scope) section.
SECTION_HEADING="## Linked Artifacts (in scope)"

TMP_LINES="$(mktemp)"
TMP_OUT="$(mktemp "${TARGET}.XXXXXX")"
trap 'rm -f "$TMP_LINES" "$TMP_OUT"' EXIT

printf '%s\n' "$LAR_LINES" > "$TMP_LINES"

if grep -Fxq "$SECTION_HEADING" "$TARGET"; then
  awk -v heading="$SECTION_HEADING" -v lines_file="$TMP_LINES" '
    BEGIN { in_section=0; inserted=0 }
    $0 == heading && !inserted {
      print heading
      while ((getline line < lines_file) > 0) print line
      close(lines_file)
      in_section=1
      inserted=1
      next
    }
    in_section && /^## / { in_section=0; print; next }
    in_section { next }
    { print }
  ' "$TARGET" > "$TMP_OUT"
else
  cat "$TARGET" > "$TMP_OUT"
  printf '\n%s\n' "$SECTION_HEADING" >> "$TMP_OUT"
  cat "$TMP_LINES" >> "$TMP_OUT"
fi

mv "$TMP_OUT" "$TARGET"
