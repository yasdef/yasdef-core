---
name: yasdef-worker-plan
description: Run one YASDEF ASDLC worker planning iteration for an assigned step. Use when the orchestrator or user asks to create, update, validate, or finish a step plan artifact under .asdlc_worker/step_plans after design is complete.
metadata:
  short-description: YASDEF worker planning phase
---

# YASDEF Worker Plan

Use this skill for one ASDLC worker planning iteration. The phase is analysis-only: do not implement runtime code.

## Inputs

The orchestrator prompt should provide:
- step id, for example `1.3`
- feature id
- branch name
- design artifact path
- step plan output path
- runtime implementation plan path
- open-questions ledger path
- blockers ledger path

If any input is missing, inconsistent, or points to a missing required file/path, do not infer it from `.asdlc_worker/feature_meta_sync.yaml` or the runtime environment. Stop and ask the user for explicit instructions.

## Artifact Model

- The step plan file under `.asdlc_worker/step_plans/` is the single planning artifact for the step.
- `build_plan_context.py` initializes that file from `assets/step_plan_TEMPLATE.md` when it is missing.
- After initialization, the file stops being a template copy and becomes the real planning artifact that will hand off to implementation once it is fully filled and passes readiness validation.
- The per-step ledgers under `.asdlc_worker/step_open_questions/` and `.asdlc_worker/step_blockers/` are loop-state artifacts for the orchestrator. Their contents determine whether the planning phase needs another iteration.

## Workflow

1. Build context:
   ```bash
   uv run python .claude/skills/yasdef-worker-plan/scripts/build_plan_context.py --step <step> --feature-id <feature-id> --design <design-file> --plan-out <step-plan-file> --runtime-plan <runtime-plan> --open-questions <open-questions-file> --blockers <blockers-file>
   ```

2. Read the printed context before editing. It includes the current step section, extracted design sections, the current step plan, the per-step ledgers, the requirements EARS file path as a pointer, and the bundled golden example.

   Treat `assets/step_plan_TEMPLATE.md` as the structural contract for a new step plan. The context builder initializes the artifact when it is missing; keep its headings and section intent unless the user explicitly changes the planning contract.

   Treat `assets/step_plan_GOLDEN_EXAMPLE.md` as a style and completeness reference only. Do not copy its domain content, IDs, paths, dates, decisions, URs, ADRs, tests, or linked artifacts into the current plan.

3. Process unresolved planning state for this iteration:
   - first, use design `## Things to Decide (for final planning discussion)` or `## Things to Decide` as the primary source of decision candidates that must have explicit recorded outcomes in the step plan
   - then use the current open-questions ledger as the unresolved question source carried across iterations
   - then use the current blockers ledger as the unresolved blocker source carried across iterations
   - use step-plan `## Decisions Needed` as the current recorded decision state
   - resolve unresolved user-required items from those sources one-by-one with the user using the `## Question Resolution Contract`

4. Update the step plan artifact:
   - update the full step plan artifact, with `## Plan (ordered)` and `## Functional Requirements (translated from design EARS)` as the primary execution contract
   - update or generate `## Plan (ordered)`
   - update or generate `## Functional Requirements (translated from design EARS)`
   - update `## Applicable UR Shortlist`
   - update `## Architecture / Helper Flow` when execution mechanics or helper/service call flow matter for implementation invariants
   - update `## Implementation Notes / Constraints` with relevant execution constraints
   - update `## Tests`, `## Docs / Artifacts`, `## Risks / Edge Cases`, and `## Assumptions` so the artifact is complete for implementation handoff
   - keep `## Applicable UR Shortlist` as exact `- None.` or a curated list of at most 8 `UR-xxxx` entries
   - mirror the design LAR block into the step plan:
   ```bash
   uv run python .claude/skills/yasdef-worker-plan/scripts/sync_step_lars.py --design <design-file> --step-plan <step-plan-file>
   ```

5. Analyze the repo against the updated plan:
   - inspect relevant repo files against the current plan
   - actively scan for missing prerequisites: schema, endpoints, validators, error codes, auth assumptions, repo/metadata registration, and handoff state the later steps depend on
   - when a prerequisite is missing, add it as a concrete `## Plan (ordered)` bullet for the current step (mark it as technical debt if discovered late) — do not record it only as a soft note in another section
   - identify remaining planning gaps and plan-critical trade-offs
   - fix self-contained planning defects directly in the step plan instead of writing them to ledgers
   - write only new user-required unresolved items to the open-questions or blockers ledger using the `## Ledger Writing Contract`

6. Run readiness once before exit:
   ```bash
   uv run python .claude/skills/yasdef-worker-plan/scripts/check_planning_readiness.py --design <design-file> --step-plan <step-plan-file> --open-questions <open-questions-file> --blockers <blockers-file>
   ```

   - if readiness fails because of a self-contained plan defect, fix it in the same session and re-run readiness
   - if readiness still depends on unresolved user-required input, keep that item in the ledgers and exit
   - do not loop internally
   - do not keep asking newly discovered repo-analysis questions in the same session after step 5; write them to ledgers and exit so the orchestrator can decide whether to re-invoke

7. Exit. The orchestrator owns the planning loop.
   - If readiness is `0` and both ledgers are clean, you may emit the completion line from `## Completion`.
   - If readiness is non-zero or either ledger still contains unresolved entries, exit without the completion line so the orchestrator can re-check and decide whether to re-invoke.

## Question Resolution Contract

- At the start of the session, check design `## Things to Decide` first. On the first iteration this is usually the primary source of decision questions because the per-step ledgers may still be empty right after initialization.
- After design `## Things to Decide`, process unresolved items already recorded in step-plan `## Decisions Needed`, then process the current open-questions ledger and blockers ledger as carried-over unresolved state from prior iterations.
- Design `## Things to Decide` provides candidate decisions that must be resolved or explicitly recorded.
- Step-plan `## Decisions Needed` is the current recorded decision state for the step and must be updated, not discarded or treated as a scratchpad.
- For every design decision item processed in this session, update step-plan `## Decisions Needed` with an explicit outcome. The outcome vocabulary is fixed:
  - `Accepted` — the decision is made; this is the chosen outcome
  - `Deferred` — the decision is postponed to a later step or phase; state where it is tracked
  - `Blocked` — the decision cannot be made because of an unresolved blocker; reference the blocker
  - Do not use `Deferred` to mean "the option I did not pick." A rejected alternative is not a separate outcome.
- The two-option prompt is only how you ask the user live; it is not how you record the result. Record exactly one line per design decision in `## Decisions Needed` using the format the template and golden example model: `- <decision title> | <Accepted|Deferred|Blocked> | <chosen result and short rationale>`. If the rejected alternative is worth noting, put it inside the rationale clause — never as its own `Option 1` / `Option 2` outcome line.
- Resolve existing items one-by-one. Do not batch unrelated questions together.
- Ask at most one planning question per assistant message.
- If a decision needs explicit user choice, ask using exactly two numbered options. Always label the first option `(Recommended)`:
  - `1. (Recommended)` the default choice with short rationale
  - `2.` the alternative choice with short trade-off rationale
- Keep the two options mutually exclusive, actionable, and easy to answer with only `1` or `2`.
- If a design item is vague, first normalize it into a concrete decision-shaped question before asking.
- After the user answers, immediately update the step plan and rewrite the ledgers so resolved items are removed and `## Decisions Needed` reflects the current recorded outcomes. Do not leave answered items in the ledger files.
- Do not auto-select unresolved design decisions just because a preferred option exists. Require explicit user choice unless the same choice was already explicitly provided for the current step.
- If design `## Things to Decide` is empty but a plan-critical trade-off exists in prerequisites, risks, tests, or docs, ask one explicit two-option confirmation before finishing question resolution. If no plan-critical trade-offs remain, record that explicitly and proceed.
- When a resolved decision is durable (affects multiple steps or has architectural implications), also record it in `.asdlc_worker/decisions.md` in addition to step-plan `## Decisions Needed`.

## Plan Update Contract

- Use the design artifact as the planning scope source of truth. Do not restate full scope sections from design in the step plan; keep the plan execution-focused.
- After question resolution, re-read every existing FR against the design `## Selected EARS Requirements (for planning translation)` section before adding new FRs. If a resolved decision changed wording, update the affected FRs first.
- Treat the whole step plan as the implementation handoff artifact, with `## Plan (ordered)` and `## Functional Requirements (translated from design EARS)` as the most important sections.
- Keep `## Plan (ordered)` concrete, execution-focused, and suitable as the later implementation contract.
- Translate selected EARS into self-contained FRs. Each FR must map to exactly one `EARS[REQ-...]` or `EARS[NFR-...]` source item.
- Each selected EARS source item must map to at least one FR.
- Canonical FR format: `- [ ] FR-<step-id>-<nnn> The system SHALL ... EARS[REQ-...]`
- If one selected EARS source item contains multiple independent SHALL outcomes, split it into multiple FRs. Split only when outcomes are independently verifiable; keep as one FR when behavior is inseparable for verification.
- Keep FR wording self-contained and testable. Do not make FR meaning depend on `## Decisions Needed` or implementation notes.
- Keep the rest of the artifact complete enough for implementation handoff: shortlist, architecture/helper flow, constraints, tests, docs/artifacts, risks/edge cases, assumptions, and decisions.
- Do not include `## Target Bullets` or `## Requirement Tags` in the step plan.
- Require `## Plan (ordered)` and `## Functional Requirements (translated from design EARS)` in that order.
- If design records `Bootstrap required: yes`, require `## Scaffold Bootstrap Plan` and place scaffold creation before dependent implementation work in `## Plan (ordered)`.

## Ledger Writing Contract

- Ledger files are not scratchpads. They are the orchestrator-visible unresolved-state files for this step.
- Before exit, rewrite the ledgers to reflect the current unresolved state only.
- Remove items that were resolved in this session.
- Write to `open-questions` only when explicit user input or approval is still required to finish planning.
- Write to `blockers` only when planning cannot close because of a real unresolved blocking condition.
- Do not write self-contained plan fixes, obvious prerequisite additions, or wording cleanups to ledgers; fix those directly in the step plan.
- If repo analysis discovers a new user-required gap late in the session, write it to the correct ledger and exit. Do not start a new internal mini-loop for it.

## Planning Rules

- Do not implement runtime code in this phase.
- Do not infer missing stack, API, or architectural decisions that require user approval.
- Keep the plan concise. The step plan is an execution contract, not a duplicate of the design artifact.
- The orchestrator, not this skill, decides whether another planning iteration is needed.

## Completion

Only after all of the following are true:
- the step plan is updated and passes `check_planning_readiness.py` (exit `0`)
- LAR sync has been applied
- both ledger files are clean
- this step's "Plan and discuss the step." bullet is marked `[x]` in the runtime implementation plan file (the path provided as `Runtime implementation plan` input)
- the runtime implementation plan lives in the bound ASDLC repo, not the worker repo; commit that file directly on its current branch without creating a new branch — the orchestrator handles pushing that commit
- planning artifacts are committed in the worker repo on the planning branch: include both the step plan and the design artifact; do not commit the step plan alone

End your final response with these exact last two lines:
`Planning phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase.`
`PHASE_FINISHED_CAN_CLOSE`
