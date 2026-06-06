from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class StepPlanHeader:
    step: str
    title: str


_STEP_PLAN_HEADER_RE = re.compile(r"^# Step Plan: ([^\s]+) - (.*)$")
_STEP_PLAN_PATH_RE = re.compile(r"^step-([0-9][0-9.]*)(-.*)?\.md$")


def extract_step_and_title(content: str) -> StepPlanHeader | None:
    for raw in content.splitlines():
        match = _STEP_PLAN_HEADER_RE.match(raw.rstrip("\r"))
        if match is not None:
            return StepPlanHeader(match.group(1), match.group(2))
    return None


def get_step_from_plan_path(path: str) -> str:
    base = path.rsplit("/", 1)[-1]
    step = base.removeprefix("step-")
    step = step.removesuffix(".md")
    return step.split("-", 1)[0]


def try_get_step_from_plan_path(path: str) -> str | None:
    base = path.rsplit("/", 1)[-1]
    match = _STEP_PLAN_PATH_RE.match(base)
    if match is None:
        return None
    return match.group(1)


def get_preferred_step_plan(
    *,
    current_branch: str,
    feature_id: str,
    plan_paths: tuple[str, ...],
    selected_step: str | None = None,
) -> str | None:
    from ..branches import get_step_from_branch_name
    from .step_sorting import sort_key

    branch_step = get_step_from_branch_name(current_branch)
    if branch_step is not None:
        expected_suffix = f"/step-{branch_step}-{feature_id}.md"
        expected_name = f"step-{branch_step}-{feature_id}.md"
        for path in plan_paths:
            if path.endswith(expected_suffix) or path.rsplit("/", 1)[-1] == expected_name:
                return path

    matching = [
        path
        for path in plan_paths
        if path.rsplit("/", 1)[-1].startswith("step-")
        and path.rsplit("/", 1)[-1].endswith(f"-{feature_id}.md")
    ]
    if matching:
        return max(matching, key=lambda path: (sort_key(get_step_from_plan_path(path)), path))

    if selected_step is not None:
        expected_name = f"step-{selected_step}-{feature_id}.md"
        for path in plan_paths:
            if path.rsplit("/", 1)[-1] == expected_name:
                return path
    return None

