from __future__ import annotations

from pathlib import Path

from yasdef_orchestrator.app.branch_manager import BranchManager
from yasdef_orchestrator.app.phases.base import Phase
from yasdef_orchestrator.domain.phase_types import PhaseResult
from yasdef_orchestrator.infra.errors import PhasePreconditionError


class AiAuditPhase(Phase):
    name = "ai_audit"
    requires_confirmation = True

    def preflight(self) -> None:
        _require_file(self.name, self.step_plan_path(), "step plan")
        _require_file(self.name, self.design_path(), "design artifact")
        _require_file(self.name, self.skill_file(), "ai audit skill")
        _require_file(self.name, self.entry_script(), "ai audit entry script")
        _require_file(self.name, self.context_script(), "ai audit context script")
        _require_file(self.name, self.closure_script(), "ai audit closure script")

    def prepare_branch(self) -> None:
        BranchManager(self.ctx.git, self.ctx.output).ensure_ai_audit_branch(
            step=self.ctx.feature.step,
            feature_id=self.ctx.feature.feature_id,
        )

    def build_prompt(self) -> str:
        return self.ctx.templates.load(self.name).format(
            step=self.ctx.feature.step,
            feature_id=self.ctx.feature.feature_id,
            branch=self.branch_name(),
            step_plan=self.step_plan_path(),
            design_file=self.design_path(),
            runtime_plan=self.ctx.layout.overmind_dir / "implementation_plan.md",
            worker_id=getattr(self.ctx.feature, "worker_uuid", ""),
        )

    def run(self, prompt: str, log_path: Path) -> PhaseResult:
        return self.run_model(prompt, log_path)

    def branch_name(self) -> str:
        return f"step-{self.ctx.feature.step}-{self.ctx.feature.feature_id}-ai-audit"

    def step_plan_path(self) -> Path:
        return self.ctx.layout.step_plans_dir / f"step-{self.ctx.feature.step}-{self.ctx.feature.feature_id}.md"

    def design_path(self) -> Path:
        return (
            self.ctx.layout.step_designs_dir
            / f"step-{self.ctx.feature.step}-{self.ctx.feature.feature_id}-design.md"
        )

    def skill_root(self) -> Path:
        return self.ctx.layout.worker_repo_root / ".codex" / "skills" / "yasdef-worker-ai-audit"

    def skill_file(self) -> Path:
        return self.skill_root() / "SKILL.md"

    def entry_script(self) -> Path:
        return self.skill_root() / "scripts" / "check_ai_audit_entry.py"

    def context_script(self) -> Path:
        return self.skill_root() / "scripts" / "build_ai_audit_context.py"

    def closure_script(self) -> Path:
        return self.skill_root() / "scripts" / "check_ai_audit_closure.py"


def _require_file(phase: str, path: Path, label: str) -> None:
    if not path.is_file():
        raise PhasePreconditionError(phase, f"{label} not found: {path}")
