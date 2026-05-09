## Context

`overmind/reqirements_ears.md` already carries external artifact references in two coordinated places: a document-level `## Linked Artifacts` registry at the bottom (entries shaped as `id: LAR-NNN | title | type | locator`) and per-requirement `**Linked Artifacts:** LAR-NNN` lines under selected `### Requirement N` blocks. The propagation contract is owned by overmind's `br_to_ears.md` rule.

The worker side (this repo) reads `overmind/reqirements_ears.md` only at two boundary phases — Design (`ai/scripts/ai_design.sh`) and ai_audit (`ai/scripts/ai_audit.sh`). Today `ai_design.sh` extracts only `### Requirement N` blocks matched by `[REQ-X]` tags discovered in step bullets and discards everything else, including the registry and the per-requirement LAR lines. Planning, Implementation, User Review, ai_audit, and post_review have zero awareness of LARs.

Two phases need LAR content for distinct concerns:

| Phase | Fetches LAR for | Becomes part of |
|---|---|---|
| Planning | Structure, copy, field shapes, decision-driving content (menu sections, schema fields, error codes) | FR text + clarification loop |
| Implementation | Visual fidelity, spacing, icons, exact pixel/asset details that text can't faithfully encode | Code |

The user's decisions are:
- Filter LARs strictly by step (step bullets → `[REQ-X]` tags → `### Requirement N` blocks → `**Linked Artifacts:**` lines → registry lookup) — not by document.
- Pass the funneled subset through Design → Plan → Implementation as a propagated, never-re-derived shortlist.
- Have planning fetch in-scope LARs as one more context input for the existing clarification loop. The loop is unchanged: fetched content participates exactly like `overmind/implementation_plan.md`, `overmind/reqirements_ears.md`, design artifact, ADRs, etc. The only new question pattern is "cannot resolve LAR-NNN — how should I proceed?", which flows through existing ask-user mechanisms.
- Have implementation also fetch in-scope LARs, but for a different purpose: visual/detail fidelity that text-form FRs cannot fully encode no matter how diligent planning was.
- Use a single reachability probe helper at both phase boundaries: planning closure (catches unfetchable links while the user is still in the loop) and implementation entry (catches drift between phases).

## Goals / Non-Goals

**Goals:**
- Make LARs flow deterministically from `overmind/reqirements_ears.md` to both planning and implementation prompts, scoped per step.
- Keep the Design phase as the single funnel point so downstream phases never re-traverse `overmind/reqirements_ears.md`.
- Let planning use fetched LAR content like any other context input — answer questions, raise new ones, drive decisions, inform FR translation — without changing the existing clarification loop's mechanics.
- Force implementation to use real fetched content for visual/detail fidelity instead of inventing pixel-level details when a LAR is in scope.
- Surface unreachable locators at planning closure (so the user can stage content while still actively engaged) and re-validate at implementation entry (drift detection).
- Leave behavior for steps with no LAR-tagged requirements completely unchanged.

**Non-Goals:**
- No caching, snapshotting, or local pre-staging of fetched content (acknowledged determinism trade-off; deferred to a follow-up change).
- No new CLI flags or orchestrator modes.
- No changes to overmind: `br_to_ears.md`, `feature_br_summary.md`, and EARS templates stay as-is.
- No new clarification-loop subroutines: planning treats fetched LAR content as just another input source, not a special artifact requiring its own confirmation step.
- No introduction of LAR awareness into ai_audit or post_review beyond what already passes through `overmind/reqirements_ears.md` at audit time.
- No per-FR `LAR[LAR-NNN]` annotation on translated functional requirements; the section + per-requirement EARS lines are sufficient signal.

## Decisions

### Decision 1: Funnel LARs strictly per step, in `ai_design.sh`, as a third filter stage

The funnel is step-driven and cascading:
1. Step bullets in `overmind/implementation_plan.md` (already collected at `ai_design.sh:24-149`) yield `[REQ-X]` tags (already done at `ai_design.sh:166-194`).
2. Matching `### Requirement N` blocks are extracted from `overmind/reqirements_ears.md` (already done at `ai_design.sh:155-164`).
3. **NEW**: scan only those extracted blocks for lines matching `**Linked Artifacts:**` followed by `LAR-NNN` IDs; collect the unique ID set.
4. **NEW**: look up each collected ID in the bottom `## Linked Artifacts` registry of `overmind/reqirements_ears.md` and capture `id | type | title | locator`.
5. **NEW**: emit a `## Linked Artifacts (in scope)` block in the design prompt context, formatted as `- LAR-NNN | <type> | <title> | <locator>` (one line per LAR, deterministic ordering by ascending numeric ID).

Rationale: this is the natural extension of the existing two-stage filter and keeps the funnel single-pass. Doing it inside `ai_design.sh` rather than in a separate helper keeps the data path close to where the REQ filter already runs and avoids an additional shell script crossing.

Alternative considered: build a standalone `helper_collect_step_lars.sh`. Rejected because every call site would still need to re-derive `[REQ-X]` tags from step bullets and re-parse `overmind/reqirements_ears.md` — duplication that the in-script approach avoids.

### Decision 2: A dedicated sync helper writes the section into design and step-plan artifacts; downstream phases never re-derive

A new helper `ai/scripts/helpers/sync_step_lars.sh <step> <target-artifact-path>` recomputes the LAR funnel from `overmind/implementation_plan.md` + `overmind/reqirements_ears.md` and idempotently writes/replaces a `## Linked Artifacts (in scope)` section in the target artifact. The design model is instructed to invoke the helper with the design artifact path (`ai/step_designs/step-<N>-design.md`) at the appropriate point in the design phase. The planning model is instructed to invoke the same helper with the step plan path (`ai/step_plans/step-<N>.md`) instead of textually mirroring the section. `ai_implementation.sh` reads the section from the step plan and injects it into the implementation prompt.

Rationale: model echoing of structured content is unreliable — formatting drift, missed lines, accidental rewording. A helper makes section landing deterministic and keeps the funnel logic centralized in one tested place. `ai_design.sh` still emits the block into prompt context so the model can reason about LARs during analysis; the helper handles the artifact-side write. The same helper is reused at the planning step to sync the same canonical section into the step plan, eliminating mirror-correctness concerns. A step with no LARs naturally produces an empty/omitted section through the helper without conditional logic.

Alternative considered: have the model echo the block verbatim in both phases. Rejected because byte-equivalent text echoing is the kind of task models reliably get slightly wrong; deterministic helpers are the established pattern across the framework (`check_design_readiness.sh`, `check_planning_readiness.sh`, `helper_find_blueprints.sh`).

### Decision 3: Planning fetches as one more context input for the existing clarification loop

The planning prompt instructs the model to fetch each in-scope LAR locator using its available web/MCP tooling at the start of context-gathering, alongside reading `overmind/implementation_plan.md`, `overmind/reqirements_ears.md`, the design artifact, and ADRs. Fetched content participates in the existing clarification loop on equal footing with every other input source: it can answer model questions, surface new ones, drive `## Things to Decide`, contribute to FR translation, and feed gap discovery.

The loop's mechanics do not change. There is no new "summarize fetched content and confirm with user" subroutine, no new artifact section for LAR summaries, no new prompt subroutine. The single new question pattern is "cannot resolve LAR-NNN (locator: ...). How should I proceed?", which flows through the existing ask-user mechanisms (`ai/open_questions.md`, `ai/blocker_log.md`, two-option prompts). The user's resolution paths — paste content directly, supply an alternate URL, or remove the LAR reference upstream — feed back into the loop the same way any other user answer does.

When a LAR is the load-bearing source for an FR, the FR text references it explicitly: e.g., "FR-1.5-003 The system SHALL render the main menu with sections Categories, Bestsellers, Membership, More — see LAR-002." The reference is informational provenance; the FR remains self-contained per the existing canonical FR template.

Rationale: planning is already the interactive Q&A phase. Fitting LAR fetch into that pattern preserves all the framework's existing gates (open questions, things-to-decide, decisions, two-option prompts) and avoids inventing parallel ceremony. Catching unfetchable links at planning closure means the user is still actively engaged and can stage content before any code is written.

### Decision 4: Implementation also fetches, for visual/detail fidelity that FRs cannot encode

Even when planning has fetched a LAR, used it during clarification, and written detailed FRs that reference it, text-form FRs lose information that visual artifacts carry: exact spacing, icons, colors, hover states, micro-interactions, mobile breakpoints, illustration crops, asset cropping. Implementation must therefore also fetch each in-scope LAR locator and use the fetched content as source of truth for visual/detail fidelity that FRs cannot fully express.

The implementation prompt contract carries one explicit rule: before implementing any FR that references a LAR-NNN, fetch the locator using available web/MCP tooling and use the fetched content as source of truth for visual/detail fidelity. If a fetch fails or content is ambiguous, stop and ask the user — never invent visual/detail content.

By the time implementation starts, planning has already proven the link is reachable, so fetch failures here are rarer and usually mean content drifted between phases (deleted, moved behind auth, URL revoked). The "stop and ask" rule handles this without inventing surrogate content.

Rationale: the user's framing is precise — "you never explain design mock detailed enough, it'll always be a loss of quality, so plan should explain 'create main menu with section Categories, Bestsellers, Membership, More, based on provided design mock' (link to design mock)." Both phases need fetch, for separate concerns: planning for structure/content/decisions, implementation for visual fidelity.

### Decision 5: Single reachability probe helper, two enforcement points

A new `ai/scripts/helpers/check_lar_reachability.sh <step>` reads `## Linked Artifacts (in scope)` from `ai/step_plans/step-<N>.md`, probes each locator (HTTP HEAD with redirect follow, GET fallback if HEAD is rejected, fixed short timeout per locator), and exits non-zero on any unreachable locator with the offending LAR ID and URL printed to stderr. Both `ai/scripts/helpers/check_planning_readiness.sh` and `ai/scripts/helpers/check_implementation_readiness.sh` invoke this helper as part of their existing checks.

At planning closure, a non-zero exit blocks the planning completion line; the user must resolve the unfetchable LAR through the clarification loop (paste content, supply alternate URL, or remove the upstream reference) before planning can close. At implementation entry, a non-zero exit blocks the implementation prompt from being generated; this catches drift between phases (the link was reachable when planning closed but is no longer reachable now).

Rationale: keeps the reachability concept isolated in a small testable helper; reuses the existing two-helper enforcement model already established by `planning-to-implementation-readiness-gate`; makes a step with no LARs short-circuit both helpers to a no-op (exit 0) without conditional logic.

### Decision 6: Reachability gate semantics — "URL responds", not "model can read content"

The probe succeeds when the locator returns any non-error HTTP status (2xx/3xx after redirect chain). It does not attempt authentication, content sniffing, or model-readability checks. A Confluence URL that returns a 200 login page is treated as reachable.

Rationale: deeper checks would require credentials per LAR type (Figma token, Confluence cookie, etc.) which is out of scope. The framework already has a fallback rule for "fetched content is ambiguous" — Decisions 3 and 4's "stop and ask the user" sentences catch login-wall and 404-but-200-shell cases at runtime in their respective phases.

### Decision 7: Empty/missing section is a valid no-op everywhere

Steps whose extracted `### Requirement N` blocks contain no `**Linked Artifacts:**` field produce an empty `## Linked Artifacts (in scope)` section (or omitted entirely — both forms accepted at parse time). Templates allow the section to be present-but-empty so planning/impl never misinterpret missing content as a contract violation. Both reachability invocations exit 0 immediately when the section is empty/absent.

Rationale: most steps will not reference LARs. The change must be invisible in those cases, both in prompt size and in gate behavior.

### Decision 8: AI_DEVELOPMENT_PROCESS.md gets minimal additions in three sections

- Section 1 (Design): one bullet — extract & propagate per-step LAR shortlist; do not fetch.
- Section 2.1 (Planning): one bullet — mirror the design's `## Linked Artifacts (in scope)` verbatim into the step plan AND fetch in-scope LARs as one more context input for the existing clarification loop; raise the standard "cannot resolve LAR-NNN" question through existing ask-user mechanisms when fetch fails.
- Section 3.1 (Implementation): one bullet — fetch in-scope LARs for visual/detail fidelity that FR text cannot fully express, and stop to ask the user instead of inventing visual/detail content when fetch fails or content is ambiguous.

Sections 2.2 (Plan quality gates) and 4.2 (Implementation Readiness Gate) inherit the reachability check via the helpers without prose changes. The Artifacts and roles section gets one line about LAR flow.

Rationale: keeps the process doc edit small and avoids creating a parallel "Linked Artifacts" mini-section that would duplicate phase ownership.

## Risks / Trade-offs

- **Risk:** Codex CLI (or whichever model session is used) may not have web/MCP fetch capability available in either planning or implementation; the model will say "I cannot fetch" mid-phase.
  - **Mitigation:** in planning, the existing clarification loop absorbs this as a normal user question. In implementation, the explicit fetch-and-don't-invent rule directs the model to stop and ask. A user_review.md UR rule will likely emerge after first runs to record the preferred fetch path per type.

- **Risk:** Reachability gate passes but the URL returns a login wall or stale content; the model fetches an unhelpful HTML shell and either bakes nothing into FRs (planning) or codes against an empty shell (implementation).
  - **Mitigation:** Decisions 3 and 4's "stop and ask the user when content is ambiguous" rules are the enforcement points in each phase. The gate is a coarse sanity check, not a content validator.

- **Risk:** Determinism regression — two fetch windows widen the drift surface compared to a single-fetch model. Same step run on Mon vs Wed against the same `overmind/reqirements_ears.md` may produce different FRs (planning) and different visual implementations (implementation).
  - **Mitigation:** acknowledged, deferred. A follow-up change can add `ai/lar_cache/<step>/<LAR-NNN>.<ext>` snapshots with `--resume` replay; the cache would feed both phases from the same frozen snapshot. No prompt or section contracts in this change need to move to support that follow-up.

- **Risk:** Drift between planning and implementation — link was reachable at planning closure but moved/auth-walled by the time implementation starts.
  - **Mitigation:** the reachability helper runs again at implementation entry (Decision 5). The user gets the same hard-fail with offending LAR ID and URL, before any code is generated.

- **Risk:** Duplicate or inconsistent registry entries inside `overmind/reqirements_ears.md` (e.g., two LAR-001 with different locators) would propagate into the design prompt verbatim.
  - **Mitigation:** the funnel does a registry-side dedup by ID at extraction time and emits the first registry hit; a CRP-041-style hygiene gate is out of scope here and remains overmind's responsibility (`br_to_ears.md`).

- **Risk:** Reachability gate slows phase transitions when a step has many LARs or a slow remote (now triggered twice per step).
  - **Mitigation:** fixed short per-locator timeout (5s default), parallelizable inside the helper if needed; gate runs once per phase transition, not per FR.

- **Risk:** Locators that are not HTTP(S) URLs (e.g., file paths, Jira IDs) leak through the registry.
  - **Mitigation:** the helper treats non-HTTP(S) locators as unreachable by default and prints the offending LAR ID; the user can fix the registry entry in overmind. Lenient extension to support file paths is a candidate follow-up.

- **Risk:** Planning adds fetch overhead and clarification cycles for steps with many LARs, lengthening time-to-implementation.
  - **Mitigation:** acknowledged trade-off. The user's reasoning — catching gaps and unreachable links while the user is still actively engaged is materially cheaper than discovering them mid-implementation — applies. The per-step REQ filter already bounds the LAR set; no length cap is introduced in this change.

## Implementation Outline

1. Extend `ai/scripts/ai_design.sh` with the third-stage LAR funnel: parse `**Linked Artifacts:**` lines from already-extracted REQ blocks, dedup IDs, look up entries in the bottom `## Linked Artifacts` registry of `overmind/reqirements_ears.md`, and emit a `## Linked Artifacts (in scope)` context block.
2. Add `ai/scripts/helpers/sync_step_lars.sh <step> <target-artifact-path>` that recomputes the funnel and idempotently writes/replaces the `## Linked Artifacts (in scope)` section in the target artifact (handles empty/missing case as a no-op).
3. Instruct the design prompt to call the sync helper with the design artifact path so the section lands in `ai/step_designs/step-<N>-design.md` deterministically.
4. Update `ai/templates/feature_design_TEMPLATE.md` and its golden example to include the section with the canonical line format.
5. Extend `ai/scripts/ai_plan.sh` to: instruct the planning prompt to call the same sync helper with the step plan path so the section lands in `ai/step_plans/step-<N>.md` deterministically; add the fetch-as-clarification-input rule line (instructing the model to fetch in-scope LARs at start of context-gathering and to raise the standard "cannot resolve" question through existing mechanisms on failure). Update `ai/templates/step_plan_TEMPLATE.md` and golden example to include the section.
6. Extend `ai/scripts/ai_implementation.sh` to inject the section from the step plan into the implementation prompt and add the fetch-for-visual-fidelity rule line.
7. Add `ai/scripts/helpers/check_lar_reachability.sh <step>` that probes each locator and exits non-zero with offending LAR ID + URL on any unreachable target; treat empty/missing section as exit 0.
8. Wire the new helper into `ai/scripts/helpers/check_planning_readiness.sh` and `ai/scripts/helpers/check_implementation_readiness.sh` so both readiness gates inherit reachability transparently.
9. Update `ai/AI_DEVELOPMENT_PROCESS.md` Sections 1, 2.1, 3.1, and the artifact roles list.
10. Add targeted shell tests for: design extraction (LARs present / LARs absent / mixed), `sync_step_lars.sh` idempotency (create / replace / empty / no-op), plan mirror correctness via helper + planning fetch rule, implementation prompt injection + implementation fetch rule, reachability gate (HTTP 200, redirect, 404, timeout, empty section), and inheritance of the reachability check by both readiness helpers.

## Open Questions

- Should the reachability gate distinguish between "transient network failure" (retry suggested) and "permanent 404/auth" (fix required)? Current decision treats both as failures with the same exit code; can be refined if false positives become noisy.
- Should non-HTTP(S) locators (file paths, Jira IDs) be supported in this change or deferred? Current decision is to treat them as unreachable; revisit after first real-world runs.
- Should an in-scope LAR shortlist length cap (similar to UR shortlist's max=8 in CRP-039) be introduced to keep prompts predictable across two fetching phases? Likely unneeded for now since the per-step REQ filter already bounds it.
