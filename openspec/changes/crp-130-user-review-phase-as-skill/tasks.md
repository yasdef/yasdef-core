## 1. Skill and Context Builder

- [x] 1.1 Add `ai/codex/skills/yasdef-worker-user-review/SKILL.md`.
- [x] 1.2 Add `ai/codex/skills/yasdef-worker-user-review/scripts/build_user_review_context.py`.
- [x] 1.3 Add skill-local assets for UR schema and golden examples.

## 2. Runtime Wiring

- [x] 2.1 Update `ai/scripts/init_asdlc_worker.sh` to install `yasdef-worker-user-review`.
- [x] 2.2 Update `.git/info/exclude` handling and durable commit paths for the installed skill.
- [x] 2.3 Move the user-review implementation-readiness gate into `ai/scripts/orchestrator.sh`.
- [x] 2.4 Replace user-review prompt generation with a compact `yasdef-worker-user-review` prompt writer and orchestrator-owned branch handoff.
- [x] 2.5 Remove the legacy `ai/scripts/ai_user_review.sh`.

## 3. Process and Supporting Scripts

- [x] 3.1 Replace the detailed Section 5 procedure in `ai/AI_DEVELOPMENT_PROCESS.md` with a skill pointer plus cross-phase rules.
- [x] 3.2 Update `ai/scripts/ai_audit.sh` messaging to reference the orchestrator user-review phase/skill.
- [x] 3.3 Update `AGENTS.md` test command listings for the new user-review skill tests.

## 4. Validation

- [x] 4.1 Add `tests/skills_python_scripts/yasdef_worker_user_review_tests.sh`.
- [x] 4.2 Update `tests/ai_scripts/user_review_phase_tests.sh` for orchestrator-owned gating, branch handoff, and compact prompt writing.
- [x] 4.3 Update worker-init and process-doc tests for the new skill layout and removed legacy prompt script.
- [ ] 4.4 Run focused user-review/init/orchestrator tests and `git diff --check`.
