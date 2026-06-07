from __future__ import annotations

from collections.abc import Sequence

from .base import ModelRunner


class CodexRunner(ModelRunner):
    name = "codex"
    needs_tty = True
    captures_log = True

    def build_argv(self, *, model: str, extras: Sequence[str], prompt: str) -> list[str]:
        return ["codex", "-m", model, *extras, prompt]

