## ADDED Requirements

### Requirement: A dedicated helper MUST validate in-scope LAR reachability through an exit-code contract
`ai/scripts/helpers/check_lar_reachability.sh <step>` SHALL read `## Linked Artifacts (in scope)` from `ai/step_plans/step-<N>.md`, probe each locator with an HTTP request that follows redirects and uses a fixed short per-locator timeout, and return `0` when every locator responds with a non-error status (2xx or 3xx after redirect chain). It SHALL return non-zero when any locator returns an error status, times out, or is not an HTTP(S) URL.

#### Scenario: All in-scope locators are reachable
- **WHEN** the helper runs for a step whose `## Linked Artifacts (in scope)` block contains locators that all return 2xx or 3xx after following redirects within the per-locator timeout
- **THEN** the helper exits with code `0`

#### Scenario: One locator is unreachable
- **WHEN** the helper runs for a step whose `## Linked Artifacts (in scope)` block contains at least one locator that returns 4xx, 5xx, times out, or is not an HTTP(S) URL
- **THEN** the helper exits non-zero
- **THEN** stderr identifies the offending LAR ID and locator URL

#### Scenario: Step has no in-scope LARs
- **WHEN** the helper runs for a step whose `ai/step_plans/step-<N>.md` omits `## Linked Artifacts (in scope)` or emits it empty
- **THEN** the helper exits with code `0` immediately without performing any HTTP probes

#### Scenario: Step plan is missing
- **WHEN** the helper runs for a step whose `ai/step_plans/step-<N>.md` does not exist
- **THEN** the helper exits non-zero
- **THEN** stderr identifies the missing step plan path

### Requirement: Both planning closure and implementation entry MUST inherit LAR reachability validation
The same reachability probe SHALL be invoked at two enforcement points:
- `ai/scripts/helpers/check_planning_readiness.sh` SHALL call `ai/scripts/helpers/check_lar_reachability.sh <step>` and SHALL exit non-zero whenever the LAR reachability helper exits non-zero, blocking planning closure until the user resolves the unfetchable LAR through the existing clarification loop.
- `ai/scripts/helpers/check_implementation_readiness.sh` SHALL call `ai/scripts/helpers/check_lar_reachability.sh <step>` and SHALL exit non-zero whenever the LAR reachability helper exits non-zero, blocking implementation entry to catch drift between phases.

#### Scenario: Unreachable LAR blocks planning closure
- **WHEN** `ai/scripts/helpers/check_planning_readiness.sh` runs for a step whose LAR reachability helper exits non-zero
- **THEN** the planning readiness helper exits non-zero
- **THEN** stderr surfaces the offending LAR ID and locator URL

#### Scenario: Unreachable LAR blocks implementation entry
- **WHEN** `ai/scripts/helpers/check_implementation_readiness.sh` runs for a step whose LAR reachability helper exits non-zero
- **THEN** the implementation readiness helper exits non-zero
- **THEN** stderr surfaces the offending LAR ID and locator URL
- **THEN** the implementation prompt is not generated and the model is not started

#### Scenario: Reachable LARs do not block either phase boundary
- **WHEN** either readiness helper runs for a step whose LAR reachability helper exits `0`
- **THEN** LAR reachability does not contribute a failure cause
- **THEN** other readiness checks proceed as before

#### Scenario: Step with no in-scope LARs is unaffected at both phase boundaries
- **WHEN** either readiness helper runs for a step whose `## Linked Artifacts (in scope)` is empty or absent
- **THEN** the LAR reachability helper exits `0`
- **THEN** readiness behavior at both phase boundaries is identical to behavior before this change

### Requirement: Reachability probe semantics MUST be limited to URL response, not content readability
The reachability probe SHALL succeed when the locator returns any non-error HTTP status (2xx or 3xx after redirect chain). It SHALL NOT attempt authentication, content sniffing, or model-readability checks. A login page that returns HTTP 200 SHALL be treated as reachable. The fetch-and-don't-invent rules in planning and implementation prompts SHALL handle login-wall, ambiguous-content, and 404-but-200-shell cases at runtime.

#### Scenario: 200 login page is treated as reachable
- **WHEN** the helper probes a locator that returns HTTP 200 with a login page body
- **THEN** the helper treats the locator as reachable and contributes no failure for that LAR

#### Scenario: 4xx and 5xx are treated as unreachable
- **WHEN** the helper probes a locator that returns HTTP 4xx or 5xx after the redirect chain
- **THEN** the helper treats the locator as unreachable and exits non-zero with the offending LAR ID and URL

#### Scenario: Non-HTTP(S) locators are treated as unreachable
- **WHEN** the helper encounters a locator that is not an `http://` or `https://` URL
- **THEN** the helper treats the locator as unreachable and exits non-zero with the offending LAR ID and locator value
