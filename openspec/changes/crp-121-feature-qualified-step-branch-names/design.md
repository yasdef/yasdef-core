## Context

Orchestrator step branches are currently named `step-<N>-<phase>` (e.g., `step-2-plan`, `step-2-implementation`). When multiple features are active and workers share the same step numbers, these names collide — operators and tooling cannot distinguish which feature a branch belongs to.

`SELECTED_FEATURE_ID` is already resolved and available in `orchestrator.sh` before step execution begins. Phase scripts (`ai_plan.sh`, `ai_implementation.sh`, `ai_user_review.sh`, `ai_audit.sh`) receive the step number but not the feature identity.

Branch creation and detection is spread across four scripts:
- `ai_plan.sh`: constructs `step-$STEP-plan` (accepts `--branch-name` override)
- `ai_implementation.sh`: constructs `step-$STEP-implementation` in `ensure_implementation_branch()`
- `ai_user_review.sh`: constructs `step-$STEP-user-review` from `step-$STEP-implementation`
- `ai_audit.sh`: constructs `step-$STEP-review` from `step-$STEP-user-review` or `step-$STEP-implementation`
- `orchestrator.sh`: branch detection via `implementation_branch_exists_for_step()`, `user_review_branch_exists_for_step()`, `get_step_from_branch_name()`

## Goals / Non-Goals

**Goals:**
- Step branches include selected feature ID in the name when a feature is selected
- All phase scripts construct feature-qualified branch names when feature ID is provided
- Orchestrator branch detection and resume logic use feature-qualified names when a feature is selected
- `get_step_from_branch_name()` extracts the correct step number from both old and new formats

**Non-Goals:**
- Standalone step branches (no feature selected) remain `step-<N>-<phase>` — no change
- Artifact file naming (step plans, designs, review results) is addressed by CRP-122

## Decisions

### 1. Name format: `step-<step>-<feature-id>-<phase>`

When `SELECTED_FEATURE_ID` is non-empty, step branches are named `step-<step>-<feature-id>-<phase>` (e.g., `step-2-auth-system-implementation`). When empty (standalone step), the existing `step-<step>-<phase>` format is used unchanged.

Alternatives considered: `<feature>/step-<N>-<phase>` (slash-namespacing creates refspec complexity) and `step-<N>@<feature>-<phase>` (`@` is unconventional in branch names). The suffix approach requires the least tooling change.

### 2. Feature ID delivery to phase scripts via `--feature-id` flag

`ai_plan.sh` already accepts `--branch-name`; the orchestrator will pass the computed feature-qualified branch name via that existing flag when `SELECTED_FEATURE_ID` is non-empty.

`ai_implementation.sh`, `ai_user_review.sh`, and `ai_audit.sh` each construct multiple related branch names from `$STEP` (implementation branch, user-review branch, review branch). Adding a single `--feature-id` flag lets each script qualify all branch name roles consistently from one parameter, rather than requiring separate `--branch-name` flags for each role.

### 3. Step extraction from branch names uses two-pass check

`get_step_from_branch_name()` in `orchestrator.sh` and the identical helpers in phase scripts currently use `^step-(.+)-(plan|implementation|user-review|review|ai-audit)$`, capturing the full middle segment. Since step IDs are always numeric (`1`, `2`, `1.3`), a first-pass check with `^step-([0-9]+([.][0-9]+)*)-[^-].*-(plan|implementation|user-review|review|ai-audit)$` captures only the numeric step and skips any feature segment. The existing generic pattern serves as fallback for backward compatibility.

### 4. Branch detection functions use `SELECTED_FEATURE_ID` global

`implementation_branch_exists_for_step()` and `user_review_branch_exists_for_step()` in `orchestrator.sh` construct the branch name as `step-$step-$SELECTED_FEATURE_ID-<phase>` when `SELECTED_FEATURE_ID` is non-empty, or `step-$step-<phase>` when empty. The global is already set before evaluation runs.

## Risks / Trade-offs

- [Tests assert exact branch names like `step-2-implementation`] → Update `orchestrator_resume_tests.sh` and `orchestrator_assignment_tests.sh` to use feature-qualified names in feature-context test setups
- [ai_implementation.sh currently has no `--feature-id` or `--branch-name` flag] → Must add this flag alongside the other phase scripts; it is called by orchestrator at line 1729 without a branch-name arg today
- [Operators with in-flight step-only branches] → Detection fallback to step-only names applies only for standalone steps; feature-selected resume always uses feature-qualified branch names
