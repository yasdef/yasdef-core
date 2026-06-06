from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class StepDesignHeader:
    step: str
    title: str


_FEATURE_DESIGN_HEADER_RE = re.compile(r"^# Feature Design: ([^\s]+) - (.*)$")
_STEP_DESIGN_PATH_RE = re.compile(r"^step-(.+)-design\.md$")


def extract_step_and_title(content: str) -> StepDesignHeader | None:
    for raw in content.splitlines():
        match = _FEATURE_DESIGN_HEADER_RE.match(raw.rstrip("\r"))
        if match is not None:
            return StepDesignHeader(match.group(1), match.group(2))
    return None


def get_step_from_design_path(path: str) -> str | None:
    base = path.rsplit("/", 1)[-1]
    match = _STEP_DESIGN_PATH_RE.match(base)
    if match is None:
        return None
    return match.group(1).split("-", 1)[0]

