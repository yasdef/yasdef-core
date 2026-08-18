from __future__ import annotations

from collections.abc import Sequence

from .base import ModelRunner


class CopilotRunner(ModelRunner):
    name = "copilot"
    needs_tty = True
    captures_log = True

    def build_argv(self, *, model: str, extras: Sequence[str], prompt: str) -> list[str]:
        # `-i` consumes the next argv element as the initial prompt, so extras stay
        # ahead of it and the rendered prompt is the single final element.
        return ["copilot", "--model", model, *extras, "-i", prompt]
