## Context

`ai/scripts/orchestrator.sh` currently assumes ASDLC-bound feature routing and artifact mirroring before worker phases run. This is correct for normal operation, but it creates an operational dead-end when ASDLC source paths are temporarily unreachable while valid local runtime files already exist under `overmind/`.

The requested behavior is an explicit operator-controlled fallback, not an implicit automatic one. Default ASDLC-first behavior must remain unchanged.

## Goals / Non-Goals

**Goals:**
- Add an explicit `--standalone` mode to orchestrator that bypasses ASDLC artifact flow and uses local `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` immediately.
- Keep current default orchestration unchanged when `--standalone` is not provided.
- Add explicit logs so operators can see whether standalone mode or ASDLC-backed mode is active.
- Update README with a dedicated workaround section and clear run behavior in section 7.

**Non-Goals:**
- No automatic fallback from default mode to standalone mode.
- No changes to worker binding formats or ASDLC source artifact schema.
- No rename of legacy local runtime filename `reqirements_ears.md` in this change.

## Decisions

1. Add a dedicated CLI flag `--standalone` in orchestrator argument parsing.
Rationale: explicit operator intent avoids hidden mode switches and preserves predictable default behavior.
Alternative considered: auto-fallback to local files when ASDLC read fails. Rejected because it silently changes source-of-truth behavior and can mask real ASDLC sync issues.

2. Split artifact acquisition into two explicit branches.
Rationale: branch-local logic is clearer and safer than mixing conditional checks throughout the current ASDLC flow.
- Default branch: existing ASDLC read/copy/mirror flow.
- Standalone branch: immediate local `overmind/` file usage, skipping ASDLC discovery/validation/mirroring.
Alternative considered: keep one merged path with many inline conditionals. Rejected due to readability and regression risk.

3. Make mode selection and artifact source explicit in logs.
Rationale: troubleshooting routing mistakes requires high-signal logs showing exactly which artifact path family was used.
Alternative considered: only debug-level logs. Rejected because mode ambiguity is operationally significant and should always be visible.

4. Document behavior in README where operators run orchestrator.
Rationale: this is operational behavior, so the runbook needs concise but explicit instructions in both workaround and run sections.
Alternative considered: document only in inline script help. Rejected because operators primarily follow README flow.

## Risks / Trade-offs

- [Risk] Standalone mode can run against stale local `overmind/` artifacts. -> Mitigation: log that remote ASDLC flow is bypassed and keep standalone opt-in only.
- [Risk] Operators may misread mode and assume ASDLC sync occurred. -> Mitigation: add explicit startup log marker and active artifact-path log line.
- [Risk] Missing local standalone inputs can fail late if unchecked. -> Mitigation: fail fast before phase execution when either local file is missing.

## Migration Plan

1. Add `--standalone` parsing and mode variable in `ai/scripts/orchestrator.sh`.
2. Refactor artifact acquisition so standalone mode bypasses ASDLC source flow and directly validates local `overmind/` inputs.
3. Add explicit standalone/default log messages identifying artifact source strategy and paths.
4. Update README with section `5.1` workaround guidance and section `7` behavior note.
5. Extend orchestrator assignment/readme tests to cover standalone routing and logging behavior.

Rollback strategy: remove `--standalone` branch and restore single ASDLC-bound artifact flow; README retains only ASDLC-first run guidance.

## Open Questions

- None. Behavior is explicit: `--standalone` is opt-in local-runtime mode; absence of the flag preserves ASDLC-bound flow.
