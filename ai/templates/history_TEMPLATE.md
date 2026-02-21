# AI Run History - Template

This file is updated by `ai/scripts/post_review.sh` with one consolidated record per step.

Entry template:

## <YYYY-MM-DDTHH:MM:SSZ>
- Step: <step number> - <step title>
- Token usage: total=<n> input=<n> (+ <n> cached) output=<n> (reasoning <n>), including:
  - Phase: design - total=<n> input=<n> (+ <n> cached) output=<n> (reasoning <n>)
  - Phase: planning - total=<n> input=<n> (+ <n> cached) output=<n> (reasoning <n>)
  - Phase: implementation - total=<n> input=<n> (+ <n> cached) output=<n> (reasoning <n>)
  - Phase: review - total=<n> input=<n> (+ <n> cached) output=<n> (reasoning <n>)
- New lines of code added: <n>
- New classes added: <n>
- Step plan: ai/step_plans/step-<step>.md
