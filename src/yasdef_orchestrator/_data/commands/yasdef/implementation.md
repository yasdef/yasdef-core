---
description: Run the YASDEF ASDLC worker implementation phase via the yasdef-worker-implementation skill.
---

Use the `yasdef-worker-implementation` skill to run the ASDLC worker implementation phase.

Inputs:
- Step: $1
- Feature id: $2
- Branch: $3
- Step plan: $4
- Design artifact: $5
- Runtime implementation plan: $6

If any of the six inputs above is missing, empty, or points to a missing required file, stop and ask the user for the missing input. Do not read `.asdlc_worker/feature_meta_sync.yaml` and do not infer any of the six inputs from runtime context.
