## Context

After crp-123 lands, `ai/scripts/orchestrator.sh` will contain:

- `try_reuse_feature_meta_sync_for_resume()` — reads `.asdlc_worker/feature_meta_sync.yaml` (4 fields: `project_id`, `worker_uuid`, `feature_id`, `selected_step`), validates `project_id`/`worker_uuid` against the binding, derives plan/ears paths under `<BOUND_PROJECT_PATH>/<feature_id>/`, and validates those exist. Returns 0 on success, 1 on any validation failure.
- `_try_fast_path_feature_context()` — wraps the reuse function. On success it then calls `analyze_feature_plan_for_worker` to set `SELECTED_STEP` if not already set. The function returns 1 either when reuse validation fails OR when reuse succeeded but no runnable step was found. Both routes fall through to slow-path discovery in `ensure_feature_runtime_context()`.

The same conflation of "stale-context" and "valid-but-unrunnable" outcomes that crp-118 identified on the pre-crp-123 code still exists in the post-crp-123 code — the function names and field schemas changed, but the decision logic did not.

`analyze_feature_plan_for_worker` returns a pipe-delimited tuple `assigned_any|requested_match|first_unchecked|blocked_by`. The post-success path in `_try_fast_path_feature_context` currently captures these into `_fa`, `_ri`, `_fu`, `_bb` and returns 1 if `_fu` is empty, irrespective of whether `_bb` (blocking step) or `_fa` (assignment count) carry useful signal.

## Goals / Non-Goals

**Goals:**
- Make a successfully validated `feature_meta_sync.yaml` sticky on the post-crp-123 codebase.
- Distinguish three fast-path outcomes:
  1. Reuse validation failed (stale/invalid metadata) → fall through to slow-path discovery (unchanged from crp-123).
  2. Reuse validation succeeded but `_fu` is empty and `_bb` is non-empty (blocked) → fail fast with a blocker message.
  3. Reuse validation succeeded but `_fu` is empty and `_bb` is empty and `_fa >= 1` (exhausted) → offer an interactive prompt letting the operator delete `feature_meta_sync.yaml` automatically or dismiss to handle it manually.
- In non-interactive mode (stdin not a TTY), replace the exhausted prompt with a die message plus manual-removal instruction, preserving CI/automation determinism.
- Apply the same semantics on `--resume` and on ordinary startup. Both call `_try_fast_path_feature_context`.
- Reference `.asdlc_worker/feature_meta_sync.yaml` in all messages and docs.

**Non-Goals:**
- Changing the reuse validation logic itself. The 5 validation steps from crp-123 (file present, identity match, derived paths exist, ears non-empty, requested step still assigned) are not in scope.
- Changing slow-path discovery behavior when reuse validation legitimately fails.
- Altering `--standalone` mode. Standalone does not write `feature_meta_sync.yaml` and is unaffected.

## Decisions

### 1. Split decision lives in `_try_fast_path_feature_context`, not the reuse function

The reuse function's job is binary: do the identity and path validations succeed? The "is there work to do" question is downstream and depends on plan analysis. Keeping the split where it is mirrors crp-118's original decision and matches crp-123's clean separation of "metadata is consistent" vs "plan has runnable bullets."

**Alternative considered:** Add a third return code from `try_reuse_feature_meta_sync_for_resume` to signal "valid but unrunnable." Rejected — callers would have to handle three codes, the reuse function would conflate two concerns, and adding a new code touches the same call sites where the new branching would live anyway.

### 2. Inspect `_fa`, `_bb`, `_fu` from `analyze_feature_plan_for_worker`

The function already returns these. The fix is to stop returning 1 from `_try_fast_path_feature_context` when `_fu` is empty and instead call `die` with the right message based on `_bb` and `_fa`:

| `_fu` | `_bb` | `_fa` | Action |
|---|---|---|---|
| non-empty | — | — | proceed (set `SELECTED_STEP=$_fu`) |
| empty | non-empty | — | `die "blocked: feature '$SELECTED_FEATURE_ID' is gated by step '$_bb'"` |
| empty | empty | ≥ 1 | print exhaustion message → if interactive: `_prompt_exhausted_feature_cleanup`; else `die` with manual-removal instruction |
| empty | empty | 0 | `die "unrunnable: feature '$SELECTED_FEATURE_ID' has no assigned bullets for this worker. Remove .asdlc_worker/feature_meta_sync.yaml to reselect."` (should not happen for a feature that passed reuse validation, but treat defensively) |

### 3. Exhausted case uses an interactive cleanup prompt, not a die

Rather than dying with a manual-removal instruction, the exhausted case offers a two-option prompt via a new helper `_prompt_exhausted_feature_cleanup`:

```
Feature '<id>' is exhausted — all assigned bullets are complete.
To start a new feature, .asdlc_worker/feature_meta_sync.yaml must be removed.

  1. Yes, delete it for me
  2. Dismissed, I'll do it myself
```

- **Choice 1**: `rm .asdlc_worker/feature_meta_sync.yaml`, print `"feature_meta_sync.yaml deleted. Re-run orchestrator to select a new feature."`, exit 0.
- **Choice 2**: print `"Remove .asdlc_worker/feature_meta_sync.yaml when ready, then re-run orchestrator."`, exit 0.

Both branches exit 0 — exhaustion is expected/normal, not an error.

**Non-interactive fallback** (stdin not a TTY): skip the prompt and `die` with the exhaustion message plus the manual-removal instruction. This preserves CI/automation determinism without requiring TTY detection in any other code path.

**Alternative considered:** always die with a message and let the operator manage the file manually. Rejected — operators naturally expect a "yes, clean up for me" affordance after a completed feature; the manual-removal path is still available via choice 2 or non-interactive mode.

### 5. Requested-step path is unchanged

When `--resume <step>` is supplied, `try_reuse_feature_meta_sync_for_resume` validates that the step is still assigned to this worker (per crp-123). On success `SELECTED_STEP` is already set, so the post-success plan-analysis branch above is not entered. The sticky check applies only to the "no requested step, find first unchecked" case — which matches the ordinary auto-advance flow.

If validation fails because the requested step is no longer assigned to this worker (crp-123 scenario), the function returns 1 and the existing fall-through to discovery occurs. That is the correct behavior because the operator-requested step is genuinely not workable in this feature; discovery may find another feature where it is, and if not, slow-path discovery fails with its own clear error.

### 6. Message format

All messages should:
- Name the current feature ID (`$SELECTED_FEATURE_ID`).
- For blocked: name the blocking step (`$_bb`).
- For exhausted prompt header and non-interactive exhausted die: point at `.asdlc_worker/feature_meta_sync.yaml` as the file to remove to allow reselection.

### 7. Resume path coverage is implicit

Because `ensure_feature_runtime_context` calls `_try_fast_path_feature_context` for both `resume_mode=0` and `resume_mode=1`, the same blocked/exhausted handling applies to both. No separate code path needed.

## Risks / Trade-offs

- **Risk:** Operators who relied on the silent fallback (e.g. an implicit "switch to a fresh feature when current one is done" workflow) will now see the exhausted prompt instead of auto-selection. → Mitigation: the prompt offers a one-keypress cleanup path; the behavior is more deterministic and matches the operator's mental model that "if I selected this feature, I am still on it."
- **Risk:** A feature whose plan was edited externally (e.g. an upstream step un-checked between runs) could now be "blocked" where it was previously running. → Acceptable: this is the correct fail-fast surface for that state change; today's silent switch hides it.
- **Trade-off:** Exhausted case is interactive while blocked case is a hard die. Acceptable — exhausted is a normal completion state requiring a deliberate next-feature selection; blocked is an actionable error requiring upstream work, not a choice.

## Migration Plan

1. After crp-123 is merged and the renamed function is in place, edit `_try_fast_path_feature_context` in `ai/scripts/orchestrator.sh`:
   a. After `try_reuse_feature_meta_sync_for_resume` returns 0 and `SELECTED_STEP` is empty, call `analyze_feature_plan_for_worker "$SELECTED_SOURCE_PLAN_PATH" "$BINDING_WORKER_UUID" ""` and capture `_fa`, `_ri`, `_fu`, `_bb`.
   b. If `_fu` non-empty → `SELECTED_STEP="$_fu"`, proceed as today.
   c. If `_fu` empty and `_bb` non-empty → `die` with blocked message.
   d. If `_fu` empty and `_bb` empty and `_fa >= 1` → print exhaustion header; if stdin is a TTY call `_prompt_exhausted_feature_cleanup`, else `die` with manual-removal instruction.
2. Implement `_prompt_exhausted_feature_cleanup` as a standalone helper:
   - Print the two-option menu.
   - Read operator choice; on `1` delete `.asdlc_worker/feature_meta_sync.yaml`, print deletion confirmation, exit 0; on `2` print dismissal reminder, exit 0.
3. Update existing tests that expected silent fallthrough to slow-path discovery on valid-but-unrunnable; either change expectation to the new surface or remove them as superseded.
4. Add tests for: blocked die, exhausted interactive prompt (choice 1 and choice 2), exhausted non-interactive die — on both `--resume` and non-`--resume` startup flows.
5. Update `Readme.md` if it describes silent rediscovery as a feature.

**Rollback:** revert the four edit lines in `_try_fast_path_feature_context`. Discovery resumes for valid-but-unrunnable cases. No data migration needed; `feature_meta_sync.yaml` itself is unchanged.

## Open Questions

- **Q1:** ~~Should the exhausted-feature message also suggest the `--standalone` escape hatch?~~ Resolved: no. The prompt's choice 1 (auto-delete) and choice 2 (manual) cover the full operator surface; `--standalone` is a different setup mode and not a reselection shortcut.
- **Q2:** If a worker has multiple features assigned via `feature_meta_sync.yaml` history (rare), does the exhausted prompt need to enumerate alternatives? Preference: no. The metadata file is single-feature by design; choice 1 deletes the file and slow-path discovery on the next run enumerates candidates from the bound repo.
