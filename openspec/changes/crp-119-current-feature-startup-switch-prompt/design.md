## Context

CRP-118 made a valid current feature sticky: once `feature_sync.yaml` passes reuse validation and the feature has a runnable step, the orchestrator commits to it immediately. This eliminates silent fallthrough to global discovery but removes the operator's ability to intentionally switch features at the start of a run. This change adds an explicit proceed-or-change prompt at startup to restore that intentional-switch path in a visible, deterministic way.

The existing `prompt_for_feature_selection_index` handles interactive multi-feature selection via a numbered list. The new startup prompt is a two-option choice that sits upstream of that picker: either reuse the current feature (fast path, no discovery needed) or trigger the full discovery flow with the current feature pre-placed at the top.

## Goals / Non-Goals

**Goals:**
- Add a two-option startup prompt (`1. Proceed with current feature` / `2. Change feature`) whenever a valid current feature is detected in non-resume, non-standalone mode.
- When the operator chooses `Change feature`, run the normal discovery flow and place the current feature first in the picker, labeled `(CURRENT)`.
- When stdin is not a TTY, skip the prompt and proceed with the current feature (preserves CI/automation determinism).
- Skip the prompt entirely for `--resume` invocations and `--standalone` mode.

**Non-Goals:**
- Prompting during `--resume` runs (resume is an explicit continuation; no ambiguity to resolve).
- Changing the blocked or exhausted fail-fast behavior introduced in CRP-118.
- Adding a `--no-prompt` flag or any other CLI flag changes.

## Decisions

### Prompt lives inside `_try_fast_path_feature_context`, gated on resume mode

The fast path is the only code path where a valid current feature is confirmed. After confirming the feature is valid with a runnable step and `resume_mode` is 0, the prompt fires. If the operator chooses proceed, the function continues as today. If the operator chooses change, the function returns a dedicated exit code (or sets a global flag) so the caller knows to run discovery with the current feature marked.

**Alternative considered:** Add a separate pre-flight function called before `_try_fast_path_feature_context`. Rejected: the prompt needs to run only when the feature is confirmed valid, which is established inside the fast path. Splitting it introduces a second validation pass.

### "Change feature" passes current feature ID to the picker via a module-level variable

When the operator chooses to change, `_try_fast_path_feature_context` sets `CURRENT_FEATURE_SWITCH_FROM_ID` to `$SELECTED_FEATURE_ID` and returns 1. Global discovery proceeds normally but passes this variable to `prompt_for_feature_selection_index`, which uses it to move the matching candidate to index 0 and append `(CURRENT)` to its display name.

**Alternative considered:** Return a distinct exit code (e.g. 2) from the fast path. Rejected: the caller (`ensure_feature_runtime_context`) already treats any non-zero return as "run discovery". Using a variable is simpler and avoids a new exit-code contract between the two functions.

### Non-interactive stdin skips the prompt and proceeds

If `! -t 0`, skip the prompt and treat as "Proceed with current feature". This matches the guard already used in `prompt_for_feature_selection_index` and keeps automated runs deterministic.

### No prompt when there is only one total candidate and it is the current feature

If global discovery would surface only one candidate (which happens to be the current feature), the operator has no meaningful choice. In this case, the "Change feature" path would just reselect the same feature anyway. The prompt is still shown for consistency but the change path immediately auto-selects the single candidate.

## Risks / Trade-offs

- [Risk] Operators running in non-interactive environments with a valid current feature will silently proceed (same as pre-CRP-118 fast-path behavior). → Mitigation: non-interactive behavior is documented; the fast path log line still identifies the selected feature.
- [Risk] Discovery after "Change feature" is chosen may return a candidate list that does not include the current feature (e.g. if it has become stale between the prompt and the discovery scan). → Mitigation: the `(CURRENT)` label is only applied when a matching candidate is found by ID; if not found, the picker shows normally without a `(CURRENT)` entry.

## Migration Plan

1. Add `CURRENT_FEATURE_SWITCH_FROM_ID=""` global variable to orchestrator state globals.
2. In `_try_fast_path_feature_context`, after confirming the feature is valid, runnable, and `resume_mode == 0` and stdin is a TTY: display the two-option prompt and read the operator's choice.
3. If choice is "Proceed": continue as today.
4. If choice is "Change": set `CURRENT_FEATURE_SWITCH_FROM_ID="$SELECTED_FEATURE_ID"`, clear the reuse state variables set by `try_reuse_feature_sync_for_resume`, and return 1.
5. In `prompt_for_feature_selection_index` (or a thin wrapper): if `CURRENT_FEATURE_SWITCH_FROM_ID` is non-empty, find the candidate at that ID, move it to index 0, and append ` (CURRENT)` to its label.
6. Update tests for both prompt paths and for the non-interactive skip.
