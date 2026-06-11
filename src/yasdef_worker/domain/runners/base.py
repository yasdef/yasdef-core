from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Sequence


class UnknownModelRunnerError(ValueError):
    pass


class ModelRunner(ABC):
    name: str
    needs_tty: bool
    captures_log: bool

    @abstractmethod
    def build_argv(self, *, model: str, extras: Sequence[str], prompt: str) -> list[str]:
        raise NotImplementedError


def get_runner(cmd: str) -> ModelRunner:
    from .claude import ClaudeRunner
    from .codex import CodexRunner
    from .echo import EchoRunner

    normalized = cmd.strip()
    registry: dict[str, type[ModelRunner]] = {
        "codex": CodexRunner,
        "claude": ClaudeRunner,
        "echo": EchoRunner,
    }
    runner_cls = registry.get(normalized)
    if runner_cls is None:
        raise UnknownModelRunnerError(f"unsupported model runner command: {cmd}")
    return runner_cls()
