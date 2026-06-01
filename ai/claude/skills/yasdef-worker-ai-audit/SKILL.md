---
name: yasdef-worker-ai-audit
description: Run the YASDEF ASDLC worker ai_audit phase for an assigned step. Use when the orchestrator or user asks to perform post-user-review analysis-only audit, produce findings, disposition each finding to a terminal state, and finish audit handoff before post_review.
metadata:
  short-description: YASDEF worker ai_audit phase
---

# YASDEF Worker AI Audit

Use this skill for the ASDLC worker ai_audit phase. This phase is analysis-only: do not modify runtime code and do not run tests.

## Inputs

The orchestrator prompt should provide:
- step id, for example `1.6`
- feature id
- branch name
- step plan path
- design artifact path
- runtime implementation plan path
- worker id

If any input is missing, inconsistent, or points to a missing required file, do not infer it from `.asdlc_worker/feature_meta_sync.yaml` or the runtime environment. Stop and ask the user for explicit instructions.

## Workflow

1. Run the entry gate as the first action:
   ```bash
   uv run python .claude/skills/yasdef-worker-ai-audit/scripts/check_ai_audit_entry.py --step <step> --feature-id <feature-id>
   ```
   If it exits non-zero, stop and report the failed preconditions.

2. Build context:
   ```bash
   uv run python .claude/skills/yasdef-worker-ai-audit/scripts/build_ai_audit_context.py --step <step> --feature-id <feature-id> --design <design-file> --runtime-plan <runtime-plan> --worker-id <worker-id>
   ```

3. Read the printed context before reviewing. The step design artifact is the single context source. Use only:
- `## Target Bullets (excluding planning/review)`
- `## Selected EARS Requirements (for planning translation)`
- `## Goal`
- `## In Scope`
- `## Out of Scope`
- `## Linked Artifacts (in scope)`

4. Phase 1 - Discovery (single pass):
- Review the current patch via `git status` and `git diff`.
- Write all findings in one pass to `step_review_results/review_result-<step>-<feature>.md`.
- Each finding must include severity, recommendation (`FollowupStep` or `RiseToCoordinator`), reasoning, references, and a three-state checkbox block:
  - `follow_up_created`
  - `raised_to_coordinator`
  - `rejected`
- Initialize all three state checkboxes unchecked.
- Do not start disposition before all findings are written.

5. Phase 2 - Disposition (mechanical loop). For each finding in order:

   5.1. Present the finding (severity, recommendation, reasoning, refs) and end the same message with exactly these three options on their own lines — do **not** print the options anywhere else in the finding presentation:

        ```
        1. reject
        2. create follow-up step
        3. raise to coordinator
        ```

        Then stop and wait for the user's choice. Do not re-print the options in a follow-up prompt; one listing per finding only.

   5.2. Apply the chosen disposition:

        - reject: mark `[x] rejected` (optional short rationale after `:`).
        - create follow-up step: do **not** edit `implementation_plan.md` by hand. Run the helper, which writes the canonical block (heading, `#### Assigned:` / `#### Repo:` / `#### Depends on:` headings, `- [ ] Plan and discuss the step.` first bullet, your action bullets, `- [ ] Review step implementation.` last bullet) and prints the new step id on stdout:

          ```bash
          uv run python .claude/skills/yasdef-worker-ai-audit/scripts/append_follow_up_step.py \
            --runtime-plan <runtime-plan> \
            --parent-step <current-step-id> \
            --worker-id <worker-id> \
            --title "<follow-up step title>" \
            --bullet "<first action bullet>" \
            [--bullet "<additional action bullet>" ...]
          ```

          The helper auto-picks the next free single-letter suffix (a..z) and copies `#### Repo:` from the parent step. Pass **only the action bullets** as `--bullet` — the helper adds the bookends. Then mark `[x] follow_up_created: <new-step-id>` in the finding's state block using the id printed by the helper.

        - raise to coordinator: create `projects/<project>/<feature>/raised_questions/<step>-<worker-id>-F<NN>.md` and mark `[x] raised_to_coordinator: <relative-path>`.

   5.3. Continue until all findings are dispositioned.

6. Mark all current-step target bullets `[x]` in the ASDLC `implementation_plan.md` in one batch, only after every finding has reached a terminal state. Every target bullet is audit-finalized at this point — directly proven (no finding), proven (finding rejected as false positive), or routed (follow_up_created / raised_to_coordinator). Leave the edit uncommitted; post_review handles the ASDLC repo commit.

7. Run closure gate:
   ```bash
   uv run python .claude/skills/yasdef-worker-ai-audit/scripts/check_ai_audit_closure.py --step <step> --feature-id <feature-id> --runtime-plan <runtime-plan> --worker-id <worker-id>
   ```
   If it exits non-zero, fix every reported error category (re-run a Phase 2 disposition, create a missing artifact, re-assign a mis-assigned follow-up step, mark a missed target bullet, etc.) and re-run until it exits `0`.

8. Commit boundary:
- Commit only worker-repo audit artifact changes on `step-<step>-<feature-id>-review`.
- Do not commit ASDLC repo changes (`implementation_plan.md`, `raised_questions/*`); those are for post_review.

9. Only after the closure gate passes and worker-repo audit changes are committed, end your final response with this exact last line:
`ai_audit phase finished. Nothing else to do now; press Ctrl-C so orchestrator can start the next phase.`

## Rules

- Analysis-only: do not touch runtime code and do not run tests.
- Findings must come from: target-bullet proof gaps, scope drift, `AGENTS.md` invariant violations, and `//TODO` markers in changed files.
- Every finding must end in exactly one terminal state: `follow_up_created` or `raised_to_coordinator` or `rejected`.
- Follow-up steps must stay assigned to the current worker.
- Do not use step plan content, `requirements_ears.md`, `implementation_plan.md`, `.asdlc_worker` ledgers, or design sections outside the required context list as context. `implementation_plan.md` is a write target only (mark current-step target bullets `[x]`, append follow-up step blocks); do not read it for context.
