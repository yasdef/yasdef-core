from __future__ import annotations

import argparse
import os
import shutil
import subprocess

from yasdef_worker.infra.errors import YasdefError

from ._shared import EXIT_ERROR, EXIT_SUCCESS, output, prompter


def add_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("uninstall", help="uninstall the global yasdef tool")
    parser.add_argument("--yes", action="store_true", help="skip the confirmation prompt")
    parser.set_defaults(handler=handle)


def handle(args: argparse.Namespace) -> int:
    user_output = output()
    argv = _detect_uninstall_argv()
    if not args.yes:
        if not prompter().confirm(
            f"Uninstall the global yasdef tool by running: {' '.join(argv)}?",
            default=False,
        ):
            user_output.warn("uninstall cancelled")
            return EXIT_ERROR
    subprocess.run(argv, check=True)
    return EXIT_SUCCESS


def _detect_uninstall_argv() -> list[str]:
    executable = os.environ.get("YASDEF_INSTALLER")
    if executable == "uv" and shutil.which("uv"):
        return ["uv", "tool", "uninstall", "yasdef-worker"]
    if executable == "pipx" and shutil.which("pipx"):
        return ["pipx", "uninstall", "yasdef-worker"]
    if shutil.which("uv"):
        return ["uv", "tool", "uninstall", "yasdef-worker"]
    if shutil.which("pipx"):
        return ["pipx", "uninstall", "yasdef-worker"]
    raise YasdefError("cannot detect install method; expected uv or pipx on PATH")
