from __future__ import annotations

from pathlib import Path

from yasdef_worker.app.history_writer import HistoryWriter
from yasdef_worker.app.metrics_collector import MetricsCollector
from yasdef_worker.app.phases.base import Phase
from yasdef_worker.app.post_review import (
    PlanSyncOperation,
    PostReviewInput,
    PostReviewOperation,
    RetryPolicy,
    TokenUsageResolver,
)
from yasdef_worker.domain.phase_types import PhaseResult
from yasdef_worker.domain.plans.implementation_plan import ImplementationPlan
from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.git_repo import GitRepo


class PostReviewPhase(Phase):
    name = "post_review"
    requires_confirmation = True

    def execute(self) -> PhaseResult:
        step = self.ctx.feature.step
        feature_id = self.ctx.feature.feature_id
        source_plan = self.ctx.feature.source_plan_path

        plan = ImplementationPlan.parse(
            source_plan.read_text(encoding="utf-8"),
            source_name=str(source_plan),
        )
        plan_step = plan.step(step)
        title = plan_step.title if plan_step is not None else ""

        source_git = GitRepo(source_plan.parent.parent)
        plan_sync: PlanSyncOperation | None = None
        if source_git.is_inside_worktree():
            plan_sync = PlanSyncOperation(
                git=source_git,
                source_plan_path=source_plan,
                output=self.ctx.output,
                retry=RetryPolicy(self.ctx.prompts, self.ctx.output),
                step_number=step,
            )

        try:
            PostReviewOperation(
                layout=self.ctx.layout,
                git=self.ctx.git,
                history=HistoryWriter(self.ctx.layout),
                metrics=MetricsCollector(self.ctx.git),
                output=self.ctx.output,
                plan_sync=plan_sync,
            ).execute(
                PostReviewInput(
                    step=step,
                    feature_id=feature_id,
                    title=title,
                    step_plan_path=self.ctx.layout.step_plans_dir / f"step-{step}-{feature_id}.md",
                    phase_usages=TokenUsageResolver.for_layout(self.ctx.layout).collect(step=step),
                )
            )
        except YasdefError as exc:
            return self.failed(str(exc))
        return self.complete()

    def preflight(self) -> None:
        raise NotImplementedError

    def prepare_branch(self) -> None:
        raise NotImplementedError

    def build_prompt(self) -> str:
        raise NotImplementedError

    def run(self, prompt: str, log_path: Path) -> PhaseResult:
        raise NotImplementedError
