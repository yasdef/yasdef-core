from __future__ import annotations

from dataclasses import dataclass

from yasdef_worker.app.feature_context import FeatureContextBuilder
from yasdef_worker.app.mainline_branch_policy import require_clean_mainline_start
from yasdef_worker.app.phases import ModelConfigRunnerFactory, PhaseContext
from yasdef_worker.app.pipeline import DEFAULT_PHASES, Pipeline, PipelineResult
from yasdef_worker.domain.models_config import list_phases
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.log_capture import LogCapture
from yasdef_worker.infra.process import ProcessRunner
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.templates import TemplateLoader
from yasdef_worker.infra.user_output import UserOutput


@dataclass(frozen=True, slots=True)
class RunOptions:
    resume_step: str | None = None
    dry_run: bool = False
    debug: bool = False


class Coordinator:
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
        phases = _configured_phases(self.layout)
        if phases and phases[0] == "design":
            require_clean_mainline_start(self.git, operation="yasdef run design")
        feature = FeatureContextBuilder(
            layout=self.layout,
            git=self.git,
            prompts=self.prompts,
            output=self.output,
            resume_step=options.resume_step,
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
        return Pipeline(ctx=ctx).iterate(phases)


def _configured_phases(layout: RuntimeLayout) -> tuple[str, ...]:
    configured = list_phases(layout.models_file.read_text(encoding="utf-8"))
    return tuple(phase for phase in configured if phase in DEFAULT_PHASES)
