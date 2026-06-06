from __future__ import annotations

from dataclasses import dataclass

from yasdef_orchestrator.app.feature_context import FeatureContextBuilder
from yasdef_orchestrator.app.phases import ModelConfigRunnerFactory, PhaseContext
from yasdef_orchestrator.app.pipeline import DEFAULT_PHASES, Pipeline, PipelineResult
from yasdef_orchestrator.domain.models_config import list_phases
from yasdef_orchestrator.infra.git_repo import GitRepo
from yasdef_orchestrator.infra.layout import RuntimeLayout
from yasdef_orchestrator.infra.log_capture import LogCapture
from yasdef_orchestrator.infra.process import ProcessRunner
from yasdef_orchestrator.infra.prompts import Prompter
from yasdef_orchestrator.infra.templates import TemplateLoader
from yasdef_orchestrator.infra.user_output import UserOutput


@dataclass(frozen=True, slots=True)
class RunOptions:
    requested_step: str | None = None
    resume: bool = False
    phases: tuple[str, ...] = ()
    dry_run: bool = False
    debug: bool = False


class Orchestrator:
    def __init__(
        self,
        *,
        layout: RuntimeLayout,
        git: GitRepo,
        prompts: Prompter,
        process: ProcessRunner,
        output: UserOutput,
    ):
        self.layout = layout
        self.git = git
        self.prompts = prompts
        self.process = process
        self.output = output

    def run(self, options: RunOptions = RunOptions()) -> PipelineResult:
        feature = FeatureContextBuilder(
            layout=self.layout,
            git=self.git,
            prompts=self.prompts,
            output=self.output,
            requested_step=options.requested_step,
            resume_mode=options.resume,
        ).build()
        ctx = PhaseContext(
            layout=self.layout,
            git=self.git,
            runner_factory=ModelConfigRunnerFactory(self.layout.models_file),
            prompts=self.prompts,
            process=self.process,
            log_capture=LogCapture(self.layout, debug=options.debug),
            templates=TemplateLoader(self.layout),
            output=self.output,
            feature=feature,
            dry_run=options.dry_run,
            debug=options.debug,
        )
        phases = options.phases or _configured_phases(self.layout)
        return Pipeline(ctx=ctx).iterate(phases)


def _configured_phases(layout: RuntimeLayout) -> tuple[str, ...]:
    configured = list_phases(layout.models_file.read_text(encoding="utf-8"))
    return tuple(phase for phase in configured if phase in DEFAULT_PHASES)
