## MODIFIED Requirements

### Requirement: Resume from first unfinished phase
The orchestrator SHALL support `--resume <step>` to evaluate the specified step against the canonical phase order and begin execution at the first phase that is not complete. Resume evaluation MUST treat design semantic readiness as design-phase handoff validation and MUST NOT block planning progression solely because the design artifact is missing `## Goal`, `## In Scope`, or `## Out of Scope`. Resume evaluation MUST treat planning semantic readiness as a planning/implementation handoff check owned by the phases and MUST NOT block implementation progression solely because `ai/step_plans/step-<N>.md` is missing, `## Plan (ordered)` is missing, `## Functional Requirements (translated from design EARS)` is missing, or the `Plan and discuss the step` bullet is missing or unchecked. For ai_audit completion and resume routing, the orchestrator MUST treat review-artifact semantic validation as a boundary-owned helper concern and MUST NOT decide ai_audit completeness based on presence of `## Disposition (per issue)` or on Accepted/Rejected disposition counts. Resume reuse of an existing `.asdlc_worker/feature_meta_sync.yaml` MUST validate `project_id` and `worker_uuid` against the binding file and MUST derive bound-source plan and ears paths from `<BOUND_PROJECT_PATH>/<feature_id>/` rather than reading any cached source-path fields. Resume reuse MUST NOT read, write, or rely on `.asdlc_worker/feature_sync.yaml`; that filename is treated as if it does not exist.

#### Scenario: Resume starts at first unfinished phase
- **WHEN** the operator runs the orchestrator with `--resume <step>` for a valid step that has completed early phases and an unfinished later phase
- **THEN** the orchestrator starts from the first unfinished phase and executes that phase and all remaining phases in order

#### Scenario: Resume starts at planning when design sections are incomplete
- **WHEN** the design artifact exists for the target step but is missing one or more of `## Goal`, `## In Scope`, or `## Out of Scope` and planning is otherwise the first unfinished phase
- **THEN** resume starts at `planning` and does not mark the design phase invalid because of the missing sections

#### Scenario: Resume starts at implementation when planning readiness artifacts are incomplete
- **WHEN** planning artifact semantics for the target step are incomplete but implementation is otherwise the first unfinished phase
- **THEN** resume starts at `implementation` and does not mark planning invalid because of missing step-plan structure or planning-gate closure

#### Scenario: Resume reuses feature_meta_sync.yaml and rederives source paths
- **WHEN** `.asdlc_worker/feature_meta_sync.yaml` exists with `project_id` and `worker_uuid` matching the binding file
- **THEN** the orchestrator derives plan and ears paths as `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` and `.../requirements_ears.md`
- **THEN** the orchestrator does not consult any cached source-path field

#### Scenario: Resume ignores legacy feature_sync.yaml
- **WHEN** `.asdlc_worker/feature_sync.yaml` is present but `.asdlc_worker/feature_meta_sync.yaml` is absent
- **THEN** the orchestrator behaves as if no metadata file exists and falls through to slow-path discovery

#### Scenario: Resume falls through to discovery when meta sync identity mismatches
- **WHEN** `.asdlc_worker/feature_meta_sync.yaml` exists but `project_id` or `worker_uuid` does not match the binding file
- **THEN** reuse fails and the orchestrator falls through to slow-path discovery

#### Scenario: Resume falls through to discovery when derived plan is missing
- **WHEN** `.asdlc_worker/feature_meta_sync.yaml` exists but `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` does not exist
- **THEN** reuse fails and the orchestrator falls through to slow-path discovery

### Requirement: Resume evaluation SHALL not own implementation-readiness checklist enforcement
When evaluating the `implementation` to `user_review` boundary, orchestrator resume logic MUST NOT use ordered-plan checklist semantics or translated functional-requirement checklist semantics to invalidate implementation completion or block downstream phase selection.

#### Scenario: Resume does not block on ordered-plan checklist semantics
- **WHEN** resume evaluates a step whose ordered-plan section is missing, empty, or not fully checked
- **THEN** orchestrator does not block resume progression on that basis alone
- **THEN** ordered-plan readiness enforcement remains the responsibility of implementation and `user_review`

#### Scenario: Resume does not block on translated functional-requirement semantics
- **WHEN** resume evaluates a step whose translated functional requirements are missing, empty, or not fully checked
- **THEN** orchestrator does not block resume progression on that basis alone
- **THEN** translated functional-requirement readiness enforcement remains the responsibility of implementation and `user_review`

#### Scenario: Resume starts at user_review after completed implementation
- **WHEN** design, planning, and implementation phases are complete for the target step and `user_review` is incomplete
- **THEN** resume starts at `user_review` and does not re-run implementation

#### Scenario: Resume starts at ai_audit after completed user_review
- **WHEN** design, planning, implementation, and `user_review` phases are complete for the target step and `ai_audit` is incomplete
- **THEN** resume starts at `ai_audit` and does not re-run earlier phases

#### Scenario: Resume does not reopen ai_audit for missing disposition section
- **WHEN** the review artifact exists for the target step, ai_audit is otherwise the last completed phase artifact, and the artifact is missing `## Disposition (per issue)`
- **THEN** the orchestrator does not mark ai_audit invalid because of the missing disposition section
- **THEN** resume routing is determined by later phase completeness instead of reopening ai_audit for semantic validation

#### Scenario: Resume does not reopen ai_audit for insufficient disposition counts
- **WHEN** the review artifact exists for the target step and its Accepted/Rejected disposition count is lower than the counted issues in the severity sections
- **THEN** the orchestrator does not mark ai_audit invalid because of disposition-count semantics
- **THEN** resume routing is determined by later phase completeness instead of reopening ai_audit for semantic validation

## ADDED Requirements

### Requirement: Resume does not require local runtime plan or ears in default mode
In default mode, resume SHALL NOT require `.asdlc_worker/overmind/implementation_plan.md` or `.asdlc_worker/overmind/requirements_ears.md` to be present on the current branch. The presence checks that previously guarded resume on non-overmind branches MUST be replaced by the equivalent checks against the bound-source paths.

#### Scenario: Resume on a non-overmind branch without local mirror succeeds
- **WHEN** resume runs in default mode on a branch other than `overmind` with no `.asdlc_worker/overmind/implementation_plan.md` present
- **THEN** the orchestrator does not error on the missing local mirror
- **THEN** resume proceeds as long as the bound-source plan and ears exist

#### Scenario: Resume errors when bound source plan is missing
- **WHEN** resume runs in default mode and the bound-source `<BOUND_PROJECT_PATH>/<feature_id>/implementation_plan.md` does not exist
- **THEN** the orchestrator fails with a clear error identifying the missing bound-source file

## REMOVED Requirements

### Requirement: Resume reuse ignores selection_mode in existing feature_sync.yaml
**Reason**: The runtime mirror and the `feature_sync.yaml` schema that carried `selection_mode` are removed by this change. The replacement file `feature_meta_sync.yaml` does not contain `selection_mode` at all, so resume cannot read or ignore it. This requirement is moot.

**Migration**: No operator action required. crp-117 (which proposed the narrow removal of `selection_mode`) is subsumed by this change and can be archived without separate implementation.

### Requirement: Resume reuse sets internal mode without recursive prefix
**Reason**: The recursive `resume_reuse:<prior selection_mode>` accumulation was a consequence of persisting `selection_mode` in `feature_sync.yaml` and reading it back. With `feature_meta_sync.yaml` not containing the field, the recursion cannot occur. The internal `SELECTED_SELECTION_MODE` variable, if retained at all for logging, is set unconditionally without any reuse-prefix concern.

**Migration**: No operator action required. Existing log lines that referenced `mode=<value>` continue to work using the unconditional internal value.
