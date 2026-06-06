from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class TokenUsage:
    total: int = 0
    input: int = 0
    cached: int = 0
    output: int = 0
    reasoning: int = 0
    raw: str = ""

    @classmethod
    def parse(cls, line: str) -> TokenUsage | None:
        usage = extract_token_usage_line(line)
        if usage is None:
            return None
        return cls(
            total=_extract_value(usage, "total"),
            input=_extract_value(usage, "input"),
            cached=_extract_cached(usage),
            output=_extract_value(usage, "output"),
            reasoning=_extract_reasoning(usage),
            raw=usage,
        )

    def __add__(self, other: TokenUsage) -> TokenUsage:
        return TokenUsage(
            total=self.total + other.total,
            input=self.input + other.input,
            cached=self.cached + other.cached,
            output=self.output + other.output,
            reasoning=self.reasoning + other.reasoning,
            raw="",
        )

    def format_human(self) -> str:
        return (
            f"total={self.total:,} input={self.input:,} (+ {self.cached:,} cached) "
            f"output={self.output:,} (reasoning {self.reasoning:,})"
        )


def extract_token_usage_line(content: str) -> str | None:
    latest: str | None = None
    for raw in content.splitlines():
        if "Token usage:" in raw:
            latest = raw.split("Token usage:", 1)[1].replace("\r", "").lstrip()
    return latest


def _extract_value(usage: str, key: str) -> int:
    match = re.search(rf"{re.escape(key)}=([0-9,][0-9,]*)", usage)
    return _to_int(match.group(1)) if match is not None else 0


def _extract_cached(usage: str) -> int:
    match = re.search(r"\(\+\s*([0-9,][0-9,]*)\s+cached\)", usage)
    return _to_int(match.group(1)) if match is not None else 0


def _extract_reasoning(usage: str) -> int:
    match = re.search(r"\(reasoning\s+([0-9,][0-9,]*)\)", usage)
    return _to_int(match.group(1)) if match is not None else 0


def _to_int(value: str) -> int:
    return int(value.replace(",", ""))

