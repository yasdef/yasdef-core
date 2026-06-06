from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import ClassVar, Protocol, TextIO

from yasdef_orchestrator.domain.models_config import canonical_phase_name, load_model_config
from yasdef_orchestrator.domain.phase_types import PhaseResult, PhaseStatus
from yasdef_orchestrator.domain.runners import ModelRunner, get_runner
from yasdef_orchestrator.infra.git_repo import GitRepo
from yasdef_orchestrator.infra.layout import RuntimeLayout
from yasdef_orchestrator.infra.log_capture import LogCapture
from yasdef_orchestrator.infra.process import PHASE_CLOSE_MARKER, ProcessRunner
from yasdef_orchestrator.infra.prompts import Prompter
from yasdef_orchestrator.infra.templates import TemplateLoader
from yasdef_orchestrator.infra.user_output import UserOutput


class PhaseFeature(Protocol):
    @property
    def step(self) -> str:
        raise NotImplementedError

    @property
    def feature_id(self) -> str:
        raise NotImplementedError



@dataclass(frozen=True, slots=True)
class PhaseRunner:
    runner: ModelRunner
    model: str
    extras: tuple[str, ...] = ()

    def build_argv(self, prompt: str) -> list[str]:
        return self.runner.build_argv(model=self.model, extras=self.extras, prompt=prompt)


class RunnerFactory(Protocol):
    def for_phase(self, phase: str) -> PhaseRunner:
        raise NotImplementedError


class ModelConfigRunnerFactory:
    def __init__(self, models_file: Path):
        self.models_file = models_file

    def for_phase(self, phase: str) -> PhaseRunner:
        config = load_model_config(self.models_file.read_text(encoding="utf-8"), phase)
        return PhaseRunner(
            runner=get_runner(config.cmd),
            model=config.model,
            extras=config.extras,
        )


@dataclass(slots=True)
class PhaseContext:
    layout: RuntimeLayout
    git: GitRepo
    runner_factory: RunnerFactory
    prompts: Prompter
    process: ProcessRunner
    log_capture: LogCapture
    templates: TemplateLoader
    output: UserOutput
    feature: PhaseFeature
    dry_run: bool = False
    debug: bool = False
    process_output: TextIO | None = None


class Phase(ABC):
    name: ClassVar[str]
    requires_confirmation: ClassVar[bool] = False

    def __init__(self, ctx: PhaseContext):
        self.ctx = ctx

    def execute(self) -> PhaseResult:
        self.preflight()
        self.prepare_branch()
        prompt = self.build_prompt()
        log_path = self.log_path()
        result = self.run(prompt, log_path)
        if result.is_complete:
            self.postflight(log_path)
        return result

    @abstractmethod
    def preflight(self) -> None:
        """Validate phase inputs before any branch or process work."""
        raise NotImplementedError

    @abstractmethod
    def prepare_branch(self) -> None:
        """Switch to or create the phase branch."""
        raise NotImplementedError

    @abstractmethod
    def build_prompt(self) -> str:
        """Render the model prompt for this phase."""
        raise NotImplementedError

    @abstractmethod
    def run(self, prompt: str, log_path: Path) -> PhaseResult:
        """Execute the phase body once."""
        raise NotImplementedError

    def postflight(self, log_path: Path) -> None:
        """Run explicit artifact/readiness checks after a successful phase run."""

    def log_path(self) -> Path:
        return self.ctx.log_capture.path_for(self.name, self.ctx.feature.step)

    def run_model(self, prompt: str, log_path: Path) -> PhaseResult:
        selected = self.ctx.runner_factory.for_phase(self.name)
        self.ctx.process.run_with_log(
            selected.build_argv(prompt),
            log_path,
            needs_tty=selected.runner.needs_tty,
            capture_log=selected.runner.captures_log,
            cwd=self.ctx.layout.worker_repo_root,
            output=self.ctx.process_output,
            close_marker=PHASE_CLOSE_MARKER,
        )
        return self.complete()

    def complete(self, detail: str = "") -> PhaseResult:
        return PhaseResult(self.name, PhaseStatus.COMPLETE, detail)

    def incomplete(self, detail: str = "") -> PhaseResult:
        return PhaseResult(self.name, PhaseStatus.INCOMPLETE, detail)

    def failed(self, detail: str = "") -> PhaseResult:
        return PhaseResult(self.name, PhaseStatus.FAILED, detail)


def normalize_phase_token(value: str) -> str:
    return canonical_phase_name(value)


def normalize_step_token(value: str) -> str:
    return value.strip()
