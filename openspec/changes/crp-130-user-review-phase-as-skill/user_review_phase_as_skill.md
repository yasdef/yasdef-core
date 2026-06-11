# User Review Phase as Codex Skill

This is the **final target** specification for the user review phase as a Codex skill (`yasdef-worker-user-review`). It is written as the to-be design, not as a diff. The single "What Changes vs. the Current Phase" section below is the only place that references the current `ai_user_review.sh` behavior — it exists to mark where this design **deliberately departs** from the current approach, so the conversion is not read as a straight prompt-to-skill translation. `user_review_step_overview.md` is the matching as-is reference.

---

## Overview

Convert the user review phase from `ai/scripts/ai_user_review.sh` prompt generation into a repo-provided Codex skill, following the design-, planning-, and implementation-phase pattern:
- shell owns orchestration, branch/path resolution, the implementation-readiness **entry gate**, model invocation, and logging
- the skill owns phase instructions and model behavior
- a Python script under the skill owns deterministic context assembly
- the skill is installed into target projects under `.codex/skills`

User review remains the fourth phase. Like implementation, it **writes runtime code**: it implements the changes the user requests during the review loop, plus directly necessary test/doc updates. It is also the only phase that writes durable user-review rules to `.asdlc_worker/user_review.md`, governed by the UR-schema / fallback / de-dup gates. Both the step plan and the design artifact are hard input gates, and the implementation-readiness check is a hard **entry** gate: review must not start from an unclosed implementation state.

Unlike design/planning/implementation, user review owns **no completion-readiness script**. Completion is explicit user confirmation plus a passing final `AGENTS.md` verification gate — there is no deterministic artifact-closure contract to re-validate at phase exit (see "What Changes" §3).

---

## What Changes vs. the Current Phase

Most of the conversion is a mechanical port and should be read as such: one-shot blind prompt → interactive skill; shell `emit()` → `build_user_review_context.py`; the `ensure_user_review_entry_gate` precheck → an orchestrator-owned entry gate invoked before the skill starts. Three changes are **deliberate departures** from the current approach and must be applied on purpose. The first two mirror the implementation-phase conversion exactly; they apply the same governing rule.

Governing rule (shared with implementation): a design layer reaches user review **either** by reference (single owner, never duplicated) **or** by translation (planning already re-expressed it) — never both. EARS is sealed behind planning's FR translation; design *details* are sealed behind planning's grounding; only the scope contract survives by reference. User review reviews the actual patch against the **grounded** step plan, not against un-grounded design prose.

### 1. Tighten which design-layer context reaches user review

| Current prompt block | To-be | Why |
|---|---|---|
| Design key excerpts — design `## Proposal / Design Details`, `## Risks and Mitigations` | **Dropped entirely.** | Double-sourced. Planning already grounds proposal/design details into step-plan `## Plan (ordered)` + `## Architecture / Helper Flow` + `## Implementation Notes`, and risks into `## Risks / Edge Cases`. The reviewer checks the patch against the grounded step plan and the live diff, not against design prose that planning may have already overridden. |
| Design `## Applicable ADR Shortlist` | **Dropped.** Use step-plan accepted decisions instead. | Planning grounds accepted ADRs into the step plan (`## Accepted Decisions` / the `Accepted` subset of `## Decisions Needed`). §5's "drift from accepted decisions" check reads the step-plan-grounded decisions, not the design ADR shortlist. |
| Scope contract — design `## Goal`, `## In Scope`, `## Out of Scope` (currently absent from the prompt; the model is told to check "design scope" without being given it) | **By-reference boundary only: `## Goal`, `## In Scope`, `## Out of Scope`.** | This is the one design layer planning is forbidden from restating, so it is passed by reference (not duplicated). The reviewer needs it to check the patch for scope drift, which §5 step 1 already requires. `## Non-goals` stays out — it is design-internal framing; `## Out of Scope` is the operative exclusion. |

### 2. Source applicable review rules from the step plan + the full `user_review.md`, not design UR rules

The current prompt passes the design `## Applicable UR Shortlist`. The skill instead supplies:
- the **step-plan `## Applicable UR Shortlist`** (planning's curated priority subset, cap 8) as the prioritized rules, and
- a pointer to the **full `.asdlc_worker/user_review.md`**, because §5 step 1 explicitly requires applying "newly relevant rules not shortlisted earlier" — user review is both the phase that *applies* UR rules and the only phase that *writes* them, so it must see the whole ruleset, not a frozen shortlist.

Design UR rules are dropped: planning already curated them into the step-plan shortlist (the same double-source the governing rule forbids).

### 3. No orchestrator exit gate and no user-review readiness script; the entry gate moves to the orchestrator

User review's outputs are runtime code, test/doc edits, and durable UR rules. There is no single deterministic artifact-closure contract to re-validate at phase exit, and code correctness is validated by the **distinct next phase** (`ai_audit`) — out of scope here. Therefore:
- The skill does **not** own a `check_*_readiness.py`. Completion is explicit user confirmation plus a passing final `AGENTS.md` verification gate, then the completion line.
- The implementation-readiness check (`check_implementation_readiness.py`) remains the hard **entry** precondition, but it moves from `ai_user_review.sh`'s `ensure_user_review_entry_gate` to the **orchestrator**, which runs it before invoking the skill and fails fast if implementation is not closed. This is the canonical "user_review entry precondition" already referenced by the implementation-phase design.
- The orchestrator does **not** re-run any readiness check after the skill exits; it advances to `ai_audit` on the user-review branch marker, as today.

---

## Tech Stack

| Layer | Tool | Role |
|---|---|---|
| Orchestration | `bash`/`sh` | resolve selected step, output paths, branch (from implementation branch), model command, prompt/log paths; run the implementation-readiness entry gate |
| Skill runtime | Codex project skill | installed at `.codex/skills/yasdef-worker-user-review` |
| Context assembly | Python 3 via `uv run python` | read step plan, design scope contract, step-plan UR shortlist, blocker/open-questions step sections; build structured review context |
| Markdown parsing | Python stdlib | extract step-plan and design-scope sections deterministically |
| Entry gate (reused) | Python 3 via `uv run python` | `check_implementation_readiness.py` from the implementation skill; run by the orchestrator as the hard entry precondition |
| Skill definition | `SKILL.md` | concise model-facing review workflow and gates from `AI_DEVELOPMENT_PROCESS.md §5` |
| Skill assets | markdown | UR template + Review Brief template + Review Brief / UR golden examples used during the review loop |

`uv` is a runtime requirement. Do not document or implement a `python3` fallback inside the user-review skill.

---

## Target File Layout

```
ai/
  codex/
    skills/
      yasdef-worker-user-review/
        SKILL.md
        scripts/
          build_user_review_context.py
        assets/
          user_review_TEMPLATE.md
          review_brief_TEMPLATE.md
          review_brief_GOLDEN_EXAMPLE.md
          user_review_GOLDEN_EXAMPLE.md
```

This replaces the legacy `ai/scripts/ai_user_review.sh` prompt generator. The skill owns `assets/` (unlike implementation) because user review consumes the Review Brief template/golden example pair and writes UR entries against the UR template + UR golden example. The entry-gate script is **not** copied here — the skill reuses the installed `.codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py`, invoked by the orchestrator.

---

## Architecture

```
orchestrator user_review phase (single-pass)
     │
     ▼
hard entry gate (orchestrator-owned)
  uv run python .codex/skills/yasdef-worker-implementation/
      scripts/check_implementation_readiness.py --step <step> --step-plan <plan>
  - fails fast if implementation is not closed (any ordered/FR item unchecked)
     │
     ▼
resolve + create branch step-N-<feature>-user-review (from …-implementation)
     │
     ▼
compact Codex prompt
  - names `yasdef-worker-user-review`
  - passes explicit variables only
  - does not duplicate review rules
     │
     ▼
yasdef-worker-user-review/SKILL.md
  - validates required inputs are present
  - instructs model to run the context builder
     │
     ▼
scripts/build_user_review_context.py
  - hard-fails when step plan or design artifact is missing
  - reads the closed step plan as the review contract
  - extracts: Plan (ordered), Functional Requirements,
    Accepted Decisions, Applicable UR Shortlist (cap 8)
  - reads the design scope contract by reference
    (Goal / In Scope / Out of Scope only)
  - extracts blocker_log / open_questions step sections
  - points to full user_review.md + UR template + golden examples
  - prints structured review context
     │
     ▼
model runs the review loop interactively
  - inspects the current-step diff as a code reviewer (self-check)
  - triages findings (fix clear/blocking now; surface the rest)
  - emits a concise Review Brief (golden-example anchor)
  - asks → clarifies → implements requested changes →
    records durable UR rules (schema / fallback / de-dup gates) → summarizes
  - repeats until the user explicitly confirms completion
  - runs the full AGENTS.md verification gate once at the end
     │
     ▼
completion line (no readiness script; user confirmation + final verification)
```

---

## Orchestrator Contract

The orchestrator follows the implementation skill pattern, with one extra hard gate:

1. Resolve the routed user-review step (from `--resume` / preferred step plan).
2. Run the implementation-readiness **entry gate** (`check_implementation_readiness.py --step <step> --step-plan <plan>`). On non-zero, stop with the "return to implementation" message; do not invoke the skill.
3. Resolve the user-review branch `step-<selected-step>-<feature-id>-user-review` and create/switch to it **from** `step-<selected-step>-<feature-id>-implementation` so it carries the implementation changes (fail safely if the implementation branch is missing or the working tree has uncommitted changes that cannot be carried).
4. Resolve: step id, feature id, branch, step plan path, design artifact path, runtime implementation plan path.
5. Write a compact prompt for logging/debug parity (`write_user_review_skill_prompt`).
6. Invoke the configured model once and return its exit status.

Example prompt shape:

```text
Use the `yasdef-worker-user-review` skill to run the ASDLC worker user review phase.

Inputs:
- Step: <step>
- Feature id: <feature-id>
- Branch: <branch>
- Step plan: <step-plan-file>
- Design artifact: <design-file>
- Runtime implementation plan: <runtime-plan>
```

The orchestrator prompt passes variables only; review rules belong in `SKILL.md`. User review is **single-pass**: the orchestrator does not loop the model and does not re-validate readiness on exit. It advances to `ai_audit` only after the user-review branch marker is present (`is_user_review_complete_for_step`), as today.

---

## Skill Input Contract

`yasdef-worker-user-review/SKILL.md` requires explicit inputs:
- step id
- feature id
- branch
- step plan path
- design artifact path
- runtime implementation plan path

If any required input is missing, inconsistent, or points to a missing required file, the skill stops and asks the user for explicit instructions. It must not infer replacement values from `.asdlc_worker/feature_meta_sync.yaml` or the runtime environment. Both the step plan and design artifact paths are required and must exist before user review starts.

---

## Skill Workflow

The skill instructs the model to:

1. Run context assembly:
   ```bash
   uv run python .codex/skills/yasdef-worker-user-review/scripts/build_user_review_context.py --step <step> --feature-id <feature-id> --step-plan <step-plan-file> --design <design-file> --runtime-plan <runtime-plan>
   ```
2. Read the printed context before reviewing. It includes the phase contract, the review contract (step-plan `## Plan (ordered)` + translated `## Functional Requirements`), step-plan accepted decisions, the applicable UR shortlist (cap 8), the design scope contract (`## Goal` / `## In Scope` / `## Out of Scope`, by reference), the blocker/open-questions step sections, and pointers to the full `user_review.md`, the UR template, and the golden examples. Design proposal/risks/ADR details and design UR rules are intentionally **not** included — planning already grounded them into the step plan.
3. **Pre-review self-check.** Inspect the current-step patch as a code reviewer (`git status` / `git diff` + nearby code). Check for defects, regressions, missing verification, and drift from the step plan, translated FRs, design scope, accepted decisions, `AGENTS.md`, and applicable `user_review.md` rules. Prioritize previous user decisions and accepted UR rules that apply to the current scope, including newly relevant rules not in the shortlist.
4. **Triage findings.** Fix immediately only when a finding is current-scope and clear/objective or review-blocking; rerun relevant verification after any fix. Otherwise leave the code unchanged and surface the finding in the Review Brief as a focused hotspot/question.
5. **Review Brief.** Before asking for feedback, emit a concise, product-level brief covering exactly: (1) what changed and how, (2) how to start the code review, (3) what to check first (top correctness/risk hotspots derived from the self-check). Keep it concise and current-scope, reference concrete entrypoints/files/tests, do not narrate artifact creation, do not guess ordering, keep it separate from the `ai_audit` Evidence Reasoning Summary, use `assets/review_brief_TEMPLATE.md` for structure, and use `assets/review_brief_GOLDEN_EXAMPLE.md` as the tone/structure anchor.
6. **Review loop.** Ask the user for the next review item (a question or change request). On each response, in order:
   1. Clarify ambiguity; if the user asked "why", answer first.
   2. Implement the requested changes plus directly necessary test/doc updates. Do not implement unrequested changes — propose them and ask.
   3. Immediately update `.asdlc_worker/user_review.md` with any generalizable rule(s) derived from the feedback + the implementation change (with references). If there are none, state that explicitly and do not change the file. Apply the UR write gates:
      - **UR-schema gate** — new entries must be template-complete per `assets/user_review_TEMPLATE.md`: `Trigger`, `Rule`, `How to verify`, `Example(s)`, `References`.
      - **Fallback gate** — if feedback is useful but cannot populate those fields with quality, record a step-specific note in the active step plan instead of creating a UR entry.
      - **De-dup gate** — if feedback overlaps an existing UR rule, update that entry rather than adding a duplicate/new UR ID.
   4. Summarize what changed and ask for the next round.
7. Repeat step 6 until the user explicitly confirms the review is complete (e.g., "done", "no more comments").
8. **Only after confirmation**, run one final verification command for the step (prefer the full `AGENTS.md` verification gate) and report the result.
9. If the final verification passes, propose the next phase (`ai_audit`). Do **not** start `ai_audit` (§6) in this phase.
10. Emit the completion line only after the user confirms completion and the final verification passes.

---

## Context Builder Responsibilities

`build_user_review_context.py` replaces the context-emitting part of `ai_user_review.sh`.

It must:
- require explicit path arguments; no runtime inference
- fail fast if the step plan or design artifact is missing or empty
- read the step plan as the review contract and extract/label:
  - `## Plan (ordered)` (normalized to `- [ ]` / `- [x]` checklist items) — the completion state being reviewed
  - `## Functional Requirements (translated from design EARS)` (or `## Functional Requirements`) — the behavior contract to verify
  - the `Accepted` subset of `## Decisions Needed` (or `## Accepted Decisions`) — the decisions to check for drift against
  - `## Applicable UR Shortlist` (cap 8) — the prioritized review rules
- extract/label, from the design artifact, the scope contract **by reference only**: `## Goal`, `## In Scope`, `## Out of Scope`
- extract/label the current-step sections of `.asdlc_worker/blocker_log.md` and `.asdlc_worker/open_questions.md`
- emit pointers (not inlined content) to the full `.asdlc_worker/user_review.md`, `assets/user_review_TEMPLATE.md`, `assets/review_brief_TEMPLATE.md`, `assets/review_brief_GOLDEN_EXAMPLE.md`, and `assets/user_review_GOLDEN_EXAMPLE.md`
- emit the phase contract block (process §5 is authoritative; phase-state source is the ordered plan only; user review writes code + UR rules; do not start `ai_audit`; completion is user confirmation + final verification + the completion line)

It must **not** extract or pass: design `## Proposal / Design Details`, `## Risks and Mitigations`, `## Applicable ADR Shortlist`, `## Non-goals`, or design UR rules. Planning has already grounded these into the step plan (or they are reachable via the AGENTS.md pointer).

Section extraction must be deterministic; missing required step-plan sections must be labeled explicitly (for example `- (missing in step plan)`) rather than silently dropped. The builder does **not** inline the diff — the model inspects the live patch via tools during the self-check.

---

## Entry Gate (reused, orchestrator-owned)

The implementation-readiness check is reused unchanged as the hard **entry** precondition; the user-review skill does not own a copy.
- Command: `uv run python .codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py --step <step> --step-plan <step-plan-file>`.
- It validates **checklist state, not code correctness**: the step plan exists, `## Plan (ordered)` is present and every item is `[x]`, and the translated FR section is present and every FR is `[x]`.
- Run by the **orchestrator** before invoking the skill. On non-zero, the orchestrator stops with a "return to implementation, satisfy the Implementation Readiness Gate, and retry user_review" message and does not invoke the skill.

User review owns **no** exit-readiness script: there is no single deterministic completion contract beyond explicit user confirmation and a passing final `AGENTS.md` verification gate.

---

## Review Rules To Carry Into SKILL.md

Preserve user-review behavior from `AI_DEVELOPMENT_PROCESS.md §5`:
- user review writes runtime code (it is an executing phase): it implements requested changes plus directly necessary test/doc updates, and does not implement unrequested changes (propose them instead)
- phase-state source is the step-plan `## Plan (ordered)` completion only; do not use `implementation_plan.md` target bullets as user_review phase-state gating
- run the pre-review self-check on the live patch first; fix clear/objective or review-blocking current-scope findings in place and rerun verification, surface the rest in the Review Brief
- emit the Review Brief before asking for feedback, within its output constraints, using `assets/review_brief_TEMPLATE.md` for structure and `assets/review_brief_GOLDEN_EXAMPLE.md` for tone; keep it separate from the `ai_audit` Evidence Reasoning Summary
- prioritize previous user decisions and accepted UR rules that apply to the current scope, including newly relevant rules not in the shortlist (read the full `user_review.md`)
- on each user response: clarify → implement requested change → record durable UR rule(s) → summarize, then ask for the next round
- apply the UR write gates (schema / fallback / de-dup) against `assets/user_review_TEMPLATE.md`; the UR golden example anchors entry shape
- repeat the loop until the user explicitly confirms completion
- only after confirmation, run the final verification (prefer the full `AGENTS.md` gate) and report the result; do not start `ai_audit` in this phase
- record new blockers in `.asdlc_worker/blocker_log.md`, unresolved questions in `.asdlc_worker/open_questions.md`, and durable design choices in `.asdlc_worker/decisions.md` per the rules
- keep project-specific verification/review constraints in `AGENTS.md`, not in `SKILL.md`
- user review commits runtime + UR-rule changes on the `step-N-<feature>-user-review` branch

---

## Artifacts

### Inputs

| Artifact | How used |
|---|---|
| Step plan | Required hard gate; the review contract — `## Plan (ordered)` (completion state), translated FRs (behavior), accepted decisions, UR shortlist (cap 8) |
| Design artifact | Required hard gate; **scope contract only** (`## Goal` / `## In Scope` / `## Out of Scope`), read by reference for the scope-drift check. Design details, risks, ADRs, and UR rules are not passed — planning grounded them |
| Current-step patch (diff) | The subject of review; inspected live by the model via `git status`/`git diff` |
| Full `.asdlc_worker/user_review.md` | Read to apply accepted UR rules (including newly relevant ones) and appended with new durable rules |
| `.asdlc_worker/blocker_log.md` / `open_questions.md` | Current-step sections surfaced as review context; new entries recorded when discovered |
| Runtime `implementation_plan.md` | step routing context only; not used as user_review phase-state gating |
| Implementation-readiness check | Reused as the orchestrator-owned hard entry gate |

### Outputs

| Artifact | Description |
|---|---|
| Runtime code + tests/docs | Changes implementing the user's review feedback (the phase's executing output) |
| `.asdlc_worker/user_review.md` | New/updated durable UR rules (schema / fallback / de-dup gates) |
| Step plan | A step-specific fallback note when feedback is useful but cannot become a UR entry; checkboxes stay `[x]` |
| Final verification result | Reported after the user confirms completion |

User review commits runtime + UR-rule changes on the `step-N-<feature>-user-review` branch; the branch's existence is the `ai_audit`-entry completion marker.

---

## Install And Migration Work

1. Add `ai/codex/skills/yasdef-worker-user-review` with `SKILL.md`, `scripts/build_user_review_context.py`, and `assets/` (`user_review_TEMPLATE.md`, `review_brief_TEMPLATE.md`, `review_brief_GOLDEN_EXAMPLE.md`, `user_review_GOLDEN_EXAMPLE.md`).
2. Update `init_asdlc_worker.sh` to install `.codex/skills/yasdef-worker-user-review` alongside the design/plan/implementation skills (the `INSTALL_SKILLS` list and the per-skill install loop), and to copy its `assets/`.
3. Update `.git/info/exclude` handling for the installed skill path.
4. Replace `run_user_review_phase`'s `ai_user_review.sh` invocation with: (a) an orchestrator-owned implementation-readiness entry gate, (b) branch creation from the implementation branch, and (c) a compact `write_user_review_skill_prompt`; keep the phase single-pass.
5. Remove the legacy `ai/scripts/ai_user_review.sh` once the skill fully replaces it (no backward compatibility required).
6. Replace the detailed user-review block in `AI_DEVELOPMENT_PROCESS.md §5` with a pointer to `.codex/skills/yasdef-worker-user-review/SKILL.md`, keeping the cross-phase rules that implementation/ai_audit still need (the borrowed entry-gate reference, the phase-state-source rule, and the `ai_audit` boundary).
7. Update OpenSpec proposal/design/tasks/specs to match the actual implementation.

---

## Tests

Python scripts in the skill must be covered under `tests/skills_python_scripts/`.

Focused script tests should cover:
- worker init installs `.codex/skills/yasdef-worker-user-review` including its `assets/`
- orchestrator user_review phase runs the implementation-readiness entry gate before invoking the skill and **fails fast** when the step is not closed
- orchestrator user_review phase creates `step-N-<feature>-user-review` from the implementation branch and writes a compact `yasdef-worker-user-review` prompt (single-pass; no post-exit readiness re-run)
- missing step plan still blocks user review
- missing design artifact still blocks user review
- context builder extracts the review contract (ordered plan, FRs, accepted decisions, UR shortlist) and the design scope contract (Goal / In Scope / Out of Scope) only
- context builder does not surface design proposal/risks, design ADRs, design UR rules, or Non-goals
- applicable UR shortlist is sourced from the step plan and capped at 8, and the full `user_review.md` is pointed to (not the design UR shortlist)
- context builder surfaces the blocker_log / open_questions current-step sections and the UR template / golden-example pointers
- legacy `ai_user_review.sh` prompt generation is no longer required after conversion

Run focused user_review/init/orchestrator tests plus `git diff --check`.

---

## Boundary With Implementation And ai_audit Skills

User review must remain a separate skill/process from both implementation and `ai_audit`.

- Implementation reaches mechanical closure (ordered plan + FRs `[x]`, full verification green) and commits on `step-N-<feature>-implementation`; it has no human in the loop. User review starts only from that closed state (the borrowed entry gate) and is the human acceptance phase.
- User review **writes code** (fixes from feedback) and is the **only** phase that writes `user_review.md`. `ai_audit` is analysis-only and must not change runtime code — separating them keeps the audit proving a frozen patch.
- User review gates on explicit user confirmation + final verification; it does not run the `ai_audit` target-bullet proof-check, the Evidence Reasoning Summary, or finding disposition. Those belong to `ai_audit` (§6) and run on the `step-N-<feature>-review` branch.
- User review reads the step plan as the review contract and the design **file** only for the scope contract (by reference) — not the planning conversation, and not the design's grounded details.
- User review commits on its own `step-N-<feature>-user-review` branch (from implementation); `ai_audit` later branches from user-review.

This boundary preserves session independence and keeps user review operating from the closed step plan, the design scope contract, and the live patch — not from prior-phase conversation history.
