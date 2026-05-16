## Context

The orchestrator writes a `feature_sync.yaml` file under `.asdlc_worker/` to persist selected-feature metadata across invocations. One field, `selection_mode`, records how the feature was chosen (e.g. `standalone_local`, `auto_single`, `user_prompt`). During `--resume`, the orchestrator reads this field back and prepends `resume_reuse:` to it, producing values like `resume_reuse:resume_reuse:standalone_local` on repeated resumes. This recursive prefix accumulation is accidental, serves no routing or validation purpose, and causes the runtime branch to appear dirty for metadata-only reasons. No downstream code uses `selection_mode` to make decisions; it appears only in a log line.

## Goals / Non-Goals

**Goals:**
- Remove `selection_mode` from the `feature_sync.yaml` schema: stop writing it and stop reading it in the resume reuse path.
- Eliminate the recursive `resume_reuse:$selection_mode` prefix accumulation.
- Keep the `SELECTED_SELECTION_MODE` variable and log line intact as an internal diagnostic, no longer persisted to disk.
- Update affected tests to not assert on `selection_mode` in the written YAML.

**Non-Goals:**
- Changing how `SELECTED_SELECTION_MODE` is set internally or what values it takes (internal-only concern).
- Altering any other field in `feature_sync.yaml` or the reuse-validation logic.
- Modifying how routing or feature selection decisions are made.

## Decisions

### Remove the field from write; remove the read in resume reuse

`selection_mode` is the only field in `write_feature_sync_metadata()` whose value is derived from a prior read of the same file. Removing it from the write eliminates the feedback loop entirely. The corresponding read in `try_reuse_feature_sync_for_resume()` becomes dead code and is removed. No other callers read `selection_mode` from the file.

**Alternative considered:** Replace `resume_reuse:$selection_mode` with a fixed `resume_reuse` string and keep writing it. Rejected because the field still has no use, still creates unnecessary state churn, and the fixed value would be misleading if the mode before the first resume was something like `auto_single`.

### Retain SELECTED_SELECTION_MODE as internal-only state

The orchestrator log line (`mode=$SELECTED_SELECTION_MODE`) is useful for operator debugging. The variable remains set at all four call sites; it is just no longer flushed to disk.

## Risks / Trade-offs

- Existing `feature_sync.yaml` files on disk may contain a `selection_mode` field. Since we stop reading it, those files will silently carry a stale ignored field until the next write regenerates the file without it. No migration script is needed; the first ordinary resume or fresh run overwrites the file.
- Tests that assert on the presence or value of `selection_mode` in written YAML will fail until updated — this is caught at test time, not silently.

## Migration Plan

1. Remove the `printf "selection_mode: ..."` line from `write_feature_sync_metadata()`.
2. Remove the `selection_mode` local variable declaration and `yaml_get_scalar` call from `try_reuse_feature_sync_for_resume()`.
3. Remove the `if [[ -n "$selection_mode" ]]; then SELECTED_SELECTION_MODE="resume_reuse:$selection_mode"` block; simplify to unconditionally set `SELECTED_SELECTION_MODE="resume_reuse"`.
4. Update `tests/ai_scripts/orchestrator_resume_tests.sh` to remove assertions on `selection_mode`.
5. Update `tests/ai_scripts/orchestrator_assignment_tests.sh` similarly if any assertions reference the field.
6. Update any spec or doc references that describe `selection_mode` as part of `feature_sync.yaml`.

Rollback: revert the four changes above; existing test suite re-covers the old behavior.
