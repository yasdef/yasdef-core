## Context

The orchestrator's `analyze_feature_plan_for_worker` function (orchestrator.sh ~L884) is an awk script that scans `implementation_plan.md` to find the first assigned step with an unchecked bullet. The plan format already includes an `#### Depends on:` field per step block (documented in Readme.md and the plan template), but the awk currently ignores it — it never checks whether dep steps are complete before selecting the next step. The result: a worker can pick up a step whose cross-team dependencies (e.g. OpenAPI contract from the backend team) are not yet done.

## Goals / Non-Goals

**Goals:**
- Skip any assigned step whose `#### Depends on:` references a step that is not fully `[x]` (zero remaining unchecked bullets).
- Exit non-zero with a human-readable `blocked by <dep-id>` message when all assigned steps are blocked.
- Fail fast with a plan error when a dep id references a step that does not exist in the plan.
- Fail fast with a plan error when a dep step has zero bullets (cannot be "fully done").
- Treat `Depends on: none` or a missing `#### Depends on:` line as "no deps" — step is always eligible.

**Non-Goals:**
- `--resume` handling — no change to resume path.
- Cross-plan dependency resolution — deps must exist in the same `implementation_plan.md`.
- Cycle detection — not in scope.

## Decisions

### Decision 1: Add dep check inside `analyze_feature_plan_for_worker`, not a separate pass

The awk already reads the entire plan in one pass. Extending it to collect per-step bullet counts and dep lists in arrays (indexed by step number) lets the `END` block compute satisfaction without a second file read.

**Alternative considered:** A separate bash pre-pass that builds a dep-satisfaction map and passes it via an awk variable. Rejected — requires reading the file twice and adds a new public function with its own error-surface.

### Decision 2: Single-pass awk with array collection

Collect during the scan:
- `step_order[]` — ordered list of step ids seen
- `dep_list[step]` — raw `Depends on:` value (empty string if line absent, `"none"` if explicitly none)
- `has_dep_line[step]` — 1 if `#### Depends on:` line was present
- `bullet_count[step]` — total `- [ ]` + `- [x]` bullets
- `unchecked_count[step]` — count of `- [ ]` bullets
- `assigned_to_worker[step]` — 1 if `#### Assigned:` matches worker UUID

In `END`: for each step in order, if assigned and has unchecked bullets, check all dep ids for satisfaction. First step that passes is `first_unchecked`. If none passes, emit blocked_by.

### Decision 3: Extend output format to carry blocked_by info

Current output: `assigned_any|requested_match|first_unchecked`
New output: `assigned_any|requested_match|first_unchecked|blocked_by`

`blocked_by` is empty when a step is found or when there are no assigned steps at all. It is set to the first unsatisfied dep id encountered when all assigned-with-work steps are blocked.

Callers already do `IFS='|' read -r assigned_any requested_match first_unchecked` — adding a fourth field is backwards-compatible; callers that don't read it ignore it.

### Decision 4: Plan errors exit non-zero immediately from awk via `exit 2`

An unknown dep id or a zero-bullet dep step is a plan authoring error, not a runtime blocked state. The awk emits a message to stderr and calls `exit 2`; the calling bash function propagates the non-zero exit without emitting a confusing "blocked by" message.

## Risks / Trade-offs

- **Dep parsing depends on exact `#### Depends on:` formatting** → Mitigation: match with `/^#### Depends on:[[:space:]]*/` (tolerates trailing spaces); document expected format in spec.
- **Multi-dep `Depends on:` values need a delimiter** → The existing readme example shows `Depends on: none` (single value). The spec must clarify that multiple deps are comma-separated; parsing splits on `,` and trims whitespace.
- **Awk array iteration order** → awk arrays are unordered; `step_order[]` (an indexed array filled in scan order) is used for deterministic step traversal in `END`.
