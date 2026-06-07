from __future__ import annotations

import argparse

from yasdef_orchestrator.app.orchestrator import Orchestrator, RunOptions
from yasdef_orchestrator.infra.process import ProcessRunner

from ._shared import (
    EXIT_ERROR,
    EXIT_SUCCESS,
    add_repo_argument,
    git_from_layout,
    layout_from_args,
    output,
    prompter,
)


def add_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("run", help="run the worker phase pipeline")
    add_repo_argument(parser)
    parser.add_argument("--resume", metavar="STEP", help="resume STEP from the first incomplete phase")
    parser.add_argument(
        "--phase",
        action="append",
        dest="phases",
        default=[],
        help="phase to execute; may be passed multiple times",
    )
    parser.add_argument("--dry-run", action="store_true", help="evaluate without model execution")
    parser.add_argument("--debug", action="store_true", help="write debug phase logs")
    parser.set_defaults(handler=handle)


def handle(args: argparse.Namespace) -> int:
    layout = layout_from_args(args)
    user_output = output()
    result = Orchestrator(
        layout=layout,
        git=git_from_layout(layout),
        prompts=prompter(),
        process=ProcessRunner(),
        output=user_output,
    ).run(
        RunOptions(
            resume_step=args.resume,
            phases=tuple(args.phases),
            dry_run=args.dry_run,
            debug=args.debug,
        )
    )
    if result.succeeded:
        return EXIT_SUCCESS
    user_output.failure("pipeline stopped", detail=result.stop_reason)
    return EXIT_ERROR
