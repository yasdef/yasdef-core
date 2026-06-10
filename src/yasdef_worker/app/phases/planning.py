from __future__ import annotations

from pathlib import Path

from yasdef_worker.app.branch_manager import BranchManager
from yasdef_worker.app.phases.base import Phase
from yasdef_worker.domain.phase_types import PhaseResult
from yasdef_worker.infra.errors import PhasePreconditionError


class PlanningPhase(Phase):
    name = "planning"
    requires_confirmation = True

    def preflight(self) -> None:
        _require_file(self.name, self.design_path(), "design artifact")

    def prepare_branch(self) -> None:
        BranchManager(self.ctx.git, self.ctx.output).ensure_plan_branch(
            step=self.ctx.feature.step,
            feature_id=self.ctx.feature.feature_id,
        )

    def build_prompt(self) -> str:
        return self.ctx.templates.load(self.name).format(
            step=self.ctx.feature.step,
            feature_id=self.ctx.feature.feature_id,
            branch=self.branch_name(),
            design_file=self.design_path(),
            step_plan_out=self.step_plan_path(),
            runtime_plan=self.ctx.feature.source_plan_path,
            open_questions_file=self.open_questions_path(),
            blockers_file=self.blockers_path(),
        )

    def run(self, prompt: str, log_path: Path) -> PhaseResult:
        return self.run_model(prompt, log_path)

    def branch_name(self) -> str:
        return f"step-{self.ctx.feature.step}-{self.ctx.feature.feature_id}-plan"

    def design_path(self) -> Path:
        return (
            self.ctx.layout.step_designs_dir
            / f"step-{self.ctx.feature.step}-{self.ctx.feature.feature_id}-design.md"
        )

    def step_plan_path(self) -> Path:
        return self.ctx.layout.step_plans_dir / f"step-{self.ctx.feature.step}-{self.ctx.feature.feature_id}.md"

    def open_questions_path(self) -> Path:
        return (
            self.ctx.layout.step_open_questions_dir
            / f"step-{self.ctx.feature.step}-{self.ctx.feature.feature_id}-open-questions.md"
        )

    def blockers_path(self) -> Path:
        return (
            self.ctx.layout.step_blockers_dir
            / f"step-{self.ctx.feature.step}-{self.ctx.feature.feature_id}-blockers.md"
        )

def _require_file(phase: str, path: Path, label: str) -> None:
    if not path.is_file():
        raise PhasePreconditionError(phase, f"{label} not found: {path}")
