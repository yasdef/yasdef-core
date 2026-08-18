## 1. Copilot runner contract

- [x] 1.1 Extend `tests/unit/domain/test_runners.py` with failing assertions for Copilot's TTY/log capabilities and exact argv without extras: `copilot --model claude-haiku-4.5 -i <prompt>`.
- [x] 1.2 Add an exact-argv test proving Copilot preserves multiple configured extra arguments in order before `-i` and keeps the complete prompt as one final argv element.
- [x] 1.3 Add `src/yasdef_worker/domain/runners/copilot.py` implementing `CopilotRunner` through the existing `ModelRunner` interface.
- [x] 1.4 Register `copilot` in the closed runner registry, export `CopilotRunner` from the runners package, and extend registry tests to cover successful Copilot selection without weakening unknown-runner rejection.
- [x] 1.5 Extend the app runner-factory test to load a Copilot phase row and assert the selected runner, model, extras, and final argv.

## 2. Packaged model defaults

- [x] 2.1 Add a package-resource test that validates the shipped `models.md` as a complete five-phase configuration and asserts every row uses command `copilot`, model `claude-haiku-4.5`, and `extras == ()`.
- [x] 2.2 Update `src/yasdef_worker/_data/setup/models.md` so its five active rows use Copilot with `claude-haiku-4.5` and no extras, explicitly removing the Codex-only `--config model_reasoning_effort='high'` fields; document the exact Copilot interactive argv shape and add a full five-row commented Copilot/Haiku example block mirroring the existing commented Claude block.
- [x] 2.3 Confirm existing manifest-guarded installer tests cover preservation of operator-modified `models.md`; add focused coverage only if the packaged-default update exposes a gap.

## 3. Skill and operator documentation

- [x] 3.1 Strengthen installer coverage to assert the `.github/skills` copy contains rewritten `.github/skills/` script paths and that all canonical worker skills remain installed for every existing target prefix.
- [x] 3.2 Update `Readme.md` to list GitHub Copilot CLI as supported, identify Copilot with `claude-haiku-4.5` as the new-worker default, retain mixed-runner configuration guidance, and state that Copilot installation/authentication is an operator prerequisite.
- [x] 3.3 Add a concise `CHANGELOG.md` entry for Copilot runner support and the packaged default-runner/model change.

## 4. Verification

- [x] 4.1 Run `uv run pytest tests/unit/domain/test_runners.py tests/unit/app/test_phase_base.py tests/unit/test_package_resources.py tests/unit/app/installer/test_init_asdlc_worker.py`.
- [x] 4.2 Run `uv run pytest tests/integration/test_init.py` to verify a bootstrapped worker receives valid default configuration and compatible installed skills.
- [x] 4.3 Run the full Python quality gate: `uv run pytest`, `uv run mypy src`, and `uv run ruff check .`.
- [x] 4.4 In an authenticated scratch worker, manually run one model-driven phase with `copilot --model claude-haiku-4.5 -i <phase-prompt>` and verify the interactive UI starts, the named canonical skill is loaded, the phase log is captured, and no Copilot-specific prompt or skill copy is required.
