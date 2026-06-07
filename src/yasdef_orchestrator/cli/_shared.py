from __future__ import annotations

import argparse
import sys
from collections.abc import Callable
from pathlib import Path

from yasdef_orchestrator.infra.errors import YasdefError
from yasdef_orchestrator.infra.git_repo import GitRepo
from yasdef_orchestrator.infra.layout import RuntimeLayout
from yasdef_orchestrator.infra.prompts import Prompter
from yasdef_orchestrator.infra.user_output import TerminalUserOutput, UserOutput

EXIT_SUCCESS = 0
EXIT_ERROR = 1

CommandHandler = Callable[[argparse.Namespace], int]


def add_repo_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--repo",
        type=Path,
        default=None,
        help="worker repository root; defaults to discovering .asdlc_worker from cwd",
    )


def layout_from_args(args: argparse.Namespace) -> RuntimeLayout:
    repo = getattr(args, "repo", None)
    if repo is not None:
        return RuntimeLayout.from_root(repo)
    return RuntimeLayout.discover()


def git_from_layout(layout: RuntimeLayout) -> GitRepo:
    return GitRepo(layout.worker_repo_root)


def prompter() -> Prompter:
    return Prompter(stdin=sys.stdin, stderr=sys.stderr)


def output() -> UserOutput:
    return TerminalUserOutput(sys.stderr)


def handle_error(exc: Exception, user_output: UserOutput | None = None) -> int:
    target = user_output if user_output is not None else output()
    if isinstance(exc, YasdefError):
        target.failure(str(exc))
    else:
        target.failure("unexpected error", detail=str(exc))
    return EXIT_ERROR
