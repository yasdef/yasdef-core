from __future__ import annotations

from collections.abc import Sequence

from .base import ModelRunner


class ClaudeRunner(ModelRunner):
    name = "claude"
    needs_tty = True
    captures_log = True

    def build_argv(self, *, model: str, extras: Sequence[str], prompt: str) -> list[str]:
        return ["claude", "--model", model, *extras, prompt]

