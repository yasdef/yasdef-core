# AI Development Process (spec-driven)

This repo aims for production-level changes, not prototypes. The workflow below is the default loop for implementing `overmind/implementation_plan.md` bullets with AI help.

Scope: this file defines the AI-assisted development process and is intended to be project-agnostic. Project-specific build/test commands and API spec locations are defined in `AGENTS.md`.

## Model selection and sessions
- Do not ask the user whether to change/switch the model. Use the current configured model by default.
- Only discuss or change the model when the user explicitly requests it or when a step plan explicitly mandates a different model/session for a specific sub-task (e.g., planning).
- If a different model/session is used, record it in the relevant step plan, but do not prompt the user about model choice.

## Git safety (local workflow)
- Never commit directly on `main`/`master`. All commits happen on a local topic branch.
- Branch setup is handled by scripts: the orchestrator planning/design phases use `step-<step>-plan`, the orchestrator implementation phase uses `step-<step>-implementation`, `ai/scripts/ai_user_review.sh` uses `step-<step>-user-review` from implementation, and `ai/scripts/ai_audit.sh` (phase key `ai_audit`) creates/switches `step-<step>-review` from user-review when available (otherwise from implementation).
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
Entry precondition:
- Before prompt generation/model start, `ai/scripts/ai_user_review.sh` runs `.codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py --step <step> --step-plan <step-plan-file>` with `uv run python` and fails fast if implementation was not finished correctly.
- User review operates on ordered-plan completion state only; do not use `overmind/implementation_plan.md` target bullets as user_review phase-state gating.

1. Before starting the user review loop, review the current-step patch as a code reviewer: inspect changed files/diff and nearby code patterns, then check for defects, regressions, missing verification, and drift from the step plan, translated requirements, design scope, accepted decisions, `AGENTS.md`, and applicable `ai/user_review.md` rules. Prioritize previous user decisions and accepted user-review rules that apply to the current changes/scope, including newly relevant rules not shortlisted earlier.
2. Triage self-check findings before asking for user review: fix immediately only when a finding is current-scope and clear/objective or review-blocking; rerun relevant verification after any fix. Otherwise, leave the code unchanged and highlight the finding in the `Review Brief` as a focused hotspot/question.
3. Before asking for review feedback, provide a concise `Review Brief` (plain language, product-level) covering exactly:
   1. what was changed and how (concrete system flow),
   2. how to start code review (where to begin and recommended order),
   3. what should be checked first (top correctness/risk hotspots).
4. Review Brief output constraints:
   - Keep it concise (short checklist-style summary; avoid long narrative).
   - Scope it to current-step changes only.
   - Reference concrete changed entrypoints/files/components/tests when available.
   - Derive "what should be checked first" from the pre-review self-check, including any unfixed current-scope hotspots/questions.
   - Do not narrate artifact creation; focus on reviewer onboarding.
   - Do not guess review ordering/entrypoints. If specific entrypoints are unclear, use cautious non-speculative guidance.
   - Keep the ai_audit entry `Evidence Reasoning Summary` separate; do not merge proof-gate entries into the Review Brief.
   - Use `ai/golden_examples/review_brief_GOLDEN_EXAMPLE.md` as the tone/structure anchor.
5. Ask the user for the next review item (a question or a change request). The user may provide feedback one-by-one; if they have multiple items, a short bullet list helps.
6. When the user responds, do this in order:
   1. Clarify ambiguous requests (ask questions if needed). If the user asked "why", answer the question first.
   2. Implement the requested changes (and any directly necessary test/doc updates). Do not implement changes that were not requested; propose them as suggestions and ask.
   3. Immediately update `ai/user_review.md` with any generalizable rule(s) derived from the user feedback and the implementation change (include references). If there are no generalizable rules, explicitly state that and do not change `ai/user_review.md`.
      - UR-schema gate: new UR entries must be template-complete using `ai/templates/user_review_TEMPLATE.md` required fields: `Trigger`, `Rule`, `How to verify`, `Example(s)`, and `References`.
      - Fallback gate: if feedback is useful but cannot populate the required UR fields with sufficient quality, do not create a UR entry; record a step-specific note in the active step plan instead.
      - De-dup gate: if new feedback overlaps an existing UR rule, update the existing UR entry instead of adding a duplicate/new UR ID.
7. Summarize what changed and ask for the next review round.
8. Repeat steps 5-7 until the user explicitly confirms the review is complete (e.g., "done", "no more comments").
9. Only after the user confirms completion:
   - Run one final verification test command for the step (prefer the repo’s full verification gate from `AGENTS.md`) and report the result.
10. If the final verification passes, propose the next step: Post-step audit/review (Section 6).
- Do not run Section 6 in the implementation phase; Section 6 is executed in the `ai_audit` phase.

### 6) Post-step ai_audit/review (required before moving to the next step)

#### 6.0) Entry proof-check against implementation_plan target bullets (required first gate)
- Before deeper audit analysis, run explicit bullet-by-bullet proof-check against current-step target bullets in `overmind/implementation_plan.md` (non-review implementation bullets for the step).
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
- If any target bullet is `NOT_PROVEN`, fail/flag ai_audit entry and stop before deeper Section 6.1 analysis. Continue 6.1-6.3 only after the entry proof-check passes.

#### 6.1) Analyse TODOs and convert them to findings (required second gate)
- After Section 6.0 passes, scan the in-scope changed files for TODO markers: `//TODO <reason>`.
- Convert every valid TODO marker into an explicit audit finding before continuing to deeper review.
- All TODO-derived findings are then processed via Sections 6.2 and 6.3 like any other finding.

#### 6.2) Audit review and findings
- Entry precondition for this phase: Section 5 (User review) is already complete. Do not ask the user to reconfirm Section 5 during post-step audit.
- Do not start the next implementation step in this phase.
- Start by identifying current uncommitted step changes (for example, `git status --short` and `git diff --name-status`) and inspecting changed files.
- Post-step audit is analysis-only. Do not change runtime code, do not implement fixes, and do not run tests in this phase.
- Allowed changes in this phase are planning/audit artifacts only (for example: `overmind/implementation_plan.md`, `ai/blocker_log.md`, `ai/open_questions.md`, `ai/decisions.md`, `ai/step_review_results/*`).
- If recording new decisions or blockers in this phase, use `ai/templates/decisions_TEMPLATE.md` + `ai/golden_examples/decisions_GOLDEN_EXAMPLE.md` and `ai/templates/blocker_log_TEMPLATE.md` + `ai/golden_examples/blocker_log_GOLDEN_EXAMPLE.md`.
- Re-check for newly introduced blockers/technical debt:
  - If it blocks the next bullet in the current step: add it to `ai/blocker_log.md`.
  - Otherwise: add it as a new future bullet in `overmind/implementation_plan.md`.
- Review all changes produced during the current step (typically on `step-<step>-review`), focusing on correctness and regression risk.
  - Perform an analysis-heavy review: cross-check against `AGENTS.md` rules (idempotency, validation, transaction boundaries, ledger/projection consistency, stream routing, guard rules), `overmind/reqirements_ears.md` acceptance criteria, and updated docs/tests.
  - Produce a detailed review in the response: list findings (if any) with severity (Critical/High/Medium/Low) and file references. If no findings, state that explicitly and mention any residual risks or testing gaps.
  - If issues are found, execute Section 6.3 for each finding. After each finding is dispositioned, return to Section 6.2 and continue the audit.
- Treat Section 6 as a closure loop, not a single pass: after every user decision and every artifact update, re-check the ai_audit completion gates and keep iterating until they pass. Do not stop because the user approved the latest bullet changes if any current-step bullet in `overmind/implementation_plan.md` is still not `[x]` or Section 6.4 still fails.
- Mark all current-step bullets in `overmind/implementation_plan.md` as `[x]` only once the post-step audit write-up is complete, every finding has an explicit disposition recorded (**Accepted** or **Rejected**), and any accepted items are captured as follow-up work (typically as a new step/bullet in `overmind/implementation_plan.md`, or as an item in `ai/open_questions.md`/`ai/blocker_log.md` if still unclear).
- **Commit gate**: only when there are **no accepted unresolved findings** and the user confirms completion, commit all step changes on the current step/review branch and propose the commit commands. If any accepted follow-up work remains, do **not** propose commit commands in this phase. Do not merge to `main`/`master` in this phase.
- Completion-line gate (ai_audit phase): output the exact ai_audit completion line (`ai_audit phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase.`) only after post-step audit write-up is complete, every finding has an explicit disposition (**Accepted** or **Rejected**) with accepted items captured as follow-up work, all current-step bullets in `overmind/implementation_plan.md` are `[x]`, and the AI Audit Disposition Gate (Section 6.4) passes.

#### 6.3) Per-finding issue disposition workflow
- Run this subsection separately for each finding identified in Section 6.2.
1. Create or update `ai/step_review_results/review_result-<current_step>.md` using `ai/templates/audit_result_TEMPLATE.md` and follow the formatting from `ai/golden_examples/audit_result_GOLDEN_EXAMPLE.md`.
2. Ask the user to accept/reject the current issue (confirm severity and whether it should be addressed now).
3. Based on the user’s decision:
   - If rejected: mark it as rejected/closed in `review_result-<current_step>.md` (brief rationale).
   - If accepted for resolution: analyze `overmind/implementation_plan.md` and add it as follow-up work in the appropriate place:
     - Prefer adding a follow-up step immediately after the current step using letter suffixes (e.g., `1.6` → `1.6a`, `1.6a` → `1.6b`, etc.) when it is directly related and should not block earlier steps.
     - Otherwise, add it as a new later step (e.g., `1.6` → `1.12`) if it’s larger or should be scheduled separately.
     - If the “what to do” is still unclear, add it as an item in `ai/open_questions.md` for an already-created step (so it is reviewed during that step’s planning bullet).
4. Return to Section 6.2 and continue the audit. Repeat Section 6.3 for the next finding until all findings have explicit disposition.

#### 6.4) AI Audit Disposition Gate (required before completion and before post_review)
- Before emitting the ai_audit completion line, run `ai/scripts/helpers/check_ai_audit_disposition_readiness.sh <current_step>`.
- The helper is the canonical validation for ai_audit completion readiness:
  - `ai/step_review_results/review_result-<current_step>.md` must exist.
  - `## Disposition (per issue)` must exist.
  - Count issues only from `## Critical`, `## High`, `## Medium`, and `## Low`, excluding `- (none)`.
  - There must be at least one `- **Accepted**:` or `- **Rejected**:` entry for each counted issue.
  - All bullets in the current step section of `overmind/implementation_plan.md` must be checklist bullets and marked `[x]` (including `Review step implementation`).
- If the helper fails:
  - Do not output the ai_audit completion line.
  - Return to the Section 6 audit loop, finish the missing per-issue dispositions and/or close remaining current-step bullets in `overmind/implementation_plan.md`, and rerun the helper.
- `post_review` must run the same helper before history consolidation or other post-review output updates.
- If the helper fails in `post_review`, stop immediately, report that ai_audit dispositions are incomplete, and rerun post_review only after the review artifact passes the helper.

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
