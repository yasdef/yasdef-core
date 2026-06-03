#!/usr/bin/env python3
"""Validate ai_audit entry preconditions."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path.cwd()
ASDLC_HOME = ROOT / ".asdlc_worker"


def is_nonempty_file(path: Path) -> bool:
    try:
        return path.is_file() and bool(path.read_text(encoding="utf-8").strip())
    except OSError:
        return False


def branch_exists(branch: str) -> bool:
    result = subprocess.run(
        ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--step", required=True)
    parser.add_argument("--feature-id", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    step_plan = ASDLC_HOME / "step_plans" / f"step-{args.step}-{args.feature_id}.md"
    design = ASDLC_HOME / "step_designs" / f"step-{args.step}-{args.feature_id}-design.md"
    user_review_branch = f"step-{args.step}-{args.feature_id}-user-review"

    errors: list[str] = []
    if not is_nonempty_file(step_plan):
        errors.append(f"MISSING: step plan at {step_plan} - run planning phase first")
    if not is_nonempty_file(design):
        errors.append(f"MISSING: design artifact at {design} - run design phase first")
    if not branch_exists(user_review_branch):
        errors.append(
            "MISSING: user_review branch "
            f"{user_review_branch} - run user_review phase for this step first"
        )

    if errors:
        for message in errors:
            print(message, file=sys.stderr)
        return 1

    print(f"OK: ai_audit entry preconditions passed for step {args.step} ({args.feature_id})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
