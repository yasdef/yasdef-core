from __future__ import annotations

from pathlib import Path

from yasdef_worker.app.branch_manager import BranchManager
from yasdef_worker.app.phases.base import Phase
from yasdef_worker.domain.phase_types import PhaseResult
from yasdef_worker.domain.plans.ledgers import ledger_has_entries
from yasdef_worker.infra.errors import PhasePreconditionError


class PlanningPhase(Phase):
    name = "planning"
    requires_confirmation = True

    def preflight(self) -> None:
        _require_file(self.name, self.design_path(), "design artifact")
        _require_file(self.name, self.readiness_script(), "planning readiness script")

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
            runtime_plan=self.ctx.layout.overmind_dir / "implementation_plan.md",
            open_questions_file=self.open_questions_path(),
            blockers_file=self.blockers_path(),
        )

    def run(self, prompt: str, log_path: Path) -> PhaseResult:
        result = self.run_model(prompt, log_path)
        if not result.is_complete:
            return result
        readiness = self.ctx.process.run(
            [
                "uv",
                "run",
                "python",
                str(self.readiness_script()),
                "--design",
                str(self.design_path()),
                "--step-plan",
                str(self.step_plan_path()),
                "--open-questions",
                str(self.open_questions_path()),
                "--blockers",
                str(self.blockers_path()),
            ],
            check=False,
        )
        ledgers_dirty = _ledger_path_has_entries(self.open_questions_path()) or _ledger_path_has_entries(
            self.blockers_path()
        )
        if readiness.returncode != 0 or ledgers_dirty:
            return self.incomplete("planning readiness failed or ledgers contain entries")
        return result

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

    def readiness_script(self) -> Path:
        return (
            self.ctx.layout.worker_repo_root
            / ".codex"
            / "skills"
            / "yasdef-worker-plan"
            / "scripts"
            / "check_planning_readiness.py"
        )


def _ledger_path_has_entries(path: Path) -> bool:
    if not path.is_file():
        return False
    return ledger_has_entries(path.read_text(encoding="utf-8"))


def _require_file(phase: str, path: Path, label: str) -> None:
    if not path.is_file():
        raise PhasePreconditionError(phase, f"{label} not found: {path}")
