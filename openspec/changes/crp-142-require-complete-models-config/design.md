## Context

See `proposal.md` for motivation. The domain parser currently skips malformed rows, `list_phases` deduplicates configured phases, and the coordinator filters the resulting list before appending `post_review`. Those behaviors make an unsupported partial pipeline look runnable and defer failure until downstream artifacts are missing.

The canonical model and workflow phase orders already live in `domain/phases.py`. Model configuration parsing is domain logic, while reading the file and coordinating a run remain infrastructure/application responsibilities. The coordinator currently applies the clean-mainline policy only when the configured first phase is `design`; every supported non-resume run will now include `design` first.

## Goals / Non-Goals

**Goals:**
- Make one pure domain operation validate and return the complete model configuration.
- Make startup reject invalid configuration before feature discovery and all run side effects.
- Preserve comments, blank lines, optional outer pipes and extra arguments, supported phase aliases, and arbitrary row order.
- Align tests and operator documentation with the supported full-workflow contract.

**Non-Goals:**
- Add a partial-run, phase-selection, or configuration-repair mode.
- Make `post_review` model-configurable.
- Change runner command validation or model invocation behavior beyond earlier configuration rejection.
- Repair the separate post-review metrics test fixtures identified during the failure-history investigation.
- Snapshot or lock `models.md` for the duration of a run; phase runners continue to re-read it, so edits made after startup remain outside this change's consistency guarantee.

## Decisions

### Validate raw rows before deriving workflow phases

Add strict domain validation that parses every active row and compares its normalized phase membership with `MODEL_PHASES`. It must newly reject malformed fields, duplicates, and omissions with line- or phase-specific diagnostics while preserving the parser's existing rejection of unknown and worker-managed phases.

This validation cannot be built on the current `list_phases` behavior because deduplication and malformed-row skipping destroy the evidence needed for useful errors. The existing per-phase lookup can consume the validated parser output or retain its current API as long as both paths share strict row semantics.

Alternative considered: retain permissive parsing and validate only the deduplicated phase tuple. Rejected because duplicate and malformed rows would remain indistinguishable from valid input or missing phases.

### Treat row order as presentation, not workflow topology

Compare normalized phase membership without requiring file order. After validation, always execute `MODEL_PHASES` in canonical order. `models.md` owns the runner, model, and optional arguments for each phase; it does not provide a supported mechanism for rearranging the worker process.

Alternative considered: reject a complete set written out of canonical order. Rejected because execution is canonical regardless, making rejection a style constraint with no functional safety benefit.

### Treat aliases as phase identities, not extra phases

Normalize existing supported aliases before membership comparison. Also accept a single optional leading and trailing pipe so both `design | codex | model` and `| design | codex | model |` are unambiguous valid rows. Diagnostics should use canonical names when describing the expected set and include the configured value or line when identifying bad input.

Alternative considered: require only underscore-form names. Rejected because textual spelling is unrelated to the product rule and would create an unnecessary configuration migration.

Alternative considered: reject Markdown-style outer pipes with a format hint. Rejected because the file has a `.md` extension, outer pipes are unambiguous, and normalization is simpler for operators without weakening field validation.

### Build workflow order only after validation succeeds

The coordinator reads and validates `models.md` as its first run operation. Missing files, directories at the path, permission failures, and other read errors are translated into actionable configuration errors. Once validation succeeds, the coordinator derives the model phase tuple from canonical `MODEL_PHASES` and appends `post_review` exactly once. It does not filter user input into a runnable subset.

This boundary applies equally to normal and resume runs and precedes mainline policy checks, feature-context construction, bound-project Git synchronization, metadata writes, branch creation, and process execution.

Alternative considered: validate inside each model runner as its phase starts. Rejected because it permits earlier discovery, Git, metadata, and branch side effects and produces late, phase-dependent failures.

### Apply the clean-mainline policy to every non-resume run

After configuration validates, every non-resume run calls `require_clean_mainline_start` without inspecting `phases[0]`. The previous predicate becomes permanently true under the complete canonical workflow and should be removed rather than retained as dead conditional behavior. Resume runs continue to skip this startup gate because they intentionally continue from an existing work branch.

Alternative considered: preserve the `phases[0] == "design"` guard. Rejected because partial and non-design starts are unsupported, so the guard implies a capability that no valid configuration can reach.

### Test supported contracts at the narrowest useful layer

Add domain tests for the valid file and each rejection class. Add coordinator tests proving an invalid configuration stops before collaborators with side effects are called and proving a valid configuration expands to the complete workflow.

Replace `_configure_design_only` with a complete five-row echo configuration. Most of its call sites exit during discovery or validation before phase execution and can retain their current product assertions unchanged. Rework the cases that only succeeded because the pipeline was partial into focused unit/application coverage, or supply complete workflow prerequisites where end-to-end execution is what the test actually verifies. Keep end-to-end invalid-configuration cases to verify the CLI-facing diagnostic and no-side-effect boundary.

Measured during implementation: ten of the nineteen `test_run.py` cases keep their assertions unchanged, and nine need rework — two more than the seven originally counted from the failure list. The two extra are the resume cases (`test_resume_step_filters_candidate_features`, `test_run_two_fresh_repos_select_same_feature`). They passed on a design-only configuration only because `_resume_phases` returned an empty tuple when the resume start phase was absent from the configured subset, so they executed no phase at all and trivially exited zero. Under a complete pipeline they genuinely enter phase execution, which is the behavior they were always meant to cover.

Rewrite all partial `models.md` fixtures in `test_coordinator.py`. The non-design-run test premise is removed; mainline and resume tests use complete configuration, while successful pipeline tests must either supply all required phase readiness state or isolate pipeline iteration with an appropriate test double. Rewrite the existing combined parser test rather than merely adding cases, because its partial file and duplicate row become invalid under the new contract.

Alternative considered: delete or migrate all twenty integration call sites. Rejected because most already test failures that occur before phase execution and become valid unchanged once their helper supplies a complete configuration.

Alternative considered: make every coordinator and integration test execute all six phases. Rejected because tests about discovery, cache behavior, and startup policy should not require unrelated phase artifacts; focused application seams are more precise for those behaviors.

The four post-review metrics failures have a different cause: their fixtures do not create the plan branch required by the current metrics range. Record that distinction in the technical-improvement document without expanding this change into metrics fixture repair.

## Risks / Trade-offs

- [Existing users intentionally rely on partial configurations] -> The run now fails instead of executing a subset; document that partial workflows are unsupported and provide the five required phase names in the error and README.
- [Strict parsing exposes previously ignored typos, placeholder rows, or unreadable files] -> Report the path plus exact line or phase when available and show the accepted row shape.
- [Validation rules drift from phase definitions] -> Compare against `MODEL_PHASES` rather than duplicating the required sequence in application code.
- [Broad integration tests lose incidental coverage when removed] -> Map each asserted behavior to focused existing or new tests before deleting partial-workflow cases.
- [A user edits `models.md` after startup validation] -> Phase-level lookup continues to reject an invalid requested row, but whole-file snapshot consistency is explicitly deferred.

## Migration Plan

1. Introduce strict domain parsing and membership validation with focused unit coverage.
2. Move coordinator startup to actionable file-read handling and the validated complete-pipeline result; make the non-resume clean-mainline call unconditional and add no-side-effect tests.
3. Rewrite coordinator fixtures, replace the integration helper with complete echo configuration, and refactor only the seven successful partial-pipeline cases.
4. Update the README and technical-improvement record with the supported contract and corrected failure grouping.
5. Run unit, integration, static type, and formatting checks before release.

Rollback is a normal code revert. No persisted data migration is required; operators with rejected files migrate by restoring one row for each of the five required phases.
