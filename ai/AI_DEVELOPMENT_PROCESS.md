# AI Development Process (spec-driven)

This repo aims for production-level changes, not prototypes. The workflow below is the default loop for implementing `overmind/implementation_plan.md` bullets with AI help.

Scope: this file defines the AI-assisted development process and is intended to be project-agnostic. Project-specific build/test commands and API spec locations are defined in `AGENTS.md`.

## Model selection and sessions
- Do not ask the user whether to change/switch the model. Use the current configured model by default.
- Only discuss or change the model when the user explicitly requests it or when a step plan explicitly mandates a different model/session for a specific sub-task (e.g., planning).
- If a different model/session is used, record it in the relevant step plan, but do not prompt the user about model choice.
- The per-phase model runner is configured in `ai/setup/models.md`. The `Command` column accepts `codex` (today's default) or `claude` (Claude Code).

## Git safety (local workflow)
- Never commit directly on `main`/`master`. All commits happen on a local topic branch.
- Branch setup is handled by scripts: the orchestrator planning/design phases use `step-<step>-plan`, the orchestrator implementation phase uses `step-<step>-implementation`, the orchestrator user_review phase uses `step-<step>-user-review` from implementation, and the orchestrator `ai_audit` phase creates/switches `step-<step>-review` strictly from `step-<step>-user-review`.
- Local workflow: create a local branch before starting a step implementation phase, commit only after tests pass and the user approves, do not push. Any merge to `main`/`master` is a separate explicit follow-up action, not part of step completion.
- Never introduce or commit unrelated changes. If unrelated changes are discovered, stop and ask the user how to proceed.

## Artifacts and their roles
- `overmind/reqirements_ears.md`: source of truth for behavioral requirements and acceptance criteria; it is consumed directly at boundary phases (Design and ai_audit).
- `overmind/implementation_plan.md`: step-level backlog and target-bullet contract artifact; Implementation/User Review do not use it as the execution state machine, and `ai_audit` starts with explicit target-bullet proof-check against it.
- `ai/step_designs/`: feature design artifacts created before planning for user review.
- `.codex/skills/yasdef-worker-design/assets/feature_design_TEMPLATE.md` and `.codex/skills/yasdef-worker-design/assets/feature_design_GOLDEN_EXAMPLE.md`: structure and example for feature design artifacts.
- `ai/step_plans/`: concise step plans produced during the step-planning phase; required input for implementation and the only mid-phase execution contract (`## Plan (ordered)` + translated functional requirements + `## Linked Artifacts (in scope)` shortlist propagated from the design artifact).
- `ai/blocker_log.md`: unknowns/blockers discovered while working an in-progress step.
- `ai/templates/blocker_log_TEMPLATE.md` and `ai/golden_examples/blocker_log_GOLDEN_EXAMPLE.md`: structure and example for blocker log entries.
- `ai/decisions.md`: durable technical decisions (“why we chose X”).
- `ai/templates/decisions_TEMPLATE.md` and `ai/golden_examples/decisions_GOLDEN_EXAMPLE.md`: structure and example for ADR entries.
- `ai/open_questions.md`: non-blocking questions tracked per step to review at plan start.
- `ai/user_review.md`: rule-based user review insights with references to accepted implementations.

## Prompt governance (single source of rules)
- Behavioral/process rules for AI execution must live in this file or the installed phase skill referenced by this file.
- Orchestrator prompts should stay minimal and phase-scoped: tell the model which skill to use and pass explicit variables only.
- Do not duplicate detailed workflow rules across orchestrator prompts. If a rule changes, update this file or the relevant phase skill.

## Planning artifact governance
- Only add entries to `ai/blocker_log.md` under steps that are already in progress in `overmind/implementation_plan.md` (at least one bullet marked `[x]`).
- When updating `overmind/implementation_plan.md`, review and update `ai/blocker_log.md` to keep blockers aligned to the in-progress steps.
- Remove blockers from `ai/blocker_log.md` once the related work is captured in `overmind/implementation_plan.md` in further steps (not current), or if it's done.
- When evaluating whether something is a blocker for a specific bullet, confirm its prerequisites exist and are complete (and if they are in previous steps, confirm those bullets are marked `[x]`). If prerequisites are missing, add them to the current step (mark as technical debt if discovered late) before evaluating the target bullet.
- Track non-blocking questions per step in `ai/open_questions.md` and review them at the start of the step-planning phase.
- Record durable technical decisions in `ai/decisions.md` (do not use `ai/blocker_log.md` for rules/memoizers).
- Canonical TODO handoff marker format is strict: `TODO YASDEF [BLK-<id>] [phase:user_review|ai_audit]: <reason>`.
- Marker usage is restricted to concrete blockers found during `user_review` or `ai_audit`; do not add these markers in design/planning/implementation phases.
- Every canonical marker must map to blocker tracking: `BLK-<id>` must match the blocker identifier used in `ai/blocker_log.md` and be specific enough to seed follow-up work.
- `ai_audit` is the only phase that converts canonical markers into follow-up implementation-plan steps and removes consumed markers after successful plan update.

## Per-step workflow (repeat for each step in `overmind/implementation_plan.md`)

### 1) Feature design (mandatory)
Before step planning:
- Feature design phase is analysis-only: do not implement runtime code in this phase.
- Detailed design-phase workflow, context assembly, bootstrap handling, missing-discussion gates, LAR shortlist behavior, and readiness validation now live in the installed Codex skill at `.codex/skills/yasdef-worker-design/SKILL.md`.
- The orchestrator invokes Codex with a prompt that calls the `yasdef-worker-design` skill for the selected step.
- The design artifact remains the planning scope contract and must be written under `.asdlc_worker/step_designs/`.
- Design is a hard gate: planning must not run without the selected step design artifact.
- Implementation uses this design artifact for the scope contract and the step plan as the primary execution input.


### 2) Step plan and discussion (mandatory first bullet)
- Planning phase is analysis-only: do not implement runtime code in this phase.
- Detailed planning workflow, context assembly, ledger handling, LAR sync, and readiness validation now live in the installed Codex skill at `.codex/skills/yasdef-worker-plan/SKILL.md`.
- The orchestrator invokes Codex with a compact prompt that calls the `yasdef-worker-plan` skill for one planning iteration, then machine-checks readiness plus the per-step ledger files before deciding whether to re-invoke.
- Planning writes the step plan under `.asdlc_worker/step_plans/` and uses per-step ledgers under `.asdlc_worker/step_open_questions/` and `.asdlc_worker/step_blockers/`.
- The plan may be produced in a separate session/model. Record planner and intended execution model/session IDs in the plan.
- Use web research for best practices when needed; record sources in the plan to reduce hallucinations.
- The cross-phase plan contract remains:
  - do not include `## Target Bullets` or `## Requirement Tags` in the step plan
  - require `## Plan (ordered)` and `## Functional Requirements (translated from design EARS)` in that order
  - keep FRs self-contained and map each FR to exactly one `EARS[REQ-...]` source
  - keep `## Applicable UR Shortlist` as exact `- None.` or a curated list of at most 8 `UR-xxxx` entries
- Implementation requires the step plan file; update the plan first if execution must deviate from it.

### 3) Implement ordered plan (adaptive batch execution)
- Detailed implementation workflow, context assembly, LAR fetch behavior, checklist update rules, verification timing, and in-session readiness validation now live in the installed Codex skill at `.codex/skills/yasdef-worker-implementation/SKILL.md`.
- The orchestrator invokes Codex with a compact prompt that calls the `yasdef-worker-implementation` skill for the selected step.
- Implementation writes runtime code and advances the step plan `## Plan (ordered)` and translated FR checklist state.
- Implementation uses the design artifact by reference for the scope contract only: `## Goal`, `## In Scope`, and `## Out of Scope`.
- `## Plan (ordered)` is the only implementation-phase execution checklist/state machine.
- Do not use `overmind/implementation_plan.md` target bullets as implementation-phase gating or completion state. Detailed target-bullet proof-check (`PROVEN`/`NOT_PROVEN`) is performed in Section 6.0 (`ai_audit` entry).

### 4) Verification gates (required before Section 5)
- **Tests (two-tier timing)**:
  - Targeted verification may run during implementation as needed (focused tests/lint/typecheck).
  - Full step verification gate from `AGENTS.md` runs once after all ordered bullets are `[x]` and before entering Section 5.
- **Requirements**: confirm every translated functional requirement is implemented and verified
  - Mark each functional-requirement checklist line `[x]` only when that requirement is implemented and verified; keep `[ ]` otherwise.
- **Docs**:
  - If endpoints/inputs/outputs change: update the API specification and client collection as defined in `AGENTS.md`.
  - If a new design choice was made: record it in `ai/decisions.md` using `ai/templates/decisions_TEMPLATE.md` and `ai/golden_examples/decisions_GOLDEN_EXAMPLE.md`.
  - If a decision replaces a prior one: mark the older ADR as **Superseded** and link to the superseding ADR.

#### 4.1) Implementation handoff constraints (required before Section 5)
- Implementation reporting must map progress/evidence to both `## Plan (ordered)` bullets and translated functional requirements.
- Do not run `overmind/implementation_plan.md` target-bullet proof-check in implementation; that proof-check is the first gate in Section 6.
- Enter Section 5 only when all checklist items in step-plan `## Plan (ordered)` are marked `[x]`, all translated functional requirement checklist items are `[x]`, and the full step verification gate has passed.

#### 4.2) Implementation Readiness Gate (required before Section 5)
- Before emitting the implementation completion line, run `.codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py --step <step> --step-plan <step-plan-file>` using `uv run python`.
- If the Implementation Readiness Gate exits non-zero, do not emit the completion line. Tell the user what failed and present exactly two options: `1.` try to fix the reason and re-run the script, `2.` finish the step immediately with failed status.
- After presenting the Implementation Readiness Gate options, stop and wait for the user's reply. Do not choose option `1` or `2` without explicit user input.
- If the user chooses `1`, continue implementation, fix the readiness issue, and re-run the Implementation Readiness Gate.
- If the user chooses `2`, finish the step immediately with failed status.
- Do not emit the implementation completion line unless the Implementation Readiness Gate later exits `0`.

### 5) User review (required before moving to the next step)
- Detailed user-review workflow, context assembly, Review Brief behavior, and UR write gates now live in the installed Codex skill at `.codex/skills/yasdef-worker-user-review/SKILL.md`.
- The orchestrator invokes Codex with a compact prompt that calls the `yasdef-worker-user-review` skill for the selected step.
- Before prompt generation/model start, the orchestrator runs `.codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py --step <step> --step-plan <step-plan-file>` with `uv run python` and fails fast if implementation was not finished correctly.
- User review operates on ordered-plan completion state only; do not use `overmind/implementation_plan.md` target bullets as user_review phase-state gating.
- Do not run Section 6 in the user_review phase; Section 6 is executed separately in the `ai_audit` phase after user review is complete.

### 6) Post-step ai_audit/review (required before moving to the next step)
- Detailed ai_audit workflow, entry gate, context assembly, two-phase discovery/disposition model, and closure validation now live in the installed Codex skill at `.codex/skills/yasdef-worker-ai-audit/SKILL.md`.
- The orchestrator invokes Codex with a compact prompt that calls `yasdef-worker-ai-audit` for the selected step.
- ai_audit remains analysis-only: do not modify runtime code and do not run tests in this phase.
- ai_audit uses the step design artifact as the single context source and writes findings to `.asdlc_worker/step_review_results/review_result-<step>-<feature-id>.md`.
- Each finding must reach exactly one terminal state: `follow_up_created`, `raised_to_coordinator`, or `rejected`.
- ai_audit may update ASDLC planning artifacts (`implementation_plan.md`, `raised_questions/`) as disposition outputs; those ASDLC changes are synced by orchestrator/post_review handoff routines.

## Estimation Gates (required)
- **Scale**: use SP values `{1, 2, 3, 5, 8}`. Keep estimates rough.
- **Notation**: append `(SP=...)` to each bullet in `overmind/implementation_plan.md`.
- **Step total**: add `Est. step total: <N> SP` under each step header.
- **Review loop**: when marking "Review step implementation" as done, append actuals (e.g., `Actuals: SP=..., tokens=..., surprises=..., est_error=...`) and recalibrate remaining step estimates.
- **Goal**: converge on an ideal step size range that balances context stability and meaningful requirement decomposition; adjust the target range as data accumulates.

## Definition of Done
- `Plan and discuss the step.` completion criteria are defined in Section 2.
- `Review step implementation.` completion criteria are defined in Section 6 (especially 6.1, 6.2, and 6.3).

For implementation bullets (all step bullets except `Plan and discuss the step.` and `Review step implementation.`), a bullet is “done” only when:
- Behavior is implemented correctly and safely (including idempotency/rollback expectations).
- Coverage exists for the success path and key failure modes.
- The step-level verification gate from Section 4 has been run and reported (prefer the repo’s full end-to-end verification gate from `AGENTS.md`).
- The change is aligned with the relevant EARS acceptance criteria.
- Any required API/docs updates are made.

Step-level completion gates (run once per step, after all implementation bullets above are done):
- User review completed (user has no questions or comments).
- If tests passed, post-step audit is complete, and user approves, commit changes with a concise, imperative message on the current step/review branch and prepare a local MR/PR summary. Do not push.
- Do not merge to `main`/`master` as part of step completion; treat merge as a separate explicit action after step completion.

## Local MR/PR summary template
```
Title: <step/bullet short name>
Summary:
- <what changed>
- <why>
```
