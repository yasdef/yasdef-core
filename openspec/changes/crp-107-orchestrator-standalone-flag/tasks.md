## 1. Add standalone mode branch in orchestrator

- [x] 1.1 Update `ai/scripts/orchestrator.sh` argument parsing to accept `--standalone` and persist mode state for downstream routing.
- [x] 1.2 Refactor artifact acquisition so default mode keeps existing ASDLC project/feature read-copy flow while standalone mode skips ASDLC discovery/validation/mirroring.
- [x] 1.3 In standalone mode, fail fast before phase execution when local `overmind/implementation_plan.md` or `overmind/reqirements_ears.md` is missing.
- [x] 1.4 Ensure default mode behavior is unchanged when `--standalone` is not provided.

## 2. Add explicit operator logging and docs

- [x] 2.1 Add explicit startup log messages for standalone mode that state remote ASDLC artifact flow is bypassed and print active local runtime artifact paths.
- [x] 2.2 Add explicit default-mode log message clarifying ASDLC read/copy flow is active.
- [x] 2.3 Update `Readme.md` with a new `5.1` standalone workaround section describing when to use it and trade-offs.
- [x] 2.4 Update `Readme.md` section `7. Run the orchestrator` with a concise note that default runs try ASDLC read/copy first and `--standalone` immediately uses local `/overmind` artifacts.

## 3. Cover behavior with tests and status verification

- [x] 3.1 Extend `tests/ai_scripts/orchestrator_assignment_tests.sh` (or dedicated orchestrator tests) for standalone routing from local `overmind/implementation_plan.md`.
- [x] 3.2 Add test coverage for standalone fail-fast when local `overmind/implementation_plan.md` or `overmind/reqirements_ears.md` is missing.
- [x] 3.3 Add test coverage for explicit standalone logging and unchanged default-mode routing behavior.
- [x] 3.4 Run relevant `tests/ai_scripts/` orchestrator suites from repository root and confirm `openspec status --change crp-107-orchestrator-standalone-flag` is apply-ready.
