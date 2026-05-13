## Why

Overmind already preserves external artifact links (Figma mockups, Confluence schemas, OpenAPI specs, etc.) inside `overmind/reqirements_ears.md` as a `## Linked Artifacts` registry plus per-requirement `**Linked Artifacts:** LAR-NNN` references. The worker pipeline ignores them entirely: `ai/scripts/ai_design.sh` extracts only `### Requirement N` blocks matching `[REQ-X]` tags from step bullets and discards the registry, so design, planning, implementation, user_review, and ai_audit have zero awareness of LARs. As a result, when a step requires the exact shape of a UI menu, the literal copy of a screen, or the precise field set of an external schema, the model has to invent those details — which is exactly the failure mode this framework is built to prevent.

Both planning and implementation need access to LAR content, but for different concerns. Planning needs structure, copy, field shapes, and decision-driving content so it can write detailed, testable FRs and surface gaps in its existing clarification loop. Implementation needs visual fidelity, exact spacing, icons, and pixel/asset details that text-form FRs cannot faithfully encode no matter how carefully planning writes them.

## Mental model for CRP-112

| Phase | Fetches LAR for | Becomes part of |
|---|---|---|
| Planning | Structure, copy, field shapes, decision-driving content (menu sections, schema fields, error codes) | FR text + clarification loop |
| Implementation | Visual fidelity, spacing, icons, exact pixel/asset details that text can't faithfully encode | Code |

- `ai_design.sh`: funnel point (unchanged).
- `ai_plan.sh`: receives shortlist; planning prompt instructs model to fetch in-scope LARs as one more context input for the existing clarification loop; "cannot resolve LAR-NNN" question pattern flows through existing ask-user mechanisms; FRs end up referencing the LAR explicitly when the LAR is the load-bearing source ("...with sections Categories, Bestsellers, Membership, More — see LAR-002").
- `check_planning_readiness.sh`: extended so unresolved LAR blocks planning closure (same exit-code contract).
- `ai_implementation.sh`: receives shortlist; implementation prompt instructs model to fetch in-scope LARs for visual/detail fidelity that FR text cannot fully express; the existing "stop and ask user when fetch fails or content is ambiguous" rule applies (and at this point, planning has already proven the link is reachable, so failure here is rarer — usually means content drifted between phases).
- `check_lar_reachability.sh`: probe helper, called by both planning-readiness and implementation-readiness gates. Same probe, two enforcement points.

## What Changes

- Teach `ai_design.sh` to extract a step-scoped LAR shortlist as a third filter stage after step bullets → REQ tags → `### Requirement N` blocks: scan the extracted blocks for `**Linked Artifacts:** LAR-NNN` lines, then look up only those IDs in the bottom `## Linked Artifacts` registry of `overmind/reqirements_ears.md`.
- Require the design artifact to echo this shortlist under a new `## Linked Artifacts (in scope)` section using `- LAR-NNN | <type> | <title> | <locator>` format.
- Add a new helper `ai/scripts/helpers/sync_step_lars.sh <step> <target-artifact-path>` that recomputes the LAR funnel and idempotently writes/replaces the `## Linked Artifacts (in scope)` section in the target artifact; instruct both the design model (with the design artifact path) and the planning model (with the step plan path) to invoke it instead of echoing the section textually, so artifact-side syncing is deterministic.
- Teach `ai_plan.sh` to use the sync helper for landing the section in the step plan and to fetch each in-scope LAR locator as one more context input for the existing clarification loop. Fetched content is treated like any other input source (alongside `overmind/implementation_plan.md`, `overmind/reqirements_ears.md`, design artifact, ADRs): it can answer questions, raise new ones, drive `## Things to Decide`, and feed FR translation. The only new question pattern is "cannot resolve LAR-NNN (locator: ...). How should I proceed?", routed through existing ask-user mechanisms (`ai/open_questions.md`, `ai/blocker_log.md`, two-option prompts).
- Add a new helper `ai/scripts/helpers/check_lar_reachability.sh <step>` that probes every in-scope LAR locator (HTTP HEAD/GET, follow redirects, short timeout) and exits non-zero on any unreachable locator with the offending LAR ID and URL. Wire it into `check_planning_readiness.sh` so unresolved fetch failures block planning closure unless the user has explicitly handled them through the clarification loop.
- Teach `ai_implementation.sh` to inject the LAR shortlist into the implementation prompt and add one explicit rule: before implementing FRs that reference a LAR, the model SHALL fetch the locator for visual/detail fidelity that FR text cannot fully express, and SHALL stop and ask the user when fetch fails or fetched content is ambiguous — never invent visual/detail content. Wire `check_lar_reachability.sh` into `check_implementation_readiness.sh` so reachability is re-validated at implementation entry (catches drift between phases).
- Update `ai/templates/feature_design_TEMPLATE.md`, `ai/templates/step_plan_TEMPLATE.md`, and the matching golden examples to include the `## Linked Artifacts (in scope)` section.
- Update `ai/AI_DEVELOPMENT_PROCESS.md` Sections 1, 2.1, 3.1 (and the artifact-roles list) to document the propagate / fetch-as-clarification-input / fetch-for-visual-fidelity rules; Sections 2.2 and 4.2 inherit the gate without separate plumbing.
- Steps whose selected EARS contain no `**Linked Artifacts:**` field produce an empty/omitted section, both reachability invocations are no-ops, and behavior for those steps is unchanged.

## Capabilities

### New Capabilities
- `linked-artifact-step-scoped-extraction`: Design phase performs the third-stage LAR funnel (step → REQ → LAR) and emits a per-step `## Linked Artifacts (in scope)` shortlist into the design artifact and the design prompt context.
- `linked-artifact-planning-fetch-and-clarify`: Planning phase prompt contract requires the model to fetch every in-scope LAR locator via available web/MCP tooling, treat fetched content as one more context input for the existing clarification loop, and raise the standard "cannot resolve LAR-NNN" question through existing ask-user mechanisms when fetch fails. Resolved content informs FR translation, decisions, and gap discovery.
- `linked-artifact-implementation-fetch-for-fidelity`: Implementation phase prompt contract requires the model to fetch every in-scope LAR locator for visual fidelity, exact spacing, icons, and pixel/asset details that FR text cannot fully encode, and to stop and ask the user instead of inventing visual/detail content when fetch fails or content is ambiguous.
- `linked-artifact-reachability-gate`: Probe helper validates that every in-scope LAR locator responds, exits non-zero with offending LAR ID and URL on failure, and is invoked at both planning closure and implementation entry as the same exit-code contract.

### Modified Capabilities
- `design-as-contract-phase-boundaries`: design is the single funnel point for step-scoped LARs; planning consumes from the design artifact, implementation consumes from the step plan, and neither re-traverses `overmind/reqirements_ears.md`.
- `planning-to-implementation-readiness-gate`: both `check_planning_readiness.sh` and `check_implementation_readiness.sh` invoke the LAR reachability helper. Planning closure fails if any in-scope LAR is unreachable and unresolved through the clarification loop; implementation entry fails if any in-scope LAR has become unreachable since planning closed (drift detection).
- `deterministic-implementation-prompt-packet`: implementation prompt packet now includes the `## Linked Artifacts (in scope)` section sourced verbatim from the step plan, plus the fetch-for-visual-fidelity rule line.

## Impact

- Prompt contracts:
  - `ai/scripts/ai_design.sh` (new third-stage LAR extraction + emit block)
  - `ai/scripts/ai_plan.sh` (read shortlist + fetch-as-clarification-input rule + emit shortlist into step plan)
  - `ai/scripts/ai_implementation.sh` (inject shortlist + fetch-for-visual-fidelity rule line)
- Helpers:
  - new `ai/scripts/helpers/sync_step_lars.sh` (centralized funnel + idempotent section sync into a target artifact)
  - new `ai/scripts/helpers/check_lar_reachability.sh`
  - `ai/scripts/helpers/check_planning_readiness.sh` extended to invoke `check_lar_reachability.sh`
  - `ai/scripts/helpers/check_implementation_readiness.sh` extended to invoke `check_lar_reachability.sh`
- Templates and golden examples:
  - `ai/templates/feature_design_TEMPLATE.md`
  - `ai/templates/step_plan_TEMPLATE.md`
  - matching golden examples under `ai/golden_examples/`
- Documentation:
  - `ai/AI_DEVELOPMENT_PROCESS.md` (Sections 1, 2.1, 3.1, and the artifact-roles list)
  - `Readme.md` (mention LAR flow under worker cycle)
- Tests:
  - targeted shell tests for design prompt contract (LAR funnel), planning prompt contract (mirror + fetch rule), implementation prompt contract (inject + fetch rule), reachability helper (probe + hard fail), and both readiness helpers' inheritance of the reachability check
- Determinism trade-off (acknowledged, not addressed in this change): runtime fetch in two phases creates two windows for content drift across days; a follow-up change can add a snapshot cache under `ai/lar_cache/<step>/` for `--resume` replay without altering this change's schema.
- CLI capability gap (acknowledged): codex CLI web access varies; the fetch-and-don't-invent rule (in both phases) is the catch for "model cannot fetch" outcomes.
