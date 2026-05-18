## Context

`init_asdlc_worker.sh` maintains two arrays that drive runtime path handling during installation: `GENERATED_EXCLUDE_PATHS` (paths added to `.git/info/exclude` so git ignores them locally) and `DURABLE_COMMIT_PATHS` (files that get committed to the target repo). The current `GENERATED_EXCLUDE_PATHS` covers generated directories and files like scripts, templates, logs, and `AI_DEVELOPMENT_PROCESS.md`, but does not include `.asdlc_worker/feature_sync.yaml`.

`feature_sync.yaml` is written by the orchestrator at runtime to record the current selected feature. It is analogous in nature to the other excluded paths — local runtime state that should never be committed or considered branch content. Because it is absent from the exclude list, every orchestrator reuse run that writes or updates the file makes the worktree appear dirty. This can block branch switches, trigger unintended stashes, and cause confusion in status checks for reasons entirely unrelated to implementation work.

## Goals / Non-Goals

**Goals:**
- Add `.asdlc_worker/feature_sync.yaml` to `GENERATED_EXCLUDE_PATHS` in `init_asdlc_worker.sh` so the file is added to `.git/info/exclude` during worker init and update runs.
- Update init tests to assert the exclude entry is present after a successful run.
- Update operator docs to note that `feature_sync.yaml` is intentionally excluded from git tracking.

**Non-Goals:**
- Changing any other field in `GENERATED_EXCLUDE_PATHS` or `DURABLE_COMMIT_PATHS`.
- Automatically patching existing worker installations that were set up before this change (operators re-run init or manually add the entry).
- Changing how `feature_sync.yaml` is read, written, or validated by the orchestrator.

## Decisions

### Single array entry in GENERATED_EXCLUDE_PATHS

The path `.asdlc_worker/feature_sync.yaml` is added as a file-level entry, matching the precedent set by `.asdlc_worker/AI_DEVELOPMENT_PROCESS.md` (also a file-level exclude rather than a directory-level one). Directory-level exclusion of `.asdlc_worker` itself is not used because other files in that directory (`asdlc_worker.yaml`, `blocker_log.md`, etc.) are committed as durable state.

**Alternative considered:** Add a wildcard pattern like `.asdlc_worker/*.yaml`. Rejected: it would also suppress `asdlc_worker.yaml` from appearing as untracked if the binding file were somehow missing, obscuring a real problem.

### Existing installations require a manual update or re-run

`ensure_exclude_entries` is idempotent — it only adds entries that are not already present. Re-running `init_asdlc_worker.sh` on an existing installation is safe and will add the new entry without duplicating others. No migration script is needed.

## Risks / Trade-offs

- [Risk] Workers that ran init before this change will continue to see `feature_sync.yaml` as untracked until they re-run init. → Mitigation: acceptable operational gap; re-running init is the documented update path and is safe to run at any time.
- [Risk] If an operator somehow committed `feature_sync.yaml` before this change, the exclude entry will not remove it from tracking (excludes do not affect tracked files). → Mitigation: the file should never have been committed; operators with this situation need to `git rm --cached .asdlc_worker/feature_sync.yaml` manually.

## Migration Plan

1. Add `".asdlc_worker/feature_sync.yaml"` as a new entry in the `GENERATED_EXCLUDE_PATHS` array in `ai/scripts/init_asdlc_worker.sh`.
2. Update `tests/ai_scripts/init_asdlc_worker_tests.sh` to assert that `.git/info/exclude` in the target repo contains `.asdlc_worker/feature_sync.yaml` after a successful init run.
3. Update `Readme.md` to note that `feature_sync.yaml` is runtime state excluded from git tracking.

Rollback: remove the added array entry. Existing exclude entries on installed workers are not rolled back automatically.
