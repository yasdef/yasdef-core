from __future__ import annotations

import io
from dataclasses import dataclass
from pathlib import Path

import pytest

from yasdef_worker.app.phases import (
    ModelConfigRunnerFactory,
    Phase,
    PhaseContext,
    PhaseRunner,
    normalize_phase_token,
    normalize_step_token,
)
from yasdef_worker.domain.phase_types import PhaseResult, PhaseStatus
from yasdef_worker.domain.runners import CopilotRunner, EchoRunner
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.log_capture import LogCapture
from yasdef_worker.infra.process import ProcessRunner
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.templates import TemplateLoader
from yasdef_worker.infra.user_output import RecordingUserOutput


@dataclass(frozen=True, slots=True)
class Feature:
    step: str
    feature_id: str
    source_plan_path: Path
    source_ears_path: Path


class StaticRunnerFactory:
    def __init__(self) -> None:
        self.requested: list[str] = []

    def for_phase(self, phase: str) -> PhaseRunner:
        self.requested.append(phase)
        return PhaseRunner(EchoRunner(), "mock-model", ("--flag",))


class StubPhase(Phase):
    name = "design"

    def __init__(self, ctx: PhaseContext, *, result: PhaseResult | None = None):
        super().__init__(ctx)
        self.calls: list[str] = []
        self._result = result

    def preflight(self) -> None:
        self.calls.append("preflight")

    def prepare_branch(self) -> None:
        self.calls.append("prepare_branch")

    def build_prompt(self) -> str:
        self.calls.append("build_prompt")
        return "PROMPT"

    def run(self, prompt: str, log_path: Path) -> PhaseResult:
        self.calls.append(f"run:{prompt}:{log_path.name}")
        return self._result or self.complete("done")

    def postflight(self, log_path: Path) -> None:
        self.calls.append(f"postflight:{log_path.name}")


def test_phase_execute_runs_lifecycle_in_order(tmp_path: Path) -> None:
    phase = StubPhase(_ctx(tmp_path))
    log_name = phase.log_path().name

    result = phase.execute()

    assert result == PhaseResult("design", PhaseStatus.COMPLETE, "done")
    assert phase.calls == [
        "preflight",
        "prepare_branch",
        "build_prompt",
        f"run:PROMPT:{log_name}",
        f"postflight:{log_name}",
    ]


def test_phase_execute_skips_postflight_when_phase_is_incomplete(tmp_path: Path) -> None:
    phase = StubPhase(
        _ctx(tmp_path),
        result=PhaseResult("design", PhaseStatus.INCOMPLETE, "missing artifact"),
    )
    log_name = phase.log_path().name

    result = phase.execute()

    assert result.is_complete is False
    assert phase.calls == [
        "preflight",
        "prepare_branch",
        "build_prompt",
        f"run:PROMPT:{log_name}",
    ]


def test_run_model_uses_configured_runner_and_writes_log(tmp_path: Path) -> None:
    output = io.StringIO()
    factory = StaticRunnerFactory()
    ctx = _ctx(tmp_path, runner_factory=factory, process_output=output)
    phase = StubPhase(ctx)

    result = phase.run_model("PROMPT", phase.log_path())

    assert result.is_complete is True
    assert factory.requested == ["design"]
    assert phase.log_path().read_text(encoding="utf-8").strip() == "-m mock-model --flag PROMPT"
    assert output.getvalue().strip() == "-m mock-model --flag PROMPT"


def test_model_config_runner_factory_loads_existing_domain_runner_config(tmp_path: Path) -> None:
    models_file = tmp_path / "models.md"
    models_file.write_text(
        "design | echo | mock-model | --extra | value\n",
        encoding="utf-8",
    )

    selected = ModelConfigRunnerFactory(models_file).for_phase("design")

    assert isinstance(selected.runner, EchoRunner)
    assert selected.model == "mock-model"
    assert selected.extras == ("--extra", "value")
    assert selected.build_argv("PROMPT") == ["echo", "-m", "mock-model", "--extra", "value", "PROMPT"]


def test_model_config_runner_factory_selects_copilot_runner(tmp_path: Path) -> None:
    models_file = tmp_path / "models.md"
    models_file.write_text(
        "design | copilot | claude-haiku-4.5\n"
        "implementation | copilot | claude-haiku-4.5 | --effort | high\n",
        encoding="utf-8",
    )
    factory = ModelConfigRunnerFactory(models_file)

    design = factory.for_phase("design")
    assert isinstance(design.runner, CopilotRunner)
    assert design.model == "claude-haiku-4.5"
    assert design.extras == ()
    assert design.build_argv("PROMPT") == [
        "copilot",
        "--model",
        "claude-haiku-4.5",
        "-i",
        "PROMPT",
    ]

    implementation = factory.for_phase("implementation")
    assert isinstance(implementation.runner, CopilotRunner)
    assert implementation.extras == ("--effort", "high")
    assert implementation.build_argv("PROMPT") == [
        "copilot",
        "--model",
        "claude-haiku-4.5",
        "--effort",
        "high",
        "-i",
        "PROMPT",
    ]


def test_phase_token_normalization_uses_canonical_phase_names() -> None:
    assert normalize_phase_token("user-review") == "user_review"
    assert normalize_phase_token("AI_AUDIT") == "ai_audit"
    with pytest.raises(ValueError, match="unsupported phase name"):
        normalize_phase_token("audit-review")


def test_step_token_normalization_trims_only() -> None:
    assert normalize_step_token(" 1.6c ") == "1.6c"


def _ctx(
    tmp_path: Path,
    *,
    runner_factory: StaticRunnerFactory | None = None,
    process_output: io.StringIO | None = None,
) -> PhaseContext:
    layout = RuntimeLayout.from_root(tmp_path)
    return PhaseContext(
        layout=layout,
        git=GitRepo(tmp_path),
        runner_factory=runner_factory or StaticRunnerFactory(),
        prompts=Prompter(interactive=False),
        process=ProcessRunner(),
        log_capture=LogCapture(layout),
        templates=TemplateLoader(layout),
        output=RecordingUserOutput(),
        feature=Feature(
            step="1.2a",
            feature_id="feature-demo",
            source_plan_path=tmp_path / "source" / "feature-demo" / "implementation_plan.md",
            source_ears_path=tmp_path / "source" / "feature-demo" / "requirements_ears.md",
        ),
        process_output=process_output,
    )
