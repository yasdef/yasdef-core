from __future__ import annotations

import argparse

from yasdef_worker.app.register_worker import RegisterWorkerOperation
from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.prompts import Prompter

from ._shared import EXIT_SUCCESS, git_from_layout, output


def add_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("register", help="bind this worker to an ASDLC project")
    parser.set_defaults(handler=handle)


def handle(_args: argparse.Namespace) -> int:
    try:
        layout = RuntimeLayout.discover()
    except YasdefError as exc:
        raise YasdefError(
            "worker runtime is not initialized; run "
            "`yasdef init <path-to-your-worker-repo>` first, then run "
            "`yasdef register` from inside that worker repo"
        ) from exc
    RegisterWorkerOperation(
        layout=layout,
        git=git_from_layout(layout),
        output=output(),
        prompts=Prompter(),
    ).execute()
    return EXIT_SUCCESS
