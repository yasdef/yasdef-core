## Why

Worker repos can become blocked when ASDLC source paths are temporarily unavailable, even though local worker runtime artifacts already exist in `overmind/`. We need an explicit operator-controlled fallback mode that keeps local execution possible without changing the default source-of-truth behavior.

## What Changes

- Add `--standalone` flag to `ai/scripts/orchestrator.sh`.
- With `--standalone`, orchestrator must skip ASDLC feature discovery, remote source validation, and feature mirroring logic.
- With `--standalone`, orchestrator must immediately use local runtime files:
  - `overmind/implementation_plan.md`
  - `overmind/reqirements_ears.md`
- Keep default behavior unchanged when `--standalone` is not provided (ASDLC-bound project/feature selection remains mandatory).
- Add clear operator-facing logging that standalone mode is active and remote ASDLC artifact flow is bypassed.
- Update `Readme.md`:
  - add **5.1 workaround** explanation for standalone mode and when to use it,
  - add concise note in **7. Run the orchestrator** that `--standalone` forces local-runtime-only behavior.
- **BREAKING**: none by default; behavior changes only under explicit `--standalone`.

## Capabilities

### New Capabilities
- `orchestrator-standalone-mode`: operator can force local-runtime-only orchestrator execution by passing `--standalone`.

### Modified Capabilities
- `orchestrator-worker-assigned-step-routing`: add conditional routing branch where `--standalone` bypasses ASDLC candidate-feature discovery and uses local `overmind/` artifacts directly.
- `overmind-process-artifact-ownership`: clarify that local `overmind/` files remain runtime copies by default, but are treated as direct runtime inputs when standalone mode is explicitly enabled.

## Impact

- Affected code:
  - `ai/scripts/orchestrator.sh`
- Affected docs:
  - `Readme.md` (new 5.1 workaround + update to section 7)
- Affected operator flows:
  - worker execution when ASDLC paths are unreachable
  - explicit temporary local-only execution via `--standalone`
- Affected tests:
  - `tests/ai_scripts/orchestrator_assignment_tests.sh` and/or dedicated orchestrator standalone-mode tests
