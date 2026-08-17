## 1. Strict Model Configuration Domain Contract

- [ ] 1.1 Add a strict domain operation that parses every active `models.md` row, accepts optional outer pipes and arbitrary row order, and rejects malformed fields, duplicate normalized phases, and missing required phases with actionable diagnostics while preserving existing unsupported-phase rejection.
- [ ] 1.2 Make model lookup and phase derivation share strict row semantics and canonical `MODEL_PHASES` execution order while preserving comments, blank lines, optional extras, and supported phase aliases.
- [ ] 1.3 Rewrite the partial and duplicate parser fixture in `tests/unit/domain/test_branches_models.py` as a complete valid configuration, retain the existing unknown/`post_review` tests, and add focused missing, duplicate, malformed, outer-pipe, and reordered-row cases.

## 2. Coordinator Startup Boundary

- [ ] 2.1 Change coordinator startup to translate missing, directory, permission, and other `models.md` read failures into actionable configuration errors and validate content before mainline checks, feature-context construction, bound-project synchronization, metadata writes, branch creation, resume analysis, or model execution.
- [ ] 2.2 Derive the runnable workflow only from the validated canonical model phases and append worker-managed `post_review` exactly once.
- [ ] 2.3 Collapse the now-always-true design-first guard into an unconditional clean-mainline check for non-resume runs, preserve the resume exemption, and remove the unsupported non-design-run test premise.
- [ ] 2.4 Rewrite every partial `models.md` fixture in `tests/unit/app/test_coordinator.py`; update the successful coordinator harness with complete phase readiness or an isolated pipeline test double, and add coverage for canonical order, early invalid/unreadable configuration failure, clean-mainline behavior, and no side-effecting collaborators.

## 3. Supported Test Process

- [ ] 3.1 Replace `_configure_design_only` with a complete five-row echo configuration and retain the thirteen call sites that exit before phase execution with their current product assertions.
- [ ] 3.2 Inventory the seven successful partial-pipeline cases and retain each asserted feature-selection, cache, log, and synchronization behavior through focused application tests or complete workflow prerequisites; do not remove unrelated early-exit coverage.
- [ ] 3.3 Add CLI-facing integration cases for early partial and missing configuration rejection with no run side effects, and ensure every remaining successful `yasdef run` scenario uses the complete phase set.

## 4. Documentation And Verification

- [ ] 4.1 Update `Readme.md` to document the mandatory five model rows, order-insensitive row placement, canonical execution order, configurable command/model columns, clean-mainline requirement for non-resume runs, and worker-managed `post_review`; confirm the shipped `models.md` template already needs no change.
- [ ] 4.2 Correct `design_docs/improvement_proposals/technical_improvements.md` to distinguish the seven partial-pipeline failures from the four post-review metrics fixture failures and replace the obsolete suggested partial-pipeline behavior.
- [ ] 4.3 Run the focused domain, coordinator, feature-context, and integration tests plus formatting, lint, and strict type checks; run the full Python suite and require it to be green except for the four documented `test_post_review.py` fixture failures tracked separately by CRP-143.
