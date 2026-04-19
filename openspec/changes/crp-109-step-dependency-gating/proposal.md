## Why

A worker can be assigned a step that depends on work owned by another worker or team (e.g. a frontend step that requires an OpenAPI contract not yet delivered by the backend team). Without a dependency gate at step-selection time, the worker picks up the step anyway and either blocks mid-execution or produces incorrect output.

## What Changes

- Parse `Depends on:` field from each step block in `implementation_plan.md` during step selection.
- Filter out any assigned step whose `Depends on:` list contains a dep id whose step block is not fully `[x]` (every bullet checked).
- If no assigned step passes the dep filter, exit non-zero with a `blocked by <dep-id>` message — never start a phase run.
- **Fail fast** (plan error, exit non-zero) when a `Depends on:` entry names a step id that does not exist anywhere in the plan.
- **Fail fast** (plan error, exit non-zero) when a referenced dep step block has zero bullets — zero bullets cannot constitute a fully satisfied step.
- `Depends on: none` or a missing `Depends on:` line is treated as no dependencies — the step is always eligible.

## Capabilities

### New Capabilities
- `step-dependency-gating`: Parsing, validation, and satisfaction-checking of `Depends on:` declarations in `implementation_plan.md` step blocks during assigned-step selection, including plan-error detection for unknown dep ids and zero-bullet dep steps.

### Modified Capabilities
- `orchestrator-worker-assigned-step-routing`: Step selection must apply the dep-satisfaction filter before choosing the next step; steps with unsatisfied deps are skipped, and an empty result after filtering exits non-zero with a blocked message.

## Impact

- `orchestrator.sh` (or equivalent step-picker logic) — dep parsing and filter loop added to the step selection path only.
- `implementation_plan.md` format — `Depends on:` field becomes a validated, load-bearing field; plans with unknown dep ids or zero-bullet dep steps are rejected at selection time.
- No changes to `--resume` handling, external APIs, or other phases.
