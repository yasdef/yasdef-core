from __future__ import annotations

import argparse
from pathlib import Path

from yasdef_worker.app.init_asdlc_worker import (
    Installer,
    default_exclude_entries,
    default_install_entries,
)
from yasdef_worker.infra.git_repo import GitRepo

from ._shared import EXIT_SUCCESS, output


def add_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("init", help="install or update worker runtime data")
    parser.add_argument("target", type=Path, help="target git repository root")
    parser.add_argument("--force", action="store_true", help="overwrite manifest-guarded files")
    parser.set_defaults(handler=handle)


def handle(args: argparse.Namespace) -> int:
    target = args.target.resolve()
    user_output = output()
    Installer(
        target_root=target,
        output=user_output,
        entries=default_install_entries(target),
        exclude_entries=default_exclude_entries(),
        git=GitRepo(target),
        force=args.force,
    ).install()
    return EXIT_SUCCESS
