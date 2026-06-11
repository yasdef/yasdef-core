---
name: yasdef-worker-implementation
description: Run the YASDEF ASDLC worker implementation phase for an assigned step. Use when yasdef or the user asks to implement runtime code from a completed step plan and design artifact, update step-plan checklist state, and finish implementation handoff.
metadata:
  short-description: YASDEF worker implementation phase
---

# YASDEF Worker Implementation

Use this skill for the ASDLC worker implementation phase. This is the executing phase: edit runtime code and update the step plan checklist state.

## Inputs

The yasdef prompt should provide:
- step id, for example `1.3`
- feature id
- branch name
- step plan path
- design artifact path
- runtime implementation plan path

If any input is missing, inconsistent, or points to a missing required file, do not infer it from `.asdlc_worker/feature_meta_sync.yaml` or the runtime environment. Stop and ask the user for explicit instructions.

## Phase Contract

- Artifact precedence: step plan is the primary execution source; design supplies scope boundary only.
- Scope boundary: use design `## Goal`, `## In Scope`, and `## Out of Scope`; do not use design `## Non-goals`.
- Execution state machine: step plan `## Plan (ordered)` only.
- Functional contract: implement step-plan translated FRs.
- Checklist updates: mark ordered bullets and FRs `[x]` only when implemented and verified.
- LAR rule: fetch in-scope locators before implementing dependent FRs; ask the user on fetch failure or ambiguity.
- Verification timing: targeted checks during implementation; full `AGENTS.md` gate once after all ordered bullets are `[x]`.
- Completion protocol: run `check_implementation_readiness.py` before the completion line.
- Runtime plan gating: do not use `implementation_plan.md` target bullets as implementation-phase proof state.

## Workflow

1. Run the context builder:
   ```bash
   uv run python .claude/skills/yasdef-worker-implementation/scripts/build_implementation_context.py --step <step> --feature-id <feature-id> --step-plan <step-plan-file> --design <design-file> --runtime-plan <runtime-plan>
   ```

2. Read the printed context before editing. It includes the phase contract, the anti-regression checklist, the execution list, step-plan execution context, and design scope contract.

   The step plan is the primary execution source. The design artifact supplies only the scope boundary: `## Goal`, `## In Scope`, and `## Out of Scope`.

   Do not use design proposal details, design risks, design ADRs, design AGENTS constraints, design codebase references, design UR rules, or design non-goals as implementation input. Planning already grounded those details into the step plan.

3. Implement against `## Plan (ordered)` as the only execution checklist/state machine and `## Functional Requirements (translated from design EARS)` as the translated behavior contract.

   Before you start editing, skim `## Plan (ordered)` and look for natural batches — bullets that touch the same file or module, share a dependency, or form a build order. If you spot batches, group your code changes that way and work a batch at a time; it's not a strict rule, follow this if possible.

4. Batch work in a coherent order, but close state per bullet:
   - mark each ordered bullet `[x]` only when implemented and verified
   - mark each FR `[x]` only when implemented and verified
   - leave incomplete work unchecked
   - if blocked on a bullet, record the blocker and continue with remaining feasible work

5. Before implementing any FR that references a `LAR-NNN`, fetch the matching locator from `## Linked Artifacts (in scope)` using available web/MCP tooling. Treat fetched content as source of truth. If fetch fails or is ambiguous, stop and ask the user instead of inventing content. Skip this when no in-scope LAR block exists.

6. If implementation must deviate from the step plan, update the step plan first, then continue.

7. If a design `## Things to Decide` item is still unresolved in the step plan, do not decide unilaterally. Recommend rerunning planning and follow the user's instruction.

8. Run targeted verification as needed during implementation. Run the full `AGENTS.md` verification gate once after all ordered bullets are `[x]`.

9. Record new blockers in `.asdlc_worker/blocker_log.md`, unresolved questions in `.asdlc_worker/open_questions.md`, and durable design choices in `.asdlc_worker/decisions.md` when the process rules require it.

10. Run the in-session checklist-closure check once before exit:
    ```bash
    uv run python .claude/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py --step <step> --step-plan <step-plan-file>
    ```

11. If the check fails, present exactly two options and wait for explicit user input:
    1. fix the remaining checklist/FR state and re-run the check
    2. finish with failed status

12. Emit the completion line only after the check exits `0`.

## Implementation Rules

- Do not pause after the first item for generic permission; continue through the step unless blocked by required user input.
- Add or update tests: cover the happy path always and key non-happy-path cases when feasible, based on the step plan and linked requirements.
- Reuse existing code patterns; keep each change minimal, cohesive, readable, and directly traceable to ordered-plan work items. Remove unnecessary boilerplate and avoid extra guard checks.
- Do not use `implementation_plan.md` target bullets as implementation-phase gating; their proof-check belongs to `ai_audit`.
- Keep project-specific implementation constraints in `AGENTS.md`, not in this skill.
- Do not commit changes at the end of the phase; leave them uncommitted so user_review can inspect the live patch directly.

## Completion

Only after code is implemented, ordered bullets and FRs are closed, verification has run, and `check_implementation_readiness.py` exits `0`, end your final response with these exact last two lines:
`Implementation phase finished. Nothing else to do now; press Ctrl-C so yasdef can start the next phase.`
`PHASE_FINISHED_CAN_CLOSE`
