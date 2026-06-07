from __future__ import annotations

import argparse
from pathlib import Path

from yasdef_worker.app.register_worker import RegisterWorkerInput, RegisterWorkerOperation

from ._shared import EXIT_SUCCESS, add_repo_argument, git_from_layout, layout_from_args, output


def add_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("register", help="bind this worker to an overmind project")
    add_repo_argument(parser)
    parser.add_argument("overmind_source_path", type=Path, help="source overmind project repository")
    parser.add_argument("--worker-uuid", required=True, help="worker UUID from workers.yaml")
    parser.set_defaults(handler=handle)


def handle(args: argparse.Namespace) -> int:
    layout = layout_from_args(args)
    RegisterWorkerOperation(
        layout=layout,
        git=git_from_layout(layout),
        output=output(),
    ).execute(
        RegisterWorkerInput(
            worker_uuid=args.worker_uuid,
            overmind_source_path=args.overmind_source_path,
        )
    )
    return EXIT_SUCCESS
