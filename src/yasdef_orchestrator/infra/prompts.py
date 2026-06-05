from __future__ import annotations

import sys
from collections.abc import Sequence
from typing import TextIO

from .errors import YasdefError


class Prompter:
    def __init__(
        self,
        *,
        stdin: TextIO | None = None,
        stderr: TextIO | None = None,
        interactive: bool | None = None,
    ):
        self.stdin = stdin if stdin is not None else sys.stdin
        self.stderr = stderr if stderr is not None else sys.stderr
        self.interactive = self.stdin.isatty() if interactive is None else interactive

    def confirm(self, prompt: str, *, default: bool | None = None) -> bool:
        if not self.interactive:
            if default is not None:
                return default
            raise YasdefError(f"cannot prompt in non-interactive mode: {prompt}")

        suffix = " [y/n] " if default is None else (" [Y/n] " if default else " [y/N] ")
        self.stderr.write(prompt + suffix)
        self.stderr.flush()
        value = self.stdin.readline().strip().lower()
        if not value and default is not None:
            return default
        return value in {"y", "yes"}

    def choose_numbered(self, prompt: str, options: Sequence[str]) -> int:
        if not options:
            raise ValueError("numbered prompt requires at least one option")
        if not self.interactive:
            raise YasdefError(f"cannot prompt in non-interactive mode: {prompt}")

        self.stderr.write(prompt + "\n")
        for index, option in enumerate(options, start=1):
            self.stderr.write(f"{index}. {option}\n")
        self.stderr.flush()
        value = self.stdin.readline().strip()
        try:
            selected = int(value)
        except ValueError as exc:
            raise YasdefError(f"invalid selection: {value}") from exc
        if selected < 1 or selected > len(options):
            raise YasdefError(f"selection out of range: {selected}")
        return selected - 1
