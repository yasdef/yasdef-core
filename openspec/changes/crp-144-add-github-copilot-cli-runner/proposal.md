## Why

Yasdef rejects `copilot` in `.asdlc_worker/setup/models.md`, so operators with GitHub Copilot CLI cannot use the same interactive, skill-driven phase workflow already available through Codex and Claude. Copilot CLI's verified `-i <prompt>` mode and existing support for the skill directories Yasdef installs make it possible to add this without another phase-specific integration.

## What Changes

- Add `copilot` as a supported model-runner command for every model-driven phase.
- Launch Copilot with the configured model and extra arguments in interactive mode, automatically executing the existing phase prompt.
- Make the packaged five-phase model configuration use GitHub Copilot CLI with `claude-haiku-4.5` by default while preserving per-phase command, model, and extra-argument overrides.
- Reuse the existing TTY, logging, prompt, installed-skill, and project-guidance paths; do not add Copilot-specific copies of phase rules.
- Document the third supported CLI and cover its command construction, registry selection, configuration, and packaged defaults with automated tests.

## Capabilities

### New Capabilities

- `github-copilot-cli-runner`: Defines GitHub Copilot CLI selection, interactive invocation, configured argument forwarding, packaged defaults, and compatibility with Yasdef's existing skills and phase execution path.

### Modified Capabilities

None.

## Impact

- Python runner dispatch under `src/yasdef_worker/domain/runners/` and its app-level configuration factory.
- Packaged `.asdlc_worker/setup/models.md` defaults and operator-facing `Readme.md` guidance.
- Unit and integration tests for runner argv, registry/factory selection, packaged configuration, and installed skill compatibility.
- Requires an installed and authenticated `copilot` executable at runtime; Yasdef does not manage Copilot installation or authentication.
- The existing direct-TTY completion limitation remains tracked separately by `crp-140-direct-tty-phase-completion` and is not changed here.
