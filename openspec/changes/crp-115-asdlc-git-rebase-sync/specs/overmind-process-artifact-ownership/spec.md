## ADDED Requirements

### Requirement: ASDLC source plan updates are synchronized through the source repo
When worker runtime plan updates are propagated back to the selected ASDLC feature after `ai_audit`, the selected feature folder SHALL remain the source of truth by receiving a copied, committed, rebased, and pushed `implementation_plan.md` update through the bound ASDLC project repo before `post_review`.

#### Scenario: Worker runtime plan update becomes ASDLC source update
- **WHEN** `ai_audit` completes for step `<N>` in default mode
- **THEN** orchestrator SHALL copy `.asdlc_worker/overmind/implementation_plan.md` to the selected ASDLC feature `implementation_plan.md`
- **AND** the selected ASDLC feature `implementation_plan.md` update SHALL be committed in the ASDLC project repo before outbound pull-rebase
- **AND** the commit SHALL be rebased and pushed from the ASDLC project repo before `post_review` starts

#### Scenario: ASDLC rebase or push fails
- **WHEN** copied worker runtime plan changes conflict with newer ASDLC source plan changes during outbound pull-rebase
- **THEN** the selected ASDLC feature folder SHALL remain the authoritative location for resolving the conflict
- **AND** orchestrator SHALL ask the operator to retry sync or finish by continuing to `post_review`
- **AND** orchestrator SHALL not report the global implementation-plan sync as complete
