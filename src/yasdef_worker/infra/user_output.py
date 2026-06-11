from __future__ import annotations

import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import TextIO


class UserOutput(ABC):
    @abstractmethod
    def info(self, msg: str) -> None:
        ...

    @abstractmethod
    def warn(self, msg: str) -> None:
        ...

    @abstractmethod
    def failure(self, msg: str, *, detail: str | None = None) -> None:
        ...

    @abstractmethod
    def step(self, msg: str) -> None:
        ...

    @abstractmethod
    def event(self, kind: str, **fields: object) -> None:
        ...


class TerminalUserOutput(UserOutput):
    def __init__(self, stream: TextIO | None = None):
        self.stream = stream if stream is not None else sys.stderr

    def info(self, msg: str) -> None:
        self.stream.write(f"{msg}\n")

    def warn(self, msg: str) -> None:
        self.stream.write(f"WARNING: {msg}\n")

    def failure(self, msg: str, *, detail: str | None = None) -> None:
        self.stream.write(f"ERROR: {msg}\n")
        if detail:
            self.stream.write(f"{detail}\n")

    def step(self, msg: str) -> None:
        self.stream.write(f"yasdef: {msg}\n")

    def event(self, kind: str, **fields: object) -> None:
        formatted = _format_event_fields(fields)
        if formatted:
            self.stream.write(f"{kind}: {formatted}\n")
        else:
            self.stream.write(f"{kind}\n")


@dataclass(frozen=True, slots=True)
class OutputEvent:
    level: str
    message: str
    fields: dict[str, object]
    kind: str | None = None


class RecordingUserOutput(UserOutput):
    def __init__(self) -> None:
        self.events: list[OutputEvent] = []

    def info(self, msg: str) -> None:
        self.events.append(OutputEvent("info", msg, {}))

    def warn(self, msg: str) -> None:
        self.events.append(OutputEvent("warn", msg, {}))

    def failure(self, msg: str, *, detail: str | None = None) -> None:
        fields: dict[str, object] = {}
        if detail is not None:
            fields["detail"] = detail
        self.events.append(OutputEvent("failure", msg, fields))

    def step(self, msg: str) -> None:
        self.events.append(OutputEvent("step", msg, {}))

    def event(self, kind: str, **fields: object) -> None:
        self.events.append(OutputEvent("event", kind, fields, kind=kind))


def _format_event_fields(fields: dict[str, object]) -> str:
    return " ".join(f"{key}={fields[key]!r}" for key in sorted(fields))
