from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path

from yasdef_orchestrator.domain.history.records import HistoryRecord
from yasdef_orchestrator.domain.history.token_usage import TokenUsage
from yasdef_orchestrator.infra.layout import RuntimeLayout

HISTORY_HEADER = (
    "# AI Run History\n\n"
    "This file is updated by `yasdef post-review` with one consolidated record per step.\n\n"
)


class HistoryWriter:
    def __init__(
        self,
        layout: RuntimeLayout,
        *,
        history_path: Path | None = None,
        now: Callable[[], datetime] | None = None,
    ):
        self.layout = layout
        self.history_path = history_path or layout.history_file
        self.now = now or (lambda: datetime.now(UTC))

    def ensure_history_file(self) -> None:
        if self.history_path.is_file():
            return
        self.history_path.parent.mkdir(parents=True, exist_ok=True)
        self.history_path.write_text(HISTORY_HEADER, encoding="utf-8")

    def write_record(self, record: HistoryRecord) -> None:
        self.ensure_history_file()
        self.remove_step_sections(record.step)
        with self.history_path.open("a", encoding="utf-8") as handle:
            handle.write(self.format_record(record))

    def remove_step_sections(self, step: str) -> None:
        if not self.history_path.is_file():
            return
        content = self.history_path.read_text(encoding="utf-8")
        self.history_path.write_text(_remove_step_sections(content, step), encoding="utf-8")

    def format_record(self, record: HistoryRecord) -> str:
        timestamp = self.now().astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        step_plan = _repo_relative(record.step_plan, self.layout.worker_repo_root)
        lines = [
            "",
            f"## {timestamp}",
            record.format_step_line(),
            f"- Token usage: {record.token_usage.format_human()}, including:",
        ]
        for phase, usage in record.phase_usages:
            lines.append(f"  - Phase: {phase} - {usage.format_human()}")
        lines.extend(
            [
                f"- New lines of code added: {record.metrics.loc_added:,}",
                f"- New files added: {record.metrics.files_added:,}",
                f"- Files touched: {record.metrics.files_touched:,}",
                f"- Step plan: {step_plan}",
            ]
        )
        return "\n".join(lines) + "\n"


def _remove_step_sections(content: str, step: str) -> str:
    prefix: list[str] = []
    sections: list[str] = []
    current: list[str] | None = None

    for line in content.splitlines(keepends=True):
        if line.startswith("## "):
            if current is not None:
                sections.append("".join(current))
            current = [line]
        elif current is None:
            prefix.append(line)
        else:
            current.append(line)
    if current is not None:
        sections.append("".join(current))

    kept = [section for section in sections if _section_step(section) != step]
    return "".join(prefix + kept)


def _section_step(section: str) -> str | None:
    for line in section.splitlines():
        if line.startswith("- Step: "):
            rest = line.removeprefix("- Step: ").strip()
            return rest.split(" ", 1)[0]
    return None


def _repo_relative(path: str, root: Path) -> str:
    candidate = Path(path)
    if candidate.is_absolute():
        try:
            return str(candidate.relative_to(root))
        except ValueError:
            return path
    return path


def total_usage(usages: tuple[tuple[str, TokenUsage], ...]) -> TokenUsage:
    total = TokenUsage()
    for _, usage in usages:
        total += usage
    return total
