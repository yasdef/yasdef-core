# Implementation Phase as Codex Skill

This is the **final target** specification for the implementation phase as a Codex skill (`yasdef-worker-implementation`). It is written as the to-be design, not as a diff. The single "What Changes vs. the Current Phase" section below is the only place that references the current `ai_implementation.sh` behavior — it exists to mark where this design **deliberately departs** from the current approach, so the conversion is not read as a straight prompt-to-skill translation. `implementation_phase_overview.md` is the matching as-is reference.

---

## Overview

Convert the implementation phase from `ai/scripts/ai_implementation.sh` prompt generation into a repo-provided Codex skill, following the design- and planning-phase pattern:
- shell owns orchestration, branch/path resolution, model invocation, and logging
- the skill owns phase instructions and model behavior
- Python scripts under the skill own deterministic context assembly and the checklist-closure check
- the skill is installed into target projects under `.codex/skills`

Implementation remains the third phase and is the only phase that **writes runtime code**; it is not analysis-only. Both the step plan and the design artifact are hard input gates: implementation must not start without either. Implementation's output is code — there is no implementation-owned artifact (no template, no golden example); the model edits source files and advances the existing step-plan checkboxes.

The legacy `ai_implementation.sh` is currently disabled (`echo "no script to check planing readiness"; exit 1`). This conversion replaces it.

---

## What Changes vs. the Current Phase

Most of the conversion is a mechanical port and should be read as such: one-shot blind prompt → interactive skill; shell `emit()` → `build_implementation_context.py`; shell `check_implementation_readiness.sh` → `check_implementation_readiness.py`. Three changes are **deliberate departures** from the current approach and must be applied on purpose.

### 1. Tighten which design-layer context reaches implementation

Governing rule: a layer reaches implementation **either** by reference (single owner, never duplicated) **or** by translation (the next phase re-expresses it) — never both. The pipeline already enforces this by never letting implementation read `requirements_ears.md` directly: EARS is sealed behind planning's FR translation. By symmetry, design *details* are sealed behind planning's grounding; only the scope contract survives by reference.

| Current prompt block | To-be | Why |
|---|---|---|
| Scope contract — design `## Goal`, `## In Scope`, `## Out of Scope`, `## Non-goals` | **By-reference boundary only: `## Goal`, `## In Scope`, `## Out of Scope`.** `## Non-goals` is dropped. | Planning is forbidden from restating scope, so this is the one design layer passed by reference, not duplicated. The design skill names exactly these three as the boundary; `## Non-goals` is design-internal framing and `## Out of Scope` is the operative exclusion. |
| Key design details — design `## Proposal / Design Details`, `## Risks and Mitigations`, `## Applicable ADR Shortlist`, `## Applicable AGENTS.md Constraints` | **Dropped entirely.** | Double-sourced. Planning already grounds proposal/design details into step-plan `## Plan (ordered)` + `## Architecture / Helper Flow` + `## Implementation Notes`, risks into `## Risks / Edge Cases`, accepted ADRs into `## Accepted Decisions`, and AGENTS constraints into `## Implementation Notes` (plus the AGENTS.md pointer). Passing the design originals hands implementation un-grounded prose it may act on after planning already overrode it. |
| Codebase entrypoints — design `## References in Current Codebase` | **Dropped.** | Planning is "design grounded to the codebase," so codebase entrypoints belong to the step plan's `## Architecture / Helper Flow`. Implementation reads entrypoints from the step plan, not from design. |

### 2. Source the anti-regression checklist from the step plan only

The current checklist dedup-merges the step-plan `## Applicable UR Shortlist` with design UR rules. The skill builds it from the **step-plan `## Applicable UR Shortlist` alone** (cap 8). Planning's curated shortlist is authoritative for the step; re-reading design UR rules is the same double-source the rule above forbids.

### 3. No orchestrator exit gate; readiness is an in-session discipline only

Implementation's output is code. There is no implementation-specific artifact contract to re-validate at phase exit, and code correctness is validated by the **distinct next phases** (user_review, ai_audit) — out of scope here. Therefore:
- The skill runs `check_implementation_readiness.py` **in-session** before its completion line, as completion discipline (all ordered bullets and FRs marked `[x]`, honoring process §4.2). This mirrors the design skill, which also runs its readiness check in-session only.
- The orchestrator does **not** re-run readiness after the skill exits. The unwired `ensure_implementation_phase_completion_gate` in `orchestrator.sh` is removed rather than wired.
- The same checklist-closure check is already consumed as the **user_review entry precondition**; that is where the closed-checklist state is enforced as a gate, not at implementation exit.

---

## Tech Stack

| Layer | Tool | Role |
|---|---|---|
| Orchestration | `bash`/`sh` | resolve selected step, output paths, branch, model command, prompt/log paths |
| Skill runtime | Codex project skill | installed at `.codex/skills/yasdef-worker-implementation` |
| Context assembly | Python 3 via `uv run python` | read step plan, design scope contract, runtime implementation plan; build structured context |
| Markdown parsing | Python stdlib | extract step-plan and design-scope sections deterministically |
| Checklist-closure check | Python 3 via `uv run python` | in-session completion discipline + user_review entry precondition; validates checklist state, not code correctness |
| Skill definition | `SKILL.md` | concise model-facing implementation workflow and gates from `AI_DEVELOPMENT_PROCESS.md §3–4` |

`uv` is a runtime requirement. Do not document or implement a `python3` fallback inside the implementation skill. The skill owns no `assets/` (no output template or golden example — implementation produces code, not an artifact).

---

## Target File Layout

```
ai/
  codex/
    skills/
      yasdef-worker-implementation/
        SKILL.md
        scripts/
          build_implementation_context.py
          check_implementation_readiness.py
```

This replaces both the legacy `ai/scripts/ai_implementation.sh` prompt generator and the shell helper `ai/scripts/helpers/check_implementation_readiness.sh`. Skill-owned runtime belongs inside the skill directory so `init_asdlc_worker.sh` can install it into `.codex/skills/yasdef-worker-implementation`.

---

## Architecture

```
orchestrator implementation phase (single-pass)
     │
     ▼
compact Codex prompt
  - names `yasdef-worker-implementation`
  - passes explicit variables only
  - does not duplicate implementation rules
     │
     ▼
yasdef-worker-implementation/SKILL.md
  - validates required inputs are present
  - instructs model to run context builder
     │
     ▼
scripts/build_implementation_context.py
  - hard-fails when step plan or design artifact is missing
  - reads the step plan as primary execution source
  - extracts: Plan (ordered), Functional Requirements,
    UR shortlist, Implementation Notes, Tests, Risks,
    Decisions Needed / Accepted, Linked Artifacts, Architecture / Helper Flow
  - reads the design scope contract by reference
    (Goal / In Scope / Out of Scope only)
  - builds the anti-regression checklist from the
    step-plan UR shortlist only (cap 8)
  - prints structured context
     │
     ▼
model edits runtime code directly
  - implements ordered bullets in a coherent batch order
  - fetches in-scope LAR locators before implementing dependent FRs
  - marks each ordered bullet [x] only when proven complete
  - marks each FR [x] only when implemented and verified
  - runs targeted checks during, full AGENTS.md gate once at the end
     │
     ▼
scripts/check_implementation_readiness.py  (in-session only)
  - validates ordered-plan + FR checklist closure
  - exits 0 → skill may emit completion line
  - orchestrator does NOT re-run this after exit
```

---

## Orchestrator Contract

The orchestrator follows the design/planning skill pattern:

1. Resolve the routed implementation step (from `--resume` / preferred step plan).
2. Resolve the implementation branch, normally `step-<selected-step>-<feature-id>-implementation`.
3. Resolve: step id, feature id, branch, step plan path, design artifact path, runtime implementation plan path.
4. Write a compact prompt for logging/debug parity (`write_implementation_skill_prompt`).
5. Invoke the configured model once and return its exit status.

Example prompt shape:

```text
Use the `yasdef-worker-implementation` skill to run the ASDLC worker implementation phase.

Inputs:
- Step: <step>
- Feature id: <feature-id>
- Branch: <branch>
- Step plan: <step-plan-file>
- Design artifact: <design-file>
- Runtime implementation plan: <runtime-plan>
```

The orchestrator prompt passes variables only; implementation rules belong in `SKILL.md`. Implementation is **single-pass**: the orchestrator does not loop the model and does not re-validate readiness on exit. Checklist-closure enforcement happens at the user_review phase entry, and code correctness is validated by the later phases.

---

## Skill Input Contract

`yasdef-worker-implementation/SKILL.md` requires explicit inputs:
- step id
- feature id
- branch
- step plan path
- design artifact path
- runtime implementation plan path

If any required input is missing, inconsistent, or points to a missing required file, the skill stops and asks the user for explicit instructions. It must not infer replacement values from `.asdlc_worker/feature_meta_sync.yaml` or the runtime environment. Both the step plan and design artifact paths are required and must exist before implementation starts.

---

## Skill Workflow

The skill instructs the model to:

1. Run context assembly:
   ```bash
   uv run python .codex/skills/yasdef-worker-implementation/scripts/build_implementation_context.py --step <step> --feature-id <feature-id> --step-plan <step-plan-file> --design <design-file> --runtime-plan <runtime-plan>
   ```
2. Read the printed context before editing. It includes the phase contract, the anti-regression checklist (from the step-plan UR shortlist), the execution list (`## Plan (ordered)`), step-plan execution context, and the design scope contract (`## Goal` / `## In Scope` / `## Out of Scope`, by reference). Design proposal/risks/ADR/AGENTS details and codebase references are intentionally **not** included — planning already grounded them into the step plan.
3. Implement against `## Plan (ordered)` (the only execution state machine) and the translated `## Functional Requirements`. Batch work in a coherent order, but close checklist state per bullet.
4. Before implementing any FR that references a `LAR-NNN`, fetch the locator using available web/MCP tooling and treat the fetched content as source of truth. Stop and ask the user instead of inventing content when fetch fails or is ambiguous. Skip if `## Linked Artifacts (in scope)` is empty/absent.
5. If implementation must deviate from the step plan, update the step plan first, then continue.
6. If a design `## Things to Decide` item is still unresolved in the step plan, do **not** decide unilaterally; recommend rerunning planning and follow the user's instruction.
7. Mark each ordered bullet `[x]` only when proven complete; mark each FR `[x]` only when implemented and verified.
8. Run targeted verification as needed during implementation; run the full `AGENTS.md` verification gate **once** after all ordered bullets are `[x]`.
9. Run the in-session completion check once before exit:
   ```bash
   uv run python .codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py --step <step> --step-plan <step-plan-file>
   ```
10. If it fails, present exactly two options (`1.` fix and re-run, `2.` finish with failed status), stop, and wait for explicit user input. Do not auto-select.
11. Emit the completion line only after the check exits `0`.

---

## Context Builder Responsibilities

`build_implementation_context.py` replaces the context-emitting part of `ai_implementation.sh`.

It must:
- require explicit path arguments; no runtime inference
- fail fast if the step plan or design artifact is missing or empty
- read the step plan as the primary execution source
- extract and label, from the step plan:
  - `## Plan (ordered)` (normalized to `- [ ]` / `- [x]` checklist items)
  - `## Functional Requirements (translated from design EARS)` (or `## Functional Requirements`)
  - `## Applicable UR Shortlist`
  - `## Architecture / Helper Flow`
  - `## Implementation Notes / Constraints`
  - `## Tests`
  - `## Risks / Edge Cases`
  - `## Decisions Needed` (full) and the `Accepted` subset
  - `## Linked Artifacts (in scope)`
- extract and label, from the design artifact, the scope contract by reference only: `## Goal`, `## In Scope`, `## Out of Scope`
- build the anti-regression checklist from the step-plan `## Applicable UR Shortlist` only, capped at 8
- emit the phase contract block (artifact precedence, execution state machine, checklist update rules, verification timing, completion protocol)

It must **not** extract or pass: design `## Proposal / Design Details`, `## Risks and Mitigations`, `## Applicable ADR Shortlist`, `## Applicable AGENTS.md Constraints`, `## References in Current Codebase`, `## Non-goals`, or design UR rules. Planning has already grounded these into the step plan (or they are reachable via the AGENTS.md pointer).

Section extraction must be deterministic; missing required step-plan sections must be labeled explicitly (for example `- (missing in step plan)`) rather than silently dropped.

---

## Checklist-Closure Check Responsibilities

`check_implementation_readiness.py` folds the existing shell gate into a single deterministic tool. It validates **checklist state, not code correctness**:
- the canonical step plan `step_plans/step-N-<feature>.md` exists
- `## Plan (ordered)` is present and contains at least one checklist item
- every normalized ordered-plan item is `[x]`
- `## Functional Requirements (translated from design EARS)` (or `## Functional Requirements`) is present and contains at least one FR entry
- every normalized FR item is `[x]`

It preserves the current normalization behavior: plain `- ` bullets are treated as unchecked checklist items, and FR `Status: Done` entries normalize to `[x]`.

Exit codes: `0` ready, `1` not closed (structured errors), `2` invalid usage.

Consumers: (a) the implementation skill, in-session, before its completion line; (b) the user_review phase entry precondition. The orchestrator does **not** run it as an implementation-exit gate.

---

## Implementation Rules To Carry Into SKILL.md

Preserve implementation behavior from `AI_DEVELOPMENT_PROCESS.md §3–4`:
- implementation writes runtime code (this is the executing phase)
- the design scope contract (`## Goal`, `## In Scope`, `## Out of Scope`) is the boundary, read by reference; the step plan `## Plan (ordered)` is the execution contract
- `## Plan (ordered)` is the **only** implementation-phase execution checklist/state machine
- do not use `overmind/implementation_plan.md` target bullets as implementation gating; their proof-check is the first gate in `ai_audit` (§6.0)
- mark an ordered bullet `[x]` only when implemented and verified; mark an FR `[x]` only when implemented and verified
- do not pause after the first item for generic permission; continue through the step. Pause only when blocked by a required user decision/input
- fetch in-scope LAR locators before implementing dependent FRs; ask the user rather than inventing content on fetch failure/ambiguity
- if implementation must deviate from the plan, update the step plan first
- do not resolve unresolved design `## Things to Decide` unilaterally; recommend rerunning planning
- targeted verification during; full `AGENTS.md` verification gate once after all ordered bullets are `[x]`
- record new blockers in `.asdlc_worker/blocker_log.md`, unresolved questions in `.asdlc_worker/open_questions.md`, and durable design choices in `.asdlc_worker/decisions.md` per the rules (feature-level files; implementation is single-pass and does not use per-step loop ledgers)
- keep project-specific implementation constraints in `AGENTS.md`, not in `SKILL.md`
- run the in-session checklist-closure check before the completion line; on failure present exactly two numbered options and wait for explicit user input

---

## Artifacts

### Inputs

| Artifact | How used |
|---|---|
| Step plan | Required hard gate; primary execution source, section-extracted; checkbox state updated in place |
| Design artifact | Required hard gate; **scope contract only** (`## Goal` / `## In Scope` / `## Out of Scope`), read by reference as the boundary. Design details, ADRs, AGENTS constraints, and codebase references are not passed — planning grounded them |
| Runtime `implementation_plan.md` | step routing context only; not used as implementation-phase gating |
| `.asdlc_worker/blocker_log.md` | new blockers recorded when discovered during implementation |
| `.asdlc_worker/open_questions.md` | unresolved questions recorded when surfaced |
| `.asdlc_worker/decisions.md` | a new durable decision may be recorded per §3.1 |
| In-scope `LAR-NNN` locators | fetched and used as source of truth for artifact-specific detail |

### Outputs

| Artifact | Description |
|---|---|
| Runtime code | the implemented change for the step (the phase's primary output) |
| Step plan | `## Plan (ordered)` and FR checkbox state advanced to `[x]` as work is proven |
| Blocker/open-questions/decisions | updated only as required by implementation rules |

Implementation commits runtime + step-plan changes on the `step-N-<feature>-implementation` branch.

---

## Install And Migration Work

1. Add `ai/codex/skills/yasdef-worker-implementation` with `SKILL.md` and the two scripts (no `assets/`).
2. Add `build_implementation_context.py` and `check_implementation_readiness.py` under `scripts/`.
3. Update `init_asdlc_worker.sh` to install `.codex/skills/yasdef-worker-implementation` alongside `yasdef-worker-design` and `yasdef-worker-plan` (the `INSTALL_SKILLS` list and the per-skill install loop).
4. Update `.git/info/exclude` handling for the installed skill path.
5. Replace `run_implementation_phase` prompt generation with a compact `write_implementation_skill_prompt`; keep the phase single-pass and remove the unwired `ensure_implementation_phase_completion_gate`.
6. Repoint the user_review entry precondition in `ai_user_review.sh` from the shell `check_implementation_readiness.sh` to the installed `.codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py`.
7. Remove the legacy `ai_implementation.sh` and `ai/scripts/helpers/check_implementation_readiness.sh` once the skill fully replaces them (no backward compatibility required).
8. Replace the detailed implementation block in `AI_DEVELOPMENT_PROCESS.md §3–4` with a pointer to `.codex/skills/yasdef-worker-implementation/SKILL.md`, keeping cross-phase rules that user_review/ai_audit still need.
9. Update OpenSpec proposal/design/tasks/specs to match the actual implementation.

---

## Tests

Python scripts in the skill must be covered under `tests/skills_python_scripts/`.

Focused script tests should cover:
- worker init installs `.codex/skills/yasdef-worker-implementation`
- orchestrator implementation phase writes a compact `yasdef-worker-implementation` prompt and runs single-pass (no post-exit readiness re-run)
- missing step plan still blocks implementation
- missing design artifact still blocks implementation
- context builder extracts required step-plan sections and the design scope contract (Goal / In Scope / Out of Scope) only
- context builder does not surface design details, ADRs, AGENTS constraints, codebase references, or Non-goals
- anti-regression checklist is built from the step-plan UR shortlist only and capped at 8
- checklist-closure check rejects unchecked ordered bullets and unchecked FR items, and passes for a fully closed step plan
- user_review entry precondition invokes the Python checklist-closure check
- legacy implementation prompt generation and shell readiness helper are no longer required after conversion

Run focused implementation/init/orchestrator/user_review tests plus `git diff --check`.

---

## Boundary With Plan Skill

Implementation must remain a separate skill/process from planning.

- Planning produces the execution contract (`## Plan (ordered)` + translated FRs), grounds design into codebase-specific notes/architecture, and resolves every design decision.
- Implementation reads the step plan as the execution source and the design **file** only for the scope contract (by reference) — not the planning conversation, and not the design's grounded details.
- Planning mirrors LAR ids/locators into the step plan; implementation fetches LAR content and uses it as source of truth.
- Planning is analysis-only; implementation writes runtime code.
- Implementation does not resolve open design decisions; it routes them back to planning.
- Implementation commits on its own `step-N-<feature>-implementation` branch, not the shared `step-N-<feature>-plan` branch.

This boundary preserves session independence and keeps implementation operating from the step plan and the design scope contract, not from live planning conversation history.
