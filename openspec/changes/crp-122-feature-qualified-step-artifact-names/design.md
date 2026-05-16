## Context

Per-step artifacts are currently keyed only by step number:
- Step plans: `ASDLC_STEP_PLANS_DIR/step-<N>.md`
- Step designs: `ASDLC_STEP_DESIGNS_DIR/step-<N>-design.md`
- Step review results: `ASDLC_STEP_REVIEW_RESULTS_DIR/review_result-<N>.md`

When multiple features are active and workers share step numbers, writing a new artifact for feature B's step 2 overwrites feature A's step 2 artifact. `SELECTED_FEATURE_ID` is already resolved before orchestrator step execution begins.

Key artifact path consumers in `orchestrator.sh`:
- `get_latest_step_plan()` (line ~693): globs `step-*.md`, picks highest-numbered
- `get_step_from_plan_path()` / `try_get_step_from_plan_path()` (line ~723): extract step from filename
- `get_step_from_design_path()` (line ~743): extracts step from design filename
- `get_preferred_step_plan()` (line ~1677): derives plan path from current branch or falls back to latest
- Phase runner functions: build paths directly as `step-$step.md`, `step-$step-design.md`, `review_result-$step.md`

Phase scripts (`ai_plan.sh`, `ai_implementation.sh`, `ai_user_review.sh`, `ai_audit.sh`) each independently construct artifact paths from `$STEP`.

## Goals / Non-Goals

**Goals:**
- Step plan, design, and review result filenames include selected feature ID when a feature is selected
- Phase scripts produce and read feature-qualified artifact paths when feature ID is supplied
- `get_latest_step_plan()`, `get_preferred_step_plan()`, and step extraction helpers correctly handle feature-qualified filenames
- Orchestrator phase runners build feature-qualified artifact paths when `SELECTED_FEATURE_ID` is non-empty

**Non-Goals:**
- Standalone step artifacts (no feature selected) retain existing naming — no migration needed
- Prompt output files under `.asdlc_worker/prompts` are not in scope
- Shared files (`implementation_plan.md`, `decisions.md`, etc.) are not step-scoped and are out of scope

## Decisions

### 1. Name format: insert feature ID between step number and suffix

| Artifact | Standalone | Feature-qualified |
|---|---|---|
| Step plan | `step-<N>.md` | `step-<N>-<feature-id>.md` |
| Step design | `step-<N>-design.md` | `step-<N>-<feature-id>-design.md` |
| Review result | `review_result-<N>.md` | `review_result-<N>-<feature-id>.md` |

Inserting the feature ID before the suffix (rather than after) keeps the step number at the front for sort/glob consistency and clearly separates the type suffix. This is symmetric with the CRP-121 branch naming pattern.

### 2. Feature ID delivery to phase scripts via `--feature-id` flag

Each phase script computes its own artifact output path from `$STEP` + optional `$FEATURE_ID`. Adding `--feature-id` to `ai_plan.sh`, `ai_implementation.sh`, `ai_user_review.sh`, and `ai_audit.sh` keeps path construction co-located with each script's existing `$STEP`-based path logic. The orchestrator passes `--feature-id "$SELECTED_FEATURE_ID"` when non-empty.

Alternative (orchestrator computes and passes full paths via `--out`/`--step-plan`) would require the orchestrator to know each script's internal naming convention, coupling them more tightly.

### 3. `get_latest_step_plan()` gains optional feature-id filter

When called with a feature ID, `get_latest_step_plan()` matches only `step-*-<feature-id>.md`. When called without one, it matches only files whose stem is purely `step-<numeric>.md` (step-only, no feature qualifier). This prevents cross-contamination when both standalone and feature-qualified plans coexist in the directory.

Since `SELECTED_STEP` is always known at orchestrator phase-run time, `get_preferred_step_plan()` constructs the path directly as `step-$SELECTED_STEP[-$SELECTED_FEATURE_ID].md` and only falls back to `get_latest_step_plan()` when no step is known.

### 4. Step extraction from feature-qualified filenames uses numeric prefix

`get_step_from_plan_path()` currently strips `step-` and `.md` giving `2-auth-system` for a feature-qualified plan — callers expect just `2`. Since step IDs are always numeric, update extraction to stop at the first `-` after the numeric prefix (i.e., return everything between `step-` and the first non-numeric `-` or end-of-stem). Apply the same fix to `try_get_step_from_plan_path()` and `get_step_from_design_path()`.

## Risks / Trade-offs

- [`get_latest_step_plan()` filename filtering is heuristic] → Rely on step IDs being numeric; a non-numeric standalone step ID would be misclassified. Current step IDs are always numeric so this is acceptable.
- [Phase scripts each need `--feature-id` added] → Four scripts require consistent flag addition; a missed script silently produces step-only paths. Tests catch this at the orchestrator assignment and resume test level.
- [Review result path is computed inside orchestrator, not a phase script] → `ai_audit.sh` writes to its own output path but the orchestrator also reads `review_result-$step.md` for phase completion detection. Both sites need updating.
