#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ai/scripts/helpers/check_ai_audit_disposition_readiness.sh <step>

Exit codes:
  0  ai_audit disposition handoff is ready
  1  ai_audit disposition handoff is not ready
  2  invalid usage
EOF
}

count_listed_issues() {
  local review_file="$1"
  awk '
    BEGIN { in_issue=0; count=0 }
    /^## (Critical|High|Medium|Low)[[:space:]]*$/ { in_issue=1; next }
    /^## / { in_issue=0; next }
    in_issue && /^- / {
      if ($0 !~ /^- \(none\)[[:space:]]*$/) count++
    }
    END { print count + 0 }
  ' "$review_file"
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

STEP="$1"
REVIEW_FILE="$ROOT/ai/step_review_results/review_result-$STEP.md"

if [[ ! -f "$REVIEW_FILE" ]]; then
  echo "AI audit disposition readiness failed for step $STEP." >&2
  echo "Review artifact not found: ai/step_review_results/review_result-$STEP.md" >&2
  echo "ai_audit dispositions were not finished correctly because the review artifact is missing." >&2
  exit 1
fi

if ! grep -Eq '^##[[:space:]]+Disposition \(per issue\)[[:space:]]*$' "$REVIEW_FILE"; then
  echo "AI audit disposition readiness failed for step $STEP." >&2
  echo "Review artifact is missing required section '## Disposition (per issue)'." >&2
  echo "ai_audit dispositions were not finished correctly because the disposition section is missing." >&2
  exit 1
fi

ISSUES_COUNT="$(count_listed_issues "$REVIEW_FILE")"
DISPOSITIONS_COUNT="$(grep -Ec '^\s*-\s+\*\*(Accepted|Rejected)\*\*:' "$REVIEW_FILE" || true)"

if [[ "$ISSUES_COUNT" -gt 0 && "$DISPOSITIONS_COUNT" -lt "$ISSUES_COUNT" ]]; then
  echo "AI audit disposition readiness failed for step $STEP." >&2
  echo "Review artifact lists $ISSUES_COUNT issue(s) but only $DISPOSITIONS_COUNT Accepted/Rejected disposition entry(ies)." >&2
  echo "Complete the missing per-issue Accepted/Rejected entries before handing off ai_audit." >&2
  exit 1
fi

echo "AI audit disposition readiness check passed for step $STEP"
