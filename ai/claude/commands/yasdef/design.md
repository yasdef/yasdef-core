---
description: Run the YASDEF ASDLC worker design phase via the yasdef-worker-design skill.
---

Use the `yasdef-worker-design` skill to run the ASDLC worker design phase.

Inputs:
- Step: $1
- Feature id: $2
- Branch: $3
- Design output: $4
- Runtime implementation plan: $5
- Runtime requirements EARS: $6

If any of the six inputs above is missing, empty, or points to a missing required file, stop and ask the user for the missing input. Do not read `.asdlc_worker/feature_meta_sync.yaml` and do not infer any of the six inputs from runtime context.
