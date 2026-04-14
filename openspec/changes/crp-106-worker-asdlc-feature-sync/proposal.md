## Why

Worker execution now depends on feature-scoped coordinator artifacts stored in ASDLC project folders, but the worker-side orchestrator still discovers work from legacy local `overmind/` artifacts and legacy identity files. That mismatch makes step selection unreliable and leaves `ai_design` without a hard guarantee that feature `requirements_ears.md` is present before design starts.

## What Changes

- Bind each worker repo to an ASDLC project source and registered worker UUID, while keeping current-feature selection separate from the durable project binding.
- Change worker next-step discovery to scan ASDLC feature folders under the bound project, find `implementation_plan.md` entries assigned to the bound worker UUID, and resolve work per feature rather than from a single local branch-scoped plan.
- Require orchestrator to build a candidate feature set from ASDLC feature folders that contain worker-assigned work for the bound worker UUID.
- Require orchestrator to select one active feature per run using an explicit rule: fail fast when no candidate features exist, auto-select when exactly one candidate feature exists, and ask the user to choose when multiple candidate features exist.
- Require orchestrator to mirror the selected feature's `implementation_plan.md` and `requirements_ears.md` into local `overmind/` on branch `overmind`, and record local feature-sync metadata for traceability and resume continuity.
- Reuse recorded local feature-sync metadata on `--resume <step>` when it still points to a valid feature/step context, so orchestrator does not re-prompt during a normal in-progress resume.
- Fail fast when the selected ASDLC feature does not provide a usable `requirements_ears.md`; `ai_design` must not run without that mirrored EARS artifact.
- Keep worker phase scripts operating on local `overmind/` paths after sync so the existing phase contract remains stable.
- Treat mirrored local `overmind/implementation_plan.md` as a worker runtime copy and ASDLC feature artifacts as the source of truth for feature selection and coordinator-owned inputs.
- Define sync-back behavior for worker-owned plan updates so local planning/audit changes to `implementation_plan.md` can be propagated back to the selected ASDLC feature artifact.
- **BREAKING**: implicit next-step discovery from legacy `ai/*_dont_touch.txt` plus local `overmind/implementation_plan.md` is replaced by ASDLC project/feature discovery driven by the worker binding artifact.

## Capabilities

### New Capabilities
- `worker-asdlc-feature-sync`: Worker orchestration resolves assigned feature work from an ASDLC project, mirrors the selected feature's coordinator artifacts into local `overmind/`, and tracks current feature sync state separately from durable project binding.

### Modified Capabilities
- `worker-project-overmind-binding`: Worker binding requirements change from generic overmind-source binding to ASDLC project binding metadata that supports project-level worker registration and separate current-feature state.
- `orchestrator-worker-assigned-step-routing`: Next-step discovery changes from legacy local identity files and one local plan source to ASDLC project/feature scanning with worker-assigned step filtering and explicit feature selection when needed.
- `design-as-contract-phase-boundaries`: Design entry requirements change so mirrored `requirements_ears.md` from the selected ASDLC feature is mandatory and missing EARS blocks design handoff.
- `overmind-process-artifact-ownership`: Coordinator artifact ownership changes so ASDLC project feature folders are the source of truth, while local worker `overmind/` files are synchronized runtime copies.

## Impact

- Affected code:
  - `ai/scripts/init_worker.sh`
  - `ai/scripts/orchestrator.sh`
  - `ai/scripts/ai_design.sh`
  - phase helpers and post-review sync logic that read or write `overmind/implementation_plan.md`
- Affected local worker artifacts:
  - `ai/project_overmind.yaml`
  - new current-feature sync/cache metadata under `ai/`
  - local mirrored `overmind/implementation_plan.md`
  - local mirrored `overmind/reqirements_ears.md`
- Affected external source-of-truth system:
  - ASDLC project folders under `projects/<project-id>/<feature-id>/`
  - project worker registry `projects/<project-id>/workers.yaml`
- Affected docs/tests:
  - worker setup and orchestrator README guidance
  - routing, sync, and design-gate shell tests under `tests/ai_scripts/`
