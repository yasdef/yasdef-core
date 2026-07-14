## Context

Overmind init step 1.1 writes two project-level artifacts per active class into the ASDLC project folder: `project_stack_blueprint_<class>.md` (planned stack evidence) and `project_agents_md_claude_md_<class>.md` (durable agent operating guidance derived from the blueprint). The worker binds to that project folder via `.asdlc_worker/project_overmind.yaml` (`overmind_source_path`, `class`, `worker_uuid`) and selects features at `overmind_source_path/<feature_id>/`.

During the design phase, the `yasdef-worker-design` skill decides whether the assigned step is a first-feature bootstrap (initial runnable scaffold for the class). For stack guidance it runs the in-skill helper `find_blueprints.py` (introduced by `crp-139-move-blueprint-helper-into-design-skill`), which globs `project_stack_blueprint_*.md` in the feature directory's parent and filters by class. Two gaps:

1. The agents-guidance artifact is invisible to the worker — nothing discovers it, and no rule offers to instantiate project-root `AGENTS.md`/`CLAUDE.md` during scaffold creation.
2. Class resolution reads `<feature_dir_parent>/.asdlc_worker/project_overmind.yaml`. In the bound layout, feature dirs live in the overmind project folder while the binding file lives in the worker repo root, so the class always resolves as unresolved and the class filter is dead code.

## Goals / Non-Goals

**Goals:**
- First-feature bootstrap checks whether both project-root `AGENTS.md` and `CLAUDE.md` are present.
- When either is absent, the user gets one informed, all-or-nothing choice: regenerate and overwrite both with identical class-matching knowledgebase content, or leave the repository unchanged.
- Accepted regeneration is materialized before the scaffold implementation model starts.
- The discovery helper reports blueprint and agents-guidance candidates in one run, class-filtered correctly in the bound layout.
- Preserve the helper's existing output contract for blueprints (labels, ordering, exit codes) so existing tests change minimally.

**Non-Goals:**
- No change to `register_worker.py` warning behavior (explicitly rejected).
- No change to overmind-side artifact generation or gating.
- No `AGENTS.md`/`CLAUDE.md` maintenance obligation for non-bootstrap features; this is a scaffold-time creation contract only.
- No inspection or modification of global guidance files.
- No content-quality, placeholder, merge, or per-file preservation workflow.
- No new CLI surface.

## Decisions

### D1: Binding file resolved by walking up from the script's installed location

The skill bundle is installed inside the worker repo (`.claude/skills/`, `.codex/skills/`, `.github/skills/`, `.agents/skills/`). The helper resolves the worker repo root by walking up from `Path(__file__).resolve()` until a directory containing `.asdlc_worker/project_overmind.yaml` is found, and reads `class` from that file.

This relies on the supported `yasdef init` contract: skill files are copied from package resources into the target worker repo, and the installer rejects symlinked package data and symlinked destinations. Editable/local installation changes where the `yasdef` Python tool reads package resources from, but `yasdef init` still writes real skill files into the worker repo. Manually symlink-installing a skill bundle is outside the supported installation contract; because `Path.resolve()` follows that link, such a manual layout may fall back to unresolved class rather than being treated as a valid worker installation.

- Why not keep `<feature_dir_parent>/.asdlc_worker/`: provably wrong in the bound layout (binding lives in the worker repo, features live in the overmind project folder).
- Why not walk up from `cwd`: the skill instructs running the helper "from the ASDLC feature folder context", which is inside the overmind project folder — cwd walk-up would miss the worker repo entirely.
- Why not an env var or CLI arg: AGENTS.md working rules forbid new script CLI flags without explicit request; an env var adds an invocation contract the model can get wrong. `__file__` is deterministic for an installed skill.
- Why keep `Path.resolve()` rather than preserve a lexical symlink path: supported installs contain real copied files, while resolving the physical script location avoids treating an arbitrary manually linked path as an installed worker skill.
- Fallback: if no binding file is found by walk-up, keep today's behavior — report `Raw project class: unresolved`, list all candidates, exit 0.

### D2: Agents-guidance discovery mirrors blueprint discovery in the same helper run

The helper additionally globs `project_agents_md_claude_md_*.md` (non-recursive, lexically sorted) in the same project-level search root and partitions with the same class-substring rules (`back|backend` / `front|frontend|web` / `mobile|ios|android`). Output is a new labeled block after the blueprint blocks: `All agents guidance candidates:`, per-class relevant/irrelevant lists, and a final `Relevant agents guidance result:` summary line.

- Why one helper, not a second script: the two artifacts are co-located, share the search root and class filter, and are consumed by the same Bootstrap Decision; a second script duplicates resolution logic and doubles the invocation surface in SKILL.md.
- Overmind class tokens (`backend`/`frontend`/`mobile`) all contain the worker substrings (`back`/`front`/`mobile`), so the existing matcher covers the new filenames without new mapping rules.
- Exit-code contract unchanged: 0 on all successful paths; non-zero only when the feature directory cannot be resolved.

### D3: Project-root existence is the only local-state gate

For bootstrap-required work, inspect only `<worker-root>/AGENTS.md` and `<worker-root>/CLAUDE.md`.

- When both paths are present, do nothing and do not prompt. Their content may be complete guidance, placeholders, or links; this change deliberately does not judge content quality.
- When either path is absent, the repository needs a reconciliation decision.
- When either path is a directory, report it as invalid and block reconciliation until the user removes, renames, or otherwise resolves that directory. A directory is neither present guidance nor an absent path, and the worker does not delete or replace it automatically.
- Global or user-home guidance is ambient tool configuration, not portable project state. It is neither discovered nor counted as satisfying the project-root gate.

This deliberately favors a small, predictable interaction over content heuristics.

### D4: Reconciliation is one binary, all-or-nothing decision

When either project-root file is absent and exactly one class-matching `project_agents_md_claude_md_<class>.md` is available, ask one question that reports each local file as present or absent and explains the consequences:

1. `Yes, regenerate both files` — first back up each existing project-root path, then replace both paths with regular files containing the exact same knowledgebase bytes. Any existing `AGENTS.md` or `CLAUDE.md` is overwritten after backup; local symlinks are preserved as symlinks in the backup and replaced at the root rather than followed.
2. `No, leave the repository unchanged` — write neither file and preserve all existing local state.

There is no per-file choice, merge mode, or "create the missing file only" behavior. The prompt must say `regenerate`/`overwrite`, not merely `create`, whenever one file already exists. If the class is unresolved or no unique matching guidance artifact exists, the model asks for guidance direction instead of offering regeneration from invented or ambiguous content.

The standard two-choice prompt is offered only when both local states are valid (`present` or `absent`). If either state is `invalid-directory`, the model asks the user to resolve that filesystem conflict and rerun the check; it does not record a reconciliation disposition or attempt materialization while the invalid state remains.

### D5: The design artifact records the decision; materialization occurs before scaffold implementation

The helper remains read-only and reports discovery plus local file state. `SKILL.md` owns the user interaction and requires `## First-Feature Bootstrap` to record one of three dispositions:

- `both-present-no-action`
- `regenerate-both-approved`
- `leave-unchanged-declined`

An accepted regeneration is materialized after the design decision is complete and before the scaffold implementation model is launched. The materializer revalidates the source artifact, replaces both local paths without following symlinks, writes identical bytes, and verifies both outputs. A declined or both-present disposition performs no write. This timing ensures the scaffold implementation session can load the generated project guidance at startup.

Materialization also revalidates both destination types. If a directory appears at either path after approval, the operation fails before changing either destination and reports that the directory must be resolved explicitly.

When at least one project-root guidance path exists, materialization first creates one collision-resistant operation directory under `<worker-root>/.asdlc_worker/agent_guidance_backups/`. Every existing root guidance path is moved or copied into that directory under its original basename without following symlinks. If backup creation or verification fails, materialization aborts before either root path is replaced. On success, the backup is retained and its location is reported to the user. The backup root is local runtime data and is added to the worker repo's git exclude entries. When both root paths are absent, no backup directory or exclude entry is needed.

## Risks / Trade-offs

- [Skill bundle copied outside a worker repo (e.g., tests, manual runs) → walk-up finds no binding] → Fallback path keeps the helper functional: class unresolved, all candidates listed, exit 0; tests exercise this path explicitly.
- [Operator manually symlinks a skill bundle into a worker repo] → This is outside the `yasdef init` installation contract; `Path.resolve()` may walk from the source checkout and report unresolved binding/class. Documentation directs development installs through `yasdef init`, which always copies the skill files.
- [Existing overmind projects created before agents-md support have blueprints but no guidance artifact] → The `Relevant agents guidance result:` line reports none found; SKILL.md routes to asking the user rather than skipping silently or inventing content.
- [One existing local file contains important uncommitted content] → The prompt explicitly states that approval backs up and overwrites both files; the materializer retains the original path under `.asdlc_worker/agent_guidance_backups/`, while declining preserves the repository byte-for-byte.
- [A local path is a symlink] → Approved regeneration replaces the link itself and never follows it to overwrite an external or global target.
- [A local path is a directory] → The state is invalid; readiness remains blocked and materialization performs no writes until the user resolves the directory.
- [Backup creation fails or collides] → Materialization aborts before changing either project-root path and reports the failure; operation ids are collision-resistant and existing backup directories are never reused or overwritten.
- [Process fails while writing the pair] → Materialization uses temporary files and rollback/cleanup so it does not report success unless both final files exist and are byte-identical.
- [crp-139 not yet archived; this change modifies its pending spec] → Sequencing constraint noted in proposal: crp-141 applies on top of crp-139's helper; if crp-139 shifts, the delta spec here must be rebased.

## Migration Plan

Single-commit change to skill bundle files, design phase/application integration, and tests; no runtime data migration. Already-scaffolded worker repos are unaffected (bootstrap contract only fires when no meaningful implementation exists). Rollback is reverting the commit.

## Open Questions

- None blocking. Approved regeneration copies the selected knowledgebase artifact verbatim to both files; adaptation and merging are out of scope.
