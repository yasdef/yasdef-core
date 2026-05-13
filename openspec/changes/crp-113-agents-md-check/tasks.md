## 1. Init Worker Guidance Check

- [x] 1.1 Add a small helper in `ai/scripts/init_worker.sh` that checks for root `AGENTS.md` under the current worker repo root.
- [x] 1.2 Resolve the class-specific blueprint path as `<project_repo>/project_stack_blueprint_<worker_class>.md`.
- [x] 1.3 Call the helper after `resolve_single_worker_match` populates `WORKER_CLASS` and before `checkout_or_create_overmind_branch`.
- [x] 1.4 Print the blueprint warning when `AGENTS.md` is missing and the matching blueprint exists.
- [x] 1.5 Print the fallback `AGENTS.md` reminder when `AGENTS.md` is missing and the matching blueprint does not exist.
- [x] 1.6 Keep the check non-blocking and suppress warnings when root `AGENTS.md` exists.

## 2. Tests And Docs

- [x] 2.1 Extend `tests/ai_scripts/init_worker_tests.sh` to prove the warning with blueprint is emitted before switching to `overmind`.
- [x] 2.2 Extend `tests/ai_scripts/init_worker_tests.sh` to prove the fallback warning is emitted when no blueprint exists.
- [x] 2.3 Extend `tests/ai_scripts/init_worker_tests.sh` to prove no warning is emitted when root `AGENTS.md` exists.
- [x] 2.4 Update worker-init documentation if the operator-facing setup flow needs to mention the new advisory warning.
- [x] 2.5 Run `bash tests/ai_scripts/init_worker_tests.sh`.
