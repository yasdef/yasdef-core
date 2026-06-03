#!/usr/bin/env python3
"""Copy the design LAR section into a step plan, idempotently."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def die(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def section_body(text: str, heading: str) -> str:
    pattern = re.compile(
        rf"(?ms)^##\s+{re.escape(heading)}\s*$\n(.*?)(?=^##\s+|\Z)"
    )
    match = pattern.search(text)
    return match.group(1).strip() if match else ""


def replace_or_append_section(step_plan_text: str, heading: str, body: str) -> str:
    block = f"## {heading}\n{body.strip()}\n"
    pattern = re.compile(
        rf"(?ms)^##\s+{re.escape(heading)}\s*$\n.*?(?=^##\s+|\Z)"
    )
    if pattern.search(step_plan_text):
        updated = pattern.sub(block, step_plan_text, count=1)
    else:
        separator = "" if step_plan_text.endswith("\n") or not step_plan_text else "\n"
        updated = f"{step_plan_text}{separator}\n{block}"
    return updated.rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--design", required=True)
    parser.add_argument("--step-plan", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    design_path = Path(args.design)
    step_plan_path = Path(args.step_plan)

    design_text = read_text(design_path)
    if not design_text.strip():
        die(f"design artifact not found or empty: {design_path}")

    step_plan_text = read_text(step_plan_path)
    if not step_plan_text.strip():
        die(f"step plan not found or empty: {step_plan_path}")

    heading = "Linked Artifacts (in scope)"
    lar_body = section_body(design_text, heading)
    if not lar_body.strip():
        return 0

    updated = replace_or_append_section(step_plan_text, heading, lar_body)
    step_plan_path.write_text(updated, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
