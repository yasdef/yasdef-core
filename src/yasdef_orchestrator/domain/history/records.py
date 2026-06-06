from __future__ import annotations

from dataclasses import dataclass

from .token_usage import TokenUsage


@dataclass(frozen=True, slots=True)
class Metrics:
    loc_added: int = 0
    files_added: int = 0
    files_touched: int = 0
    direction_note: str = ""

    def __add__(self, other: Metrics) -> Metrics:
        note = self.direction_note or other.direction_note
        if self.direction_note and other.direction_note and self.direction_note != other.direction_note:
            note = f"{self.direction_note}; {other.direction_note}"
        return Metrics(
            loc_added=self.loc_added + other.loc_added,
            files_added=self.files_added + other.files_added,
            files_touched=self.files_touched + other.files_touched,
            direction_note=note,
        )

    def format_human(self) -> str:
        return (
            f"new lines of code added: {self.loc_added:,}\n"
            f"new files added: {self.files_added:,}\n"
            f"files touched: {self.files_touched:,}"
        )


@dataclass(frozen=True, slots=True)
class HistoryRecord:
    step: str
    title: str
    step_plan: str
    token_usage: TokenUsage
    metrics: Metrics
    phase_usages: tuple[tuple[str, TokenUsage], ...] = ()

    def format_step_line(self) -> str:
        if self.title:
            return f"- Step: {self.step} - {self.title}"
        return f"- Step: {self.step}"

