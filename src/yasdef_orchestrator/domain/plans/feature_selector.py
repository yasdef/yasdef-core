from __future__ import annotations

from dataclasses import dataclass

from .implementation_plan import ImplementationPlan, ImplementationPlanError, PlanStep


@dataclass(frozen=True, slots=True)
class FeatureAnalysis:
    assigned_any: bool
    target_match: bool
    first_unchecked: str | None
    blocked_by: str | None


def analyze_for_worker(
    plan: ImplementationPlan,
    worker_uuid: str,
    target_step: str | None = None,
) -> FeatureAnalysis:
    assigned_steps = plan.steps_assigned_to(worker_uuid)
    assigned_any = bool(assigned_steps)
    target_match = target_step is not None and any(
        step.number == target_step for step in assigned_steps
    )
    blocked_by: str | None = None

    for step in plan.steps:
        if step.assigned_uuid != worker_uuid or step.unchecked_count == 0:
            continue

        blocking_step = _first_incomplete_dependency(plan, step)
        if blocking_step is None:
            return FeatureAnalysis(assigned_any, target_match, step.number, blocked_by)
        if blocked_by is None:
            blocked_by = blocking_step

    return FeatureAnalysis(assigned_any, target_match, None, blocked_by)


def plan_has_assigned_step_for_worker(
    plan: ImplementationPlan,
    worker_uuid: str,
    step_number: str,
) -> bool:
    step = plan.step(step_number)
    return step is not None and step.assigned_uuid == worker_uuid


def _first_incomplete_dependency(plan: ImplementationPlan, step: PlanStep) -> str | None:
    for dep in step.depends_on:
        dep_step = plan.step(dep)
        if dep_step is None:
            raise ImplementationPlanError(
                f"plan error: step {step.number} depends on {dep} "
                "which does not exist in the plan"
            )
        if not dep_step.bullets:
            raise ImplementationPlanError(
                f"plan error: dep step {dep} has zero bullets and cannot be considered complete"
            )
        if dep_step.unchecked_count > 0:
            return dep
    return None
