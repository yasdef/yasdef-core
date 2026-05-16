## 1. Init script change

- [ ] 1.1 Add `".asdlc_worker/feature_sync.yaml"` as a new entry in the `GENERATED_EXCLUDE_PATHS` array in `ai/scripts/init_asdlc_worker.sh` (alongside the existing file-level exclude for `.asdlc_worker/AI_DEVELOPMENT_PROCESS.md`)

## 2. Test updates

- [ ] 2.1 In `tests/ai_scripts/init_asdlc_worker_tests.sh`, add a test that verifies `.git/info/exclude` contains `.asdlc_worker/feature_sync.yaml` after a fresh install run
- [ ] 2.2 Add a test that verifies the entry is present after an update run on an existing installation
- [ ] 2.3 Add a test that verifies running init multiple times does not duplicate the entry in `.git/info/exclude`

## 3. Documentation

- [ ] 3.1 Update `Readme.md` to note that `.asdlc_worker/feature_sync.yaml` is local runtime state excluded from git tracking by the worker init flow
