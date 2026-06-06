from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum


class BranchPhase(str, Enum):
    PLAN = "plan"
    IMPLEMENTATION = "implementation"
    USER_REVIEW = "user-review"
    AI_AUDIT = "ai-audit"


@dataclass(frozen=True, slots=True)
class BranchSpec:
    target: str
    source_required: bool = False
    source_branch: str | None = None


def branch_phase_token(phase: str) -> str:
    normalized = phase.strip().lower().replace("_", "-")
    aliases = {
        "planning": BranchPhase.PLAN.value,
        "plan": BranchPhase.PLAN.value,
        "implementation": BranchPhase.IMPLEMENTATION.value,
        "user-review": BranchPhase.USER_REVIEW.value,
        "ai-audit": BranchPhase.AI_AUDIT.value,
    }
    if normalized not in aliases:
        raise ValueError(f"unsupported branch phase: {phase}")
    return aliases[normalized]


def step_branch_name(step: str, feature: str, phase: str) -> str:
    return f"step-{step}-{feature}-{branch_phase_token(phase)}"


def implementation_branch_spec(step: str, feature: str) -> BranchSpec:
    return BranchSpec(target=step_branch_name(step, feature, "implementation"))


def user_review_branch_spec(step: str, feature: str) -> BranchSpec:
    return BranchSpec(
        target=step_branch_name(step, feature, "user_review"),
        source_required=True,
        source_branch=step_branch_name(step, feature, "implementation"),
    )


def ai_audit_branch_spec(step: str, feature: str) -> BranchSpec:
    return BranchSpec(
        target=step_branch_name(step, feature, "ai_audit"),
        source_required=True,
        source_branch=step_branch_name(step, feature, "user_review"),
    )


_BRANCH_RE = re.compile(
    r"^step-([0-9]+(?:[.][0-9]+)*[a-z]?)-[^-].*-(plan|implementation|user-review|ai-audit)$"
)


def get_step_from_branch_name(branch: str) -> str | None:
    match = _BRANCH_RE.match(branch)
    if match is not None:
        return match.group(1)
    return None
