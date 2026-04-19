## 1. Extend awk data collection in analyze_feature_plan_for_worker

- [x] 1.1 Add `step_order` indexed array to record step ids in scan order
- [x] 1.2 Parse `#### Depends on:` line per step block into `dep_list[step]` and set `has_dep_line[step]`
- [x] 1.3 Track `bullet_count[step]` (total `- [ ]` + `- [x]` lines) and `unchecked_count[step]` (only `- [ ]`) per step block
- [x] 1.4 Track `assigned_to_worker[step]` when `#### Assigned:` matches target UUID

## 2. Add dep-satisfaction logic in awk END block

- [x] 2.1 In END, iterate `step_order[]`; for each step where `assigned_to_worker[step]` and `unchecked_count[step] > 0`, run dep check
- [x] 2.2 For each dep id in `dep_list[step]` (comma-split, trimmed): if dep id not in `step_order` set → emit plan-error to stderr and `exit 2`
- [x] 2.3 If dep step exists but `bullet_count[dep] == 0` → emit plan-error to stderr and `exit 2`
- [x] 2.4 If dep step has `unchecked_count[dep] > 0` → dep not satisfied; record first blocking dep id, skip this step
- [x] 2.5 If all deps satisfied, set `first_unchecked = step` and break

## 3. Extend output format and caller handling

- [x] 3.1 Change awk `printf` to emit four fields: `assigned_any|requested_match|first_unchecked|blocked_by`
- [x] 3.2 Update all `IFS='|' read -r` call sites in orchestrator.sh to capture the new `blocked_by` field
- [x] 3.3 In the standalone picker: when `first_unchecked` is empty and `blocked_by` is non-empty, `die` with `"blocked by <blocked_by>"`
- [x] 3.4 In the feature picker: same blocked-by exit path as standalone

## 4. Tests

- [x] 4.1 Add test: assigned step with `Depends on: none` is selected normally
- [x] 4.2 Add test: assigned step with missing `Depends on:` line is selected normally
- [x] 4.3 Add test: assigned step with fully-`[x]` dep is selected
- [x] 4.4 Add test: assigned step with unchecked-bullet dep is skipped; next unblocked assigned step is selected instead
- [x] 4.5 Add test: all assigned steps blocked → exit non-zero with `blocked by <dep-id>` in output
- [x] 4.6 Add test: `Depends on:` references non-existent step id → exit non-zero with plan-error message
- [x] 4.7 Add test: `Depends on:` references a step with zero bullets → exit non-zero with plan-error message
- [x] 4.8 Add test: multiple comma-separated deps, all satisfied → step selected
- [x] 4.9 Add test: multiple comma-separated deps, one unsatisfied → step skipped
