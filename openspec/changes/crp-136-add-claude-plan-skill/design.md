## Context

CRP-128 made the ASDLC planning phase a Codex skill at `ai/codex/skills/yasdef-worker-plan/` with three Python helpers (`build_plan_context.py`, `check_planning_readiness.py`, `sync_step_lars.py`) and two assets (`step_plan_TEMPLATE.md`, `step_plan_GOLDEN_EXAMPLE.md`). The orchestrator's `run_planning_phase` (`ai/scripts/orchestrator.sh:683–771`) drives an iteration loop: invoke the skill with a compact 8-input prompt, then run `check_planning_readiness.py` plus per-step ledger checks, then repeat until ready and ledgers are clean.

CRP-133 and CRP-135 established the Claude-parallel install pattern: byte-identical script/asset copies, a Claude-conventions `SKILL.md`, a slash command with explicit inputs, and an `install_claude_skills()` skills-list extension. CRP-134 made the orchestrator dispatch the planning phase to `claude` based on `ai/setup/models.md`. Today, an operator who switches the planning row in `models.md` to `claude` has no `.claude/skills/yasdef-worker-plan/` installed in the worker repo, so the runner change is not usable for planning.

This change creates the Claude parallel of the planning skill plus a slash command, and extends the worker bootstrap to install both alongside the Codex skill set and the existing Claude skill sets.

## Goals / Non-Goals

**Goals:**
- A Claude Code skill at `ai/claude/skills/yasdef-worker-plan/` that runs the same workflow as the Codex skill with the same Python helpers and assets.
- A Claude Code slash command at `ai/claude/commands/yasdef/plan.md` that triggers the skill with all eight inputs supplied explicitly by the caller.
- A single `init_asdlc_worker.sh` invocation installs the Codex planning skill, the Claude planning skill, and the Claude planning command into the target repo.

**Non-Goals:**
- Modifying the Codex planning skill, its Python helpers, or its assets in any way.
- Adding Claude Code parallels for implementation / user-review (each follows in a dedicated CRP — 137, 138).
- Adding a Codex slash-command parallel — Codex does not have an equivalent first-class slash-command surface.
- Changing the orchestrator's planning iteration loop, `run_with_output_log` behavior, `post_review.sh`, or `build_phase_cmd.sh`.
- Editing the active `cmd` value for the planning row in `ai/setup/models.md` — this CRP makes the Claude planning path *available*; switching to it is an operator decision.
- Moving the planning readiness script lookup off `.codex/skills/yasdef-worker-plan/scripts/check_planning_readiness.py` (orchestrator.sh:694). The orchestrator pins the readiness check to the Codex tree today. Switching that pin to the active runner's tree is a follow-up; see Risks.
- Refactoring the Python helpers into a shared library across Codex and Claude trees.

## Decisions

**Decision 1: Real source-tree copies, not symlinks or single-source install**

The Claude planning skill lives at `ai/claude/skills/yasdef-worker-plan/` as a full directory. Python scripts and assets are byte-identical copies of `ai/codex/skills/yasdef-worker-plan/`; `SKILL.md` is allowed to diverge to match Claude Code skill conventions. Same reasoning as CRP-133/135: symlinks are fragile in `copy_dir_contents`, in tarballs, and on Windows-host worktrees; a single-source dual-install path violates the "each skill owns its own scripts" rule.

**Decision 2: SKILL.md is allowed to diverge; scripts and assets are not**

Claude Code skill conventions may differ from Codex. The Claude `SKILL.md` is free to follow Claude conventions. The workflow contract — the 8 inputs, the iteration loop, the readiness invariants enforced by `check_planning_readiness.py`, the LARS sync invoked via `sync_step_lars.py`, the open-questions and blockers ledger semantics, the analysis-only / no-runtime-code rule, the exact sentinel completion line — is fixed across both versions because all of that is what the Python helpers and the orchestrator enforce.

Scripts and assets stay byte-identical because they're contract-bearing artifacts that must produce identical output regardless of which skill host invokes them.

**Decision 3: Slash command takes all 8 inputs explicitly; no `feature_meta_sync.yaml` lookup**

The Claude slash command body mirrors the orchestrator's compact prompt in `run_planning_phase`: it lists all 8 inputs (Step, Feature id, Branch, Design artifact, Step plan output, Runtime implementation plan, Open questions ledger, Blockers ledger) as labeled arguments the caller supplies. It does not introspect `feature_meta_sync.yaml`. Same rationale as CRP-133/135: symmetry with the Codex input contract, the orchestrator already resolves the values during routing, and removing the yaml-lookup path keeps the command minimal and removes a drift point if the yaml shape changes.

The trade-off — ergonomics for human operators who would have to type all 8 values for manual `/yasdef:plan` invocation — is accepted. The natural invocation path is the orchestrator.

**Decision 4: Install paths follow the Codex tracked-but-excluded convention; reuse CRP-133's install plumbing**

`.claude/skills/yasdef-worker-plan` joins `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS`; `.claude/commands/yasdef/plan.md` joins `DURABLE_COMMIT_PATHS`. The `.claude/commands/yasdef` directory entry is already present in `GENERATED_EXCLUDE_PATHS` from CRP-133.

The `install_claude_skills()` and `install_claude_commands()` functions already exist (CRP-133). The skills list iterated by `install_claude_skills()` gains `yasdef-worker-plan` (joining `yasdef-worker-ai-audit` from CRP-133 and `yasdef-worker-design` from CRP-135 once that lands). `install_claude_commands()` already copies `$SOURCE_CLAUDE_COMMANDS_DIR/yasdef/` as a directory, so the new `plan.md` file is picked up automatically once it exists.

**Decision 5: Don't fix the readiness-script tree pin in this CRP**

`run_planning_phase` reads `.codex/skills/yasdef-worker-plan/scripts/check_planning_readiness.py` directly (orchestrator.sh:694) to run the readiness gate between iterations. With the Claude skill installed alongside the Codex skill, both trees will have a byte-identical copy of the script, so the readiness check keeps working unchanged for an operator who has both installed. The bootstrap installs both trees in the same pass, so this assumption holds.

If a future CRP wants to install *only* the Claude skill (without the Codex skill), it will need to either (a) update the orchestrator to look up the readiness script in the active runner's tree, or (b) keep installing both trees. Either is acceptable; deferring the decision to the operator-driven CRP that motivates it is cleaner than pre-committing.

## Risks / Trade-offs

- **Orchestrator readiness gate pinned to `.codex/skills/`** → If an operator uninstalls the Codex planning skill (not supported by the current bootstrap, but possible by hand), the readiness check breaks. Mitigation: documented in Decision 5; the bootstrap installs both trees so this is theoretical until a future CRP changes the install policy.
- **Script drift between Codex and Claude trees** → Real risk over time. Mitigation: a sync-check (lint or CI assertion that the three `scripts/*.py` files are byte-identical) is recommended as a follow-up but out of scope.
- **Doubled disk footprint of the planning skill in target repos** → Accepted. Each skill is < 30 KB; doubling is negligible.
- **Slash-command ergonomics** → Accepted. Operators invoking `/yasdef:plan` manually must supply 8 inputs. The orchestrator is the primary path.
- **Skill content evolution synchronization** → If a future change updates the Codex skill's Python helpers, the Claude tree must be updated in lockstep. The install-list pattern in `init_asdlc_worker.sh` keeps the touchpoint obvious in code review.

## Migration Plan

1. Create `ai/claude/skills/yasdef-worker-plan/` with `scripts/` and `assets/` subdirectories; copy the three Python scripts and two assets byte-for-byte from `ai/codex/skills/yasdef-worker-plan/`.
2. Author the Claude `SKILL.md` — same 8 inputs, same iteration workflow, adapted framing for Claude Code conventions where they differ.
3. Create `ai/claude/commands/yasdef/plan.md` mirroring the orchestrator's compact prompt with 8 explicit input lines.
4. Extend `init_asdlc_worker.sh`: add `yasdef-worker-plan` to the skills-list iterated by `install_claude_skills`; add `.claude/skills/yasdef-worker-plan` to `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS`; add `.claude/commands/yasdef/plan.md` to `DURABLE_COMMIT_PATHS`.
5. Extend `tests/ai_scripts/init_asdlc_worker_tests.sh` with assertions covering all new install artifacts, exclude-list entries, and HEAD-tracked durability.
6. Run init against a scratch target repo to verify the Claude planning tree lands correctly alongside the Codex tree and the CRP-133 / CRP-135 trees.

Rollback: revert the change. Operators who'd opted in by setting `cmd=claude` for the planning row in `models.md` would see a skill-not-found error and switch back to `codex`. No state migration needed.
