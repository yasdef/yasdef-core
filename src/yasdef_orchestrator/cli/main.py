from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from typing import cast

from yasdef_orchestrator import __version__

from . import init, post_review, register, run, uninstall
from ._shared import CommandHandler, EXIT_SUCCESS, handle_error


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="yasdef")
    parser.add_argument("--version", action="version", version=f"yasdef {__version__}")
    subparsers = parser.add_subparsers(dest="command", required=True)
    run.add_parser(subparsers)
    post_review.add_parser(subparsers)
    init.add_parser(subparsers)
    register.add_parser(subparsers)
    uninstall.add_parser(subparsers)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    handler = getattr(args, "handler", None)
    if handler is None:
        parser.print_help()
        return EXIT_SUCCESS
    typed_handler = cast(CommandHandler, handler)
    try:
        return typed_handler(args)
    except KeyboardInterrupt:
        return handle_error(RuntimeError("interrupted"))
    except Exception as exc:  # pragma: no cover - defensive boundary
        return handle_error(exc)


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main(sys.argv[1:]))
