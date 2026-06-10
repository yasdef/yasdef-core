from __future__ import annotations

import argparse
import sys
from collections.abc import Callable
from pathlib import Path
from typing import TextIO

from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.user_output import TerminalUserOutput, UserOutput

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


def prompter(*, stdin: TextIO | None = None, stderr: TextIO | None = None) -> Prompter:
    return Prompter(
        stdin=stdin if stdin is not None else sys.stdin,
        stderr=stderr if stderr is not None else sys.stderr,
    )


def output(*, stderr: TextIO | None = None) -> UserOutput:
    return TerminalUserOutput(stderr if stderr is not None else sys.stderr)


def handle_error(exc: Exception, user_output: UserOutput | None = None) -> int:
    target = user_output if user_output is not None else output()
    if isinstance(exc, YasdefError):
        if exc.exit_code != EXIT_SUCCESS:
            target.failure(str(exc))
        return exc.exit_code
    else:
        target.failure("unexpected error", detail=str(exc))
    return EXIT_ERROR
