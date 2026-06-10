from __future__ import annotations

from pathlib import Path

from yasdef_worker.app.branch_manager import BranchManager
from yasdef_worker.app.phases.base import Phase
from yasdef_worker.domain.phase_types import PhaseResult
from yasdef_worker.infra.errors import PhasePreconditionError


class AiAuditPhase(Phase):
    name = "ai_audit"
    requires_confirmation = True

    def preflight(self) -> None:
        _require_file(self.name, self.step_plan_path(), "step plan")
        _require_file(self.name, self.design_path(), "design artifact")
        self.skill_file()
        self.entry_script()
        self.context_script()
        self.closure_script()

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
            runtime_plan=self.ctx.feature.source_plan_path,
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

    def skill_file(self) -> Path:
        return self.installed_skill_file(
            "yasdef-worker-ai-audit",
            "SKILL.md",
            label="ai audit skill",
        )

    def entry_script(self) -> Path:
        return self.installed_skill_file(
            "yasdef-worker-ai-audit",
            "scripts",
            "check_ai_audit_entry.py",
            label="ai audit entry script",
        )

    def context_script(self) -> Path:
        return self.installed_skill_file(
            "yasdef-worker-ai-audit",
            "scripts",
            "build_ai_audit_context.py",
            label="ai audit context script",
        )

    def closure_script(self) -> Path:
        return self.installed_skill_file(
            "yasdef-worker-ai-audit",
            "scripts",
            "check_ai_audit_closure.py",
            label="ai audit closure script",
        )


def _require_file(phase: str, path: Path, label: str) -> None:
    if not path.is_file():
        raise PhasePreconditionError(phase, f"{label} not found: {path}")
