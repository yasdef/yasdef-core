## ADDED Requirements

### Requirement: Default mode reads plan and ears directly from bound source
In default mode (no `--standalone`), the orchestrator and all phase scripts SHALL read `implementation_plan.md` and `requirements_ears.md` directly from their bound-source locations at `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` and `<BOUND_PROJECT_PATH>/<feature_id>/requirements_ears.md`. The orchestrator MUST NOT create or maintain any per-worker mirror of these files under `.asdlc_worker/overmind/`.

#### Scenario: Feature selection does not mirror plan and ears
- **WHEN** the orchestrator selects a feature in default mode
- **THEN** no copy of `implementation_plan.md` or `requirements_ears.md` is written to `.asdlc_worker/overmind/`
- **THEN** subsequent phase scripts receive `$ASDLC_RUNTIME_PLAN_PATH` and `$ASDLC_RUNTIME_EARS_PATH` resolving to the bound-source paths

#### Scenario: Phase scripts read from bound source via env vars
- **WHEN** any of `ai_design.sh`, `ai_plan.sh`, `ai_implementation.sh`, `ai_user_review.sh`, `ai_audit.sh` runs in default mode
- **THEN** the script reads plan and ears content from the paths supplied via `$ASDLC_RUNTIME_PLAN_PATH` and `$ASDLC_RUNTIME_EARS_PATH`
- **THEN** those paths point at `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` and `.../requirements_ears.md`

#### Scenario: Resume on a non-overmind branch does not require local mirror files
- **WHEN** the orchestrator resumes in default mode on a branch other than `overmind`
- **THEN** the orchestrator does not require `.asdlc_worker/overmind/implementation_plan.md` or `.asdlc_worker/overmind/requirements_ears.md` to be present on that branch
- **THEN** resume proceeds using the bound-source paths

### Requirement: AI agent writes during plan and ai_audit phases land on bound source
The orchestrator SHALL allow the AI agent's mid-step writes to `implementation_plan.md` (the plan-phase `Plan and discuss the step` tick and the ai_audit-phase remaining-bullets ticks) to land on the bound-source file directly. No intermediate runtime copy SHALL exist.

#### Scenario: Plan phase writes appear in bound source working tree
- **WHEN** the plan phase completes and the AI has marked `Plan and discuss the step` as `[x]`
- **THEN** the bound-source `implementation_plan.md` working tree contains the `[x]` mark for that bullet
- **THEN** the change is uncommitted in the bound repo until end-of-step sync

#### Scenario: ai_audit phase writes appear in bound source working tree
- **WHEN** the ai_audit phase completes and the AI has marked remaining current-step bullets as `[x]`
- **THEN** the bound-source `implementation_plan.md` working tree contains those `[x]` marks
- **THEN** changes accumulated since plan-phase writes are still uncommitted in the bound repo until end-of-step sync

### Requirement: End-of-step sync commits and pushes bound source plan once per step
At end of step (immediately before `post_review`), the orchestrator SHALL perform a single `git add + git commit + git pull --rebase + git push` on the bound repo for the feature's `implementation_plan.md` file. There MUST be no intermediate runtime → source copy step.

#### Scenario: Successful end-of-step sync produces one commit on the bound repo
- **WHEN** plan and ai_audit phases have completed with at least one change to the bound-source plan
- **THEN** the orchestrator stages and commits the change on the bound repo with the existing commit-message format
- **THEN** the orchestrator runs `git pull --rebase` then `git push` on the bound repo

#### Scenario: No-op sync when bound source plan is unchanged
- **WHEN** the bound-source plan is byte-identical to its committed state at end of step
- **THEN** the orchestrator does not create a commit on the bound repo
- **THEN** the orchestrator still runs `git pull --rebase` to keep the bound repo current and does not push

#### Scenario: Push failure invokes existing retry/finish prompt
- **WHEN** `git pull --rebase` or `git push` fails during end-of-step sync
- **THEN** the orchestrator presents the existing two-option `retry` / `finish` prompt
- **THEN** `finish` skips the global sync for this step and continues to `post_review` exactly as today

### Requirement: Pre-step clean check rejects dirty bound source plan
Before allowing plan or ai_audit phases to write to the bound-source plan, the orchestrator SHALL verify that the bound-source `implementation_plan.md` for the selected feature has no uncommitted changes. If dirty, the orchestrator MUST fail fast with a clear error directing the operator to commit, stash, or restore the bound repo.

#### Scenario: Clean bound source plan allows step execution
- **WHEN** the bound-source `implementation_plan.md` has no uncommitted changes at step start
- **THEN** the orchestrator proceeds with the requested phases

#### Scenario: Dirty bound source plan from prior aborted run blocks step execution
- **WHEN** the bound-source `implementation_plan.md` has uncommitted changes at step start
- **THEN** the orchestrator exits non-zero with a message identifying the dirty file and the bound repo path
- **THEN** the message instructs the operator to commit, stash, or `git restore` the file before rerunning

### Requirement: Standalone mode keeps local runtime plan and ears
The `--standalone` mode SHALL continue to read and write `implementation_plan.md` and `requirements_ears.md` from local `.asdlc_worker/overmind/`. Standalone mode MUST NOT consult or write `feature_meta_sync.yaml`.

#### Scenario: Standalone mode requires local runtime plan and ears
- **WHEN** the orchestrator runs with `--standalone` and either `.asdlc_worker/overmind/implementation_plan.md` or `.asdlc_worker/overmind/requirements_ears.md` is missing
- **THEN** the orchestrator exits non-zero with the existing standalone-mode error message

#### Scenario: Standalone mode does not write feature_meta_sync.yaml
- **WHEN** the orchestrator runs successfully with `--standalone`
- **THEN** no `.asdlc_worker/feature_meta_sync.yaml` is written
