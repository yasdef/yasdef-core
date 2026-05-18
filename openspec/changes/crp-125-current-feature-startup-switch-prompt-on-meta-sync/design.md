## Context

After crp-123 and crp-124 land, `_try_fast_path_feature_context` in `ai/scripts/orchestrator.sh` will:

1. Call `try_reuse_feature_meta_sync_for_resume` to validate the 4-field `feature_meta_sync.yaml` and derive bound-source paths.
2. On reuse success, call `analyze_feature_plan_for_worker` to compute `_fa`, `_ri`, `_fu`, `_bb`.
3. Per crp-124: if `_fu` is empty, `die` with blocked (when `_bb` non-empty) or exhausted (when `_bb` empty) message.
4. If `_fu` non-empty: set `SELECTED_STEP="$_fu"` and proceed silently — *this is the point crp-125 modifies*.

The remaining behavior gap is at step 4: the silent reuse of a valid runnable feature gives the operator no startup affordance to switch contexts. crp-125 inserts a two-option prompt at exactly that point, gated by mode and TTY state.

`prompt_for_feature_selection_index` is the existing interactive multi-candidate picker used by slow-path discovery; it returns the chosen index back to `ensure_feature_runtime_context`. crp-125 extends it to support placing a designated candidate first with a `(CURRENT)` label when a module-level signal variable is set.

## Goals / Non-Goals

**Goals:**
- Add the two-option startup prompt when a valid runnable current feature is detected in non-resume, non-standalone, interactive mode.
- On `Change feature`, route control to slow-path discovery with the prior current feature pre-placed at index 0 of the picker, labeled `(CURRENT)`.
- Skip the prompt cleanly in `--resume`, `--standalone`, and non-interactive contexts (auto-proceed in those cases).
- Compose cleanly with crp-124's sticky/fail-fast semantics: the prompt only fires *after* crp-124's blocked/exhausted gates have not tripped.
- Reference `feature_meta_sync.yaml` consistently in messages, docs, and tests.

**Non-Goals:**
- Prompting during `--resume` runs. Resume is an explicit continuation signal; adding a confirmation step would degrade the experience without information gain.
- Adding a `--no-prompt` or `--force-prompt` CLI flag. The TTY heuristic plus mode flags are sufficient.
- Adding a separate "clear current feature" command. Operators who want to forcibly reset can `rm .asdlc_worker/feature_meta_sync.yaml`; the prompt removes the need for that workflow in normal use.
- Changing crp-124's fail-fast semantics. Blocked/exhausted features still die; the prompt never sees them.
- Changing how `feature_meta_sync.yaml` is written after a new selection. The slow-path discovery already overwrites it (crp-123 contract).

## Decisions

### 1. Prompt lives inside `_try_fast_path_feature_context`, after the post-success plan analysis

The fast path is the only place where "valid current feature with runnable step" is established. Splitting the prompt into a separate pre-flight function would require duplicating reuse validation. Keep it inline immediately after the `_fu` non-empty branch that crp-124 leaves unmodified.

Specifically, after `SELECTED_STEP="$_fu"` is set, before returning 0, run the prompt gate:

```
if [[ "$resume_mode" -eq 0 && "$STANDALONE_MODE" -ne 1 && -t 0 ]]; then
  # display prompt, read choice
fi
```

**Alternative considered:** Add a wrapper around `_try_fast_path_feature_context` in `ensure_feature_runtime_context`. Rejected — that wrapper would have to redo reuse validation to know whether the prompt applies, doubling the work.

### 2. "Change feature" signaling via `CURRENT_FEATURE_SWITCH_FROM_ID`

When the operator picks `Change feature`, set `CURRENT_FEATURE_SWITCH_FROM_ID="$SELECTED_FEATURE_ID"`, reset reuse-populated state variables (`SELECTED_FEATURE_ID`, `SELECTED_FEATURE_PATH`, `SELECTED_STEP`, `IMPLEMENTATION_PLAN_FILE`), and return 1 from `_try_fast_path_feature_context`. The existing caller treats any non-zero return as "run slow-path discovery," so no new exit-code contract is needed.

**Alternative considered:** Return a distinct exit code (e.g., 2) to indicate "change requested." Rejected — adds new contract surface; a global signal variable is simpler and matches existing patterns in the file (e.g., `FEATURE_CONTEXT_READY`).

### 3. Picker relabeling

In `prompt_for_feature_selection_index`, before building the display list, check `CURRENT_FEATURE_SWITCH_FROM_ID`. If non-empty, scan the candidate ID array for a match; if found, reorder so the match sits at index 0 and append ` (CURRENT)` to its displayed name. The returned index from the picker is in the reordered list; the caller (`ensure_feature_runtime_context`) must re-map it to the original `candidate_*` arrays.

**Alternative considered:** Have the caller reorder candidate arrays before calling the picker. Rejected — the picker is the closest function to display concerns; the reorder logic belongs there.

### 4. Non-interactive auto-proceed

If `! -t 0`, skip the prompt and treat as `Proceed`. This is consistent with `prompt_for_feature_selection_index`'s existing TTY guard and keeps CI/automation runs deterministic. Document the behavior in the spec scenario so operators running unattended understand why no prompt appears.

**Alternative considered:** Fail fast in non-interactive mode when a prompt would otherwise appear. Rejected — that would break automation that relies on sticky reuse, with no operator benefit.

### 5. Auto-select on single discovery candidate

If the operator picks `Change feature` and slow-path discovery surfaces only one candidate, the picker auto-selects it without prompting (existing behavior of `prompt_for_feature_selection_index`). The `(CURRENT)` relabel happens but no choice is required. This matches the principle: prompt only when there is a real choice.

### 6. Stale current ID after Change

If discovery returns a candidate list that does not include the prior current feature ID, the picker displays normally with no `(CURRENT)` entry. The operator picks freely. `CURRENT_FEATURE_SWITCH_FROM_ID` is cleared after the picker returns (or on next orchestrator startup) so it does not leak across runs.

### 7. Composition with crp-124

The prompt sits strictly after crp-124's `_fu`-empty fail-fast branches. The combined fast-path flow is:

```
try_reuse_feature_meta_sync_for_resume → success
  analyze_feature_plan_for_worker → _fa,_ri,_fu,_bb
    if _fu non-empty:
      SELECTED_STEP=$_fu
      if resume_mode==0 && !STANDALONE_MODE && -t 0:
        prompt
        if "Change" → set CURRENT_FEATURE_SWITCH_FROM_ID, return 1
      return 0
    elif _bb non-empty:
      die blocked   # crp-124
    else:
      die exhausted # crp-124
```

This composition is explicit in both the design and the spec scenarios so reviewers see no contradiction with crp-124.

### 8. `feature_meta_sync.yaml` rewrite after Change

After slow-path discovery completes following a `Change feature` choice, `write_feature_meta_sync_metadata` (from crp-123) overwrites the file with the new `feature_id` and `selected_step`. No explicit deletion of the prior file is needed; the write is atomic via tmp+rename.

## Risks / Trade-offs

- **Risk:** Operators relying on silent sticky reuse (e.g., quick iteration loops) face an extra prompt every orchestrator invocation. → Mitigation: the prompt is `Enter` to proceed (option 1) — single keypress. Non-interactive contexts auto-proceed. Operators who genuinely want zero friction can pipe `1` via stdin or use `--resume`.
- **Risk:** The `(CURRENT)` reorder in the picker breaks operator muscle memory if they expected stable candidate ordering. → Mitigation: the reorder only happens when `CURRENT_FEATURE_SWITCH_FROM_ID` is set, which is only after the operator explicitly chose `Change feature`. Other invocations of the picker are unchanged.
- **Risk:** `CURRENT_FEATURE_SWITCH_FROM_ID` leaks across orchestrator runs via process-level state. → Mitigation: it is a shell variable, reset per invocation. No persistence to disk.

## Migration Plan

1. After crp-123 and crp-124 are both merged, add `CURRENT_FEATURE_SWITCH_FROM_ID=""` to the global state declarations in `ai/scripts/orchestrator.sh`.
2. In `_try_fast_path_feature_context`, after the post-success branch that sets `SELECTED_STEP="$_fu"`, add the prompt gate per Decision 1. If the operator picks `Change`, reset reuse state and return 1.
3. Extend `prompt_for_feature_selection_index` (or wrap it) to honor `CURRENT_FEATURE_SWITCH_FROM_ID` per Decision 3.
4. Update `ensure_feature_runtime_context` to clear `CURRENT_FEATURE_SWITCH_FROM_ID` after slow-path discovery completes.
5. Update tests: positive proceed, positive change, non-interactive skip, resume skip, standalone skip, stale-ID after change, single-candidate auto-select.
6. Update `Readme.md`.
7. After crp-125 is filed, close `crp-119-current-feature-startup-switch-prompt` with the `_CLOSED` suffix and leave a one-line pointer to crp-125.

**Rollback:** revert the four edit regions (state global, fast-path prompt block, picker reorder, ensure_feature_runtime_context clear). The fast path resumes silent sticky reuse. No data migration needed; `feature_meta_sync.yaml` itself is unaffected by this change.

## Open Questions

- **Q1:** Should the prompt include a `3. Show feature details` option to let the operator inspect the current feature before deciding? Preference: no — keep the prompt narrow; operators can `cat <bound-project>/<feature_id>/implementation_plan.md` separately. Confirm during implementation.
- **Q2:** Should the prompt time out after some period and auto-proceed? Preference: no — there is no obvious correct default (auto-proceed surprises operators who walked away mid-decision). Confirm during implementation.
- **Q3:** If the operator picks `Change feature` but slow-path discovery finds zero candidates (e.g., all features blocked or unassigned), what error surface is appropriate? Today slow-path already has a "no candidate features" die. Confirm the error message is comprehensible in the "I just chose to change" context — possibly add the prior feature ID to the error.
