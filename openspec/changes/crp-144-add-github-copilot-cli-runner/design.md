## Context

See `proposal.md` for motivation and `specs/github-copilot-cli-runner/spec.md` for the behavior contract.

The Python orchestrator already isolates command construction behind `ModelRunner`. `CodexRunner` and `ClaudeRunner` both declare that they need a TTY and captured logs, while `ModelConfigRunnerFactory` resolves the command, model, and extra fields from the selected phase row. All concrete phases call the same `run_model` path and use runner-independent prompt templates that name a canonical `yasdef-worker-*` skill.

The installer already copies every canonical phase skill into `.claude/skills`, `.codex/skills`, `.github/skills`, and `.agents/skills`, rewriting embedded skill paths for each target. GitHub Copilot CLI supports the existing project skill locations and project `AGENTS.md`; no new installed asset family is required. A manual smoke test confirmed that `copilot --model claude-haiku-4.5 -i "<prompt>"` starts interactive mode and automatically executes the supplied prompt.

## Goals / Non-Goals

**Goals:**

- Add Copilot through the existing runner boundary with no phase-specific dispatch branches.
- Preserve configured extra arguments exactly and keep the phase prompt as one argv element.
- Use the shared TTY/logging execution behavior and canonical skill bundle.
- Ship a complete Copilot/Claude-Haiku default pipeline while preserving operator configuration on reinitialization.
- Keep the domain runner implementation pure and compatible with `mypy --strict`.

**Non-Goals:**

- Installing, updating, authenticating, or logging into GitHub Copilot CLI.
- Adding headless `copilot -p`, autopilot, blanket permission, or retry behavior.
- Adding Copilot-specific phase prompts, commands, custom agents, or duplicated skills.
- Solving direct-TTY automatic phase termination; that remains owned by `crp-140-direct-tty-phase-completion`.
- Generalizing the closed runner registry into a plugin system.

## Decisions

### Decision 1: Add a dedicated `CopilotRunner`

Add `src/yasdef_worker/domain/runners/copilot.py` with the same `ModelRunner` interface and runtime characteristics as the other interactive runners:

```python
class CopilotRunner(ModelRunner):
    name = "copilot"
    needs_tty = True
    captures_log = True

    def build_argv(self, *, model, extras, prompt):
        return ["copilot", "--model", model, *extras, "-i", prompt]
```

Register and export the runner alongside Codex, Claude, and the test-only Echo runner. The exact registry remains intentionally closed so configuration mistakes fail as unsupported runners rather than being executed as arbitrary commands.

Alternative considered: treat every unknown command as a Codex-shaped executable. Rejected because the Python orchestrator deliberately replaced that legacy shell behavior with an explicit runner registry, and Copilot has a distinct prompt flag.

### Decision 2: Put configured extras before `-i`

Copilot's `-i` option consumes the next argv element as its initial prompt. Placing configured extras after `--model` and before `-i` keeps operator options independent from the prompt and makes the prompt the final, single argv element. Yasdef passes extras through verbatim, matching the current configuration contract.

Alternative considered: append extras after the prompt. Rejected because it makes option parsing dependent on whether the CLI continues parsing after the `-i` value and obscures the required prompt boundary.

Alternative considered: use `-p`. Rejected because `-p` is non-interactive and requires unattended permission configuration, contrary to Yasdef's interactive workflow.

### Decision 3: Reuse the shared TTY and log path unchanged

Set `needs_tty=True` and `captures_log=True`; do not add Copilot branches in `Phase.run_model` or `ProcessRunner`. On an attached terminal, the existing `script -q` wrapper provides the pseudo-TTY and captures output. In non-TTY test contexts, existing process behavior remains unchanged.

The direct-TTY close-marker limitation is shared by all interactive runners and is explicitly excluded from this change. CRP-144 must neither depend on completing CRP-140 nor introduce a Copilot-only lifecycle mechanism.

Alternative considered: special-case Copilot in `ProcessRunner`. Rejected because its TUI requirements match the runner capabilities already modeled by `needs_tty` and `captures_log`.

### Decision 4: Keep prompts and installed skills runner-independent

Do not change phase prompt templates or canonical `SKILL.md` files for Copilot. The prompts already instruct the model to use the exact skill name, and Yasdef init already installs compatible copies under project skill directories recognized by Copilot. Existing installer prefix-rewrite tests provide the integration boundary; add only focused coverage if the current tests do not explicitly prove the `.github` copy's rewritten content.

Alternative considered: add `.github`-specific prompt templates or Copilot custom agents. Rejected because that would create parallel process rules and increase drift risk without adding required behavior.

### Decision 5: Make Copilot with `claude-haiku-4.5` the packaged default

Replace the five active Codex rows in the packaged `models.md` with complete Copilot rows using `claude-haiku-4.5` and no extra arguments. In particular, remove the Codex-only `--config model_reasoning_effort='high'` fields rather than carrying them into the Copilot defaults. Keep documented Codex and Claude examples, add the Copilot invocation shape, and add a full five-row commented Copilot/Haiku example block mirroring the existing commented Claude block. Do not add implicit model defaults in Python: the existing configuration continues to require a non-empty model for every phase.

This affects new workers and reinitializations where the existing file still matches the prior install manifest. The installer's manifest-guarded overwrite behavior preserves operator-modified configurations unless `--force` is explicitly used.

Alternative considered: leave Codex active and add only commented Copilot examples. Rejected because the requested default is Copilot with Claude Haiku 4.5.

### Decision 6: Test command construction without invoking the external CLI

Unit tests assert the exact Copilot argv with and without extras, its TTY/log flags, registry resolution, and app-level factory selection. Package/installer tests assert that all five shipped rows resolve to `copilot` plus `claude-haiku-4.5`, have an empty extras tuple, and retain project skills with rewritten paths. Automated tests must not require Copilot installation, credentials, network access, or paid inference.

A manual smoke test remains the evidence for the external CLI interaction itself. The confirmed invocation is recorded in the change context, but no live Copilot call belongs in CI.

## Risks / Trade-offs

- **Copilot CLI changes its option contract** → Keep the argv construction isolated in one runner and cover the currently verified shape exactly; update the runner and documentation together if the CLI changes.
- **The default switch surprises existing operators** → Manifest-guarded installation preserves modified configurations; release notes and `Readme.md` state the new default explicitly.
- **Copilot does not select the named skill reliably in a future version** → Keep the prompt explicit, verify installed skills in tests, and include a manual phase smoke check in validation without introducing duplicate rules preemptively.
- **TTY sessions still require manual lifecycle handling** → Keep CRP-144 scoped to runner integration and complete the shared solution in CRP-140.
- **Authentication or organization policy prevents startup** → Treat Copilot as an external prerequisite and surface its non-zero process failure through the existing error path.

## Migration Plan

1. Add and register the runner with focused unit tests.
2. Change packaged model defaults and documentation, then add resource/installer assertions for the complete default pipeline.
3. Run the targeted runner, app factory, package resource, and init suites followed by the full Python quality gate.
4. Build/install the package into a scratch worker, authenticate Copilot externally, and run one interactive phase smoke using `claude-haiku-4.5`.

Rollback consists of restoring the previous packaged Codex rows and removing the Copilot registry entry/module. Existing operator-edited `models.md` files remain untouched by manifest-guarded reinitialization; a worker already configured with `copilot` must be changed back to `codex` or `claude` before using a rolled-back release.
