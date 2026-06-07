---
name: yasdef-worker-design
description: Run the YASDEF ASDLC worker design phase for an assigned step. Use when yasdef or the user asks to create, update, validate, or finish a step design artifact under .asdlc_worker/step_designs before planning.
metadata:
  short-description: YASDEF worker design phase
---

# YASDEF Worker Design

Use this skill for the ASDLC worker design phase. The phase is analysis-only: do not implement runtime code.

## Inputs

The yasdef prompt should provide:
- step id, for example `1.3`
- feature id
- design output path, normally `.asdlc_worker/step_designs/step-<step>-<feature-id>-design.md`
- runtime plan path
- runtime EARS path

If any input is missing, inconsistent, or points to a missing file/path, do not infer it from `.asdlc_worker/feature_meta_sync.yaml` or the runtime environment. Stop and ask the user for explicit instructions.

## Workflow

1. Run the context builder:
   ```bash
   uv run python .claude/skills/yasdef-worker-design/scripts/build_design_context.py --step <step> --design-out <design-file> --plan <runtime-plan> --ears <runtime-ears>
   ```

2. Read the printed context before editing. It includes the step section, selected EARS blocks, in-scope LAR shortlist, blocker/open-question sections, feature metadata, the current design artifact, and the bundled golden example.

   Treat `assets/feature_design_TEMPLATE.md` as the structural contract for a new design artifact. The context builder uses it to initialize the artifact when missing; keep its headings and section intent unless the user explicitly changes the design contract.

   Treat `assets/feature_design_GOLDEN_EXAMPLE.md` as a style and completeness reference only. Do not copy its domain content, IDs, paths, dates, decisions, ADRs, UR rules, or linked artifacts into the current design. Use it to calibrate level of detail, decision shape, section density, and concise wording.

3. Edit the design artifact directly. Keep it concise and decision-focused.

4. Apply the design rules and gates below.

5. Before finishing, run:
   ```bash
   uv run python .claude/skills/yasdef-worker-design/scripts/check_design_readiness.py <design-file>
   ```

6. If readiness fails, fix the design and re-run the gate. If a real user decision is required, ask exactly one concrete question and wait.

7. Finish only after the readiness gate exits `0`.

## Required Design Content

The design artifact must include:
- `## Target Bullets (excluding planning/review)`
- `## Selected EARS Requirements (for planning translation)`
- `## Goal`
- `## In Scope`
- `## Out of Scope`
- `## Things to Decide (for final planning discussion)`
- `## Linked Artifacts (in scope)`
- relevant `user_review.md` rules
- relevant accepted ADR shortlist from `.asdlc_worker/decisions.md`

The scope contract lives in `## Goal`, `## In Scope`, and `## Out of Scope`. Planning and implementation use those sections as the boundary.

## Design Rules

- Do not fetch LAR content in design. Only shortlist referenced LAR ids and locators from `requirements_ears.md`.
- Do not update `.asdlc_worker/decisions.md` in design. Capture candidate decisions under `## Things to Decide`.
- Include only relevant rules from `.asdlc_worker/user_review.md`; do not dump the whole file.
- Shortlist only relevant accepted ADRs; do not dump all ADRs.
- Track unresolved follow-up questions in `.asdlc_worker/open_questions.md` when they must be explicitly handled during planning.
- Design is a hard gate: planning must not run without the design artifact.

## Bootstrap Decision

Before handoff, decide whether this is first-feature bootstrap.

Treat the step as first-feature bootstrap only when it must create the initial runnable scaffold/stack for the worker class because there is no meaningful existing implementation to extend.

Inspect:
- existing source files for the class
- app/module scaffold
- dependency/build setup
- runtime entrypoints
- whether the step bullets are scaffold creation work or normal feature extension work

If bootstrap is required, add `## First-Feature Bootstrap (only if needed)` with:
- `Bootstrap required: yes`
- blueprint lookup result
- blueprint evidence or explicit user stack decision
- concrete planning handoff

When stack/architecture guidance is needed, run `.asdlc_worker/scripts/helpers/helper_find_blueprints.sh` from the ASDLC feature folder context where `implementation_plan.md` and `requirements_ears.md` live. If class metadata is missing/unsupported or no relevant blueprint exists, ask the user for stack/scaffold direction instead of inventing one.

## Missing Discussion Points Gate

Before handoff, scan for planning-relevant unresolved gaps:
- scope boundaries and exclusions
- external interfaces and dependencies
- data and state lifecycle
- failure, recovery, and rollback behavior
- operational and quality constraints
- verification strategy

Normalize meaningful unresolved findings into `## Things to Decide (for final planning discussion)`.

Each decision item must be concrete, action-driving, and contain mutually exclusive options with trade-offs, both options must be realistically viable. For non-trivial scope, capture 1-5 plan-critical items. If there are no plan-critical choices, write `- None.` with a short rationale.

## Completion

Only after the design artifact is updated and `check_design_readiness.py` exits `0`, end your final response with these exact last two lines:
`Design phase finished. Nothing else to do now; press Ctrl-C so yasdef can start the next phase.`
`PHASE_FINISHED_CAN_CLOSE`
