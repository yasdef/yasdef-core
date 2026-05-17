## Context

LAR (Linked Artifact) locators flow from `requirements_ears.md` through design and planning into implementation via `sync_step_lars.sh`. Currently both planning (`ai_plan.sh`) and implementation (`ai_implementation.sh`) fire MCP fetches to resolve LAR content. The planning fetch was added to give the planner UI/schema detail when writing the step plan, but EARS requirements already encode all behavioral constraints the planner needs — LAR content is implementation-level detail (pixel specs, field names, error codes) that belongs at the implementation stage.

Two code sites drive the planning-phase fetch behavior:
- `ai_plan.sh` line 692: injects `Fetch rule (planning): ...` into the planning prompt
- `AI_DEVELOPMENT_PROCESS.md` line 106: describes the fetch as part of the planning step

## Goals / Non-Goals

**Goals:**
- Remove the fetch rule injection from the planning prompt in `ai_plan.sh`
- Update `AI_DEVELOPMENT_PROCESS.md` to reflect planning as propagation-only
- Keep the `sync_step_lars.sh` invocation instruction and the LAR context-pack section in the planning prompt unchanged — the planner still sees the shortlist, just doesn't fetch content

**Non-Goals:**
- Any change to `ai_implementation.sh` (implementation fetch is unchanged)
- Any change to `sync_step_lars.sh` or the LAR funnel pipeline
- Any change to design-phase behavior (design already explicitly prohibits fetching)

## Decisions

**Remove fetch rule only, keep LAR section in context pack.**
Lines 728–733 of `ai_plan.sh` pass the design's `## Linked Artifacts (in scope)` section into the context pack. This is informational (the planner sees locators for awareness) and costs no MCP calls — keep it. Only line 692 (the `Fetch rule (planning):` printf) is removed. The surrounding `if [[ -n "$DESIGN_LAR_SECTION" ]]; then` block on line 690–693 shrinks to one printf call (line 691 for `sync_step_lars.sh` invocation).

**Single-line process doc update.**
`AI_DEVELOPMENT_PROCESS.md` line 106 currently reads: *"Mirror the design's `## Linked Artifacts (in scope)` block verbatim into the step plan via `sync_step_lars.sh`; also fetch each in-scope LAR locator..."*. The `; also fetch ...` clause and everything after it on that bullet is removed.

## Risks / Trade-offs

[Planner missing LAR-encoded architectural constraints] → Mitigated by the EARS requirements process: any constraint that affects plan structure must be captured as a REQ block in `requirements_ears.md`. If a LAR holds an undocumented constraint not reflected in EARS, the implementor will catch it at fetch time and can flag it as a plan deviation. This is an acceptable trade-off and an incentive to keep EARS requirements complete.

[Stale LAR content at implementation] → Not introduced by this change; implementation already fetches fresh at JIT time.
