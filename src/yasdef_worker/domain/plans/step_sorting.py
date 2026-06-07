from __future__ import annotations

import re

StepSortKey = tuple[tuple[int, str], ...]


def sort_key(step: str) -> StepSortKey:
    parts: list[tuple[int, str]] = []
    for part in step.split("."):
        match = re.match(r"^([0-9]*)(.*)$", part)
        if match is None:
            parts.append((0, part))
            continue
        number_text = match.group(1)
        suffix = match.group(2)
        number = int(number_text) if number_text else 0
        parts.append((number, suffix))
    return tuple(parts)


def make_sort_key(step: str) -> str:
    out: list[str] = []
    for number, suffix in sort_key(step):
        out.append(f"{number:010d}{suffix}")
    return ".".join(out)

