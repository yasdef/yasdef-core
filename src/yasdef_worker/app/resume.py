from __future__ import annotations

import re
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import ClassVar, Protocol

from yasdef_worker.domain.phases import WORKFLOW_PHASES
from yasdef_worker.domain.phase_types import PhaseResult, PhaseStatus
from pathlib import Path

from yasdef_worker.domain.plans.implementation_plan import ImplementationPlan
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout

class ResumeFeature(Protocol):
    feature_id: str


@dataclass(frozen=True, slots=True)
class StepGateCounts:
    plan_checked: bool
    review_checked: bool
    implementation_total: int
    implementation_checked: int


class PhaseStateEvaluator(ABC):
    phase: ClassVar[str]

    @abstractmethod
    def evaluate(
        self,
        *,
        step: str,
        feature: ResumeFeature,
        plan: ImplementationPlan,
        counts: StepGateCounts,
        layout: RuntimeLayout,
        git: GitRepo,
    ) -> PhaseResult:
        raise NotImplementedError


class DesignStateEvaluator(PhaseStateEvaluator):
    phase = "design"

    def evaluate(
        self,
        *,
        step: str,
        feature: ResumeFeature,
        plan: ImplementationPlan,
        counts: StepGateCounts,
        layout: RuntimeLayout,
        git: GitRepo,
    ) -> PhaseResult:
        path = layout.step_designs_dir / f"step-{step}-{feature.feature_id}-design.md"
        if path.is_file():
            return PhaseResult(self.phase, PhaseStatus.COMPLETE, "design artifact present")
        return PhaseResult(self.phase, PhaseStatus.INCOMPLETE, f"missing {path}")


class PlanningStateEvaluator(PhaseStateEvaluator):
    phase = "planning"

    def evaluate(
        self,
        *,
        step: str,
        feature: ResumeFeature,
        plan: ImplementationPlan,
        counts: StepGateCounts,
        layout: RuntimeLayout,
        git: GitRepo,
    ) -> PhaseResult:
        step_plan = layout.step_plans_dir / f"step-{step}-{feature.feature_id}.md"
        if counts.plan_checked and step_plan.is_file():
            return PhaseResult(
                self.phase,
                PhaseStatus.COMPLETE,
                "step plan present and planning gate closed",
            )
        if counts.implementation_checked > 0 or counts.review_checked:
            return PhaseResult(
                self.phase,
                PhaseStatus.COMPLETE,
                "later-phase execution markers detected",
            )
        return PhaseResult(self.phase, PhaseStatus.INCOMPLETE, "later-phase execution has not started")


class ImplementationStateEvaluator(PhaseStateEvaluator):
    phase = "implementation"

    def evaluate(
        self,
        *,
        step: str,
        feature: ResumeFeature,
        plan: ImplementationPlan,
        counts: StepGateCounts,
        layout: RuntimeLayout,
        git: GitRepo,
    ) -> PhaseResult:
        step_plan = layout.step_plans_dir / f"step-{step}-{feature.feature_id}.md"
        if not step_plan.is_file():
            return PhaseResult(self.phase, PhaseStatus.FAILED, f"missing {step_plan}")
        branch = f"step-{step}-{feature.feature_id}-implementation"
        if (
            _review_artifact(layout, step, feature.feature_id).is_file()
            or git.branch_exists(f"step-{step}-{feature.feature_id}-user-review")
            or git.branch_exists(branch)
        ):
            return PhaseResult(self.phase, PhaseStatus.COMPLETE, "implementation marker detected")
        return PhaseResult(self.phase, PhaseStatus.INCOMPLETE, f"missing implementation marker {branch}")


class UserReviewStateEvaluator(PhaseStateEvaluator):
    phase = "user_review"

    def evaluate(
        self,
        *,
        step: str,
        feature: ResumeFeature,
        plan: ImplementationPlan,
        counts: StepGateCounts,
        layout: RuntimeLayout,
        git: GitRepo,
    ) -> PhaseResult:
        branch = f"step-{step}-{feature.feature_id}-user-review"
        if _review_artifact(layout, step, feature.feature_id).is_file() or git.branch_exists(branch):
            return PhaseResult(self.phase, PhaseStatus.COMPLETE, "user_review marker detected")
        return PhaseResult(self.phase, PhaseStatus.INCOMPLETE, f"missing user_review marker {branch}")


class AiAuditStateEvaluator(PhaseStateEvaluator):
    phase = "ai_audit"

    def evaluate(
        self,
        *,
        step: str,
        feature: ResumeFeature,
        plan: ImplementationPlan,
        counts: StepGateCounts,
        layout: RuntimeLayout,
        git: GitRepo,
    ) -> PhaseResult:
        artifact = _review_artifact(layout, step, feature.feature_id)
        if artifact.is_file():
            return PhaseResult(self.phase, PhaseStatus.COMPLETE, "review artifact present")
        return PhaseResult(self.phase, PhaseStatus.INCOMPLETE, f"missing {artifact}")


class PostReviewStateEvaluator(PhaseStateEvaluator):
    phase = "post_review"

    def evaluate(
        self,
        *,
        step: str,
        feature: ResumeFeature,
        plan: ImplementationPlan,
        counts: StepGateCounts,
        layout: RuntimeLayout,
        git: GitRepo,
    ) -> PhaseResult:
        if not counts.review_checked:
            return PhaseResult(
                self.phase,
                PhaseStatus.INCOMPLETE,
                "review gate 'Review step implementation' is not [x]",
            )
        if not layout.history_file.is_file():
            return PhaseResult(self.phase, PhaseStatus.INCOMPLETE, f"missing {layout.history_file}")
        history = layout.history_file.read_text(encoding="utf-8")
        if re.search(rf"^- Step:\s+{re.escape(step)}(?:\s|$)", history, re.MULTILINE) is None:
            return PhaseResult(self.phase, PhaseStatus.INCOMPLETE, f"no history record found for step {step}")
        return PhaseResult(self.phase, PhaseStatus.COMPLETE, "review gate closed and history contains step record")


DEFAULT_EVALUATORS: tuple[PhaseStateEvaluator, ...] = (
    DesignStateEvaluator(),
    PlanningStateEvaluator(),
    ImplementationStateEvaluator(),
    UserReviewStateEvaluator(),
    AiAuditStateEvaluator(),
    PostReviewStateEvaluator(),
)


@dataclass(frozen=True, slots=True)
class ResumeAnalysis:
    states: tuple[PhaseResult, ...]
    start_phase: str | None

    @property
    def all_done(self) -> bool:
        return self.start_phase is None

    @property
    def blocked(self) -> bool:
        for state in self.states:
            if state.status is PhaseStatus.FAILED:
                return True
            if not state.is_complete:
                # Phases after the first incomplete haven't run yet; their state is meaningless.
                return False
        return False

    @property
    def block_reason(self) -> str | None:
        for state in self.states:
            if state.status is PhaseStatus.FAILED:
                return state.detail
        return None

    def phases_to_execute(self) -> tuple[str, ...]:
        if self.start_phase is None or self.blocked:
            return ()
        start = WORKFLOW_PHASES.index(self.start_phase)
        return WORKFLOW_PHASES[start:]

    def dry_run_report(self, step: str) -> str:
        lines = [f"Resume dry-run for step {step}"]
        for state in self.states:
            lines.append(f"  - {state.phase}: {state.status.value} ({state.detail})")
        if self.blocked:
            lines.append("Selected start phase: none (resume blocked by invalid phase state)")
            lines.append(f"Skipped phases: {' '.join(WORKFLOW_PHASES)}")
            lines.append("Executed phases: (none)")
            lines.append(f"Block reason: {self.block_reason}")
        elif self.all_done:
            lines.append("Selected start phase: none (all phases complete)")
            lines.append(f"Skipped phases: {' '.join(WORKFLOW_PHASES)}")
            lines.append("Executed phases: (none)")
        else:
            executed = self.phases_to_execute()
            skipped = WORKFLOW_PHASES[: WORKFLOW_PHASES.index(self.start_phase or "design")]
            lines.append(f"Selected start phase: {self.start_phase}")
            lines.append(f"Skipped phases: {' '.join(skipped) if skipped else '(none)'}")
            lines.append(f"Executed phases: {' '.join(executed)}")
        return "\n".join(lines)


def analyze_resume(
    *,
    step: str,
    feature: ResumeFeature,
    plan: ImplementationPlan,
    layout: RuntimeLayout,
    git: GitRepo,
    evaluators: tuple[PhaseStateEvaluator, ...] = DEFAULT_EVALUATORS,
) -> ResumeAnalysis:
    counts = step_gate_counts(plan, step)
    states = tuple(
        evaluator.evaluate(
            step=step,
            feature=feature,
            plan=plan,
            counts=counts,
            layout=layout,
            git=git,
        )
        for evaluator in evaluators
    )
    start_phase = None
    for state in states:
        if not state.is_complete:
            start_phase = state.phase
            break
    return ResumeAnalysis(states, start_phase)


def step_gate_counts(plan: ImplementationPlan, step: str) -> StepGateCounts:
    plan_step = plan.step(step)
    if plan_step is None:
        return StepGateCounts(False, False, 0, 0)

    plan_checked = False
    review_checked = False
    implementation_total = 0
    implementation_checked = 0
    for bullet in plan_step.bullets:
        gate_text = _gate_text(bullet.raw)
        if gate_text.startswith("plan and discuss the step"):
            plan_checked = bullet.checked
            continue
        if gate_text.startswith("review step implementation"):
            review_checked = bullet.checked
            continue
        implementation_total += 1
        if bullet.checked:
            implementation_checked += 1
    return StepGateCounts(plan_checked, review_checked, implementation_total, implementation_checked)


def _gate_text(raw: str) -> str:
    text = re.sub(r"^- \[[ xX]\]\s*", "", raw).strip().lower()
    while True:
        stripped = re.sub(r"^\[[^]]+\]\s*", "", text)
        if stripped == text:
            return text
        text = stripped


def _review_artifact(layout: RuntimeLayout, step: str, feature_id: str) -> Path:
    return layout.step_review_results_dir / f"review_result-{step}-{feature_id}.md"
