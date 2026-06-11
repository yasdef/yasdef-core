## Context

CRP-130 made the ASDLC user_review phase a Codex skill at `ai/codex/skills/yasdef-worker-user-review/` with one Python helper (`build_user_review_context.py`) and four assets (`review_brief_TEMPLATE.md`, `review_brief_GOLDEN_EXAMPLE.md`, `user_review_TEMPLATE.md`, `user_review_GOLDEN_EXAMPLE.md`). The orchestrator's `run_user_review_phase` (`ai/scripts/orchestrator.sh:1966–2021`) runs an orchestrator-owned implementation-readiness gate, creates/switches to a user-review branch, then invokes the model once with a compact 6-input prompt that names the skill.

CRP-133 / CRP-135 / CRP-136 / CRP-137 established the Claude-parallel install pattern: byte-identical script/asset copies, a Claude-conventions `SKILL.md`, a slash command with explicit inputs, and an `install_claude_skills()` skills-list extension. CRP-134 made the orchestrator dispatch the user_review phase to `claude` based on `ai/setup/models.md`. Today, an operator who switches the user_review row in `models.md` to `claude` has no `.claude/skills/yasdef-worker-user-review/` installed in the worker repo, so the runner change is not usable for user_review.

This change is the final entry in the CRP-135..138 series. After it lands, all five ASDLC worker phases have Claude parallels and the orchestrator's runner-dispatch (CRP-134) is fully usable across the worker lifecycle.

## Goals / Non-Goals

**Goals:**
- A Claude Code skill at `ai/claude/skills/yasdef-worker-user-review/` that runs the same workflow as the Codex skill with the same Python helper and assets.
- A Claude Code slash command at `ai/claude/commands/yasdef/user-review.md` that triggers the skill with all six inputs supplied explicitly by the caller.
- A single `init_asdlc_worker.sh` invocation installs the Codex user_review skill, the Claude user_review skill, and the Claude user_review command into the target repo.
- All five worker phases have a Claude parallel after this change ships.

**Non-Goals:**
- Modifying the Codex user_review skill, its Python helper, or its assets in any way.
- Changing the orchestrator's user_review phase invocation, the orchestrator-owned implementation-readiness gate, `run_with_output_log` behavior, `post_review.sh`, or `build_phase_cmd.sh`.
- Editing the active `cmd` value for the user_review row in `ai/setup/models.md` — this CRP makes the Claude user_review path *available*; switching to it is an operator decision.
- Moving the `SKILL.md` existence check off `.codex/skills/yasdef-worker-user-review/SKILL.md` (orchestrator.sh:1993). Same deferral as the earlier CRPs in this series.
- Refactoring the Python helper into a shared library across Codex and Claude trees.

## Decisions

**Decision 1: Real source-tree copies, not symlinks or single-source install**

The Claude user_review skill lives at `ai/claude/skills/yasdef-worker-user-review/` as a full directory. The Python script and assets are byte-identical copies of `ai/codex/skills/yasdef-worker-user-review/`; `SKILL.md` is allowed to diverge to match Claude Code skill conventions. Same reasoning as CRP-133/135/136/137.

**Decision 2: SKILL.md is allowed to diverge; the script and assets are not**

Claude Code skill conventions may differ from Codex. The Claude `SKILL.md` is free to follow Claude conventions. The workflow contract — the 6 inputs, the executing-phase semantics (this phase edits runtime code in response to user feedback), the durable-rules update behavior on `.asdlc_worker/user_review.md`, the review-brief authoring shape, the analysis-only-where-applicable rules, the exact sentinel completion line — is fixed across both versions.

The script and assets stay byte-identical because they're contract-bearing artifacts that must produce identical output regardless of which skill host invokes them.

**Decision 3: Slash command takes all 6 inputs explicitly; no `feature_meta_sync.yaml` lookup**

The Claude slash command body mirrors the orchestrator's compact prompt in `run_user_review_phase`: it lists all 6 inputs (Step, Feature id, Branch, Step plan, Design artifact, Runtime implementation plan) as labeled arguments the caller supplies. It does not introspect `feature_meta_sync.yaml`. Same rationale as the earlier CRPs in this series.

**Decision 4: Slash command filename uses `user-review.md` (hyphen), matching the directory convention**

The Codex skill directory is `yasdef-worker-user-review` (hyphen), and the orchestrator and history files use `user_review` (underscore) as the phase token. The Claude slash command file is named `user-review.md` so the resulting slash command is `/yasdef:user-review` — kebab-case is the Claude Code slash-command convention, and it matches the skill directory's hyphenation. Operators who think in `user_review` (the phase token) can find it by analogy with the directory name.

Alternative considered:
- *`user_review.md` (underscore)* — rejected. Underscores in slash-command names are unconventional in Claude Code and would clash with the directory naming the other commands in this series follow.

**Decision 5: Install paths follow the Codex tracked-but-excluded convention; reuse CRP-133's install plumbing**

`.claude/skills/yasdef-worker-user-review` joins `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS`; `.claude/commands/yasdef/user-review.md` joins `DURABLE_COMMIT_PATHS`. The `.claude/commands/yasdef` directory entry is already present in `GENERATED_EXCLUDE_PATHS` from CRP-133.

The `install_claude_skills()` and `install_claude_commands()` functions already exist. The skills list gains `yasdef-worker-user-review` (joining all four entries added by CRP-133 / CRP-135 / CRP-136 / CRP-137). `install_claude_commands()` already copies `$SOURCE_CLAUDE_COMMANDS_DIR/yasdef/` as a directory, so the new `user-review.md` file is picked up automatically.

**Decision 6: Don't fix the SKILL.md existence-check tree pin in this CRP**

`run_user_review_phase` reads `.codex/skills/yasdef-worker-user-review/SKILL.md` directly (orchestrator.sh:1993) as a pre-flight check. With both trees installed, the file exists in both, so this keeps working unchanged. Switching the pin to the active runner's tree is deferred to a future CRP that motivates it (same deferral pattern as CRP-136/137).

## Risks / Trade-offs

- **Orchestrator pre-flight check pinned to `.codex/skills/`** → If an operator uninstalls the Codex user_review skill, the orchestrator-side check breaks. Mitigation: documented in Decision 6; the bootstrap installs both trees.
- **Script drift between Codex and Claude trees** → Real risk over time. Mitigation: sync-check (lint or CI assertion) is recommended as a follow-up but out of scope.
- **Doubled disk footprint of the user_review skill in target repos** → Accepted. Each skill is < 25 KB; doubling is negligible.
- **Slash-command ergonomics** → Accepted. Operators invoking `/yasdef:user-review` manually must supply 6 inputs. The orchestrator is the primary path.
- **Skill content evolution synchronization** → If a future change updates the Codex skill's Python helper or assets, the Claude tree must be updated in lockstep. The install-list pattern in `init_asdlc_worker.sh` keeps the touchpoint obvious in code review.

## Migration Plan

1. Create `ai/claude/skills/yasdef-worker-user-review/` with `scripts/` and `assets/` subdirectories; copy the one Python script and four assets byte-for-byte from `ai/codex/skills/yasdef-worker-user-review/`.
2. Author the Claude `SKILL.md` — same 6 inputs, same executing-phase semantics, same durable-rules-update behavior, adapted framing for Claude Code conventions where they differ.
3. Create `ai/claude/commands/yasdef/user-review.md` mirroring the orchestrator's compact prompt with 6 explicit input lines.
4. Extend `init_asdlc_worker.sh`: add `yasdef-worker-user-review` to the skills-list iterated by `install_claude_skills`; add `.claude/skills/yasdef-worker-user-review` to `GENERATED_EXCLUDE_PATHS` and `DURABLE_COMMIT_PATHS`; add `.claude/commands/yasdef/user-review.md` to `DURABLE_COMMIT_PATHS`.
5. Extend `tests/ai_scripts/init_asdlc_worker_tests.sh` with assertions covering all new install artifacts, exclude-list entries, and HEAD-tracked durability.
6. Run init against a scratch target repo to verify the Claude user_review tree lands correctly alongside the Codex tree and all four prior Claude trees (CRP-133 / CRP-135 / CRP-136 / CRP-137). After this verification, the full Claude parallel set is in place: `yasdef-worker-design`, `yasdef-worker-plan`, `yasdef-worker-implementation`, `yasdef-worker-user-review`, `yasdef-worker-ai-audit`.

Rollback: revert the change. Operators who'd opted in by setting `cmd=claude` for the user_review row in `models.md` would see a skill-not-found error and switch back to `codex`. No state migration needed.
