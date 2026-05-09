## ADDED Requirements

### Requirement: Planning readiness helper SHALL include LAR reachability validation
`ai/scripts/helpers/check_planning_readiness.sh <step>` SHALL invoke `ai/scripts/helpers/check_lar_reachability.sh <step>` as part of its checks and SHALL exit non-zero when the LAR reachability helper exits non-zero. The non-zero exit blocks planning closure until the user resolves the unfetchable LAR through the existing clarification loop (paste content, supply alternate URL, or remove the upstream reference).

#### Scenario: Reachable LARs do not block planning closure
- **WHEN** the planning readiness helper runs for a step whose in-scope LAR locators all resolve successfully
- **THEN** LAR reachability does not contribute a failure cause
- **THEN** other planning readiness checks proceed as before

#### Scenario: Unreachable LARs block planning closure
- **WHEN** the planning readiness helper runs for a step whose in-scope LAR shortlist contains at least one unreachable locator
- **THEN** the helper exits non-zero
- **THEN** stderr surfaces the offending LAR ID and locator URL
- **THEN** the planning phase does not emit the standard planning completion line

#### Scenario: Step with no in-scope LARs is unaffected at planning closure
- **WHEN** the planning readiness helper runs for a step whose `## Linked Artifacts (in scope)` is empty or absent
- **THEN** the LAR reachability helper exits `0`
- **THEN** planning readiness behavior is identical to behavior before this change

### Requirement: Implementation readiness helper SHALL include LAR reachability validation
`ai/scripts/helpers/check_implementation_readiness.sh <step>` SHALL invoke `ai/scripts/helpers/check_lar_reachability.sh <step>` as part of its checks and SHALL exit non-zero when the LAR reachability helper exits non-zero. The non-zero exit blocks implementation entry to catch drift between phases (a locator reachable at planning closure but no longer reachable at implementation entry).

#### Scenario: Reachable LARs do not block implementation readiness
- **WHEN** the implementation readiness helper runs for a step whose in-scope LAR locators all resolve successfully
- **THEN** LAR reachability does not contribute a failure cause
- **THEN** other implementation readiness checks proceed as before

#### Scenario: Unreachable LARs block implementation readiness
- **WHEN** the implementation readiness helper runs for a step whose in-scope LAR shortlist contains at least one unreachable locator
- **THEN** the helper exits non-zero
- **THEN** stderr surfaces the offending LAR ID and locator URL
- **THEN** the implementation prompt is not generated and the model is not started

#### Scenario: Step with no in-scope LARs is unaffected at implementation entry
- **WHEN** the implementation readiness helper runs for a step whose `## Linked Artifacts (in scope)` is empty or absent
- **THEN** the LAR reachability helper exits `0`
- **THEN** implementation readiness behavior is identical to behavior before this change

### Requirement: Planning step plan SHALL carry the in-scope LAR shortlist via the sync helper
The planning model SHALL land the `## Linked Artifacts (in scope)` section in `ai/step_plans/step-<N>.md` by invoking `ai/scripts/helpers/sync_step_lars.sh <step> ai/step_plans/step-<N>.md` rather than by textually echoing the section. The helper recomputes the section from `overmind/implementation_plan.md` and `overmind/reqirements_ears.md`, so the step plan's section is byte-equivalent to the design artifact's section by construction.

#### Scenario: Step plan section is produced by the sync helper
- **WHEN** the planning phase finishes for a step
- **THEN** `ai/step_plans/step-<N>.md` contains a `## Linked Artifacts (in scope)` section whose content matches the helper's freshly recomputed output

#### Scenario: Helper handles non-empty shortlist
- **WHEN** the helper runs for a step whose design artifact contains a non-empty `## Linked Artifacts (in scope)` block
- **THEN** the step plan contains the same `## Linked Artifacts (in scope)` block with identical entries in identical order

#### Scenario: Helper handles empty or absent shortlist
- **WHEN** the helper runs for a step whose design artifact omits `## Linked Artifacts (in scope)` or emits it empty
- **THEN** the step plan is left with no `## Linked Artifacts (in scope)` section or an empty one
- **THEN** downstream readiness and implementation behavior treat both forms equivalently
