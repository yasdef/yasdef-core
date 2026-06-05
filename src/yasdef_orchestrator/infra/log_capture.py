from __future__ import annotations

import re
from pathlib import Path

from .layout import RuntimeLayout

SENTINEL_MARKER = (
    "phase finished. Nothing else to do now, press ctrl-c if it was not closed "
    "atomatically so we can start next phase"
)


class LogCapture:
    def __init__(self, layout: RuntimeLayout, *, debug: bool = False, project: str | None = None):
        self.layout = layout
        self.debug = debug
        self.project = project or layout.worker_repo_root.name

    def path_for(self, phase: str, step: str | None = None) -> Path:
        phase_token = _normalize_token(phase)
        if self.debug:
            step_token = _normalize_token(step or "unknown-step")
            return self.layout.logs_dir / f"{self.project}-{phase_token}-{step_token}-log"
        return self.layout.logs_dir / f"{self.project}-{phase_token}-latest-log"

    def sentinel_present(self, log_path: Path) -> bool:
        if not log_path.exists():
            return False
        content = log_path.read_bytes().decode("utf-8", errors="replace")
        return SENTINEL_MARKER in content


def _normalize_token(value: str) -> str:
    token = value.strip().lower().replace("-", "_")
    token = re.sub(r"[^a-z0-9_.]+", "_", token)
    token = re.sub(r"_+", "_", token).strip("_")
    return token or "unknown"
