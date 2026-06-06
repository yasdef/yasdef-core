from __future__ import annotations

from pathlib import Path

from yasdef_orchestrator.app.branch_manager import BranchManager
from yasdef_orchestrator.app.phases.base import Phase
from yasdef_orchestrator.domain.phase_types import PhaseResult
from yasdef_orchestrator.infra.errors import PhasePreconditionError


class DesignPhase(Phase):
    name = "design"
    requires_confirmation = True

    def preflight(self) -> None:
        if not self.ctx.feature.step:
            raise PhasePreconditionError(self.name, "step is required")
        if not self.ctx.feature.feature_id:
            raise PhasePreconditionError(self.name, "feature id is required")

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
            design_out=self.design_path(),
            runtime_plan=self.ctx.layout.overmind_dir / "implementation_plan.md",
            runtime_ears=self.ctx.layout.overmind_dir / "reqirements_ears.md",
        )

    def run(self, prompt: str, log_path: Path) -> PhaseResult:
        return self.run_model(prompt, log_path)

    def postflight(self, log_path: Path) -> None:
        if not self.design_path().is_file():
            raise PhasePreconditionError(self.name, f"design artifact not found: {self.design_path()}")
        readiness = (
            self.ctx.layout.worker_repo_root
            / ".codex"
            / "skills"
            / "yasdef-worker-design"
            / "scripts"
            / "check_design_readiness.py"
        )
        if readiness.is_file():
            self.ctx.process.run(["uv", "run", "python", str(readiness), str(self.design_path())])

    def branch_name(self) -> str:
        return f"step-{self.ctx.feature.step}-{self.ctx.feature.feature_id}-plan"

    def design_path(self) -> Path:
        return (
            self.ctx.layout.step_designs_dir
            / f"step-{self.ctx.feature.step}-{self.ctx.feature.feature_id}-design.md"
        )
