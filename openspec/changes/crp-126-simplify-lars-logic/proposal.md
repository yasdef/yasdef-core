## Why

Planning-phase LAR fetching via MCP duplicates the fetch that already happens at implementation time, consuming tokens without adding value — EARS requirements encode all behavioral constraints the planner needs, while LAR content (Confluence pages, Figma files, API schemas) is implementation-level detail best consumed just-in-time.

## What Changes

- Remove the LAR content fetch from the planning phase (`ai_plan.sh`): the planning prompt no longer injects a fetch rule or fires MCP calls for LAR locators.
- Keep the LAR shortlist propagation at planning: `sync_step_lars.sh` still mirrors the design's `## Linked Artifacts (in scope)` block verbatim into the step plan — locators remain present for implementation to consume.
- Implementation-phase LAR fetch remains unchanged: `ai_implementation.sh` still fetches each in-scope LAR locator just-in-time before implementing any FR that references it.
- Update `AI_DEVELOPMENT_PROCESS.md` line 106 to drop the fetch instruction from the planning step description, retaining only the `sync_step_lars.sh` mirroring instruction.

## Capabilities

### New Capabilities
- `lar-jit-fetch-scope`: Defines the authoritative rule that LAR content is fetched only at implementation phase, not at planning phase; planning is limited to mechanical LAR shortlist propagation via `sync_step_lars.sh`.

### Modified Capabilities
<!-- none -->

## Impact

- `ai/scripts/ai_plan.sh`: remove fetch-rule injection and LAR section pass-through from planning prompt.
- `ai/AI_DEVELOPMENT_PROCESS.md`: update planning step (line 106) to remove fetch instruction.
- No change to `ai/scripts/ai_implementation.sh`, `ai/scripts/helpers/sync_step_lars.sh`, or any test contracts.
