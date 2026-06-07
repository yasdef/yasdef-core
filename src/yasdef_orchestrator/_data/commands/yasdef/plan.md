---
description: Run the YASDEF ASDLC worker planning phase via the yasdef-worker-plan skill.
---

Use the `yasdef-worker-plan` skill to run one ASDLC worker planning iteration.

Inputs:
- Step: $1
- Feature id: $2
- Branch: $3
- Design artifact: $4
- Step plan output: $5
- Runtime implementation plan: $6
- Open questions ledger: $7
- Blockers ledger: $8

If any of the eight inputs above is missing, empty, or points to a missing required file, stop and ask the user for the missing input. Do not read `.asdlc_worker/feature_meta_sync.yaml` and do not infer any of the eight inputs from runtime context.
