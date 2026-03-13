#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ai/scripts/helpers/check_design_readiness.sh <design-file>

Exit codes:
  0  design artifact is ready
  1  design artifact is not ready
  2  invalid usage
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

DESIGN_FILE="$1"

if [[ ! -f "$DESIGN_FILE" ]]; then
  echo "Design readiness failed: file not found: $DESIGN_FILE" >&2
  exit 1
fi

missing_sections=()
for section in "Goal" "In Scope" "Out of Scope"; do
  if ! awk -v target="$section" '
    /^##[[:space:]]+/ {
      line = $0
      sub(/^##[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == target) { found = 1; exit }
    }
    END { exit(found ? 0 : 1) }
  ' "$DESIGN_FILE"; then
    missing_sections+=("$section")
  fi
done

if [[ ${#missing_sections[@]} -gt 0 ]]; then
  echo "Design readiness failed: missing required sections: ${missing_sections[*]}" >&2
  exit 1
fi

echo "Design readiness check passed: $DESIGN_FILE"
