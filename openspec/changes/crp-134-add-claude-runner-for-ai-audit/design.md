## Context

`ai/scripts/orchestrator.sh` currently invokes a single model runner — Codex — and the invocation shape is duplicated across five phase functions:

```bash
local cmd=("$MODEL_CMD" -m "$MODEL_MODEL")
if [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
  cmd+=("${MODEL_ARGS[@]}")
fi
cmd+=("$prompt_arg")
```

`models.md` already carries a `cmd` column (per-phase: `phase | cmd | model | args...`), so the file is structurally ready to name a different runner. What's missing is (a) the orchestrator-side logic to assemble a Claude-correct argv, and (b) a place for that logic to live so it doesn't get duplicated five more times.

CRP-133 just installed `.claude/skills/yasdef-worker-ai-audit/` in the target repo, so the ai_audit phase is the only phase whose Claude side is bootstrap-ready. The other four phases (design, planning, implementation, user_review) still have only Codex skills; their Claude parallels will land in future CRPs.

Codex and Claude Code CLIs differ in shape:

| Aspect | Codex | Claude |
|---|---|---|
| Model flag | `-m <id>` | `--model <id>` |
| Reasoning effort | `--config model_reasoning_effort='high'` | no CLI equivalent (Claude Opus 4.7 has thinking on by default) |
| Prompt delivery | positional arg | positional arg (same as `claude "explain this"` from a terminal) |
| Tool-permission gate | none | claude's interactive UI prompts per tool; `--allowed-tools` skips approvals for a named tool list |
| TTY requirement | optional | required for interactive UI (otherwise claude switches to `--print` mode and refuses positional prompt) |

## Goals / Non-Goals

**Goals:**
- Let `models.md` route the ai_audit phase to either `codex` or `claude` purely by changing the `cmd` column.
- Preserve today's Codex behavior byte-for-byte: a row that says `ai_audit | codex | gpt-5.5 | --config | model_reasoning_effort='high'` produces the same argv as today.
- Eliminate the five duplicated `cmd=()` blocks in the phase functions by extracting one shared `build_phase_cmd "$prompt"` helper.
- Keep the same inline 7-input prompt body (built in `run_ai_audit_phase`, orchestrator.sh:2110-2122) for both runners — Claude picks up the skill via the `yasdef-worker-ai-audit` name in `SKILL.md`.

**Non-Goals:**
- Adding Claude support for design / planning / implementation / user_review (their Claude skills are not installed yet — each is a future per-phase CRP).
- Changing the `models.md` file format or its parser (`load_model_config`).
- Adding new model-config knobs (`--max-turns`, `--allowed-tools`, `--thinking-tokens`, `--output-format`).
- An interactive runner-picker at orchestrator startup (rejected during discussion — `models.md` owns the choice).
- Starting the orchestrator-to-Python migration (tracked separately in `design_docs/orchestrator_to_python.md`).
- Routing orchestrator-triggered runs through the `/yasdef:audit` slash command (the slash command is for manual operator use; orchestrator keeps building the inline prompt).
- Changing closure semantics, `post_review.sh`, or anything downstream of the model invocation.

## Decisions

**Decision 1: Pass extras through verbatim; only the model flag is structurally different**

`build_claude_cmd` and `build_codex_cmd` both pass `MODEL_ARGS` through verbatim. The only branch-level difference is the model-selection flag: codex uses `-m <model>`, claude uses `--model <model>`. The prompt is positional in both cases.

Pass-through-not-hardcode was chosen after smoke testing revealed that any hardcoded permission flag has skill-specific implications the orchestrator shouldn't bake in. Claude Code's `--allowed-tools` is the natural per-phase knob, and it belongs in `models.md` so the operator can adjust it without a code change. The default `ai_audit | claude | ...` row may carry `--allowed-tools <list>` to skip in-UI tool-approval prompts for the specific tools the ai_audit skill calls.

The risk that pass-through was rejected to avoid in earlier drafts — operator pastes a codex-style `--config model_reasoning_effort='high'` into a claude row — turns into a loud `claude` CLI error at exec time, not silent breakage. Loud failures are better than silent ones; the original "hardcode-and-ignore" rule was solving the wrong problem.

Alternative considered:
- *Per-runner extras column* — add a `claude_extras` column. Rejected: format change with no offsetting benefit once pass-through is the default.

**Decision 2: Same inline prompt for both runners; same TTY handling**

The orchestrator continues to build the existing 7-input prompt body in `run_ai_audit_phase`; `build_phase_cmd` hands it to the CLI as a positional arg for both runners. Claude finds the skill via its `SKILL.md` `name:` field exactly as Codex does today.

`run_with_output_log` already had a `script -q <log>` branch that allocated a pseudo-TTY for codex when stdout was a terminal — letting codex run interactively while still capturing a log. This CRP extends that branch's condition to also match `claude`. Result: claude opens its interactive UI, the operator approves tool calls in-UI, the run is still captured to the per-phase audit log. No per-phase if/else in the orchestrator, no `-p` headless mode, no lost logging.

Alternatives considered:
- *Hardcode `-p` and rely on `--allowed-tools` for unattended runs* — works but loses the in-UI inspection/approval workflow the operator wants for ai_audit.
- *Skip `run_with_output_log` entirely for claude* — gives interactive UI but drops the audit log. Worse than extending the existing `script -q` branch.
- *Route Claude runs through `/yasdef:audit`* — would exercise the slash command. Rejected: maintaining two prompt shapes for the same orchestrator path doubles the surface area for prompt-drift bugs. The slash command stays as a manual operator affordance.

**Decision 3: One shared `build_phase_cmd "$prompt"` helper, dispatch on `$MODEL_CMD`**

The helper takes the prompt string and reads `MODEL_CMD` / `MODEL_MODEL` / `MODEL_ARGS` globals (set earlier by `load_model_config`). It emits a bash array via a global `BUILD_PHASE_CMD` (bash can't return arrays from functions). Phase functions become:

```bash
load_model_config "ai_audit"
build_phase_cmd "$prompt_arg"
run_with_output_log "ai_audit" "$step" "${BUILD_PHASE_CMD[@]}"
```

Alternative considered:
- *Return argv via stdout, parse with `read -a`* — fragile around prompts containing newlines and special chars.
- *One helper per runner with no dispatch wrapper* — leaks the `if/elif` into all five phase functions; same shape duplication we're removing.

Inside `build_phase_cmd`, dispatch is a small `case "$MODEL_CMD"` block: `claude` calls `build_claude_cmd "$prompt"`, anything else falls through to `build_codex_cmd "$prompt"`. Each writes to `BUILD_PHASE_CMD`. The permissive default preserves pre-CRP semantics: existing tests (`tests/ai_scripts/orchestrator_planning_skill_tests.sh`, `tests/ai_scripts/orchestrator_resume_tests.sh`) mock the model CLI by writing `echo` or a path to a fake script into the test repo's `models.md`, and that pattern keeps working because `cmd` was always treated as "the executable to invoke." The trade-off is that an operator typo on `codex` (e.g., `codes`) silently invokes the codex shape with the typoed binary, which will fail at exec time anyway with a clear "command not found" — acceptable given Claude dispatch is opt-in by writing `claude` exactly.

**Decision 4: Stay in bash**

Extracting the argv-builder to Python is rejected for this CRP. Bash has the same access to the existing `MODEL_*` globals and the same `cmd=()` array idiom that `run_with_output_log` already consumes; a Python helper would require a bash↔Python boundary (prompt via tempfile or env var, argv as JSON, re-exec) that pays a cost twice — once setting it up here, once tearing it down during the broader Python migration. The Python migration plan lives in `design_docs/orchestrator_to_python.md`; the inflection points that would justify porting `build_phase_cmd` are listed there.

**Decision 5: Test the helper directly, not through the orchestrator**

Add `tests/ai_scripts/model_runner_tests.sh` that sources `orchestrator.sh` (or a future smaller helper file), sets `MODEL_CMD` / `MODEL_MODEL` / `MODEL_ARGS`, calls `build_phase_cmd "<sample prompt>"`, and asserts the resulting `BUILD_PHASE_CMD` array element-by-element. Two scenarios per runner — codex with extras, claude with extras-that-must-be-dropped — keeps the matrix small and the failures readable. End-to-end coverage stays in the existing orchestrator tests via dry-run.

## Risks / Trade-offs

- **Operator writes a Claude row with Codex extras** → `models.md` is permissive; pass-through means `--config model_reasoning_effort='high'` in a claude row reaches the `claude` CLI, which rejects it with a clear error and exits non-zero. Failure is loud, immediate, and self-correcting (operator removes the bad flag).
- **`script -q` not available in the operator's environment** → `run_with_output_log` falls back to the `tee` path, which pipes claude's stdout; claude then sees non-TTY and refuses to accept a positional prompt (`"Input must be provided either through stdin or as a prompt argument when using --print"`). Mitigation: `script` is a BSD/POSIX utility shipped on every macOS and almost every Linux distribution. If it's truly missing, the operator can install `bsdmainutils` (Linux) or its equivalent.
- **Sourcing `orchestrator.sh` from tests pulls in side effects** → Mitigation: the helper functions are pure (read globals, write `BUILD_PHASE_CMD`); the test sets the globals before calling and doesn't trigger the orchestrator's top-level execution. If side-effect contamination becomes a problem, extract the helpers into `ai/scripts/helpers/build_phase_cmd.sh` and source only that.
- **`--permission-mode acceptEdits` is broader than `ai_audit` needs** → ai_audit is analysis-only; it shouldn't be writing files outside `step_review_results/` and the runtime plan. Still, `acceptEdits` is the standard headless-Claude posture. If tighter scoping is ever needed, `--allowed-tools` is the next knob to add — explicitly out of scope here.
- **Codex behavior drift** → `build_codex_cmd` must produce the same argv as today; if anything diverges, all five phases regress at once. Mitigation: test in step 1 asserts the codex argv matches the current shape literally; the refactor lands before the Claude branch is implemented.

## Migration Plan

1. Extract today's inlined `cmd=()` block into `build_codex_cmd` (and a `build_phase_cmd` dispatcher that only knows the codex case). Update all five phase functions to call the dispatcher. No behavior change; existing orchestrator tests pass unchanged.
2. Add the failing test for `build_claude_cmd` in `tests/ai_scripts/model_runner_tests.sh`.
3. Implement `build_claude_cmd` with the four transform rules. Test passes.
4. Add the dispatcher case for `claude` in `build_phase_cmd`. Unknown-runner case dies with a descriptive message.
5. Document the two-runner choice in the header comment of `ai/setup/models.md` and (briefly) in `ai/AI_DEVELOPMENT_PROCESS.md` if it covers operator-facing config.
6. Manual smoke: in a worker repo, set `ai_audit | claude | claude-opus-4-7 |  |` and run the orchestrator's ai_audit phase end-to-end; verify the Claude skill is picked up and the closure gate passes.

Rollback: revert the orchestrator change. Operators who'd updated their `models.md` to `claude` would see the unknown-runner error and switch back to `codex`. No state migration needed.

## Open Questions

- **Where in `orchestrator.sh` should the helpers live?** Natural home is right after `load_model_config` (line ~511). If the file grows or the helpers gain meaningful complexity, extract to `ai/scripts/helpers/build_phase_cmd.sh` — but for the current scope, inline is fine.
- ~~**Should the dispatcher fall back to codex on an unknown runner, or die?**~~ Resolved during implementation: fall back to codex. Strict dispatch collided with the established test convention of writing `echo` or a path to a fake script into a test repo's `models.md`. Preserving that convention is more valuable than catching operator typos on `codex`, which fail loudly at exec time anyway.
- **Should the runner choice be logged at phase-start?** Recommendation: yes — one line `using <codex|claude> for phase <name>` at INFO level so operators can confirm which runner actually ran. Cheap and makes log forensics easier.
