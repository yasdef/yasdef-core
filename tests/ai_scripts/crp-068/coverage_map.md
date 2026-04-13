# CRP-068 Contract Coverage Map

This folder contains staged-runtime contract tests for BR feature scripts.
The suite validates execution contract and parameter semantics under ASDLC deployment.

## Requirements -> Tests

- Dedicated CR-scoped folder requirement:
  - Satisfied by location of this suite under `tests/ai_scripts/crp-068/`

- Staged-only runtime requirement (`<asdlc>/.commands/...` only):
  - `test_rejects_non_staged_invocation_for_all_feature_scripts`

- Scaffold parameter contract (`feature_br_scaffold.sh` uses `--path` only):
  - `test_scaffold_uses_path_only_and_writes_feature_summary`

- Other script parameter contract (`--feature_path` only):
  - `test_other_scripts_use_feature_path_and_require_feature_summary`

- Feature-folder readiness guard for non-scaffold scripts:
  - `test_other_scripts_use_feature_path_and_require_feature_summary`
  - ensures `feature_br_summary.md` is required under the resolved feature path.

- Coverage limited to affected BR scripts:
  - `feature_br_scaffold.sh`
  - `feature_scan_repo_for_br.sh`
  - `feature_task_to_br.sh`
  - `feature_user_br_clarification.sh`
