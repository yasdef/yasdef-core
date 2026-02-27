# AI Development Process (spec-driven)

This repo aims for production-level changes, not prototypes. The workflow below is the default loop for implementing `ai/implementation_plan.md` bullets with AI help.

Scope: this file defines the AI-assisted development process and is intended to be project-agnostic. Project-specific build/test commands and API spec locations are defined in `AGENTS.md`.

## Model selection and sessions
- Do not ask the user whether to change/switch the model. Use the current configured model by default.
- Only discuss or change the model when the user explicitly requests it or when a step plan explicitly mandates a different model/session for a specific sub-task (e.g., planning).
- If a different model/session is used, record it in the relevant step plan, but do not prompt the user about model choice.

## Git safety (local workflow)
- Never commit directly on `main`/`master`. All commits happen on a local topic branch.
- Branch setup is handled by scripts: `ai/scripts/ai_design.sh` and `ai/scripts/ai_plan.sh` use `step-<step>-plan`, `ai/scripts/ai_implementation.sh` uses `step-<step>-implementation`, and `ai/scripts/ai_audit.sh` (used by phase key `ai_audit`) creates/switches `step-<step>-review` from `step-<step>-implementation` so uncommitted implementation changes are carried into review.
- Local workflow: create a local branch before starting a step implementation phase, commit only after tests pass and the user approves, do not push. Any merge to `main`/`master` is a separate explicit follow-up action, not part of step completion.
- Never introduce or commit unrelated changes. If unrelated changes are discovered, stop and ask the user how to proceed.

## Artifacts and their roles
- `reqirements_ears.md`: source of truth for behavioral requirements and acceptance criteria.
- `ai/implementation_plan.md`: step-level backlog and target-bullet contract artifact; Implementation/User Review do not use it as the execution state machine, and `ai_audit` starts with explicit target-bullet proof-check against it.
- `ai/step_designs/`: feature design artifacts created before planning for user review.
- `ai/templates/feature_design_TEMPLATE.md` and `ai/golden_examples/feature_design_GOLDEN_EXAMPLE.md`: structure and example for feature design artifacts.
- `ai/step_plans/`: concise step plans produced during the step-planning phase; required input for execution prompts.
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
- Track non-blocking questions per step in `ai/open_questions.md` and review them at the start of the step-planning phase.
- Record durable technical decisions in `ai/decisions.md` (do not use `ai/blocker_log.md` for rules/memoizers).

## Per-step workflow (repeat for each step in `ai/implementation_plan.md`)

### 1) Feature design (mandatory)
Before step planning:
- Feature design phase is analysis-only: do not implement runtime code in this phase.
- Generate or update the feature design artifact via `ai/scripts/ai_design.sh` at `ai/step_designs/step-<step>-design.md`.
- Use `ai/templates/feature_design_TEMPLATE.md` as the default structure and follow `ai/golden_examples/feature_design_GOLDEN_EXAMPLE.md`.
- The feature design should be concise and capture: goals/non-goals, scope/out of scope, decisions/trade-offs, proposal/design details, risks/mitigations, quality/testing, alternatives, open questions, and relevant code references.
- Include only relevant constraints from `AGENTS.md` and relevant insights from `ai/user_review.md` (do not dump all rules).
- Shortlist only relevant accepted ADRs from `ai/decisions.md` and capture them in the design artifact (do not dump all ADRs).
- In this phase, do not finalize durable decisions and do not update `ai/decisions.md`; capture candidate decisions under "Things to Decide" in the design artifact for final planning discussion.
- Design decision quality gate: make "Things to Decide" entries concrete and action-driving (decision-shaped, not generic questions), with mutually exclusive options and explicit trade-offs so planning can present clear `1`/`2` choices.
- Design decision depth gate: for non-trivial scope, capture at least 1-3 plan-critical "Things to Decide" items. If there are truly no plan-critical choices, explicitly record `- None.` with short rationale.
- Track unresolved questions/unknowns in `ai/open_questions.md` when they need explicit follow-up in planning.
- Design is a hard gate: planning must not run without `ai/step_designs/step-<step>-design.md`.
- Implementation prompts must use this design artifact plus the step plan as primary context inputs.
- Completion-line gate: output the exact design completion line (`Design phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase.`) after verifying that this step is finished, nothing left to do


### 2) Step plan and discussion (mandatory first bullet)

#### 2.1) Planning draft and decision capture
- Planning phase is analysis-only: do not implement runtime code in this phase.
- Execute the planning flow autonomously end-to-end; do not pause for generic "next step" confirmation. Ask the user only for required project-specific inputs/decisions or true blockers.
- Generate or update the step plan artifact via `ai/scripts/ai_plan.sh` and write it to `ai/step_plans/step-<step>.md`.
- Use `ai/templates/step_plan_TEMPLATE.md` as the default structure and follow the style in `ai/golden_examples/step_plan_GOLDEN_EXAMPLE.md`.
- The plan may be produced in a separate session/model. Record planner and intended execution model/session IDs in the plan.
- Use web research for best practices when needed; record sources in the plan to reduce hallucinations.
- The plan must be concise and execution-focused: ordered steps, constraints, decisions, tests, and docs/artifacts to update.
- Scope contract lives in the feature design artifact: `## Goal`, `## In Scope`, and `## Out of Scope`. Do not restate those sections in the step plan; instead add a pointer to the design and focus the plan on execution.
- The plan must include an "Implementation Notes" or "Constraints" section that explicitly references `AGENTS.md` and `ai/AI_DEVELOPMENT_PROCESS.md`.
- The plan must include an "Architecture / Helper Flow" section describing helper/service design and call flow when applicable.
- The plan must include an "Applicable UR Shortlist" section.
- Accepted shortlist content is strict: either exact `- None.` (use this when there are no UR rules yet, or none apply), or a curated list where each bullet includes a `UR-xxxx` ID with optional one-line rationale.
- Prioritize shortlist signal quality: when using UR IDs, recommended shortlist size is 3-8 items; enforced maximum is 8.
- The plan must include design-derived constraints and decisions needed for execution:
  - Include relevant constraints extracted from design's `Applicable AGENTS.md Constraints` and `Applicable User Review Rules`.
  - Include non-negotiable invariants derived from the design's ADR shortlist and the step plan context.
- Planning prompt/output should avoid inlining full `AGENTS.md` and full `ai/user_review.md`; use design-extracted relevant subsets by default.
- Execution uses `ai/scripts/ai_implementation.sh` and requires the step plan file; update the plan if execution deviates.
- Identify prerequisites (schema, endpoints, validators, error codes, auth assumptions).
- If prerequisites are missing, add them as new bullets to the current step (mark as technical debt if discovered late).
- Identify decisions that must be made (including all design "Things to Decide" items); ask questions and record the outcome in `ai/decisions.md` when durable.
- If design "Things to Decide" entries are vague, normalize them into concrete decision prompts before closure (clear options, impact/risk trade-off, and what changes in implementation depending on choice).
- If any decision is required to proceed, explicitly ask the user before implementing.
- Resolve every item listed in design `## Things to Decide (for final planning discussion)` (or `## Things to Decide`) during planning. In the step plan `## Decisions Needed`, record an explicit outcome per item: `Accepted`, `Deferred`, or `Blocked` (with rationale and where the follow-up is tracked).
- Review `ai/open_questions.md` for the current step; add new questions there and remove answered ones.
- Add only true blockers/unknowns to `ai/blocker_log.md` using `ai/templates/blocker_log_TEMPLATE.md` and `ai/golden_examples/blocker_log_GOLDEN_EXAMPLE.md` (only for steps already in progress).
- Add SP estimates to every bullet in the step and record the step total (see Estimation Gates below). If the step total exceeds the target range, split the step before implementing code.

#### 2.2) Plan quality gates and closure
- Open-questions quality gate: do not consider the planning bullet complete while any open questions remain for the step. Ask questions one-by-one (at most one per assistant message), wait for the user's answer, then update the step plan and remove/close the answered question(s) in `ai/open_questions.md`.
- Things-to-decide quality gate: do not consider the planning bullet complete while any design "Things to Decide" item lacks an explicit recorded outcome in the step plan. If unresolved, ask the user, then update the step plan and tracking artifacts.
- Decision-confirmation quality gate: for each unresolved item from design `## Things to Decide`, ask the user for an explicit decision and record the answer before closing planning, even when a preferred/default option exists in design notes.
- Decision prompt format (when decision-confirmation gate triggers): use exactly two options in numbered format. Option `1.` must be the recommended/default choice with short rationale; option `2.` must be the alternative with short trade-off rationale.
- Decision prompt scope gate: do not auto-select unresolved design decisions in planning. Require explicit user choice unless the same decision was already explicitly provided by the user for the current step.
- Decision prompt actionability gate: keep the two options mutually exclusive and actionable, and explicitly allow the user to reply with only `1` or `2`.
- Decision-depth quality gate: if design unresolved decisions are empty but a plan-critical trade-off still exists in prerequisites/risks/tests/docs, ask one explicit two-option confirmation prompt before closing planning; if no plan-critical trade-offs remain, explicitly record that no additional decision prompt is required.
- UR-shortlist quality gate: do not close planning if `## Applicable UR Shortlist` is missing, uses non-canonical content, or includes more than 8 UR IDs.
- If blockers, open questions, or unresolved design "Things to Decide" items remain, present them and continue planning discussion; do not finish the planning phase until they are resolved/closed.
- Only when the plan is accepted, open questions are resolved/closed, and all design "Things to Decide" items have explicit outcomes, immediately mark the "Plan and discuss the step" bullet as done and add Step sections to `ai/blocker_log.md` and `ai/open_questions.md` (even if "none"), then commit the planning artifacts.
- Completion-line gate: output the exact planning completion line (`Planning phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase.`) only after verifying in `ai/implementation_plan.md` that this step's "Plan and discuss the step." bullet is marked `[x]` (and included in the planning commit when changed).

### 3) Implement ordered plan (adaptive batch execution)
#### 3.1) Adaptive implementation execution
- Do not pause after the first completed item to ask for generic permission to continue. Continue through the remaining work in the same step.
- Exception: pause and ask the user only when blocked by a required user decision/input.
- Treat the feature design as the scope contract (`## Goal`, `## In Scope`, `## Out of Scope`) and the step plan `## Plan (ordered)` as the execution contract.
- `## Plan (ordered)` is the only implementation-phase execution checklist/state machine.
- Ordered bullets are checkbox lifecycle items (`[ ]` / `[x]`). If a bullet is plain text without checkbox syntax, treat it as unchecked until normalized/closed.
- Implementation strategy is adaptive: batch work in the most coherent order when needed, but close checklist state per ordered bullet and mark `[x]` only when that specific bullet is proven complete.
- Review the step plan, design artifact, and supporting artifacts before coding: linked requirements sections, `ai/decisions.md`, `ai/blocker_log.md`, and `ai/open_questions.md`.
- If implementation must deviate from the step plan, update the step plan first, then continue implementation.
- If design "Things to Decide" are still unresolved in the step plan during implementation: do not decide unilaterally in implementation. Recommend rerunning planning to resolve decisions first, then follow the user's instruction on whether to return to planning or proceed with explicit risk acceptance.
- If a required project decision/blocker appears during implementation, stop and ask the user before proceeding.
- Reuse existing code patterns and keep each change minimal, cohesive, readable, and directly traceable to ordered-plan work items.
- Remove unnecessary boilerplate and avoid extra guard checks.
- Add or update tests so the happy path is always covered and, when feasible, core reasonable non-happy-path cases are covered based on the step plan and linked requirements.
- Record new blockers/unknowns in `ai/blocker_log.md` (using `ai/templates/blocker_log_TEMPLATE.md` and `ai/golden_examples/blocker_log_GOLDEN_EXAMPLE.md`), unresolved questions in `ai/open_questions.md`, and durable design choices in `ai/decisions.md` (using `ai/templates/decisions_TEMPLATE.md` and `ai/golden_examples/decisions_GOLDEN_EXAMPLE.md`).
- Keep project-specific implementation constraints out of this section; enforce them from `AGENTS.md`.

#### 3.2) Ordered checklist closure (required before Section 4)
- Before changing any ordered bullet from `[ ]` to `[x]`, make sure that bullet is implemented and verified for the current change.
- If implementation or verification is incomplete/uncertain, keep the bullet `[ ]`.
- If blocked, record blockers/open questions and continue with remaining feasible work.
- Do not use `ai/implementation_plan.md` target bullets as implementation-phase gating or completion state.
- Detailed target-bullet proof-check (`PROVEN`/`NOT_PROVEN`) is performed in Section 6.0 (`ai_audit` entry).

### 4) Verification gates (required before Section 5)
- **Tests (two-tier timing)**:
  - Targeted verification may run during implementation as needed (focused tests/lint/typecheck).
  - Full step verification gate from `AGENTS.md` runs once after all ordered bullets are `[x]` and before entering Section 5.
- **Requirements**: confirm affected `reqirements_ears.md` acceptance criteria are satisfied for the implemented ordered-plan scope.
- **Docs**:
  - If endpoints/inputs/outputs change: update the API specification and client collection as defined in `AGENTS.md`.
  - If a new design choice was made: record it in `ai/decisions.md` using `ai/templates/decisions_TEMPLATE.md` and `ai/golden_examples/decisions_GOLDEN_EXAMPLE.md`.
  - If a decision replaces a prior one: mark the older ADR as **Superseded** and link to the superseding ADR.

#### 4.1) Implementation handoff constraints (required before Section 5)
- Implementation reporting must map progress/evidence to ordered bullets in `## Plan (ordered)` only.
- Do not run `ai/implementation_plan.md` target-bullet proof-check in implementation; that proof-check is the first gate in Section 6.
- Enter Section 5 only when all checklist items in step-plan `## Plan (ordered)` are marked `[x]` and the full step verification gate has passed.

### 5) User review (required before moving to the next step)
Entry precondition:
- This precondition is enforced before model execution by `ai/scripts/ai_user_review.sh`: the step plan exists, contains `## Plan (ordered)`, all ordered checklist items are marked `[x]`, and the Section 4 full verification gate has passed.
- User review operates on ordered-plan completion state only; do not use `ai/implementation_plan.md` target bullets as user_review phase-state gating.

1. Before starting the user review loop, review `ai/user_review.md` for applicable rules and known pitfalls, then re-check the implemented code against those rules once again (including any rules not shortlisted earlier but now relevant based on actual changes). If there is room to improve the last changes (without scope creep), propose those improvements first.
2. Before asking for review feedback, provide a concise `Review Brief` (plain language, product-level) covering exactly:
   1. what was changed and how (concrete system flow),
   2. how to start code review (where to begin and recommended order),
   3. what should be checked first (top correctness/risk hotspots).
3. Review Brief output constraints:
   - Keep it concise (short checklist-style summary; avoid long narrative).
   - Scope it to current-step changes only.
   - Reference concrete changed entrypoints/files/components/tests when available.
   - Do not narrate artifact creation; focus on reviewer onboarding.
   - Do not guess review ordering/entrypoints. If specific entrypoints are unclear, use cautious non-speculative guidance.
   - Keep the ai_audit entry `Evidence Reasoning Summary` separate; do not merge proof-gate entries into the Review Brief.
   - Use `ai/golden_examples/review_brief_GOLDEN_EXAMPLE.md` as the tone/structure anchor.
4. Ask the user for the next review item (a question or a change request). The user may provide feedback one-by-one; if they have multiple items, a short bullet list helps.
5. When the user responds, do this in order:
   1. Clarify ambiguous requests (ask questions if needed). If the user asked "why", answer the question first.
   2. Implement the requested changes (and any directly necessary test/doc updates). Do not implement changes that were not requested; propose them as suggestions and ask.
   3. Immediately update `ai/user_review.md` with any generalizable rule(s) derived from the user feedback and the implementation change (include references). If there are no generalizable rules, explicitly state that and do not change `ai/user_review.md`.
6. Summarize what changed and ask for the next review round.
7. Repeat steps 4-6 until the user explicitly confirms the review is complete (e.g., "done", "no more comments").
8. Only after the user confirms completion, run one final verification test command for the step (prefer the repo’s full verification gate from `AGENTS.md`) and report the result.
9. If the final verification passes, propose the next step: Post-step audit/review (Section 6).
- Do not run Section 6 in the implementation phase; Section 6 is executed in the `ai_audit` phase.

### 6) Post-step ai_audit/review (required before moving to the next step)

#### 6.0) Entry proof-check against implementation_plan target bullets (required first gate)
- Before deeper audit analysis, run explicit bullet-by-bullet proof-check against current-step target bullets in `ai/implementation_plan.md` (non-review implementation bullets for the step).
- Allowed outcomes per target bullet:
  - `PROVEN`: concrete implementation evidence exists.
  - `NOT_PROVEN`: implementation evidence is missing/incomplete/uncertain.
- Required proof for `PROVEN`:
  1 - Code implementation references exist: specific changed file path(s) and key symbols with core logic.
  2 - Behavioral reachability is shown from concrete entrypoints first (controller/handler/job/UI/CLI), then supporting flow as needed.
  3 - Test evidence exists: new/updated tests validate behavior, or there is explicit credible mapping to existing coverage.
- Evidence Reasoning Summary output (required at ai_audit entry):
  1 - Keep it compact and scannable.
  2 - Include each in-scope target bullet exactly once with `PROVEN` or `NOT_PROVEN`.
  3 - For every `PROVEN` bullet, include code refs, reachability, and test evidence/mapping.
  4 - No guesses: missing/uncertain evidence requires `NOT_PROVEN`.
- If any target bullet is `NOT_PROVEN`, fail/flag ai_audit entry and stop before deeper Section 6.1 analysis. Continue 6.1/6.2 only after the entry proof-check passes.

#### 6.1) Audit review and findings
- Entry precondition for this phase: Section 5 (User review) is already complete. Do not ask the user to reconfirm Section 5 during post-step audit.
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
  - If issues are found, execute Section 6.2 for each finding. After each finding is dispositioned, return to Section 6.1 and continue the audit.
- Record estimation actuals on the "Review step implementation" bullet (actual SP, token usage or time, surprises). Update future bullet estimates and the step-size target based on the error.
- If the "Review step implementation" bullet is complete but missing actuals, do not report this as a user-facing finding/issue. Instead, append a best-effort estimated `Actuals: ...` entry immediately in this phase and continue the audit.
- Close the "Review step implementation" bullet once the post-step audit write-up is complete and every finding has an explicit disposition recorded (**Accepted** or **Rejected**) and any accepted items are captured as follow-up work (typically as a new step/bullet in `ai/implementation_plan.md`, or as an item in `ai/open_questions.md`/`ai/blocker_log.md` if still unclear).
- **Commit gate**: only when there are **no accepted unresolved findings** and the user confirms completion, commit all step changes on the current step/review branch and propose the commit commands. If any accepted follow-up work remains, do **not** propose commit commands in this phase. Do not merge to `main`/`master` in this phase.
- Completion-line gate (ai_audit phase): output the exact ai_audit completion line (`ai_audit phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase.`) only after post-step audit write-up is complete and every finding has an explicit disposition (**Accepted** or **Rejected**) with accepted items captured as follow-up work.

#### 6.2) Per-finding issue disposition workflow
- Run this subsection separately for each finding identified in Section 6.1.
1. Create or update `ai/step_review_results/review_result-<current_step>.md` using `ai/templates/audit_result_TEMPLATE.md` and follow the formatting from `ai/golden_examples/audit_result_GOLDEN_EXAMPLE.md`.
2. Ask the user to accept/reject the current issue (confirm severity and whether it should be addressed now).
3. Based on the user’s decision:
   - If rejected: mark it as rejected/closed in `review_result-<current_step>.md` (brief rationale).
   - If accepted for resolution: analyze `ai/implementation_plan.md` and add it as follow-up work in the appropriate place:
     - Prefer adding a follow-up step immediately after the current step using letter suffixes (e.g., `1.6` → `1.6a`, `1.6a` → `1.6b`, etc.) when it is directly related and should not block earlier steps.
     - Otherwise, add it as a new later step (e.g., `1.6` → `1.12`) if it’s larger or should be scheduled separately.
     - If the “what to do” is still unclear, add it as an item in `ai/open_questions.md` for an already-created step (so it is reviewed during that step’s planning bullet).
4. Return to Section 6.1 and continue the audit. Repeat Section 6.2 for the next finding until all findings have explicit disposition.

## Estimation Gates (required)
- **Scale**: use SP values `{1, 2, 3, 5, 8}`. Keep estimates rough.
- **Notation**: append `(SP=...)` to each bullet in `ai/implementation_plan.md`.
- **Step total**: add `Est. step total: <N> SP` under each step header.
- **Review loop**: when marking "Review step implementation" as done, append actuals (e.g., `Actuals: SP=..., tokens=..., surprises=..., est_error=...`) and recalibrate remaining step estimates.
- **Goal**: converge on an ideal step size range that balances context stability and meaningful requirement decomposition; adjust the target range as data accumulates.

## Definition of Done
- `Plan and discuss the step.` completion criteria are defined in Section 2.
- `Review step implementation.` completion criteria are defined in Section 6 (especially 6.1 and 6.2).

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
