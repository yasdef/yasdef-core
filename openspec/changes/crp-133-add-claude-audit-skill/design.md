## Context

CRP-131 converted the ai_audit phase into a Codex skill installed at `<target>/.codex/skills/yasdef-worker-ai-audit/` with three Python helpers (entry gate, context builder, closure check) and four assets (audit_result template/golden, raised_question template/golden). The orchestrator's `run_ai_audit_phase` calls the model with a compact prompt that invokes the skill by name.

Operators running Claude Code instead of Codex in the worker repo currently have no equivalent skill installed. They can still invoke the helper scripts manually, but they lose the "use the skill" affordance and the slash-command ergonomics Claude Code provides.

This change creates a Claude Code parallel of the skill plus a slash command, and extends the worker bootstrap to install both alongside the Codex skill set.

## Goals / Non-Goals

**Goals:**
- A Claude Code skill at `ai/claude/skills/yasdef-worker-ai-audit/` that runs the same workflow as the Codex skill with the same Python helpers and assets.
- A Claude Code slash command at `ai/claude/commands/yasdef/audit.md` that triggers the skill with all seven inputs supplied explicitly by the caller.
- A single `init_asdlc_worker.sh` invocation installs Codex skill, Claude skill, and Claude command into the target repo.

**Non-Goals:**
- Modifying the Codex skill, its Python helpers, or its assets in any way.
- Adding Claude Code parallels for the other four skills (design, plan, implementation, user-review) — those follow in dedicated CRPs.
- Adding a Codex slash-command parallel — Codex does not have an equivalent first-class slash-command surface.
- Changing the orchestrator's ai_audit phase invocation, post_review, or the ai_audit closure semantics.
- Refactoring the Python helpers into a shared library across Codex and Claude trees — each skill tree owns its own copy of the helpers per the established skill ownership rule.

## Decisions

**Decision 1: Real source-tree copies, not symlinks or single-source install**

The Claude skill lives at `ai/claude/skills/yasdef-worker-ai-audit/` as a full directory. Python scripts and assets are byte-identical copies of `ai/codex/skills/yasdef-worker-ai-audit/`; `SKILL.md` is allowed to diverge to match Claude Code skill conventions.

Alternatives considered:
- *Symlinks from `ai/claude/skills/...` to `ai/codex/skills/...`* — rejected. Symlinks are fragile in `copy_dir_contents`, in tarballs, and on Windows-host worktrees. They also obscure the rule "each skill owns its own scripts".
- *Single source, dual install (only `ai/codex/skills/`, install_claude_skills copies from the same source)* — rejected. Violates the user's stated source-tree layout and makes "Claude skill" not a real source artifact.

Drift between Codex and Claude script copies is a bug, not a feature; future sync-check tooling (lint or Make target) can flag it.

**Decision 2: SKILL.md is allowed to diverge; scripts and assets are not**

Claude Code skill conventions may differ from Codex (frontmatter shape, in-skill cross-references, asset references using a different syntax). The Claude `SKILL.md` is free to follow Claude conventions. The workflow contract — 7 inputs, 9 workflow steps, 6 closure error categories, the exact sentinel completion line, the analysis-only / commit-boundary / read-target rules — is fixed across both versions because all of that is what the Python helpers and the orchestrator enforce.

Scripts and assets stay byte-identical because they're contract-bearing artifacts that must produce identical output regardless of which skill host invokes them.

**Decision 3: Slash command takes all 7 inputs explicitly; no `feature_meta_sync.yaml` lookup**

The Claude slash command body mirrors the orchestrator's compact prompt: it lists all 7 inputs as labeled arguments the caller supplies. It does not introspect `feature_meta_sync.yaml`. Rationale:
- Symmetry with the Codex skill's input contract (which forbids `feature_meta_sync.yaml` reads).
- The orchestrator already resolves all 7 values from `feature_meta_sync.yaml` during routing; the slash command is the manual-invocation equivalent and the caller is expected to supply the same values.
- Removing the yaml-lookup path keeps the command code minimal and removes a possible drift point if the yaml shape changes.

The trade-off — ergonomics for human operators who would have to type all 7 values — is accepted. A future ergonomics-focused change can layer a lookup helper on top if needed.

**Decision 4: Install paths follow the Codex tracked-but-excluded convention**

Both `.claude/skills/yasdef-worker-ai-audit/` and `.claude/commands/yasdef/` go into `GENERATED_EXCLUDE_PATHS`; `.claude/skills/yasdef-worker-ai-audit/` and `.claude/commands/yasdef/audit.md` go into `DURABLE_COMMIT_PATHS`. This matches how the Codex skill is handled: tracked once at bootstrap, ignored from subsequent diffs so re-running init does not produce spurious diffs.

**Decision 5: Only ai_audit for now**

The four other phases (design, plan, implementation, user-review) are not Claude-mirrored in this CRP. The install function `install_claude_skills()` iterates a list so future skills can be appended without restructuring.

## Risks / Trade-offs

- **Script drift between Codex and Claude trees** → Real risk over time. Mitigation: a sync-check (lint or CI assertion that the two `scripts/*.py` files are byte-identical) is recommended as a follow-up but not required for this CRP. Until it exists, code review owns drift detection.
- **Doubled disk footprint of the skill in target repos** → Accepted. Each skill is < 30 KB; doubling is negligible.
- **Slash-command ergonomics** → Accepted. Operators invoking `/yasdef:audit` manually must supply 7 inputs. The natural invocation path is still the orchestrator; the slash command is a manual fallback.
- **Skill content evolution synchronization** → If a future change updates the Codex skill's Python helpers (e.g. adds a 7th closure error category), the Claude tree must be updated in lockstep. The two-list install pattern in `init_asdlc_worker.sh` makes the touchpoints obvious in code review.

## Migration Plan

1. Create the Claude source tree by copying the four Codex script/asset files byte-for-byte and authoring a new SKILL.md.
2. Create the slash command.
3. Extend `init_asdlc_worker.sh` with two source-dir globals, two new install functions, two extended path-list constants, and two install-flow calls.
4. Extend `tests/ai_scripts/init_asdlc_worker_tests.sh` with the new assertions.
5. Run the init test against a scratch target repo to verify both the Codex and Claude trees land correctly.
6. No data migration, no orchestrator changes, no spec changes for downstream phases.
