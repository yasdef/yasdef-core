## Why

User review is the last phase still driven by a shell-built prompt packet instead of a repo-provided Codex skill. That keeps user-review behavior duplicated across shell, process documentation, and prompt text, and it prevents the phase from following the same design/planning/implementation pattern already established elsewhere.

The target design moves user review to a skill-owned behavior model with deterministic context assembly, while keeping branch control, entry gating, and model invocation in the orchestrator.

## What Changes

- Add a new repo skill: `ai/codex/skills/yasdef-worker-user-review`.
- Move deterministic user-review context assembly into `build_user_review_context.py`.
- Install the new skill into target repos during `init_asdlc_worker.sh`.
- Move the implementation-readiness entry gate from the legacy user-review prompt script into `orchestrator.sh`.
- Replace the detailed Section 5 process prose in `AI_DEVELOPMENT_PROCESS.md` with a pointer to the installed skill, while preserving cross-phase rules.
- Remove the legacy `ai/scripts/ai_user_review.sh` prompt generator.
- Update user-review, init, and orchestrator tests to match the skill-driven flow.

## Capabilities

### New Capabilities
- `worker-user-review-skill`: Define the skill-owned user-review workflow, context contract, Review Brief behavior, and UR rule-writing gates.

### Modified Capabilities
- `orchestrator-user-review-phase`: Change user review from prompt-script driven to skill-driven, with orchestrator-owned readiness gating and branch handoff.

## Impact

- Affected scripts: `ai/scripts/orchestrator.sh`, `ai/scripts/init_asdlc_worker.sh`, and `ai/scripts/ai_audit.sh`.
- Affected process rules: `ai/AI_DEVELOPMENT_PROCESS.md` Section 5.
- Affected assets: new skill-local UR template and golden examples under `ai/codex/skills/yasdef-worker-user-review/assets/`.
- Affected tests: `tests/ai_scripts/*user_review*`, `tests/ai_scripts/init_asdlc_worker_tests.sh`, `tests/ai_scripts/implementation_evidence_tests.sh`, and `tests/skills_python_scripts/`.
