#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PLAN_FILE="$ROOT/overmind/implementation_plan.md"

usage() {
  cat <<'EOF'
Usage: ai/scripts/helpers/check_ai_audit_disposition_readiness.sh <step>

Exit codes:
  0  ai_audit completion handoff is ready
  1  ai_audit completion handoff is not ready
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

get_step_bullet_status() {
  local plan_file="$1"
  local step="$2"
  awk -v target="$step" '
    BEGIN {
      found_step=0
      in_step=0
      have_review=0
      review_checked=0
      unchecked=0
      plain=0
    }
    /^### Step / {
      line = $0
      sub(/^### Step /, "", line)
      split(line, parts, " ")
      in_step = (parts[1] == target)
      if (in_step) found_step=1
      next
    }
    in_step && /^- / {
      if ($0 ~ /^- \[[ ]\]/) {
        unchecked++
      } else if ($0 !~ /^- \[[xX]\]/) {
        plain++
      }

      if ($0 ~ /^- \[[ xX]\]/) {
        raw = $0
        checked = (raw ~ /^- \[[xX]\]/)
        text = raw
        sub(/^- \[[ xX]\][[:space:]]*/, "", text)
        gate_text = tolower(text)

        while (gate_text ~ /^\[[^]]+\][[:space:]]*/) {
          sub(/^\[[^]]+\][[:space:]]*/, "", gate_text)
        }

        if (gate_text ~ /^review step implementation([[:space:]\.]|$)/) {
          have_review = 1
          if (checked) review_checked = 1
        }
      }
    }
    END {
      printf "%d|%d|%d|%d|%d", found_step, have_review, review_checked, unchecked, plain
    }
  ' "$plan_file"
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

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "AI audit disposition readiness failed for step $STEP." >&2
  echo "Implementation plan not found: overmind/implementation_plan.md" >&2
  echo "ai_audit cannot finish until the current step review gate is closed in the implementation plan." >&2
  exit 1
fi

STEP_STATUS="$(get_step_bullet_status "$PLAN_FILE" "$STEP")"
IFS='|' read -r FOUND_STEP HAVE_REVIEW REVIEW_CHECKED UNCHECKED_COUNT PLAIN_COUNT <<<"$STEP_STATUS"

if [[ "$FOUND_STEP" -ne 1 ]]; then
  echo "AI audit disposition readiness failed for step $STEP." >&2
  echo "Step $STEP section was not found in overmind/implementation_plan.md." >&2
  echo "Add/update the current step section in the implementation plan before handing off ai_audit." >&2
  exit 1
fi

if [[ "$HAVE_REVIEW" -ne 1 ]]; then
  echo "AI audit disposition readiness failed for step $STEP." >&2
  echo "Current step review gate was not found in overmind/implementation_plan.md." >&2
  echo "Add the current step bullet 'Review step implementation' to the implementation plan before handing off ai_audit." >&2
  exit 1
fi

if [[ "$REVIEW_CHECKED" -ne 1 ]]; then
  echo "AI audit disposition readiness failed for step $STEP." >&2
  echo "Current step review gate in overmind/implementation_plan.md is not [x]." >&2
  echo "Mark 'Review step implementation' complete before handing off ai_audit." >&2
  exit 1
fi

if [[ "$PLAIN_COUNT" -gt 0 ]]; then
  echo "AI audit disposition readiness failed for step $STEP." >&2
  echo "Current step has $PLAIN_COUNT non-checklist bullet(s) in overmind/implementation_plan.md." >&2
  echo "Normalize current-step bullets to checklist form and mark all of them [x] before handing off ai_audit." >&2
  exit 1
fi

if [[ "$UNCHECKED_COUNT" -gt 0 ]]; then
  echo "AI audit disposition readiness failed for step $STEP." >&2
  echo "Current step has $UNCHECKED_COUNT unchecked checklist bullet(s) in overmind/implementation_plan.md." >&2
  echo "Mark all current-step checklist bullets [x] before handing off ai_audit." >&2
  exit 1
fi

echo "AI audit disposition readiness check passed for step $STEP"
