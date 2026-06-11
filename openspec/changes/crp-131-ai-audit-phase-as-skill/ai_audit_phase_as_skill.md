# AI Audit Phase as Codex Skill

This is the **final target** specification for the ai_audit phase as a Codex skill (`yasdef-worker-ai-audit`). It is written as the to-be design, not as a diff. The single "What Changes vs. the Current Phase" section below is the only place that references the current `ai_audit.sh` behavior — it exists to mark where this design **deliberately departs** from the current approach, so the conversion is not read as a straight prompt-to-skill translation. `ai_audit_phase_overview.md` is the matching as-is reference.

---

## Overview

Convert the ai_audit phase from `ai/scripts/ai_audit.sh` prompt generation into a repo-provided Codex skill, following the design-, planning-, implementation-, and user-review-phase pattern:
- shell owns orchestration, branch/path resolution, model invocation, and logging
- the skill owns phase instructions and model behavior
- Python scripts under the skill own the entry gate, deterministic context assembly, and the closure check
- the skill is installed into target projects under `.codex/skills`

ai_audit remains the fifth phase. It is **analysis-only**: it produces no runtime code changes. Its single sharp question is **"For the current step, are all target bullets PROVEN by the current patch — and if not, what are the gaps?"** Everything else in the phase is structure that lets that question be answered, recorded, and routed to follow-up work.

**No backward compatibility.** The skill replaces `ai/scripts/ai_audit.sh`, `ai/scripts/helpers/check_ai_audit_disposition_readiness.sh`, and the legacy `ai/scripts/templates/audit_result_TEMPLATE.md` + `ai/scripts/golden_examples/audit_result_GOLDEN_EXAMPLE.md` outright. The skill scripts must not preserve flags, environment toggles, sentinel strings (beyond the completion line), file-format quirks, exit-code semantics, prompt-fragment shapes, or section names from the old shell-based audit. Anything that exists only to keep the old approach working in parallel is out of scope; the conversion is a clean cut, not a coexistence.

The step plan, the step design file, and a completed user_review phase are hard input gates: audit must not start without all three. The **step design file** is audit's single context source — it already contains the snapshot of `## Target Bullets`, `## Selected EARS Requirements`, `## Goal` / `## In Scope` / `## Out of Scope`, and `## Linked Artifacts (in scope)` that was committed to when this step's scope was frozen. Audit does **not** re-read `implementation_plan.md` for content, does **not** re-resolve EARS from `requirements_ears.md`, and does **not** read the step plan. `implementation_plan.md` is a write target only (mark target bullets `[x]`, append follow-up step blocks).

---

## What Changes vs. the Current Phase

The audit's analytical core (prove the patch against target bullets) is preserved, but the **workflow shape changes substantially**. Three changes are deliberate departures and must be applied on purpose.

Governing rule (shared with implementation and user_review): a design layer reaches audit **either by reference or by translation, never both**. EARS is sealed behind its own resolved blocks; design *details* are sealed behind planning's grounding (which audit does not read); only the design scope contract survives by reference. Audit sits on the **"what"** axis alongside design (high-level commitments + behavior contract); planning/implementation/user_review own the **"how"** axis. Audit must not reach into "how" artifacts.

### 1. Single-pass discovery + mechanical disposition loop (instead of an interleaved findings/disposition loop)

Today's §6.2 is explicitly an interleaved loop: produce a finding → §6.3 disposition → return to §6.2 → produce another finding. Models are unreliable in long stateful loops, and a session crash mid-loop leaves the artifact in an indeterminate state.

The skill replaces this with two **decoupled** phases inside one session:

| Phase | Shape | Why |
|---|---|---|
| **Phase 1 — Discovery** | Single-pass, no loop. Model reviews everything once, writes every finding into the review_result with severity, recommendation, reasoning, refs, and an explicit state-machine checklist. | Plays to the model's strength: holistic analysis with full context. Output is durable before any user interaction starts. |
| **Phase 2 — Disposition** | Mechanical loop. Per finding: present → user picks one of three options → act → mark state → next. | Tight, recoverable. Each finding's state is durable in the artifact; a crashed session resumes by re-reading the file. |

A deterministic closure check ends Phase 2; the model iterates against its structured errors until exit 0.

### 2. Three terminal states per finding (instead of binary Accepted/Rejected)

Today findings are dispositioned as `Accepted` or `Rejected`. The new model uses three mutually-exclusive terminal states routed by the user, with deterministic cross-verification on the artifacts each produces:

| State | Meaning | Artifact created |
|---|---|---|
| `follow_up_created` | Same-scope gap; fixable inside the current feature/worker | New `### Step N.Na` block appended to `implementation_plan.md` (ASDLC repo) with `#### Assigned:` matching the current worker |
| `raised_to_coordinator` | Broader/deeper concern, security implication, more-than-one-possible-solution, prerequisite from another service/worker | New file at `<asdlc>/projects/<project>/<feature>/raised_questions/<step>-<worker-id>-F<NN>.md` |
| `rejected` | Not a real issue / false positive | Closed in review_result; no further artifact |

The closure check verifies, per finding: exactly one state checked; the recorded artifact (follow-up step heading or raised-question file) actually exists; the follow-up step is assigned to the current worker. See "Closure-Check Responsibilities" for the full error surface.

### 3. Tighten the context to the audit question — single source: the step design file

The current prompt re-extracts target bullets from `implementation_plan.md`, resolves `[REQ-N]` tags from `requirements_ears.md`, inlines four design shortlists (Risks, AGENTS, UR, ADR), and passes full-file pointers to `requirements_ears.md`, `implementation_plan.md`, the step plan, `user_review.md`, `decisions.md`, AGENTS.md, and the disposition helper.

The skill collapses all of that to: **read the step design file, full stop.** The design file already contains the snapshot of target bullets, resolved EARS, scope contract, and LARs that defined this step's scope when it was frozen. Re-extracting from `implementation_plan.md` + `requirements_ears.md` reintroduces upstream surface that has already been resolved.

| Current prompt block | To-be | Why |
|---|---|---|
| `== Step ==` (number + title) | **Pulled from the step design file's title line.** | Same content, single source. |
| `== Target bullets ==` (extracted from `implementation_plan.md` step section) | **Pulled from design file `## Target Bullets (excluding planning/review)`.** | Design already pre-extracted them at design time; this is the snapshot of what the step committed to. |
| `== Linked EARS requirement blocks ==` (resolved from `[REQ-N]` tags via `requirements_ears.md`) | **Pulled from design file `## Selected EARS Requirements (for planning translation)`.** | Design already resolved the EARS blocks (with full User Story / Acceptance Criteria / Verification). No re-resolution from `requirements_ears.md`. |
| Scope contract — design `## Goal`, `## In Scope`, `## Out of Scope` (currently absent from the prompt) | **Added: pulled from the design file.** | Needed for the scope-drift check; the design file is now the single context source so this slots in naturally. |
| LAR registry | **Pulled from design file `## Linked Artifacts (in scope)`.** | Design already mirrored the LAR refs into the step. Either a real list or the literal `- None.` |
| Design `## Risks and Mitigations` | **Dropped.** | Design-internal framing; audit's cross-check is against `AGENTS.md` and the patch, not design's risk narrative. |
| Design `## Applicable AGENTS.md Constraints` | **Dropped.** | `AGENTS.md` is the source of truth; pass as a pointer. Audit cross-checks against `AGENTS.md` directly. |
| Design `## Applicable User Review Rules` | **Dropped.** | User review already applied UR rules; audit's cross-check is against `AGENTS.md` + EARS, not UR. |
| Design `## Applicable ADR Shortlist` | **Dropped.** | Accepted ADRs are project-state; not the patch-vs-commitment check audit performs. |
| Design `## Proposal / Design Details`, `## Non-goals`, `## Things to Decide`, `## Trade-offs`, `## Quality and Testing`, `## Alternatives`, `## References in Current Codebase`, `## Unknowns / Assumptions to Validate` | **Dropped.** | Design-phase process artifacts; out of scope for audit's "is the patch proven against commitments" question. |
| Full-file pointer to `requirements_ears.md` | **Dropped.** | Audit no longer reads `requirements_ears.md` at all. Design's resolved EARS blocks are sufficient. |
| Full-file pointer to `implementation_plan.md` | **Dropped as a context pointer.** It remains a **write target** (mark `[x]`, append follow-up step blocks). | Adjacent steps are out of scope; target bullets come from the design file's snapshot, not from re-reading `implementation_plan.md`. |
| Pointer to step plan | **Dropped.** | Step plan is "how" axis — out of scope for audit. Audit reads the step design, not the step plan. |
| Pointer to `.asdlc_worker/user_review.md` | **Dropped.** | UR is "how" axis. Audit's cross-check is against `AGENTS.md`. |
| Pointer to `.asdlc_worker/decisions.md` | **Dropped.** | Audit does not write durable decisions in the new model (they land in raised_questions or follow-up steps). |
| Pointer to `.asdlc_worker/blocker_log.md` / `open_questions.md` | **Dropped (both as context and as write targets).** | In the new disposition model, every finding routes to exactly one of three terminal states. No "leftover unresolved" state remains; the legacy ledger files have no role in audit. |
| Pointer to `AGENTS.md` | **Kept.** | One authority pointer survives: project-wide invariants that can't be inlined and apply to every step. |
| Pointer to disposition helper | **Replaced.** Now points to `check_ai_audit_closure.py` (Python, inside the skill). | Helper is rebuilt under the new state-machine model. |
| Pointer to audit_result template + golden example | **Kept.** Moves to skill `assets/`. | Structural reference for the output artifact. |
| New: pointer to raised_question template + golden example | **Added.** New skill `assets/`. | Structural reference for the new per-finding raised-question files. |

---

## Tech Stack

| Layer | Tool | Role |
|---|---|---|
| Orchestration | `bash`/`sh` | resolve selected step, output paths, branch (from user_review or implementation), model command, prompt/log paths |
| Skill runtime | Codex project skill | installed at `.codex/skills/yasdef-worker-ai-audit` |
| Entry gate | Python 3 via `uv run python` | `check_ai_audit_entry.py` — preconditions before context assembly |
| Context assembly | Python 3 via `uv run python` | `build_ai_audit_context.py` — reads the step design file and emits its pre-extracted sections as structured context |
| Closure check | Python 3 via `uv run python` | `check_ai_audit_closure.py` — structured errors over the per-finding state machine; model iterates until exit 0 |
| Markdown parsing | Python stdlib | extract design-file sections (Target Bullets, Selected EARS, Goal/In Scope/Out of Scope, Linked Artifacts) and finding state-machine checkboxes from the review_result; parse `### Step N.Na` headings + `#### Assigned:` lines in `implementation_plan.md` for the closure check |
| YAML parsing | not used | skill scripts never read `feature_meta_sync.yaml` — values come from explicit prompt inputs (orchestrator does the yaml read during routing) |
| Skill assets | markdown | audit_result template + golden example; raised_question template + golden example |
| Skill definition | `SKILL.md` | concise model-facing audit workflow and gates from `AI_DEVELOPMENT_PROCESS.md §6` |

`uv` is a runtime requirement. Do not document or implement a `python3` fallback inside the audit skill.

---

## Target File Layout

```
ai/
  codex/
    skills/
      yasdef-worker-ai-audit/
        SKILL.md
        scripts/
          check_ai_audit_entry.py
          build_ai_audit_context.py
          check_ai_audit_closure.py
        assets/
          audit_result_TEMPLATE.md
          audit_result_GOLDEN_EXAMPLE.md
          raised_question_TEMPLATE.md
          raised_question_GOLDEN_EXAMPLE.md
```

This replaces:
- `ai/scripts/ai_audit.sh` (prompt generation + shell preconditions + branch resolution)
- `ai/scripts/helpers/check_ai_audit_disposition_readiness.sh` (closure-style shell helper, replaced by the Python closure check)
- `ai/scripts/templates/audit_result_TEMPLATE.md` and `ai/scripts/golden_examples/audit_result_GOLDEN_EXAMPLE.md` (moved into skill `assets/`)

Skill-owned runtime belongs inside the skill directory so `init_asdlc_worker.sh` can install it into `.codex/skills/yasdef-worker-ai-audit`.

---

## Architecture

```
orchestrator ai_audit phase (single-pass)
     │
     ▼
resolve + create branch step-N-<feature>-review
  strictly from step-N-<feature>-user-review (no fallback)
     │
     ▼
compact Codex prompt
  - names `yasdef-worker-ai-audit`
  - passes explicit variables only
  - does not duplicate audit rules
     │
     ▼
yasdef-worker-ai-audit/SKILL.md
  - validates required inputs are present
     │
     ▼
scripts/check_ai_audit_entry.py  (model-invoked, first action)
  - step plan exists
  - design artifact exists
  - user_review phase complete (branch exists)
  - exit 1 → model stops and reports
  - exit 0 → continue
     │
     ▼
scripts/build_ai_audit_context.py
  - reads the step design file (single context source)
  - verifies the design file's identity matches BOTH the current
    --step and --feature-id (a same-numbered step from another
    feature must never be accepted)
  - extracts: ## Target Bullets, ## Selected EARS Requirements,
    ## Goal, ## In Scope, ## Out of Scope, ## Linked Artifacts (in scope)
  - runs `git status --short --untracked-files=all` for the step delta
  - takes --runtime-plan and --worker-id as explicit CLI inputs;
    derives the ASDLC repo root from the runtime-plan path
    (the ancestor of projects/<project>/<feature>/implementation_plan.md)
  - prints structured context with pointers to AGENTS.md, the output path,
    skill assets, and the closure helper
     │
     ▼
Phase 1 — Discovery (single pass, no loop)
  model writes every finding into review_result with severity,
  recommendation (FollowupStep | RiseToCoordinator), reasoning, refs,
  and a per-finding 3-checkbox state machine
     │
     ▼
Phase 2 — Disposition (mechanical loop)
  per finding:
    1. present finding + recommendation + reasoning
    2. ask: 1. reject  2. create follow-up step  3. raise to coordinator
    3. act:
       - reject       → mark [x] rejected (optional rationale)
       - follow-up    → append ### Step N.Na to implementation_plan.md
                        with #### Assigned: <current-worker-uuid>;
                        mark [x] follow_up_created: <step-id>
       - raise        → write file at
                        <asdlc>/projects/<project>/<feature>/raised_questions/
                          <step>-<worker-id>-F<NN>.md;
                        mark [x] raised_to_coordinator: <relative-path>
    4. next finding
     │
     ▼
scripts/check_ai_audit_closure.py  (model-invoked, iterates until exit 0)
  - per-finding state-machine validation
  - artifact existence cross-verification
  - worker-assignment cross-verification
     │
     ▼
commit worker-repo changes on the review branch (review_result only)
ASDLC-repo changes are left in the working tree for post_review
     │
     ▼
emit the exact sentinel completion line
```

---

## Orchestrator Contract

The orchestrator follows the design/plan/implementation/user_review skill pattern. It owns shell-only concerns:

1. Resolve the routed audit step (from `--resume` / preferred step plan).
2. Resolve the audit branch `step-<selected-step>-<feature-id>-review` and create/switch to it **strictly from** `step-<selected-step>-<feature-id>-user-review`. There is no fallback to the implementation branch — the pipeline is strictly `implementation → user_review → audit`, and audit must not start from an unreviewed implementation state. Fail with a clear "run user_review for this step first" message if the user-review branch is missing. Fail safely if the working tree has uncommitted changes that cannot be carried.
3. Resolve and pass to the skill as explicit prompt inputs: step id, feature id, branch, step plan path (entry-gate existence check only), design artifact path, runtime implementation plan path (`$ASDLC_RUNTIME_PLAN_PATH`, same value used by the implementation and user_review skill prompts), worker uuid. The orchestrator already loads these from `feature_meta_sync.yaml` during routing — the skill never reads `feature_meta_sync.yaml` itself, matching the implementation and user_review skill convention.
4. Write a compact prompt for logging/debug parity (`write_ai_audit_skill_prompt`).
5. Invoke the configured model once and return its exit status.

Example prompt shape (matches the `write_implementation_skill_prompt` / `write_user_review_skill_prompt` pattern in `orchestrator.sh`):

```text
Use the `yasdef-worker-ai-audit` skill to run the ASDLC worker ai_audit phase.

Inputs:
- Step: <step>
- Feature id: <feature-id>
- Branch: <branch>
- Step plan: <step-plan-file>
- Design artifact: <design-file>
- Runtime implementation plan: <runtime-plan>
- Worker id: <worker-uuid>
```

The orchestrator prompt passes variables only; audit rules belong in `SKILL.md`. The orchestrator **does not run any helper scripts** — the entry gate, context builder, and closure check are all model-invoked from inside the session.

ai_audit is **single-pass**: the orchestrator does not loop the model and does not re-validate readiness on exit. It advances to `post_review` according to post_review's existing entry conditions (out of scope for this spec).

---

## Skill Input Contract

`yasdef-worker-ai-audit/SKILL.md` requires explicit inputs:
- step id
- feature id
- branch
- step plan path (for the entry-gate existence check)
- design artifact path (audit's single context source)
- runtime implementation plan path (the `implementation_plan.md` in the ASDLC repo — write target)
- worker uuid (for the follow-up-step `#### Assigned:` check)

If any input is missing, inconsistent, or points to a missing required file, **do not infer it from `.asdlc_worker/feature_meta_sync.yaml` or the runtime environment.** Stop and ask the user for explicit instructions. This matches the implementation and user_review skill convention: the orchestrator owns all `feature_meta_sync.yaml` reads; skills consume explicit prompt inputs only. The skill scripts may derive the ASDLC repo root from the runtime-plan path itself (it is the ancestor of `projects/<project>/<feature>/implementation_plan.md`) — that is a path computation on a passed-in value, not a `feature_meta_sync.yaml` lookup.

---

## Skill Workflow

The skill instructs the model to:

1. **Entry gate.** Run as the first action in the session:
   ```bash
   uv run python .codex/skills/yasdef-worker-ai-audit/scripts/check_ai_audit_entry.py \
     --step <step> --feature-id <feature-id>
   ```
   On non-zero exit, stop and report which precondition failed (do not proceed).

2. **Context assembly.** On entry-gate pass, run:
   ```bash
   uv run python .codex/skills/yasdef-worker-ai-audit/scripts/build_ai_audit_context.py \
     --step <step> --feature-id <feature-id> --design <design-file> \
     --runtime-plan <runtime-plan> --worker-id <worker-uuid>
   ```
   Read the printed context before reviewing. It includes:
   - the phase contract (analysis-only; the audit question; the two-phase model)
   - target bullets for the current step — pulled from the design file's `## Target Bullets (excluding planning/review)`
   - resolved EARS blocks for the step — pulled from the design file's `## Selected EARS Requirements (for planning translation)` (full User Story / Acceptance Criteria / Verification per block)
   - the scope contract — pulled from the design file's `## Goal`, `## In Scope`, `## Out of Scope`
   - the LAR registry for the step — pulled from the design file's `## Linked Artifacts (in scope)`
   - the step delta file list (`git status --short --untracked-files=all`)
   - the current worker uuid and the ASDLC repo root (derived from the runtime-plan path)
   - pointers: `AGENTS.md`; review_result output path; `assets/audit_result_TEMPLATE.md`; `assets/audit_result_GOLDEN_EXAMPLE.md`; `assets/raised_question_TEMPLATE.md`; `assets/raised_question_GOLDEN_EXAMPLE.md`; `check_ai_audit_closure.py`

3. **Phase 1 — Discovery (single pass).** Review the current patch against the inlined context. Inspect changed files via `git status` / `git diff` and nearby code. Produce findings only from these sources:
   - **Target bullet NOT_PROVEN** — concrete implementation evidence (code refs + key symbols, reachability from entrypoints, test evidence) is missing, incomplete, or uncertain for a target bullet
   - **Scope drift** — files changed that fall outside the design `## Goal` / `## In Scope`, or contradict `## Out of Scope`
   - **AGENTS.md invariant violation** — patch violates an `AGENTS.md` rule (idempotency, validation, transaction boundaries, ledger/projection consistency, stream routing, guard rules)
   - **`//TODO <reason>` markers in changed files** — every `//TODO` becomes its own finding

   Write every finding into the review_result file in one pass, with the per-finding state machine initialized to all-unchecked. **Do not start Phase 2 until Phase 1 is complete.**

   Do not produce findings for general code quality, test coverage, or documentation gaps unless a target bullet explicitly demanded them — user_review already owns those.

4. **Phase 2 — Disposition (mechanical loop).** For each finding, in order:
   1. Present the finding (severity, recommendation, reasoning, refs).
   2. Ask the user, with exactly three numbered options:
      ```
      1. reject
      2. create follow-up step
      3. raise to coordinator
      ```
   3. Act on the user's choice:
      - **reject** — mark `[x] rejected` in the finding's state block; optionally append a one-line rationale after the colon.
      - **create follow-up step** — append a new `### Step N.Na` block to `implementation_plan.md` in the ASDLC repo, immediately after the current step section. The new step **must** carry `#### Assigned: <current-worker-uuid>` (same worker as the current step). Follow the existing implementation_plan.md structure as the template (Repo / Depends on / Evidence / Assigned / Coordination / bullets). Mark `[x] follow_up_created: <new-step-id>` (e.g. `1.6a`).
      - **raise to coordinator** — write a new file at `<asdlc>/projects/<project>/<feature>/raised_questions/<step>-<worker-id>-F<NN>.md` using `assets/raised_question_TEMPLATE.md` and `assets/raised_question_GOLDEN_EXAMPLE.md` as references. Mark `[x] raised_to_coordinator: <relative-path>` (relative to the ASDLC repo root).
   4. Move to the next finding.

5. **Closure check.** When all findings have been dispositioned, run:
   ```bash
   uv run python .codex/skills/yasdef-worker-ai-audit/scripts/check_ai_audit_closure.py \
     --step <step> --feature-id <feature-id>
   ```
   On non-zero exit, read the structured error categories, fix each (re-run a Phase 2 step, create a missing artifact, re-assign a mis-assigned follow-up step, etc.), and re-run the helper until exit 0.

6. **Commit.** Commit worker-repo changes (`step_review_results/review_result-<step>-<feature>.md` only) on the audit branch. **Do not commit ASDLC-repo changes** (implementation_plan.md edits and new raised_questions/ files) — post_review handles atomic pull-rebase + commit + push for the ASDLC repo.

7. **Sentinel.** Emit the exact completion line, character for character:
   ```
   ai_audit phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase.
   ```

---

## Entry-Gate Responsibilities

`check_ai_audit_entry.py` enforces audit's hard preconditions before any context assembly happens.

It must:
- require explicit `--step` and `--feature-id` arguments
- read paths from arguments only; never read `feature_meta_sync.yaml` or the runtime environment
- verify: step plan `step_plans/step-N-<feature>.md` exists
- verify: design artifact `step_designs/step-N-<feature>-design.md` exists
- verify: `step-N-<feature>-user-review` branch exists (the user_review phase completion marker)

Exit codes:
- `0` — all preconditions pass
- `1` — at least one precondition failed; print structured per-precondition error to stderr
- `2` — invalid usage or system/configuration error

Each failed precondition is reported as a separate, model-actionable line (e.g., `MISSING: design artifact at <path> — run the design phase first`).

---

## Context-Builder Responsibilities

`build_ai_audit_context.py` replaces the context-emitting part of `ai_audit.sh`. The step design file is its **only** content source — it never reads `implementation_plan.md`, `requirements_ears.md`, the step plan, or `.asdlc_worker/` ledger files for context.

It must:
- require explicit arguments: `--step`, `--feature-id`, `--design` (step design path), `--runtime-plan` (ASDLC `implementation_plan.md` path — write target), `--worker-id` (worker uuid for the follow-up-step assignment check)
- **never read `.asdlc_worker/feature_meta_sync.yaml`** — match the implementation and user_review skill convention (skills consume explicit prompt inputs only)
- derive the ASDLC repo root from `--runtime-plan` (the ancestor of `projects/<project>/<feature>/implementation_plan.md`); use it to construct the `raised_questions/` directory path
- fail fast if the step design file is missing or empty
- **strictly verify the design file's identity matches both `--step` and `--feature-id`** before extracting anything. The expected filename is `step-<step>-<feature-id>-design.md` and the file's title line must declare the same step number + feature reference. A design file for the same step number but a different feature must be rejected with a clear error (e.g., `EXPECTED design for step 1.6 feature umss_core_functionality-1777635876, GOT step 1.6 feature payments_core-1777912345`). Step/feature identity is not inferable from the step number alone.
- extract and emit, from the step design file, these sections verbatim under labeled blocks:
  - `## Target Bullets (excluding planning/review)` — the commitments
  - `## Selected EARS Requirements (for planning translation)` — the behavior contract (full User Story / Acceptance Criteria / Verification per requirement block)
  - `## Goal`
  - `## In Scope`
  - `## Out of Scope`
  - `## Linked Artifacts (in scope)` — LAR refs (a real list or the literal `- None.`)
- run `git status --short --untracked-files=all` and inline the output as the step delta file list
- emit pointers (not inlined content) to: `AGENTS.md`; the review_result output path (`step_review_results/review_result-<step>-<feature>.md`); `assets/audit_result_TEMPLATE.md`; `assets/audit_result_GOLDEN_EXAMPLE.md`; `assets/raised_question_TEMPLATE.md`; `assets/raised_question_GOLDEN_EXAMPLE.md`; `scripts/check_ai_audit_closure.py`
- echo back, in the printed context, the `worker_id` (from `--worker-id`) and the derived `asdlc_repo_path` so the model can construct correct follow-up-step assignments and raised-question file paths without re-deriving them
- emit the phase contract block (analysis-only; the audit question; the two-phase model; the three terminal states; the commit/no-commit split between worker and ASDLC repos; the sentinel completion line)

It must **not** extract or pass: any other section of the design file (`## Proposal / Design Details`, `## Risks and Mitigations`, `## Applicable ADR Shortlist`, `## Applicable AGENTS.md Constraints`, `## Applicable User Review Rules`, `## References in Current Codebase`, `## Non-goals`, `## Things to Decide`, `## Trade-offs`, `## Quality and Testing`, `## Alternatives`, `## Unknowns / Assumptions to Validate`); any content from `implementation_plan.md`, `requirements_ears.md`, the step plan, `.asdlc_worker/blocker_log.md`, `open_questions.md`, `decisions.md`, or `user_review.md`.

Section extraction must be deterministic; missing required sections must be labeled explicitly (for example `- (missing in design file)`) rather than silently dropped. The builder does **not** inline diffs — the model inspects the live patch via tools.

---

## Closure-Check Responsibilities

`check_ai_audit_closure.py` is the deterministic gate the model iterates against in-session. It validates **per-finding state-machine closure and artifact existence**, not code correctness.

It must:
- locate the review_result at `step_review_results/review_result-<step>-<feature>.md` and fail with a clear error if missing
- parse all findings (`### F-NN` blocks) and their state-machine checkboxes
- take `--worker-id` and `--runtime-plan` as explicit CLI inputs; derive the ASDLC repo root from the runtime-plan path. Never read `feature_meta_sync.yaml`
- group errors into the categories below and emit each category as a **separate** block (clear model input)

### Error categories

```
ERROR: Disposition phase needed
Findings without any disposition state checked: F-02, F-05
Action: re-run Phase 2 for these findings.

ERROR: Conflicting disposition state
Findings with more than one disposition state checked: F-03
Action: resolve to exactly one of follow_up_created | raised_to_coordinator | rejected.

ERROR: Missing follow-up step
Findings marked [x] follow_up_created but no matching step heading in implementation_plan.md: F-04 (expected: ### Step 1.6a)
Action: insert the step block after the current step section.

ERROR: Follow-up step mis-assigned
Findings whose follow-up step is assigned to a different worker: F-04 (1.6a #### Assigned: <other-uuid>, expected <current-uuid>)
Action: re-assign the follow-up step to the current worker; the same worker that surfaced the gap must own the fix.

ERROR: Missing raised-question file
Findings marked [x] raised_to_coordinator but no matching file in raised_questions/: F-02 (expected at projects/<project>/<feature>/raised_questions/1.6-<worker>-F02.md)
Action: create the file at the expected path; re-run the helper.
```

Exit codes:
- `0` — all findings are closed with cross-verified artifacts
- `1` — at least one category produced errors
- `2` — invalid usage or system/configuration error

Consumers: the audit skill, in-session only. The helper is **not** shared with post_review (post_review keeps its current entry-gate design).

### What the helper does NOT check

- rejection rationale presence — `[x] rejected` alone is sufficient
- follow-up step structural completeness beyond `#### Assigned:` matching the current worker — the model is trusted to follow the existing `implementation_plan.md` pattern (Repo / Depends on / Evidence / Coordination / bullets)
- worker-repo file allowlist / runtime code changes — the analysis-only constraint is enforced by SKILL.md instruction (audit proves a frozen patch; touching runtime code makes the proof circular), not by a mechanical guard

---

## Audit Rules To Carry Into SKILL.md

Preserve audit behavior from `AI_DEVELOPMENT_PROCESS.md §6`, applied through the new two-phase shape:

- audit is **analysis-only**: it must not modify runtime code or run tests. Only planning/audit artifacts are touched: review_result (worker repo); `implementation_plan.md` edits and new files under `raised_questions/` (ASDLC repo).
- audit sits on the **"what"** axis: it proves the patch against the step's frozen commitments (target bullets) and the EARS behavior contracts those bullets reference. It does **not** read the step plan or design details — those are "how" axis or design-internal framing.
- the step design file is audit's **single context source**. Target bullets, resolved EARS, scope contract, and LAR refs are all pulled from the design file's pre-extracted sections; `implementation_plan.md` and `requirements_ears.md` are not re-read.
- the closure loop is the closure helper, not an interleaved §6.2 loop. Findings are produced once in Phase 1; user decisions are routed once per finding in Phase 2.
- every finding must reach exactly one terminal state (`follow_up_created` | `raised_to_coordinator` | `rejected`); the helper enforces count-equality between checkboxes and artifacts.
- follow-up steps go into `implementation_plan.md` as new `### Step N.Na` blocks; they must be `#### Assigned:` to the current worker (the same worker that surfaced the gap owns the fix).
- raised questions go to dedicated files; they are the escalation path for broader/deeper concerns, security implications, multiple possible solutions, or prerequisites from another service/worker.
- **commit boundary**: worker-repo writes (review_result) commit on the audit branch at end of phase. ASDLC-repo writes (implementation_plan.md edits and raised_questions/ files) are left in the working tree for post_review's atomic pull-rebase + commit + push. Do not create branches in the ASDLC repo.
- emit the literal sentinel completion line only after the closure helper exits `0` and the worker-repo commit is made.

---

## Artifacts

### Inputs

| Artifact | How used |
|---|---|
| `step_designs/step-N-<feature>-design.md` | Required hard gate; **audit's single context source**. Pre-extracted sections inlined: `## Target Bullets`, `## Selected EARS Requirements`, `## Goal`, `## In Scope`, `## Out of Scope`, `## Linked Artifacts (in scope)`. All other design sections (Proposal/Risks/ADRs/AGENTS shortlist/UR/Non-goals/Things to Decide/Trade-offs/Quality/Alternatives/References/Unknowns) are not passed |
| `step_plans/step-N-<feature>.md` | Required hard gate (entry precondition); **not** read for content during the audit — step plan is "how" axis |
| User_review phase completion marker | Required hard gate (entry precondition); `step-N-<feature>-user-review` branch must exist |
| `implementation_plan.md` (ASDLC repo) | **Write target only**. Not read for context. Audit marks current-step target bullets `[x]` and appends `### Step N.Na` blocks for `follow_up_created` findings |
| `requirements_ears.md` | **Not read by audit at all.** Design's pre-resolved EARS blocks are sufficient |
| `AGENTS.md` | Authority pointer for the invariant cross-check (the one knowledge pointer audit retains) |
| Current-step patch (diff) | The subject of audit; inspected live by the model via `git status` / `git diff` |
| `feature_meta_sync.yaml` | **Not read by the skill.** The orchestrator reads it during routing and passes the resolved values (`Worker id`, `Runtime implementation plan`, etc.) as explicit prompt inputs — matching the implementation and user_review skill convention |

### Outputs

| Artifact | Repo | Description |
|---|---|---|
| `step_review_results/review_result-<step>-<feature>.md` | Worker | Every finding with severity, recommendation, reasoning, refs, and the three-checkbox state machine. Committed by audit on `step-N-<feature>-review` |
| `implementation_plan.md` edits | ASDLC | Current step's target bullets marked `[x]`; new `### Step N.Na` blocks appended for `follow_up_created` findings, each `#### Assigned:` to the current worker. **Left uncommitted** for post_review |
| `<asdlc>/projects/<project>/<feature>/raised_questions/<step>-<worker>-F<NN>.md` | ASDLC | One file per `raised_to_coordinator` finding, structured per `assets/raised_question_TEMPLATE.md`. **Left uncommitted** for post_review |

Audit does not write to `.asdlc_worker/blocker_log.md`, `open_questions.md`, `decisions.md`, or `user_review.md`. In the new disposition model, every finding routes to one of three terminal states; no leftover unresolved state remains that would need those ledgers.

---

## Install And Migration Work

1. Add `ai/codex/skills/yasdef-worker-ai-audit/` with `SKILL.md`, the three scripts under `scripts/`, and the four assets under `assets/`.
2. Move `audit_result_TEMPLATE.md` and `audit_result_GOLDEN_EXAMPLE.md` from `ai/scripts/templates/` and `ai/scripts/golden_examples/` into the skill's `assets/`.
3. Author the new `raised_question_TEMPLATE.md` and `raised_question_GOLDEN_EXAMPLE.md` in the skill's `assets/`.
4. Update `init_asdlc_worker.sh` to install `.codex/skills/yasdef-worker-ai-audit` alongside the design/plan/implementation/user-review skills (the `INSTALL_SKILLS` list and the per-skill install loop), and to copy its `assets/`.
5. Update `.git/info/exclude` handling for the installed skill path.
6. Replace `run_ai_audit_phase` in `orchestrator.sh`: keep step routing + branch creation (`ensure_review_branch` semantics); replace `ai_audit.sh` invocation with a compact `write_ai_audit_skill_prompt` + single model run. Remove `ai_audit.sh`'s `emit()` and prompt-file path entirely.
7. Update `post_review`'s ASDLC-repo commit routine to pick up the new `raised_questions/` directory in addition to `implementation_plan.md`. Whether that's a directory-level `git add` or an explicit allowlist is a post_review-internal decision (out of scope here, but noted as a required ripple effect).
8. Remove the legacy `ai/scripts/ai_audit.sh` and `ai/scripts/helpers/check_ai_audit_disposition_readiness.sh` once the skill fully replaces them (no backward compatibility required).
9. Replace the detailed audit block in `AI_DEVELOPMENT_PROCESS.md §6.0–6.4` with a pointer to `.codex/skills/yasdef-worker-ai-audit/SKILL.md`, keeping the cross-phase rules later steps may still need (e.g., the analysis-only invariant and the audit→post_review handoff contract).
10. Update OpenSpec proposal/design/tasks/specs to match the actual implementation.

---

## Tests

Python scripts in the skill must be covered under `tests/skills_python_scripts/`.

Focused script tests should cover:

**Install / orchestrator**
- worker init installs `.codex/skills/yasdef-worker-ai-audit` including its `assets/`
- orchestrator ai_audit phase creates `step-N-<feature>-review` strictly from `…-user-review` (no fallback) and writes a compact `yasdef-worker-ai-audit` prompt (single-pass; no post-exit re-check)
- orchestrator fails fast with a "run user_review first" message if `step-N-<feature>-user-review` is missing
- legacy `ai_audit.sh` prompt generation is no longer required after conversion

**Entry gate**
- entry gate fails on missing step plan, missing design artifact, missing user_review branch — each as a distinct error line
- entry gate passes when all three preconditions are met

**Context builder**
- builder reads **only** the step design file as its content source
- builder rejects a design file whose filename or title declares a different feature id than `--feature-id`, even if the step number matches (e.g., reject `step-1.6-payments_core-...-design.md` when `--feature-id=umss_core_functionality-...`)
- builder rejects a design file whose step number does not match `--step`
- the five required design sections are extracted verbatim under labeled blocks: `## Target Bullets (excluding planning/review)`, `## Selected EARS Requirements (for planning translation)`, `## Goal`, `## In Scope`, `## Out of Scope`, `## Linked Artifacts (in scope)`
- `git status --short --untracked-files=all` output is inlined as the step delta
- `--worker-id` is taken as an explicit CLI input and echoed back in the printed context; `asdlc_repo_path` is derived from `--runtime-plan` and echoed back; skill scripts never read `feature_meta_sync.yaml`
- builder does **not** read or surface: `implementation_plan.md`, `requirements_ears.md`, step plan, blocker_log, open_questions, decisions.md, user_review.md, or design sections other than the five above (Proposal/Risks/ADRs/AGENTS shortlist/UR/Non-goals/Things to Decide/Trade-offs/Quality/Alternatives/References/Unknowns)
- missing required design sections are labeled explicitly (`- (missing in design file)`) rather than silently dropped

**Closure check**
- closure check rejects: findings with no disposition checked; findings with more than one disposition checked; `follow_up_created` without a matching `### Step N.Na` heading in implementation_plan.md; follow-up step heading present but `#### Assigned:` mismatches the current worker; `raised_to_coordinator` without a matching file under `raised_questions/`
- closure check returns each error category as a separate, model-actionable block
- closure check passes when all findings have exactly one terminal state and the recorded artifacts exist with correct assignment

**End-to-end shape**
- per-finding state-machine checkboxes are correctly parsed including the post-colon artifact reference (`[x] follow_up_created: 1.6a`, `[x] raised_to_coordinator: projects/.../raised_questions/...md`, `[x] rejected: <optional rationale>`)
- worker-repo changes commit on the audit branch; ASDLC-repo changes remain uncommitted (post_review responsibility)
- the literal sentinel completion line is emitted only after closure-check exit 0 and the worker-repo commit

Run focused ai_audit / init / orchestrator tests plus `git diff --check`.

---

## Boundary With User Review And Post Review

The audit skill must remain a separate skill/process from both user_review and post_review.

- **User review** writes runtime code (fixes from feedback) and writes `user_review.md` (durable UR rules). It gates on explicit user confirmation + a passing final `AGENTS.md` verification gate. **Audit** is analysis-only — it must not change runtime code; the audit proves a frozen patch.
- Audit reads the **step design file** as its single context source — for target bullets, resolved EARS, scope contract, and LAR refs (all pre-extracted by the design phase). It does not read `implementation_plan.md`, `requirements_ears.md`, the step plan, `.asdlc_worker/` ledger files, or planning/user_review conversation history.
- Audit produces and dispositions findings; **post_review** consolidates history and handles atomic pull-rebase + commit + push of the ASDLC repo (including audit's uncommitted `implementation_plan.md` edits and new `raised_questions/` files). The closure helper is **not** shared with post_review — post_review keeps its current entry-gate design.
- Audit commits on its own `step-N-<feature>-review` branch (from user-review); post_review later operates without a new branch.

This boundary preserves session independence and keeps audit operating from the closed step delta, the design file's frozen commitments + behavior contract + scope, and the live patch — not from prior-phase conversation history or upstream artifacts the design phase has already resolved.
