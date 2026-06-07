from __future__ import annotations

from dataclasses import dataclass
from typing import TypeAlias

from yasdef_worker.app.phases import (
    AiAuditPhase,
    DesignPhase,
    ImplementationPhase,
    Phase,
    PhaseContext,
    PlanningPhase,
    UserReviewPhase,
    normalize_phase_token,
)
from yasdef_worker.domain.phase_types import PhaseResult, PhaseStatus
from yasdef_worker.infra.errors import YasdefError

PhaseType: TypeAlias = type[Phase]

DEFAULT_PHASES: dict[str, PhaseType] = {
    "design": DesignPhase,
    "planning": PlanningPhase,
    "implementation": ImplementationPhase,
    "user_review": UserReviewPhase,
    "ai_audit": AiAuditPhase,
}


@dataclass(frozen=True, slots=True)
class PipelineResult:
    executed: tuple[PhaseResult, ...]
    stopped: bool = False
    stop_reason: str = ""

    @property
    def succeeded(self) -> bool:
        return not self.stopped and all(result.is_complete for result in self.executed)


class Pipeline:
    def __init__(
        self,
        *,
        ctx: PhaseContext,
        phase_types: dict[str, PhaseType] | None = None,
    ):
        self.ctx = ctx
        self.phase_types = dict(phase_types or DEFAULT_PHASES)

    def iterate(self, phases: tuple[str, ...]) -> PipelineResult:
        executed: list[PhaseResult] = []
        for requested in phases:
            phase_name = normalize_phase_token(requested)
            phase_type = self.phase_types.get(phase_name)
            if phase_type is None:
                result = PhaseResult(phase_name, PhaseStatus.FAILED, "unknown phase")
                executed.append(result)
                return PipelineResult(tuple(executed), stopped=True, stop_reason=result.detail)

            if phase_type.requires_confirmation and self.ctx.prompts.interactive:
                if not self.ctx.prompts.confirm(f"Proceed with {phase_name} phase?", default=True):
                    detail = f"user denied phase progression at {phase_name}"
                    result = PhaseResult(phase_name, PhaseStatus.SKIPPED, detail)
                    executed.append(result)
                    return PipelineResult(tuple(executed), stopped=True, stop_reason=detail)

            try:
                result = phase_type(self.ctx).execute()
            except YasdefError as exc:
                result = PhaseResult(phase_name, PhaseStatus.FAILED, str(exc))
            executed.append(result)
            if not result.is_complete:
                return PipelineResult(tuple(executed), stopped=True, stop_reason=result.detail)

        return PipelineResult(tuple(executed))
