## Why

Overmind init step 1.1 now produces a per-class agent-guidance artifact `project_agents_md_claude_md_<class>.md` at project level, next to the stack blueprints. The worker never reads it: first-feature bootstrap discovery (`find_blueprints.py` in the `yasdef-worker-design` skill) only globs `project_stack_blueprint_*.md`, and no phase rule offers to instantiate project-root `AGENTS.md` and `CLAUDE.md` from that guidance. As a result, freshly scaffolded worker repos can start implementation work without the agent operating rules overmind already prepared for them.

The worker must not silently merge with or selectively preserve one local guidance file. Project repositories may already contain either file as meaningful guidance, a placeholder, or a symlink, and users may also have unrelated global guidance. The bootstrap interaction therefore needs one explicit, all-or-nothing decision whenever either project-root file is absent.

Additionally, the helper's class resolution is broken in the current bound layout: it reads `class` from `<feature_dir_parent>/.asdlc_worker/project_overmind.yaml`, but feature folders live in the overmind project folder (`overmind_source_path/<feature_id>`) while the binding file lives in the worker repo root (`RuntimeLayout.binding_file`). The class therefore resolves as `unresolved` and the class filter never fires.

## What Changes

- Extend `src/yasdef_worker/_data/skills/yasdef-worker-design/scripts/find_blueprints.py`:
  - Also discover `project_agents_md_claude_md_*.md` at the project-level search root (parent of the feature directory), partitioned by worker class with the same substring rules as blueprints, reported as a distinct labeled block with its own summary line.
  - Fix class resolution: locate `.asdlc_worker/project_overmind.yaml` by walking up from the script's own installed location (the skill bundle lives inside the worker repo under `.claude/skills/`, `.codex/skills/`, etc.), instead of `<feature_dir_parent>/.asdlc_worker/`.
  - Report whether project-root `AGENTS.md` and `CLAUDE.md` are present; global guidance locations are not inspected and do not satisfy the project-root check.
- Update `src/yasdef_worker/_data/skills/yasdef-worker-design/SKILL.md` `## Bootstrap Decision`:
  - When `Bootstrap required: yes`, record the agents-guidance lookup, both local file states, and the reconciliation decision in `## First-Feature Bootstrap (only if needed)`.
  - If both local files are present, leave them unchanged without prompting, regardless of their content.
  - If either file is absent, ask one binary question: regenerate both project-root files from the class-matching knowledgebase artifact, backing up and overwriting either existing file so the outputs are identical, or leave the repository unchanged. Do not offer per-file, merge, or partial-preservation choices.
  - If either project-root path is a directory, report a blocking invalid state and ask the user to resolve it before offering regeneration.
  - If no unambiguous class-matching guidance artifact exists, ask the user for guidance rather than offering regeneration from invented content.
- Materialize an accepted `regenerate both` decision after design and before the scaffold implementation model starts. Before overwriting, preserve each existing root path under `.asdlc_worker/agent_guidance_backups/<operation-id>/`, then write identical bytes to both project-root files as one all-or-nothing operation; a declined decision writes neither file and creates no backup.
- Update design readiness, phase/application integration, and tests for the discovery, decision, overwrite, no-op, and pre-model materialization contracts.

Out of scope: global `AGENTS.md`/`CLAUDE.md` discovery or modification; content-quality or placeholder detection when both project-root files already exist; automatic deletion, renaming, or replacement of a directory at either guidance path; per-file merge/preservation choices; overmind-side artifact generation (already exists); non-bootstrap feature flow.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `yasdef-worker-design-skill`: the in-skill discovery helper gains agents-guidance discovery, project-root file-state reporting, and worker-repo-rooted class resolution; the Bootstrap Decision contract gains an all-or-nothing AGENTS.md + CLAUDE.md reconciliation decision. (Baseline spec is introduced by `crp-139-move-blueprint-helper-into-design-skill`; this change layers on top of it.)

## Impact

- `src/yasdef_worker/_data/skills/yasdef-worker-design/scripts/find_blueprints.py`: discovery + class-resolution changes.
- `src/yasdef_worker/_data/skills/yasdef-worker-design/SKILL.md`: Bootstrap Decision section extended.
- `src/yasdef_worker/_data/skills/yasdef-worker-design/scripts/check_design_readiness.py`: validates the recorded reconciliation state for bootstrap-required designs.
- Design phase/application integration: materializes an accepted decision before later scaffold model work starts.
- Installer/runtime exclude configuration: keeps local agent-guidance backups out of normal source-control staging.
- Design helper, readiness, phase, and integration tests: updated/extended assertions.
- Depends on `crp-139-move-blueprint-helper-into-design-skill` (helper already lives in the skill bundle) and on overmind producing `project_agents_md_claude_md_<class>.md` (init step 1.1, already shipped).
- No new CLI surface and no registration-time creation behavior.
