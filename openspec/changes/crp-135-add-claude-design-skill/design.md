## Context

CRP-127 made the ASDLC design phase a Codex skill at `ai/codex/skills/yasdef-worker-design/` with two Python helpers (`build_design_context.py`, `check_design_readiness.py`) and two assets (`feature_design_TEMPLATE.md`, `feature_design_GOLDEN_EXAMPLE.md`). The orchestrator's `run_design_phase` (`ai/scripts/orchestrator.sh:778–845`) calls the model with a compact prompt that names the skill and supplies five inputs: step, feature id, branch, design output path, runtime implementation plan path, runtime requirements EARS path.

CRP-133 established the Claude-parallel install pattern by adding `ai/claude/skills/yasdef-worker-ai-audit/` plus `/yasdef:audit`. CRP-134 made the orchestrator dispatch any phase to the `claude` runner based on `ai/setup/models.md`. Today, an operator who switches the design row in `models.md` to `claude` has no `.claude/skills/yasdef-worker-design/` installed in the worker repo, so the runner change is not usable for the design phase.

This change creates the Claude parallel of the design skill plus a slash command, and extends the worker bootstrap to install both alongside the Codex skill set and the Claude ai_audit skill installed by CRP-133.

## Goals / Non-Goals

**Goals:**
- A Claude Code skill at `ai/claude/skills/yasdef-worker-design/` that runs the same workflow as the Codex skill with the same Python helpers and assets.
- A Claude Code slash command at `ai/claude/commands/yasdef/design.md` that triggers the skill with all five inputs supplied explicitly by the caller.
- A single `init_asdlc_worker.sh` invocation installs the Codex design skill, the Claude design skill, and the Claude design command into the target repo.

**Non-Goals:**
- Modifying the Codex design skill, its Python helpers, or its assets in any way.
- Adding Claude Code parallels for plan / implementation / user-review (each follows in a dedicated CRP — 136, 137, 138).
- Adding a Codex slash-command parallel — Codex does not have an equivalent first-class slash-command surface.
- Changing the orchestrator's design phase invocation, `run_with_output_log` behavior, `post_review.sh`, or `build_phase_cmd.sh`.
- Editing the active `cmd` value for the design row in `ai/setup/models.md` — this CRP makes the Claude design path *available*; switching to it is an operator decision.
- Refactoring the Python helpers into a shared library across Codex and Claude trees — each skill tree owns its own copy of the helpers per the established skill ownership rule.

## Decisions

**Decision 1: Real source-tree copies, not symlinks or single-source install**

The Claude design skill lives at `ai/claude/skills/yasdef-worker-design/` as a full directory. Python scripts and assets are byte-identical copies of `ai/codex/skills/yasdef-worker-design/`; `SKILL.md` is allowed to diverge to match Claude Code skill conventions.

This mirrors the CRP-133 decision: symlinks are fragile in `copy_dir_contents`, in tarballs, and on Windows-host worktrees, and a single-source dual-install path violates the "each skill owns its own scripts" rule and makes "Claude skill" not a real source artifact.

Drift between Codex and Claude script copies is a bug, not a feature; future sync-check tooling (lint or Make target) can flag it. Until it exists, code review owns drift detection.

**Decision 2: SKILL.md is allowed to diverge; scripts and assets are not**

Claude Code skill conventions may differ from Codex (frontmatter shape, in-skill cross-references, asset-reference syntax). The Claude `SKILL.md` is free to follow Claude conventions. The workflow contract — the 5 inputs, the design-artifact path layout under `.asdlc_worker/step_designs/`, the analysis-only / no-runtime-code rule, the sentinel completion line, the helper invocations (`build_design_context.py` for context assembly, `check_design_readiness.py` for closure validation) — is fixed across both versions because all of that is what the Python helpers and the orchestrator enforce.

Scripts and assets stay byte-identical because they're contract-bearing artifacts that must produce identical output regardless of which skill host invokes them.

**Decision 3: Slash command takes all 5 inputs explicitly; no `feature_meta_sync.yaml` lookup**

The Claude slash command body mirrors the orchestrator's compact prompt in `run_design_phase`: it lists all 5 inputs (Step, Feature id, Branch, Design output, Runtime implementation plan, Runtime requirements EARS) as labeled arguments the caller supplies. It does not introspect `feature_meta_sync.yaml`. Same rationale as CRP-133: symmetry with the Codex input contract, the orchestrator already resolves the values during routing, and removing the yaml-lookup path keeps the command minimal and removes a drift point if the yaml shape changes.

The trade-off — ergonomics for human operators who would have to type all 5 values for manual `/yasdef:design` invocation — is accepted. The natural invocation path is the orchestrator; the slash command is a manual fallback.

**Decision 4: Install paths follow the Codex tracked-but-excluded convention; reuse CRP-133's install plumbing**

`.claude/skills/yasdef-worker-design` joins `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS`; `.claude/commands/yasdef/design.md` joins `DURABLE_COMMIT_PATHS`. The `.claude/commands/yasdef` directory entry is already present in `GENERATED_EXCLUDE_PATHS` from CRP-133 and is not duplicated.

The `install_claude_skills()` and `install_claude_commands()` functions already exist (CRP-133). The skills list iterated by `install_claude_skills()` gains `yasdef-worker-design` — no new install function needed. `install_claude_commands()` already copies `$SOURCE_CLAUDE_COMMANDS_DIR/yasdef/` as a directory, so the new `design.md` file is picked up automatically once it exists; no code change to the function body is needed beyond having the file on disk.

**Decision 5: Each phase Claude skill is its own CRP (135, 136, 137, 138)**

The four remaining phases (design, plan, implementation, user-review) get one CRP each rather than a single bundled change. Rationale:
- Each phase's Codex skill has its own helper script set and asset set; bundling would produce one large task list with no logical grouping.
- Each CRP is independently reviewable and revertable — if the design skill ships but the implementation skill needs more work, the orchestrator behavior is unaffected because `models.md` rows are independent.
- The install-list extension is a one-line change per CRP, so the per-CRP overhead is small.

## Risks / Trade-offs

- **Script drift between Codex and Claude trees** → Real risk over time. Mitigation: a sync-check (lint or CI assertion that the two `scripts/*.py` files are byte-identical) is recommended as a follow-up but out of scope for this CRP.
- **Doubled disk footprint of the design skill in target repos** → Accepted. Each skill is < 20 KB; doubling is negligible.
- **Slash-command ergonomics** → Accepted. Operators invoking `/yasdef:design` manually must supply 5 inputs. The orchestrator is the primary path; the slash command is a manual fallback.
- **Skill content evolution synchronization** → If a future change updates the Codex skill's Python helpers, the Claude tree must be updated in lockstep. The install-list pattern in `init_asdlc_worker.sh` keeps the touchpoint obvious in code review.

## Migration Plan

1. Create `ai/claude/skills/yasdef-worker-design/` with `scripts/` and `assets/` subdirectories; copy the two Python scripts and two assets byte-for-byte from `ai/codex/skills/yasdef-worker-design/`.
2. Author the Claude `SKILL.md` — same 5 inputs, same workflow, adapted framing for Claude Code conventions where they differ.
3. Create `ai/claude/commands/yasdef/design.md` mirroring the orchestrator's compact prompt with 5 explicit input lines.
4. Extend `init_asdlc_worker.sh`: add `yasdef-worker-design` to the skills-list iterated by `install_claude_skills`; add `.claude/skills/yasdef-worker-design` to `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS`; add `.claude/commands/yasdef/design.md` to `DURABLE_COMMIT_PATHS`.
5. Extend `tests/ai_scripts/init_asdlc_worker_tests.sh` with assertions covering all new install artifacts, exclude-list entries, and HEAD-tracked durability.
6. Run init against a scratch target repo to verify the Claude design tree lands correctly alongside the Codex tree and the CRP-133 ai_audit tree.

Rollback: revert the change. Operators who'd opted in by setting `cmd=claude` for the design row in `models.md` would see a skill-not-found error and switch back to `codex`. No state migration needed.
