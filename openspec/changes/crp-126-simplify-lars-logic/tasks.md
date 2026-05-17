## 1. Remove planning-phase fetch rule from ai_plan.sh

- [x] 1.1 Delete the `printf 'Fetch rule (planning): ...'` line (line 692) from the `if [[ -n "$DESIGN_LAR_SECTION" ]]; then` block in `ai/scripts/ai_plan.sh`
- [x] 1.2 Verify the surrounding block still emits the `sync_step_lars.sh` invocation instruction (line 691) and the context-pack LAR section (lines 728–733) unchanged

## 2. Update AI_DEVELOPMENT_PROCESS.md

- [x] 2.1 In `ai/AI_DEVELOPMENT_PROCESS.md` line 106, remove the `; also fetch each in-scope LAR locator using available web/MCP tooling...` clause and everything after it on that bullet, leaving only the `sync_step_lars.sh` mirroring instruction

## 3. Verify tests pass

- [x] 3.1 Run `tests/ai_scripts/sync_step_lars_tests.sh` and confirm all tests pass
- [x] 3.2 Run `tests/ai_scripts/ai_plan_lar_tests.sh` and confirm all tests pass (update any test that asserts the fetch rule is present in planning output)
