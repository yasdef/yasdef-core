## Context

The planning phase is currently driven by a detailed prompt block in `ai/scripts/ai_plan.sh` (`run_planning_phase`). This block duplicates planning rules into the orchestrator shell script, making them hard to keep in sync with `AI_DEVELOPMENT_PROCESS.md §2` and impossible to update without touching orchestration logic. There is no deterministic context assembly or readiness gate — the model is expected to self-enforce structure from a long inline prompt.

The design-phase conversion (`yasdef-worker-design`) established the skill pattern: orchestrator writes a compact variable-passing prompt, the skill owns all model-facing instructions, and Python scripts handle deterministic context assembly and readiness validation. This change applies the same pattern to planning.

## Goals / Non-Goals

**Goals:**
- Move all planning rules into `yasdef-worker-plan/SKILL.md`
- Add `build_plan_context.py` to assemble structured context from design + implementation-plan artifacts deterministically
- Add `check_planning_readiness.py` to validate planning closure gates with exit codes
- Add `sync_step_lars.py` to mirror design LAR references into the step plan deterministically
- Make the orchestrator planning prompt compact (variables only, no inline rules)
- Install the skill via `init_asdlc_worker.sh` into `.codex/skills/yasdef-worker-plan`
- Cover all new Python scripts with tests under `tests/skills_python_scripts/`
- Introduce per-step open-questions and blocker files as machine-readable orchestrator loop ledgers
- Add gap analysis as an explicit SKILL.md-instructed phase within each planning iteration: model reads repo against current plan, identifies gaps requiring user input, writes them to ledger files
- Restructure `ai_plan.sh` planning phase as an orchestrator loop: invoke skill → machine-check readiness + ledger state → repeat or done

**Non-Goals:**
- Changing the step plan artifact format or the set of planning closure gates
- Merging planning and design into a single skill or phase
- Adding a `python3` fallback — `uv` is a runtime requirement
- Changing post-planning phase behavior (implementation readiness gate, commit behavior)

## Decisions

**Skill structure mirrors `yasdef-worker-design`**
SKILL.md owns model-facing instructions; scripts own deterministic work; assets own templates and golden examples. This keeps the pattern consistent and makes both skills upgradeable independently.

**`uv run python` is the only runtime path**
No `python3` fallback inside the skill. Requiring `uv` enforces a consistent dependency-managed environment and avoids silent divergence from the project's standard runtime.

**Design artifact is a hard input gate**
`build_plan_context.py` must fail fast with a clear error if the design artifact is missing or empty. The skill must not infer or substitute a design path. This preserves the session-independence property: planning always operates from an on-disk artifact, not from a live conversation.

**Explicit path arguments only; no runtime inference**
All paths (`--design`, `--plan-out`, `--runtime-plan`) are passed explicitly. The scripts must not read `.asdlc_worker/feature_meta_sync.yaml` or probe the runtime environment for missing values. If a required input is absent, the skill stops and asks for explicit instructions.

**Readiness gate exit codes: `0` ready, `1` gates failed, `2` system/usage error**
Structured exit codes let the orchestrator and model distinguish recoverable gate failures from configuration problems without parsing stderr.

**Template initialization via explicit placeholder assertions**
`build_plan_context.py` initializes a missing step plan from `assets/step_plan_TEMPLATE.md`. It must not silently leave required placeholders unresolved — use a renderer or explicit placeholder-hit assertions before writing.

**Compact orchestrator prompt**
The orchestrator passes only variables. All planning rules live in `SKILL.md`. This is the same contract as the design skill prompt and avoids drift between the prompt and the skill.

**Orchestrator drives the loop; skill owns one iteration**
Each skill session runs three phases in order: (1) resolve open questions from ledger files and design Things to Decide with the user; (2) update/generate `## Plan (ordered)` and `## Functional Requirements`; (3) analyse the repo against the current plan and write any gaps requiring user input to ledger files. The skill exits after step 3 — it does not loop internally. The orchestrator re-checks machine conditions after each exit and decides whether to invoke again. This keeps individual sessions focused and avoids context accumulation across loop iterations.

**Per-step ledger files replace section-based shared files**
`open_questions.md` and `blocker_log.md` currently use per-step sections in shared files. New planning runs under this skill use per-step files in dedicated directories: `step_open_questions/step-<step>-<feature-id>-open-questions.md` and `step_blockers/step-<step>-<feature-id>-blockers.md`. This follows the same directory-per-type pattern already established by `step_designs/` and `step_plans/`, and requires adding `ASDLC_STEP_OPEN_QUESTIONS_DIR` and `ASDLC_STEP_BLOCKERS_DIR` to `runtime_layout.sh`. This makes the orchestrator loop condition machine-checkable by file state alone. Existing shared-file entries remain valid for active steps already in progress.

**Loop termination is fully machine-checked**
After each skill exit, `ai_plan.sh` runs `check_planning_readiness.py` and inspects ledger files without invoking the model. Both must pass for the loop to terminate. `check_planning_readiness.py` serves a dual role: orchestrator loop condition (called by the shell) and model-callable validation inside the skill before the session exits.

**Gap analysis output discipline: ledger files only for user-required inputs**
During the gap analysis phase, the model writes to ledger files only for gaps that require explicit user input or approval — missing prerequisites with scope ambiguity, design decisions that surface during repo analysis, conflicting constraints. Gaps the model can resolve independently within the session (adding a clear prerequisite bullet, clarifying an FR) are resolved in place without writing to ledger files.

## Risks / Trade-offs

**Legacy script removal timing** → Do not remove `ai_plan.sh` planning blocks or legacy scripts until the skill is verified working in at least one live planning session. Keep both paths operative during transition.

**Worker install propagation** → `init_asdlc_worker.sh` must be updated before the skill is usable in worker projects. If the install step is missed, workers will continue using the old inline prompt. Mitigation: make the install step part of the same PR as the skill.

**`.git/info/exclude` handling** → The installed skill path in worker projects (`.codex/skills/yasdef-worker-plan`) must be excluded the same way as the design skill. Missing this causes the installed skill to appear as untracked changes in worker repos.

**Golden example scope creep** → `step_plan_GOLDEN_EXAMPLE.md` must be treated as style/completeness reference only. The skill must explicitly instruct the model not to copy domain content from the example. Mitigation: SKILL.md must state this constraint clearly.

## Migration Plan

1. Add `ai/codex/skills/yasdef-worker-plan/` with all files.
2. Move `step_plan_TEMPLATE.md` and `step_plan_GOLDEN_EXAMPLE.md` into `assets/` if they currently live elsewhere.
3. Update `init_asdlc_worker.sh` to install the new skill directory.
4. Update `.git/info/exclude` handling in `init_asdlc_worker.sh` for the installed skill path.
5. Replace `run_planning_phase` prompt block with an orchestrator loop that invokes the skill with a compact variable-only prompt, then checks `check_planning_readiness.py` exit code and ledger file state, repeating until both pass.
6. Initialize per-step ledger files on first skill invocation for a step; document that existing active steps using the shared-file format remain valid until replanned.
7. Replace the detailed planning block in `AI_DEVELOPMENT_PROCESS.md` with a pointer to `SKILL.md`.
8. Add tests under `tests/skills_python_scripts/`.
9. Verify in a live planning session before removing legacy planning scripts.

## Open Questions
