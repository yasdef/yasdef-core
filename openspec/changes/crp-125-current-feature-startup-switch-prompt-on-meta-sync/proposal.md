## Why

Once crp-123 and crp-124 land, the orchestrator's fast path will silently reuse a valid runnable feature pinned via `.asdlc_worker/feature_meta_sync.yaml` and fail fast on blocked/exhausted. The remaining gap is the operator-intent surface: with crp-124 alone, there is no visible affordance to *deliberately* switch features at startup short of removing `feature_meta_sync.yaml` from disk. Operators need an explicit proceed-or-change decision at orchestrator startup whenever a valid current feature is detected.

This change re-states crp-119's intent on top of the crp-123/124 baseline. The mechanism is unchanged in spirit (a two-option prompt), but the detection check, filename references, and call-site naming all need to reflect the new schema and the new fast-path semantics. crp-119 will be closed once this change is filed.

## What Changes

- After the fast path confirms a valid runnable current feature (i.e., `try_reuse_feature_meta_sync_for_resume` returns 0 AND plan analysis returns a non-empty `first_unchecked` so crp-124's fail-fast cases do not apply), in non-resume + non-standalone mode + interactive stdin, prompt the operator with two options:
  - `1. Proceed with current feature`
  - `2. Change feature`
- On choice `1`, proceed with the current feature exactly as today's sticky path does.
- On choice `2`, set a module-level `CURRENT_FEATURE_SWITCH_FROM_ID="$SELECTED_FEATURE_ID"`, clear the reuse-populated `SELECTED_*` state, and return failure from the fast path so the caller runs slow-path discovery.
- In `prompt_for_feature_selection_index`, when `CURRENT_FEATURE_SWITCH_FROM_ID` is non-empty, locate the matching candidate and move it to index 0 with a ` (CURRENT)` suffix on the display label.
- After slow-path discovery completes, write the newly selected feature to `.asdlc_worker/feature_meta_sync.yaml` exactly as crp-123 already specifies (overwriting any previous entry). No explicit deletion step is needed; the write is the source of truth.
- Skip the prompt entirely when:
  - `--resume` is in effect (resume is itself an explicit continuation signal),
  - `--standalone` is in effect (no bound feature concept),
  - stdin is not a TTY (CI/automation determinism — auto-proceed with current feature).
- Skip the prompt entirely when no valid current feature exists (no `feature_meta_sync.yaml`, or reuse validation fails, or crp-124's blocked/exhausted fail-fast applies — those paths never reach the prompt).
- When `Change feature` produces a discovery candidate list with exactly one candidate, the picker auto-selects without prompting (existing behavior).
- When the discovery candidate list does not contain the prior current feature's ID (e.g., it became stale between prompt and discovery), the picker displays normally without a `(CURRENT)` entry.

## Capabilities

### New Capabilities
- `current-feature-startup-switch-prompt`: Orchestrator offers an explicit proceed-or-change decision whenever a valid runnable current feature is pinned via `feature_meta_sync.yaml`, with non-interactive auto-proceed and resume/standalone skip rules.

### Modified Capabilities
- `orchestrator-worker-assigned-step-routing`: Interactive feature selection includes an explicit current-feature handoff path; the picker places the prior current feature first with a `(CURRENT)` label when discovery surfaces it.

## Impact

- Affected runtime script:
  - `ai/scripts/orchestrator.sh` (post-crp-123/124 code): `_try_fast_path_feature_context`, `prompt_for_feature_selection_index`, and the module-level state globals
- Affected tests:
  - `tests/ai_scripts/orchestrator_assignment_tests.sh`
  - `tests/ai_scripts/orchestrator_resume_tests.sh`
- Affected docs/spec references:
  - `Readme.md`
  - operator-facing orchestration flow documentation
- Dependency order:
  - **Must land after crp-123 and crp-124.** This change builds on the renamed function and the sticky/fail-fast semantics.
- Supersedes:
  - **crp-119-current-feature-startup-switch-prompt** — same intent, written against the pre-crp-123 schema and pre-crp-124 sticky semantics. Close crp-119 when this change is filed.
- Combined startup flow after all three changes land:
  1. Read `.asdlc_worker/feature_meta_sync.yaml`; if missing or invalid → slow-path discovery (writes new meta_sync after pick).
  2. Reuse validation passes.
  3. Plan analysis: blocked → fail fast (crp-124); exhausted → fail fast (crp-124).
  4. Plan analysis: runnable → if non-resume + non-standalone + interactive stdin → prompt (crp-125).
     - Proceed → use current feature silently.
     - Change → set `CURRENT_FEATURE_SWITCH_FROM_ID`, return failure, slow-path discovery runs with `(CURRENT)` label, write new meta_sync after pick.
