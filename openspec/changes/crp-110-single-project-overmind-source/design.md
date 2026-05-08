## Context

`init_worker.sh` and `orchestrator.sh` were written when overmind was a centralized source repo that hosted multiple projects under `projects/<project-id>/`. The new overmind layout publishes one ASDLC project per repo, and operators point worker tooling directly at that single project repo. Two path-resolution shapes therefore have to change: how `init_worker` discovers `workers.yaml` and `project_id`, and how `orchestrator` resolves `BOUND_PROJECT_PATH` for feature enumeration.

The binding file `ai/project_overmind.yaml` and the field `overmind_source_path` are kept (operator confirmed) — only their semantics shift from "parent of many projects" to "single project repo". `--standalone` already uses local runtime files and is intentionally untouched.

## Goals / Non-Goals

**Goals:**
- Resolve `BOUND_PROJECT_PATH` as `overmind_source_path` directly, with no `projects/<id>/` or `<id>/` fallback.
- Read `project_id` from `<project_repo>/init_progress_definition.yaml` `meta_info.project_id` during init.
- Validate at orchestrator startup that the bound `project_id` matches `init_progress_definition.yaml.meta_info.project_id` to detect rebinding drift.
- Skip `.git` and non-feature subdirectories during feature enumeration to tolerate the project repo being a real git working tree.
- Keep field names, file names, and capability names stable so artifacts and skills remain readable.

**Non-Goals:**
- No backward compatibility with the multi-project `<source>/projects/<id>/` layout.
- No rename of `ai/project_overmind.yaml`, `overmind_source_path`, `bound_project_path`, or any field in `ai/feature_sync.yaml`.
- No changes to `--standalone` behavior, phase scripts, or capability/skill names.
- No new operator flags.

## Decisions

1. Source `project_id` from `<project_repo>/init_progress_definition.yaml` `meta_info.project_id`.
   Rationale: that file already exists in ASDLC project repos as the bootstrap progress definition (`overmind-bootstrap-progress-checklist`), so reusing it avoids inventing a new contract file. The path is no longer a reliable carrier of `project_id` once the `projects/<id>/` wrapper is gone.
   Alternatives considered:
   - Top-level `project_id:` scalar in `workers.yaml` — rejected because `workers.yaml` is a registry, not a project descriptor.
   - Basename of the project repo directory — rejected because directory names are operator-controlled clones and cannot be trusted for identity.
   - Operator-entered during init — rejected because it allows binding drift between local and overmind state.

2. Keep `overmind_source_path` field name; change semantics only.
   Rationale: operator explicitly requested no field rename. Stable schema avoids breaking `ai/feature_sync.yaml` consumers and keeps existing logs readable. Semantics shift is documented in README.
   Alternative considered: rename to `project_repo_path`. Rejected per operator decision.

3. Add an `init_progress_definition.yaml` cross-check at orchestrator startup.
   Rationale: with the path simplification, the only way to detect a stale `project_id` in `ai/project_overmind.yaml` (e.g., operator pointed at the wrong repo) is to compare it against an authoritative value inside the project repo. Failing fast on mismatch protects against silently mirroring the wrong feature's artifacts.
   Alternative considered: skip the check and trust the binding. Rejected because the cost is one small YAML read and the failure mode (mirroring wrong project) is hard to debug after the fact.

4. Skip `.git` and subdirectories without `implementation_plan.md` during feature enumeration.
   Rationale: the project repo will commonly be a git working tree, so `.git` would otherwise appear as a feature candidate; non-feature subdirectories (docs, tooling, drafts) must not poison the candidate set.
   Alternative considered: rely on the existing `[[ -f "$plan_path" ]] || continue` filter alone. Acceptable but less defensive — adding an explicit `.git` skip makes the rule self-evident in code review.

5. Hard cut. No legacy fallback to `<source>/projects/<id>/` or `<source>/<id>/`.
   Rationale: pre-alpha repository, operator explicitly chose hard cut, and a fallback path would mask new-format misconfiguration silently. Re-running `init_worker.sh` is the documented migration step.
   Alternative considered: read both layouts during a transition. Rejected for the reasons above.

## Risks / Trade-offs

- [Risk] Existing workers will fail until they re-run `init_worker.sh` against the new project repo path. → Mitigation: README step `4` updated; orchestrator fail-fast message names the binding file and instructs the operator to re-run `init_worker.sh`.
- [Risk] `init_progress_definition.yaml` schema is owned by overmind and could shift the location of `meta_info.project_id`. → Mitigation: scan strictly for `meta_info:` key, then nested `project_id:` scalar; fail fast with a clear "expected meta_info.project_id" message so a schema change surfaces immediately.
- [Risk] Operators may point `overmind_source_path` at a parent directory by habit. → Mitigation: orchestrator fails fast on missing root `workers.yaml` and missing `init_progress_definition.yaml`, both of which are absent at the parent level.
- [Risk] Tests under `crp-068/` use the old layout in fixtures. → Mitigation: only the fixture is rebuilt; the contract under test (`overmind-feature-path-override`) is unchanged.

## Migration Plan

1. Land `init_worker.sh` rewrite for single-project source (workers.yaml at root + `init_progress_definition.yaml` for `project_id`).
2. Land `orchestrator.sh` resolution change (`BOUND_PROJECT_PATH = overmind_source_path`) and `init_progress_definition.yaml` cross-check.
3. Update `Readme.md` and rebuild test fixtures.
4. Operators re-run `bash ai/scripts/init_worker.sh` against the new project repo path. Their existing `ai/feature_sync.yaml` is regenerated on the next default-mode orchestrator run.

Rollback strategy: revert the script changes; restore the multi-project `find` and the `<source>/projects/<id>/` fallback resolution; revert README and fixture updates. No data migration required because the binding-file schema is unchanged.

## Open Questions

- None. Operator confirmed: keep field names, single project repo only, ignore `.git`, no backward compatibility, `--standalone` untouched, capability/skill names not renamed.
