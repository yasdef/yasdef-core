from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class PhaseStatus(str, Enum):
    COMPLETE = "complete"
    INCOMPLETE = "incomplete"
    BLOCKED = "blocked"
    SKIPPED = "skipped"
    FAILED = "failed"


@dataclass(frozen=True, slots=True)
class PhaseResult:
    phase: str
    status: PhaseStatus
    detail: str = ""

    @property
    def is_complete(self) -> bool:
        return self.status is PhaseStatus.COMPLETE

