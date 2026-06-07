from __future__ import annotations

import re
from dataclasses import dataclass


class ImplementationPlanError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class StepBullet:
    raw: str
    checked: bool


@dataclass(frozen=True, slots=True)
class PlanStep:
    number: str
    title: str
    depends_on: tuple[str, ...]
    assigned_uuid: str | None
    bullets: tuple[StepBullet, ...]

    @property
    def unchecked_count(self) -> int:
        return sum(1 for bullet in self.bullets if not bullet.checked)

    @property
    def checked_count(self) -> int:
        return sum(1 for bullet in self.bullets if bullet.checked)


@dataclass(frozen=True, slots=True)
class ImplementationPlan:
    steps: tuple[PlanStep, ...]
    source_name: str = ""

    def step(self, number: str) -> PlanStep | None:
        for plan_step in self.steps:
            if plan_step.number == number:
                return plan_step
        return None

    def has_step(self, number: str) -> bool:
        return self.step(number) is not None

    def steps_assigned_to(self, worker_uuid: str) -> tuple[PlanStep, ...]:
        return tuple(step for step in self.steps if step.assigned_uuid == worker_uuid)

    @classmethod
    def parse(cls, content: str, *, source_name: str = "") -> ImplementationPlan:
        return parse_implementation_plan(content, source_name=source_name)


@dataclass(slots=True)
class _MutableStep:
    number: str
    title: str
    depends_on: tuple[str, ...]
    assigned_uuid: str | None
    bullets: list[StepBullet]


_STEP_RE = re.compile(r"^### Step ([^\s]+)(?:\s+(.*))?$")
_DEPENDS_RE = re.compile(r"^#### Depends on:\s*(.*)$")
_ASSIGNED_RE = re.compile(r"^#### Assigned:\s*(.*)$")
_BULLET_RE = re.compile(r"^- \[([ xX])\]\s*(.*)$")


def parse_implementation_plan(content: str, *, source_name: str = "") -> ImplementationPlan:
    steps: list[PlanStep] = []
    current: _MutableStep | None = None

    for raw in content.splitlines():
        line = raw.rstrip("\r")
        step_match = _STEP_RE.match(line)
        if step_match is not None:
            if current is not None:
                steps.append(_freeze_step(current))
            number = step_match.group(1)
            title = (step_match.group(2) or "").strip()
            current = _MutableStep(number, title, (), None, [])
            continue

        if current is None:
            continue

        depends_match = _DEPENDS_RE.match(line)
        if depends_match is not None:
            current.depends_on = _parse_depends(depends_match.group(1))
            continue

        assigned_match = _ASSIGNED_RE.match(line)
        if assigned_match is not None:
            assigned = assigned_match.group(1).strip()
            current.assigned_uuid = assigned or None
            continue

        bullet_match = _BULLET_RE.match(line)
        if bullet_match is not None:
            marker = bullet_match.group(1)
            current.bullets.append(StepBullet(line, marker.lower() == "x"))

    if current is not None:
        steps.append(_freeze_step(current))

    return ImplementationPlan(tuple(steps), source_name=source_name)


def step_exists_in_implementation_plan(plan: ImplementationPlan, step: str) -> bool:
    return plan.has_step(step)


def array_contains_ci(needle: str, values: tuple[str, ...]) -> bool:
    lowered = needle.lower()
    return any(value.lower() == lowered for value in values)


def _freeze_step(step: _MutableStep) -> PlanStep:
    return PlanStep(
        number=step.number,
        title=step.title,
        depends_on=step.depends_on,
        assigned_uuid=step.assigned_uuid,
        bullets=tuple(step.bullets),
    )


def _parse_depends(value: str) -> tuple[str, ...]:
    trimmed = value.strip()
    if not trimmed or trimmed.lower() == "none":
        return ()
    return tuple(part.strip() for part in trimmed.split(",") if part.strip())


