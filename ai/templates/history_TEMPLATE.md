# AI Run History - Template

This file is updated by `ai/scripts/post_review.sh` with one consolidated record per step.

Entry template:

## <YYYY-MM-DDTHH:MM:SSZ>
- Step: <step number> - <step title>
- Token usage: total=<n> input=<n> (+ <n> cached) output=<n> (reasoning <n>), including:
  - Phase: design - total=<n> input=<n> (+ <n> cached) output=<n> (reasoning <n>)
  - Phase: planning - total=<n> input=<n> (+ <n> cached) output=<n> (reasoning <n>)
  - Phase: implementation - total=<n> input=<n> (+ <n> cached) output=<n> (reasoning <n>)
  - Phase: user_review - total=<n> input=<n> (+ <n> cached) output=<n> (reasoning <n>)
  - Phase: ai_audit - total=<n> input=<n> (+ <n> cached) output=<n> (reasoning <n>)
- Workflow phases for the step: design -> planning -> implementation -> user_review -> ai_audit -> post_review
- `post_review` is a non-model consolidation phase, so it usually has no model token usage line.
- New lines of code added: <n>
- New classes added: <n>
- Step plan: ai/step_plans/step-<step>.md
