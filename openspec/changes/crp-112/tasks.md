## 1. Extend design with the third-stage LAR funnel

- [ ] 1.1 Extend `ai/scripts/ai_design.sh` to add the third filter stage: scan the already-extracted `### Requirement N` blocks for `**Linked Artifacts:**` lines, dedup `LAR-NNN` IDs, and look each ID up in the bottom `## Linked Artifacts` registry of `overmind/reqirements_ears.md`.
- [ ] 1.2 Emit a `## Linked Artifacts (in scope)` block in the design prompt context with one line per LAR formatted as `- LAR-NNN | <type> | <title> | <locator>`, ordered by ascending numeric ID.
- [ ] 1.3 Add `ai/scripts/helpers/sync_step_lars.sh <step> <target-artifact-path>` that recomputes the LAR funnel from `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` and idempotently writes/replaces a `## Linked Artifacts (in scope)` section in the target artifact at the given path; handles the empty/no-LARs case as a successful no-op (no section or an empty section, never a partial one).
- [ ] 1.4 Update the design prompt contract to instruct the model to invoke `ai/scripts/helpers/sync_step_lars.sh <step> ai/step_designs/step-<N>-design.md` for artifact-side syncing of the section instead of echoing the block textually.
- [ ] 1.5 Update `ai/templates/feature_design_TEMPLATE.md` and `ai/golden_examples/feature_design_GOLDEN_EXAMPLE.md` to include the `## Linked Artifacts (in scope)` section with the canonical line format and a note that the section may be empty/omitted when no LARs are in scope.

## 2. Mirror the LAR shortlist through planning and add the fetch-as-clarification-input rule

- [ ] 2.1 Extend `ai/scripts/ai_plan.sh` to read `## Linked Artifacts (in scope)` from `ai/step_designs/step-<N>-design.md` for prompt context only and to instruct the model to invoke `ai/scripts/helpers/sync_step_lars.sh <step> ai/step_plans/step-<N>.md` for artifact-side syncing of the section into the step plan instead of echoing the block textually.
- [ ] 2.2 Add the fetch-as-clarification-input rule line to the planning prompt: model SHALL fetch each in-scope LAR locator using its available web/MCP tooling at the start of context-gathering, treat fetched content as one more context input alongside `overmind/implementation_plan.md`, `overmind/reqirements_ears.md`, the design artifact, and ADRs, and route any fetch failure through existing ask-user mechanisms (`ai/open_questions.md`, `ai/blocker_log.md`, two-option prompts) using the standard "cannot resolve LAR-NNN (locator: ...). How should I proceed?" question pattern.
- [ ] 2.3 Suppress the planning fetch rule line and the section block when the design artifact has no in-scope LAR entries.
- [ ] 2.4 Update `ai/templates/step_plan_TEMPLATE.md` and `ai/golden_examples/step_plan_GOLDEN_EXAMPLE.md` to include the `## Linked Artifacts (in scope)` section using the same canonical line format as the design template.

## 3. Inject the shortlist and the fetch-for-visual-fidelity rule into implementation

- [ ] 3.1 Extend `ai/scripts/ai_implementation.sh` to read `## Linked Artifacts (in scope)` from `ai/step_plans/step-<N>.md` and inject it byte-equivalently into the implementation prompt packet at a fixed deterministic position.
- [ ] 3.2 Add the single fetch-for-visual-fidelity rule line to the implementation prompt: model SHALL fetch each in-scope LAR locator using its available web/MCP tooling before implementing FRs that reference it, use the fetched content as source of truth for visual fidelity, exact spacing, icons, hover states, micro-interactions, mobile breakpoints, illustration crops, and other pixel/asset details that FR text cannot fully encode, and stop and ask the user when fetch fails or fetched content is ambiguous.
- [ ] 3.3 Suppress the implementation fetch rule line and the section block when the step plan has no in-scope LAR entries.

## 4. Add the LAR reachability helper and wire it into both readiness gates

- [ ] 4.1 Add `ai/scripts/helpers/check_lar_reachability.sh <step>` that reads `## Linked Artifacts (in scope)` from `ai/step_plans/step-<N>.md`, probes each locator (HTTP HEAD with redirect follow, GET fallback, fixed short timeout per locator), and exits non-zero on any unreachable locator with the offending LAR ID and URL printed to stderr.
- [ ] 4.2 Treat empty/missing `## Linked Artifacts (in scope)` as exit-`0` and missing step plan as exit-non-zero, matching the spec scenarios.
- [ ] 4.3 Treat non-HTTP(S) locators as unreachable in this iteration (deferring richer locator-type support).
- [ ] 4.4 Wire `ai/scripts/helpers/check_lar_reachability.sh` into `ai/scripts/helpers/check_planning_readiness.sh` so its non-zero exit propagates as a planning-readiness failure that blocks planning closure.
- [ ] 4.5 Wire `ai/scripts/helpers/check_lar_reachability.sh` into `ai/scripts/helpers/check_implementation_readiness.sh` so its non-zero exit propagates as an implementation-readiness failure (drift detection between phases).

## 5. Documentation

- [ ] 5.1 Update `ai/AI_DEVELOPMENT_PROCESS.md` Section 1 (Design): add one bullet stating design extracts and propagates the per-step LAR shortlist and does not fetch.
- [ ] 5.2 Update `ai/AI_DEVELOPMENT_PROCESS.md` Section 2.1 (Planning): add one bullet stating planning mirrors the design's `## Linked Artifacts (in scope)` block verbatim AND fetches in-scope LARs as one more context input for the existing clarification loop, with the standard "cannot resolve LAR-NNN" question pattern routed through existing ask-user mechanisms.
- [ ] 5.3 Update `ai/AI_DEVELOPMENT_PROCESS.md` Section 3.1 (Implementation): add one bullet with the fetch-for-visual-fidelity rule from Decision 4.
- [ ] 5.4 Update the artifact roles list in `ai/AI_DEVELOPMENT_PROCESS.md` to mention LAR flow from design through plan into implementation.
- [ ] 5.5 Update `Readme.md` worker cycle description to mention the LAR flow path across design, planning (fetch as clarification input), and implementation (fetch for visual fidelity).

## 6. Tests

- [ ] 6.1 Add `tests/ai_scripts/` coverage for `ai/scripts/ai_design.sh` LAR funnel: bullets reference LAR-tagged REQs, bullets reference no LAR-tagged REQs, multiple LARs deduped and ordered, referenced LAR missing from registry.
- [ ] 6.1a Add coverage for `ai/scripts/helpers/sync_step_lars.sh`: target artifact lacks the section (helper appends it), target artifact already has the section (helper replaces idempotently), step has no LARs (no-op leaves no section or empty section), repeated invocations produce byte-equivalent output.
- [ ] 6.2 Add coverage for `ai/scripts/ai_plan.sh` planning prompt + sync helper invocation + planning fetch rule presence/absence: non-empty shortlist, empty/absent shortlist, no re-parsing of `overmind/reqirements_ears.md`.
- [ ] 6.3 Add coverage for `ai/scripts/ai_implementation.sh` injection + implementation fetch rule presence/absence: shortlist position, byte-determinism across runs.
- [ ] 6.4 Add coverage for `ai/scripts/helpers/check_lar_reachability.sh`: HTTP 200, redirect chain, 404, timeout, empty section, missing step plan, non-HTTP(S) locator, 200-login-page treated as reachable.
- [ ] 6.5 Add coverage for `ai/scripts/helpers/check_planning_readiness.sh` inheriting the LAR reachability failure (planning closure blocked).
- [ ] 6.6 Add coverage for `ai/scripts/helpers/check_implementation_readiness.sh` inheriting the LAR reachability failure (implementation entry blocked, drift detection).
- [ ] 6.7 Run the relevant `tests/ai_scripts/` suites from repo root and confirm the new contract is covered.
