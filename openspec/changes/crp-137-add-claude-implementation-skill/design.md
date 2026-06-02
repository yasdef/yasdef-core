## Context

CRP-129 made the ASDLC implementation phase a Codex skill at `ai/codex/skills/yasdef-worker-implementation/` with two Python helpers (`build_implementation_context.py`, `check_implementation_readiness.py`) and no assets. The orchestrator's `run_implementation_phase` (`ai/scripts/orchestrator.sh:1893–1960`) calls the model with a compact prompt naming the skill and supplying six inputs (step, feature id, branch, step plan path, design artifact path, runtime implementation plan path), and pins both the context-builder and the readiness check to the Codex tree under `.codex/skills/yasdef-worker-implementation/scripts/`.

CRP-133 / CRP-135 / CRP-136 established the Claude-parallel install pattern: byte-identical script/asset copies, a Claude-conventions `SKILL.md`, a slash command with explicit inputs, and an `install_claude_skills()` skills-list extension. CRP-134 made the orchestrator dispatch the implementation phase to `claude` based on `ai/setup/models.md`. Today, an operator who switches the implementation row in `models.md` to `claude` has no `.claude/skills/yasdef-worker-implementation/` installed in the worker repo, so the runner change is not usable for implementation.

This change creates the Claude parallel of the implementation skill plus a slash command, and extends the worker bootstrap to install both alongside the Codex skill set and the existing Claude skill sets.

## Goals / Non-Goals

**Goals:**
- A Claude Code skill at `ai/claude/skills/yasdef-worker-implementation/` that runs the same workflow as the Codex skill with the same Python helpers.
- A Claude Code slash command at `ai/claude/commands/yasdef/implementation.md` that triggers the skill with all six inputs supplied explicitly by the caller.
- A single `init_asdlc_worker.sh` invocation installs the Codex implementation skill, the Claude implementation skill, and the Claude implementation command into the target repo.

**Non-Goals:**
- Modifying the Codex implementation skill or its Python helpers in any way.
- Adding Claude Code parallels for user-review (follows in a dedicated CRP — 138).
- Adding a Codex slash-command parallel — Codex does not have an equivalent first-class slash-command surface.
- Changing the orchestrator's implementation phase invocation, `run_with_output_log` behavior, `post_review.sh`, or `build_phase_cmd.sh`.
- Editing the active `cmd` value for the implementation row in `ai/setup/models.md` — this CRP makes the Claude implementation path *available*; switching to it is an operator decision.
- Moving the implementation context-builder and readiness-script lookups off `.codex/skills/yasdef-worker-implementation/scripts/...` (orchestrator.sh:1920–1921, 2023). The orchestrator pins these to the Codex tree today; same deferral as CRP-136 for planning. See Risks.
- Refactoring the Python helpers into a shared library across Codex and Claude trees.

## Decisions

**Decision 1: Real source-tree copies, not symlinks or single-source install**

The Claude implementation skill lives at `ai/claude/skills/yasdef-worker-implementation/` as a full directory. Python scripts are byte-identical copies of `ai/codex/skills/yasdef-worker-implementation/`; `SKILL.md` is allowed to diverge to match Claude Code skill conventions. Same reasoning as CRP-133/135/136.

**Decision 2: SKILL.md is allowed to diverge; scripts are not**

Claude Code skill conventions may differ from Codex. The Claude `SKILL.md` is free to follow Claude conventions. The workflow contract — the 6 inputs, the executing-phase semantics (this is the only phase that edits runtime code), the step-plan checklist update behavior, the readiness invariants enforced by `check_implementation_readiness.py`, the analysis-only-where-applicable rules, the exact sentinel completion line — is fixed across both versions.

Scripts stay byte-identical because they're contract-bearing artifacts that must produce identical output regardless of which skill host invokes them.

**Decision 3: No assets directory, mirroring the Codex tree**

The Codex implementation skill has no `assets/` subdirectory. The Claude tree mirrors that exactly — no `assets/` directory is created. If a future Codex change adds assets, the Claude tree must add them in lockstep.

**Decision 4: Slash command takes all 6 inputs explicitly; no `feature_meta_sync.yaml` lookup**

The Claude slash command body mirrors the orchestrator's compact prompt in `run_implementation_phase`: it lists all 6 inputs (Step, Feature id, Branch, Step plan, Design artifact, Runtime implementation plan) as labeled arguments the caller supplies. It does not introspect `feature_meta_sync.yaml`. Same rationale as the earlier CRPs.

The trade-off — ergonomics for human operators who would have to type all 6 values — is accepted. The orchestrator is the primary path.

**Decision 5: Install paths follow the Codex tracked-but-excluded convention; reuse CRP-133's install plumbing**

`.claude/skills/yasdef-worker-implementation` joins `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS`; `.claude/commands/yasdef/implementation.md` joins `DURABLE_COMMIT_PATHS`. The `.claude/commands/yasdef` directory entry is already present in `GENERATED_EXCLUDE_PATHS` from CRP-133.

The `install_claude_skills()` and `install_claude_commands()` functions already exist. The skills list gains `yasdef-worker-implementation` (joining the entries added by CRP-133 / CRP-135 / CRP-136). `install_claude_commands()` already copies `$SOURCE_CLAUDE_COMMANDS_DIR/yasdef/` as a directory, so the new `implementation.md` file is picked up automatically.

**Decision 6: Don't fix the context/readiness-script tree pin in this CRP**

`run_implementation_phase` reads `.codex/skills/yasdef-worker-implementation/scripts/build_implementation_context.py` and `.../check_implementation_readiness.py` directly (orchestrator.sh:1920–1921). With both trees installed, both have byte-identical copies of the scripts, so this keeps working unchanged. Switching the pin to the active runner's tree is deferred to a future CRP that motivates it (same deferral pattern as CRP-136).

## Risks / Trade-offs

- **Orchestrator context/readiness gate pinned to `.codex/skills/`** → If an operator uninstalls the Codex implementation skill, the orchestrator-side helpers break. Mitigation: documented in Decision 6; the bootstrap installs both trees.
- **Script drift between Codex and Claude trees** → Real risk over time. Mitigation: sync-check (lint or CI assertion) is recommended as a follow-up but out of scope.
- **Doubled disk footprint of the implementation skill in target repos** → Accepted. Each skill is < 20 KB; doubling is negligible.
- **Slash-command ergonomics** → Accepted. Operators invoking `/yasdef:implementation` manually must supply 6 inputs. The orchestrator is the primary path.
- **Skill content evolution synchronization** → If a future change updates the Codex skill's Python helpers, the Claude tree must be updated in lockstep. The install-list pattern in `init_asdlc_worker.sh` keeps the touchpoint obvious in code review.

## Migration Plan

1. Create `ai/claude/skills/yasdef-worker-implementation/` with a `scripts/` subdirectory; copy the two Python scripts byte-for-byte from `ai/codex/skills/yasdef-worker-implementation/`. Do NOT create an `assets/` directory (parity with Codex).
2. Author the Claude `SKILL.md` — same 6 inputs, same executing-phase semantics, adapted framing for Claude Code conventions where they differ.
3. Create `ai/claude/commands/yasdef/implementation.md` mirroring the orchestrator's compact prompt with 6 explicit input lines.
4. Extend `init_asdlc_worker.sh`: add `yasdef-worker-implementation` to the skills-list iterated by `install_claude_skills`; add `.claude/skills/yasdef-worker-implementation` to `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS`; add `.claude/commands/yasdef/implementation.md` to `DURABLE_COMMIT_PATHS`.
5. Extend `tests/ai_scripts/init_asdlc_worker_tests.sh` with assertions covering all new install artifacts, exclude-list entries, and HEAD-tracked durability.
6. Run init against a scratch target repo to verify the Claude implementation tree lands correctly alongside the Codex tree and the CRP-133 / CRP-135 / CRP-136 trees.

Rollback: revert the change. Operators who'd opted in by setting `cmd=claude` for the implementation row in `models.md` would see a skill-not-found error and switch back to `codex`. No state migration needed.
