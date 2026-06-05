---
name: yasdef-worker-user-review
description: Run the YASDEF ASDLC worker user review phase for an assigned step. Use when the orchestrator or user asks to review a closed implementation step with the user, implement requested follow-up changes, record durable user-review rules, and finish the user review handoff before ai_audit.
metadata:
  short-description: YASDEF worker user review phase
---

# YASDEF Worker User Review

Use this skill for the ASDLC worker user review phase. This is an executing phase: edit runtime code, apply requested test/doc updates, and update `.asdlc_worker/user_review.md` when feedback yields a durable rule.

## Inputs

The orchestrator prompt should provide:
- step id, for example `1.3`
- feature id
- branch name
- step plan path
- design artifact path
- runtime implementation plan path

If any input is missing, inconsistent, or points to a missing required file, do not infer it from `.asdlc_worker/feature_meta_sync.yaml` or the runtime environment. Stop and ask the user for explicit instructions.

## User Review Rules

- User review writes runtime code and durable user-review rules.
- Treat step-plan `## Plan (ordered)` as the phase-state source. Do not use `implementation_plan.md` target bullets as user-review proof state.
- Record new blockers in `.asdlc_worker/blocker_log.md`, unresolved questions in `.asdlc_worker/open_questions.md`, and durable technical decisions in `.asdlc_worker/decisions.md` when the process rules require it.
- Keep project-specific verification and review constraints in `AGENTS.md`, not in this skill.
- User review commits runtime and UR-rule changes on the `step-<step>-<feature-id>-user-review` branch.

## Workflow

1. Build context:
   ```bash
   uv run python .claude/skills/yasdef-worker-user-review/scripts/build_user_review_context.py --step <step> --feature-id <feature-id> --step-plan <step-plan-file> --design <design-file> --runtime-plan <runtime-plan>
   ```

2. Read the printed context before reviewing. It includes the phase contract, the review contract from the step plan, accepted decisions, the step-plan `## Applicable UR Shortlist`, the design scope contract (`## Goal`, `## In Scope`, `## Out of Scope`), the current-step blocker/open-question sections, and pointers to the full `.asdlc_worker/user_review.md` plus the local assets.

   The step plan is the review contract. The design artifact supplies only the scope boundary.

   Do not use design proposal details, design risks, design ADRs, design non-goals, or design UR rules as review input. Planning already grounded those details into the step plan.

3. Run the pre-review self-check on the live patch first: inspect `git status`, `git diff`, and nearby code, then check for defects, regressions, missing verification, and drift from the step plan, translated FRs, design scope, accepted decisions, `AGENTS.md`, and applicable `.asdlc_worker/user_review.md` rules. Prioritize previous user decisions and accepted UR rules that apply to the current scope, including newly relevant rules not in the shortlist.

4. Triage self-check findings before asking for feedback:
   - fix immediately only when a finding is current-scope and clear/objective or review-blocking
   - rerun relevant verification after any fix
   - otherwise leave the code unchanged and surface the finding in the Review Brief as a focused hotspot/question

5. Emit a concise Review Brief before asking for feedback. Cover exactly:
   - what changed and how (concrete system flow)
   - how to start the code review (where to begin and recommended order)
   - what to check first, derived from the pre-review self-check, including any unfixed current-scope hotspots/questions

   Use `assets/review_brief_TEMPLATE.md` for the output structure and `assets/review_brief_GOLDEN_EXAMPLE.md` for tone and density. Keep it concise and current-scope. Reference concrete entrypoints/files/tests when available. Do not narrate artifact creation. Do not guess ordering or entrypoints; if entrypoints are unclear, give cautious non-speculative guidance. Keep it separate from the `ai_audit` Evidence Reasoning Summary.

6. Ask the user for the next review item. On each response, in order:
   1. Clarify ambiguity. If the user asked "why", answer that first.
   2. Implement the requested change plus directly necessary test/doc updates. Do not implement unrequested changes; propose them and ask.
   3. Immediately update `.asdlc_worker/user_review.md` with any durable generalizable rule derived from the feedback and implementation change. If there is no durable rule, say so explicitly and leave the file unchanged.
      - UR-schema gate: new entries must be template-complete per `assets/user_review_TEMPLATE.md` with `Trigger`, `Rule`, `How to verify`, `Example(s)`, and `References`.
      - Fallback gate: if the feedback is useful but cannot populate those fields with quality, record a step-specific note in the active step plan instead of creating a UR entry.
      - De-dup gate: if the feedback overlaps an existing UR rule, update that entry instead of creating a duplicate/new UR ID.
   4. Summarize what changed and ask for the next round.

7. Repeat step 6 until the user explicitly confirms review completion.

8. Only after the user confirms completion, run one final verification command for the step. Prefer the full `AGENTS.md` verification gate. Report the result. After final `AGENTS.md` verification passes, end your final response with these exact last two lines:
`User review phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase.`
`PHASE_FINISHED_CAN_CLOSE`
