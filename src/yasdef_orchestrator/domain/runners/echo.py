from __future__ import annotations

from collections.abc import Sequence

from .base import ModelRunner


class EchoRunner(ModelRunner):
    name = "echo"
    needs_tty = False
    captures_log = True

    def __init__(self, cmd: str = "echo") -> None:
        self._cmd = cmd
        self.name = cmd

    def build_argv(self, *, model: str, extras: Sequence[str], prompt: str) -> list[str]:
        return [self._cmd, "-m", model, *extras, prompt]

