# AI Development Process (spec-driven)

This repo aims for production-level changes, not prototypes. The workflow below is the default loop for implementing `ai/implementation_plan.md` bullets with AI help.

Scope: this file defines the AI-assisted development process and is intended to be project-agnostic. Project-specific build/test commands and API spec locations are defined in `AGENTS.md`.

## Model selection and sessions
- Do not ask the user whether to change/switch the model. Use the current configured model by default.
- Only discuss or change the model when the user explicitly requests it or when a step plan explicitly mandates a different model/session for a specific sub-task (e.g., planning).
- If a different model/session is used, record it in the relevant step plan, but do not prompt the user about model choice.

## Git safety (local workflow)
- Never commit directly on `main`/`master`. All commits happen on a local topic branch.
- Branch setup is handled by scripts: `ai/scripts/ai_plan.sh` uses `step-<step>-plan`, `ai/scripts/ai_implementation.sh` uses `step-<step>-implementation`, and `ai/scripts/ai_review.sh` creates/switches `step-<step>-review` from `step-<step>-implementation` so uncommitted implementation changes are carried into review.
- Local workflow: create a local branch before starting a bullet, commit only after tests pass and the user approves, do not push. Any merge to `main`/`master` is a separate explicit follow-up action, not part of step completion.
- Never introduce or commit unrelated changes. If unrelated changes are discovered, stop and ask the user how to proceed.

## Artifacts and their roles
- `reqirements_ears.md`: source of truth for behavioral requirements and acceptance criteria.
- `ai/implementation_plan.md`: ordered execution plan; work happens bullet-by-bullet, with SP estimates and step totals tracked there.
- `ai/step_plans/`: concise step plans produced during the "Plan and discuss the step" bullet; required input for execution prompts.
- `ai/blocker_log.md`: unknowns/blockers discovered while working an in-progress step.
- `ai/templates/blocker_log_TEMPLATE.md` and `ai/golden_examples/blocker_log_GOLDEN_EXAMPLE.md`: structure and example for blocker log entries.
- `ai/decisions.md`: durable technical decisions (“why we chose X”).
- `ai/templates/decisions_TEMPLATE.md` and `ai/golden_examples/decisions_GOLDEN_EXAMPLE.md`: structure and example for ADR entries.
- `ai/open_questions.md`: non-blocking questions tracked per step to review at plan start.
- `ai/user_review.md`: rule-based user review insights with references to accepted implementations.

## Prompt governance (single source of rules)
- Behavioral/process rules for AI execution must live in this file.
- `ai/scripts/*.sh` prompts should stay minimal and phase-scoped: tell the model which phase it is in, where outputs go, and to follow the relevant sections of this file plus `AGENTS.md`.
- Do not duplicate detailed workflow rules across script prompts. If a rule changes, update this file and keep scripts as thin wrappers.

## Planning artifact governance
- Only add entries to `ai/blocker_log.md` under steps that are already in progress in `ai/implementation_plan.md` (at least one bullet marked `[x]`).
- When updating `ai/implementation_plan.md`, review and update `ai/blocker_log.md` to keep blockers aligned to the in-progress steps.
- Remove blockers from `ai/blocker_log.md` once the related work is captured in `ai/implementation_plan.md` in further steps (not current), or if it's done.
- When evaluating whether something is a blocker for a specific bullet, confirm its prerequisites exist and are complete (and if they are in previous steps, confirm those bullets are marked `[x]`). If prerequisites are missing, add them to the current step (mark as technical debt if discovered late) before evaluating the target bullet.
- Track non-blocking questions per step in `ai/open_questions.md` and review them at the start of the step’s "Plan and discuss the step" bullet.
- Record durable technical decisions in `ai/decisions.md` (do not use `ai/blocker_log.md` for rules/memoizers).

## Per-step workflow (repeat for each step in `ai/implementation_plan.md`)

### 1) Plan and discuss the step (mandatory first bullet)
Before writing code for the step:
- Planning phase is analysis-only: do not implement runtime code in this phase.
- Execute the planning flow autonomously end-to-end; do not pause for generic "next step" confirmation. Ask the user only for required project-specific inputs/decisions or true blockers.
- Generate or update the step plan artifact via `ai/scripts/ai_plan.sh` and write it to `ai/step_plans/step-<step>.md`.
- Use `ai/templates/step_plan_TEMPLATE.md` as the default structure and follow the style in `ai/golden_examples/step_plan_GOLDEN_EXAMPLE.md`.
- The plan may be produced in a separate session/model. Record planner and intended execution model/session IDs in the plan.
- Use web research for best practices when needed; record sources in the plan to reduce hallucinations.
- The plan must be concise and explicit about scope, assumptions, risks, tests, and docs/artifacts to update.
- The plan must include an "Implementation Notes" or "Constraints" section that explicitly references `AGENTS.md` and `ai/AI_DEVELOPMENT_PROCESS.md`.
- The plan must include an "Architecture / Helper Flow" section describing helper/service design and call flow when applicable.
- Execution uses `ai/scripts/ai_implementation.sh` and requires the step plan file; update the plan if execution deviates.
- Step plans may include a "User Command (manual only - do not execute in assistant)" section. This is for the human operator only; assistants must not run it.
- Identify prerequisites (schema, endpoints, validators, error codes, auth assumptions).
- If prerequisites are missing, add them as new bullets to the current step (mark as technical debt if discovered late).
- Identify decisions that must be made; ask questions and record the outcome in `ai/decisions.md`.
- If any decision is required to proceed, explicitly ask the user before implementing.
- Review `ai/open_questions.md` for the current step; add new questions there and remove answered ones.
- Open-questions completion gate: do not consider the planning bullet complete while any open questions remain for the step. Ask questions one-by-one (at most one per assistant message), wait for the user's answer, then update the step plan and remove/close the answered question(s) in `ai/open_questions.md`.
- Add only true blockers/unknowns to `ai/blocker_log.md` using `ai/templates/blocker_log_TEMPLATE.md` and `ai/golden_examples/blocker_log_GOLDEN_EXAMPLE.md` (only for steps already in progress).
- Add SP estimates to every bullet in the step and record the step total (see Estimation Gates below). If the step total exceeds the target range, split the step before implementing code.
- Only when the plan is accepted and open questions are resolved/closed, immediately mark the "Plan and discuss the step" bullet as done and add Step sections to `ai/blocker_log.md` and `ai/open_questions.md` (even if "none"), then commit the planning artifacts.
- Completion-line gate: output the exact planning completion line (`Planning phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase.`) only after verifying in `ai/implementation_plan.md` that this step's "Plan and discuss the step." bullet is marked `[x]` (and included in the planning commit when changed).
- If blockers or open questions remain, present them and continue planning discussion; do not finish the planning phase until they are resolved/closed.

### 2) Implement bullets (one at a time)
For each bullet:
- Execution order (required): within the implementation phase, complete all unchecked implementation bullets in the current step up to (but excluding) `Review step implementation.` before entering Section 4 (User review). Do not run Section 4 after each bullet.
- Do not pause after the first completed bullet to ask for generic permission to continue. Continue through the remaining unchecked implementation bullets in the same step.
- Exception: pause and ask the user only when a specific bullet is blocked by a required user decision/input that is necessary to implement that bullet correctly.
- Treat the step plan as the implementation contract: execute only in-scope items for the current bullet.
- Review the step plan and supporting artifacts before coding: linked requirements sections, `AGENTS.md`, `ai/decisions.md`, `ai/blocker_log.md`, `ai/open_questions.md`, and `ai/user_review.md`.
- Convert the step plan's ordered plan into a short implementation checklist and complete items one by one.
- If implementation must deviate from the step plan, update the step plan first, then continue implementation.
- If a required project decision/blocker appears during implementation, stop and ask the user before proceeding.
- Reuse existing code patterns and keep each change minimal, cohesive, readable, and directly traceable to a step-plan item.
- Remove unnecessary boilerplate and avoid extra guard checks.
- Add or update tests so the happy path is always covered and, when feasible, core reasonable non-happy-path cases are covered based on the step plan and linked requirements.
- Record new blockers/unknowns in `ai/blocker_log.md` (using `ai/templates/blocker_log_TEMPLATE.md` and `ai/golden_examples/blocker_log_GOLDEN_EXAMPLE.md`), unresolved questions in `ai/open_questions.md`, and durable design choices in `ai/decisions.md` (using `ai/templates/decisions_TEMPLATE.md` and `ai/golden_examples/decisions_GOLDEN_EXAMPLE.md`).
- Keep project-specific implementation constraints out of this section; enforce them from `AGENTS.md`.

### 3) Verification gates (required before marking a bullet done)
- **Tests**: run tests for the bullet; add/adjust unit/integration tests covering the new behavior and failure modes. Prefer the repo’s full end-to-end verification gate from `AGENTS.md`.
- **Requirements**: confirm affected `reqirements_ears.md` acceptance criteria are satisfied.
- **Docs**:
  - If endpoints/inputs/outputs change: update the API specification and client collection as defined in `AGENTS.md`.
  - If a new design choice was made: record it in `ai/decisions.md` using `ai/templates/decisions_TEMPLATE.md` and `ai/golden_examples/decisions_GOLDEN_EXAMPLE.md`.
  - If a decision replaces a prior one: mark the older ADR as **Superseded** and link to the superseding ADR.

### 4) User review (required before moving to the next step)
Entry precondition:
- All non-review implementation bullets in the current step are marked `[x]`. If any remain unchecked, return to Sections 2-3 and complete them first.

0. Before starting the user review, review `ai/user_review.md` for applicable rules and known pitfalls, then re-check the current implementation once again; if there is room to improve the last changes (without scope creep), propose those improvements first.
1. Ask the user for the next review item (a question or a change request). The user may provide feedback one-by-one; if they have multiple items, a short bullet list helps.
2. When the user responds, do this in order:
   1. Clarify ambiguous requests (ask questions if needed). If the user asked "why", answer the question first.
   2. Implement the requested changes (and any directly necessary test/doc updates). Do not implement changes that were not requested; propose them as suggestions and ask.
   3. Immediately update `ai/user_review.md` with any generalizable rule(s) derived from the user feedback and the implementation change (include references). If there are no generalizable rules, explicitly state that and do not change `ai/user_review.md`.
3. Summarize what changed and ask for the next review round.
4. Repeat steps 1-3 until the user explicitly confirms the review is complete (e.g., "done", "no more comments").
5. Only after the user confirms completion, run one final verification test command for the step (prefer the repo’s full verification gate from `AGENTS.md`) and report the result.
6. If the final verification passes, propose the next step: Post-step audit (Section 5).
- Completion-line gate (implementation phase): output the exact implementation completion line (`Implementation phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase.`) only after Section 4 is complete and the final verification command has been run and reported.
- Do not run Section 5 in the implementation phase; Section 5 is executed in the review phase.

### 5) Post-step audit (required before moving to the next step)
- Entry precondition for this phase: Section 4 (User review) is already complete. Do not ask the user to reconfirm Section 4 during post-step audit.
- Do not start the next implementation step in this phase.
- Start by identifying current uncommitted step changes (for example, `git status --short` and `git diff --name-status`) and inspecting changed files.
- Post-step audit is analysis-only. Do not change runtime code, do not implement fixes, and do not run tests in this phase.
- Allowed changes in this phase are planning/audit artifacts only (for example: `ai/implementation_plan.md`, `ai/blocker_log.md`, `ai/open_questions.md`, `ai/decisions.md`, `ai/step_review_results/*`).
- If recording new decisions or blockers in this phase, use `ai/templates/decisions_TEMPLATE.md` + `ai/golden_examples/decisions_GOLDEN_EXAMPLE.md` and `ai/templates/blocker_log_TEMPLATE.md` + `ai/golden_examples/blocker_log_GOLDEN_EXAMPLE.md`.
- If the user asks to fix an issue immediately during post-step audit, do not implement it and do not suggest immediate implementation yourself; record it as follow-up work (step/bullet/open question/decision) per this section.
- Re-check for newly introduced blockers/technical debt:
  - If it blocks the next bullet in the current step: add it to `ai/blocker_log.md`.
  - Otherwise: add it as a new future bullet in `ai/implementation_plan.md`.
- Ensure no behavior was changed “just to satisfy a test”.
- Review all changes produced during the current step (typically on `step-<step>-review`), focusing on correctness and regression risk.
  - Perform an analysis-heavy review: cross-check against `AGENTS.md` rules (idempotency, validation, transaction boundaries, ledger/projection consistency, stream routing, guard rules), `reqirements_ears.md` acceptance criteria, and updated docs/tests.
  - Produce a detailed review in the response: list findings (if any) with severity (Critical/High/Medium/Low) and file references. If no findings, state that explicitly and mention any residual risks or testing gaps.
  - If issues are found:
    1. Create or update `ai/step_review_results/review_result-<current_step>.md` using `ai/templates/review_result_TEMPLATE.md` and follow the formatting from `ai/golden_examples/review_result_GOLDEN_EXAMPLE.md`.
    2. Ask the user to accept/reject each listed issue individually (confirm severity and whether it should be addressed now).
    3. Based on the user’s decision:
       - If rejected: mark it as rejected/closed in `review_result-<current_step>.md` (brief rationale).
       - If accepted for resolution: analyze `ai/implementation_plan.md` and add it as follow-up work in the appropriate place:
         - Prefer adding a follow-up step immediately after the current step using letter suffixes (e.g., `1.6` → `1.6a`, `1.6a` → `1.6b`, etc.) when it is directly related and should not block earlier steps.
         - Otherwise, add it as a new later step (e.g., `1.6` → `1.12`) if it’s larger or should be scheduled separately.
         - If the “what to do” is still unclear, add it as an item in `ai/open_questions.md` for an already-created step (so it is reviewed during that step’s planning bullet).
- Record estimation actuals on the "Review step implementation" bullet (actual SP, token usage or time, surprises). Update future bullet estimates and the step-size target based on the error.
- Close the "Review step implementation" bullet once the post-step audit write-up is complete and every finding has an explicit disposition recorded (**Accepted** or **Rejected**) and any accepted items are captured as follow-up work (typically as a new step/bullet in `ai/implementation_plan.md`, or as an item in `ai/open_questions.md`/`ai/blocker_log.md` if still unclear).
- If the "Review step implementation" bullet is complete but missing actuals, do not report this as a user-facing finding/issue. Instead, append a best-effort estimated `Actuals: ...` entry immediately in this phase and continue the audit.
- **Commit gate**: only when there are **no accepted unresolved findings** and the user confirms completion, commit all step changes on the current step/review branch and propose the commit commands. If any accepted follow-up work remains, do **not** propose commit commands in this phase. Do not merge to `main`/`master` in this phase.
- Completion-line gate (review phase): output the exact review completion line (`Review phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase.`) only after post-step audit write-up is complete and every finding has an explicit disposition (**Accepted** or **Rejected**) with accepted items captured as follow-up work.

## Estimation Gates (required)
- **Scale**: use SP values `{1, 2, 3, 5, 8}`. Keep estimates rough.
- **Notation**: append `(SP=...)` to each bullet in `ai/implementation_plan.md`.
- **Step total**: add `Est. step total: <N> SP` under each step header.
- **Review loop**: when marking "Review step implementation" as done, append actuals (e.g., `Actuals: SP=..., tokens=..., surprises=..., est_error=...`) and recalibrate remaining step estimates.
- **Goal**: converge on an ideal step size range that balances context stability and meaningful requirement decomposition; adjust the target range as data accumulates.

## Definition of Done
- `Plan and discuss the step.` completion criteria are defined in Section 1.
- `Review step implementation.` completion criteria are defined in Section 5.

For implementation bullets (all step bullets except `Plan and discuss the step.` and `Review step implementation.`), a bullet is “done” only when:
- Behavior is implemented correctly and safely (including idempotency/rollback expectations).
- Coverage exists for the success path and key failure modes.
- Tests have been run for the bullet (prefer the repo’s full end-to-end verification gate from `AGENTS.md`).
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
