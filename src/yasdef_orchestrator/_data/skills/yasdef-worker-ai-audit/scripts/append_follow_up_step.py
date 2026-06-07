#!/usr/bin/env python3
"""Append a canonical follow-up step block to implementation_plan.md.

The model invokes this during ai_audit Phase 2 disposition when a finding's
chosen disposition is `create follow-up step`. The script owns the structural
shape so the model never authors it by hand:

    ### Step <parent>.<letter> <title>
    #### Assigned: <worker-id>
    #### Repo: <parent-step-repo>
    #### Depends on: <parent-step-id>
    - [ ] Plan and discuss the step.
    - [ ] <action bullet 1>
    - [ ] <action bullet N>
    - [ ] Review step implementation.

The parent step's `#### Repo:` value is read from the plan; the letter suffix
is auto-picked as the next free letter (a..z). The new step id is printed on
stdout so the caller can use it for the `[x] follow_up_created: <id>` mark.
"""

from __future__ import annotations

import argparse
import re
import string
import sys
from pathlib import Path


STEP_HEADING_RE = re.compile(r"^###\s+Step\s+(\S+)\b(.*)$", re.IGNORECASE)
REPO_LINE_RE = re.compile(r"^####\s+Repo:\s*(.+?)\s*$")

PLAN_BOOKEND = "- [ ] Plan and discuss the step."
REVIEW_BOOKEND = "- [ ] Review step implementation."


class AppendError(Exception):
    """Raised when inputs are invalid or the plan cannot be safely amended."""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-plan", required=True, type=Path)
    parser.add_argument("--parent-step", required=True)
    parser.add_argument("--worker-id", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument(
        "--bullet",
        required=True,
        action="append",
        help="Action bullet text (without leading `- [ ]`). Repeatable.",
    )
    return parser.parse_args(argv)


def find_step_section(lines: list[str], step_id: str) -> tuple[int, int] | None:
    """Return (start_idx, end_idx_exclusive) for the `### Step <step_id>` section.

    The section ends at the next `### ` heading or EOF.
    """
    start = -1
    for idx, line in enumerate(lines):
        heading = STEP_HEADING_RE.match(line.rstrip())
        if heading and heading.group(1) == step_id:
            start = idx
            break
    if start == -1:
        return None
    end = len(lines)
    for idx in range(start + 1, len(lines)):
        if lines[idx].startswith("### "):
            end = idx
            break
    return start, end


def extract_repo(section_lines: list[str]) -> str:
    for line in section_lines:
        match = REPO_LINE_RE.match(line.rstrip())
        if match:
            return match.group(1).strip()
    return ""


def existing_suffix_letters(lines: list[str], parent_step: str) -> set[str]:
    prefix = f"{parent_step}"
    letters: set[str] = set()
    for line in lines:
        heading = STEP_HEADING_RE.match(line.rstrip())
        if not heading:
            continue
        step_id = heading.group(1)
        if not step_id.startswith(prefix) or step_id == parent_step:
            continue
        suffix = step_id[len(prefix) :]
        if len(suffix) == 1 and suffix in string.ascii_lowercase:
            letters.add(suffix)
    return letters


def next_free_letter(used: set[str]) -> str:
    for letter in string.ascii_lowercase:
        if letter not in used:
            return letter
    raise AppendError(
        "no free single-letter suffix (a..z) available for follow-up steps under this parent"
    )


def build_block(
    new_step_id: str,
    title: str,
    worker_id: str,
    repo: str,
    parent_step: str,
    bullets: list[str],
) -> list[str]:
    block = [
        f"### Step {new_step_id} {title}",
        f"#### Assigned: {worker_id}",
        f"#### Repo: {repo}",
        f"#### Depends on: {parent_step}",
        PLAN_BOOKEND,
    ]
    block.extend(f"- [ ] {bullet}" for bullet in bullets)
    block.append(REVIEW_BOOKEND)
    return block


def insert_block(lines: list[str], end_idx: int, block_lines: list[str]) -> list[str]:
    """Insert block_lines at end_idx, padded with a blank line above and below."""
    head = lines[:end_idx]
    tail = lines[end_idx:]
    pad_above = [] if head and head[-1].strip() == "" else [""]
    pad_below = [] if tail and tail[0].strip() == "" else [""]
    return head + pad_above + block_lines + pad_below + tail


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        if not args.runtime_plan.is_file():
            raise AppendError(f"runtime plan not found: {args.runtime_plan}")
        text = args.runtime_plan.read_text(encoding="utf-8")
        lines = text.splitlines()

        section = find_step_section(lines, args.parent_step)
        if section is None:
            raise AppendError(
                f"parent step `### Step {args.parent_step}` not found in {args.runtime_plan}"
            )
        start_idx, end_idx = section
        repo = extract_repo(lines[start_idx:end_idx])
        if not repo:
            raise AppendError(
                f"parent step `### Step {args.parent_step}` has no `#### Repo:` heading; "
                "add it before creating a follow-up step"
            )

        used = existing_suffix_letters(lines, args.parent_step)
        letter = next_free_letter(used)
        new_step_id = f"{args.parent_step}{letter}"

        bullets = [b.strip() for b in args.bullet if b.strip()]
        if not bullets:
            raise AppendError("at least one --bullet is required (action bullets only)")

        block = build_block(
            new_step_id=new_step_id,
            title=args.title.strip(),
            worker_id=args.worker_id,
            repo=repo,
            parent_step=args.parent_step,
            bullets=bullets,
        )
        new_lines = insert_block(lines, end_idx, block)
        new_text = "\n".join(new_lines)
        if text.endswith("\n") and not new_text.endswith("\n"):
            new_text += "\n"
        args.runtime_plan.write_text(new_text, encoding="utf-8")
        print(new_step_id)
        return 0
    except AppendError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
