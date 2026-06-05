from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


class YasdefError(Exception):
    """Base class for user-facing orchestrator failures."""

    exit_code = 1


@dataclass(slots=True)
class ProcessFailed(YasdefError):
    argv: list[str]
    returncode: int
    log_path: Path | None = None
    stderr_tail: str | None = None

    def __post_init__(self) -> None:
        detail = f"process failed with exit code {self.returncode}: {' '.join(self.argv)}"
        if self.log_path is not None:
            detail += f" (log: {self.log_path})"
        if self.stderr_tail:
            detail += f"\n{self.stderr_tail}"
        Exception.__init__(self, detail)


@dataclass(slots=True)
class GitOperationFailed(YasdefError):
    op: str
    argv: list[str]
    returncode: int
    stderr: str

    def __post_init__(self) -> None:
        detail = f"git {self.op} failed with exit code {self.returncode}: {' '.join(self.argv)}"
        if self.stderr:
            detail += f"\n{self.stderr}"
        Exception.__init__(self, detail)


@dataclass(slots=True)
class InstallSafetyError(YasdefError):
    path: Path
    reason: str

    def __post_init__(self) -> None:
        Exception.__init__(self, f"install safety violation at {self.path}: {self.reason}")


@dataclass(slots=True)
class PhasePreconditionError(YasdefError):
    phase: str
    reason: str

    def __post_init__(self) -> None:
        Exception.__init__(self, f"{self.phase} phase precondition failed: {self.reason}")

