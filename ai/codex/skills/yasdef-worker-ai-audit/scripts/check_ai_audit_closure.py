#!/usr/bin/env python3
"""Validate ai_audit per-finding closure state and artifact links."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path


WORKER_HOME_DIR = ".asdlc_worker"
PROJECTS_DIR = "projects"


class Disposition(Enum):
    FOLLOW_UP_CREATED = "follow_up_created"
    RAISED_TO_COORDINATOR = "raised_to_coordinator"
    REJECTED = "rejected"


DISPOSITION_KEYWORDS = "|".join(d.value for d in Disposition)
DISPOSITION_LINE_RE = re.compile(
    rf"^\s*-\s+\[(?P<mark>[ xX])\]\s+(?P<keyword>{DISPOSITION_KEYWORDS})\s*:?\s*(?P<ref>.*)$"
)
FINDING_HEADING_RE = re.compile(r"(?m)^###\s+(F-\d+)\b.*$")
STEP_HEADING_RE = re.compile(r"^###\s+Step\s+(\S+)\b", re.IGNORECASE)
ASSIGNED_LINE_RE = re.compile(r"^####\s+Assigned:\s*(.+?)\s*$")
BULLET_LINE_RE = re.compile(r"^\s*-\s+\[(?P<mark>[ xX])\]\s+(?P<text>.+?)\s*$")


class ClosureError(Exception):
    """Raised when required closure inputs are missing or malformed."""


@dataclass
class Finding:
    finding_id: str
    states: dict[Disposition, str]  # only contains entries whose checkbox is `[x]`

    @property
    def checked_states(self) -> list[Disposition]:
        return list(self.states.keys())


@dataclass
class StepBlock:
    step_id: str
    assigned: str
    unchecked_bullets: list[str]


def read_nonempty(path: Path, label: str) -> str:
    if not path.is_file():
        raise ClosureError(f"{label} not found: {path}")
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        raise ClosureError(f"{label} is empty: {path}")
    return text


def derive_asdlc_repo_root(runtime_plan: Path) -> Path:
    """Return the ASDLC repo root from `<root>/projects/<project>/<feature>/implementation_plan.md`."""
    resolved = runtime_plan.resolve()
    parts = resolved.parts
    if len(parts) < 5 or parts[-1] != "implementation_plan.md":
        raise ClosureError(
            "runtime plan must point at "
            f"<asdlc-repo>/{PROJECTS_DIR}/<project>/<feature>/implementation_plan.md: {runtime_plan}"
        )
    if parts[-4] != PROJECTS_DIR:
        raise ClosureError(
            "runtime plan must sit under "
            f"<asdlc-repo>/{PROJECTS_DIR}/<project>/<feature>/: {runtime_plan}"
        )
    return Path(*parts[:-4])


def parse_findings(review_text: str) -> list[Finding]:
    parts = FINDING_HEADING_RE.split(review_text)
    if len(parts) < 3:
        return []

    findings: list[Finding] = []
    for finding_id, body in zip(parts[1::2], parts[2::2]):
        states: dict[Disposition, str] = {}
        for line in body.splitlines():
            match = DISPOSITION_LINE_RE.match(line)
            if not match or match.group("mark").lower() != "x":
                continue
            states[Disposition(match.group("keyword"))] = match.group("ref").strip()
        findings.append(Finding(finding_id=finding_id, states=states))
    return findings


def iter_step_blocks(plan_text: str) -> list[tuple[str, str]]:
    """Return list of (step_id, block_text) pairs for every `### Step <id>` heading."""
    blocks: list[tuple[str, str]] = []
    current_id: str | None = None
    current_lines: list[str] = []
    for line in plan_text.splitlines():
        heading = STEP_HEADING_RE.match(line.strip())
        if heading:
            if current_id is not None:
                blocks.append((current_id, "\n".join(current_lines)))
            current_id = heading.group(1)
            current_lines = [line]
            continue
        if current_id is not None:
            current_lines.append(line)
    if current_id is not None:
        blocks.append((current_id, "\n".join(current_lines)))
    return blocks


def parse_step_block(block_text: str) -> StepBlock:
    assigned = ""
    unchecked: list[str] = []
    step_id = ""
    for index, line in enumerate(block_text.splitlines()):
        if index == 0:
            heading = STEP_HEADING_RE.match(line.strip())
            if heading:
                step_id = heading.group(1)
            continue
        assignment = ASSIGNED_LINE_RE.match(line.strip())
        if assignment:
            assigned = assignment.group(1).strip()
            continue
        bullet = BULLET_LINE_RE.match(line)
        if bullet and bullet.group("mark").lower() != "x":
            text = bullet.group("text").strip()
            snippet = text if len(text) <= 80 else text[:80] + "..."
            unchecked.append(snippet)
    return StepBlock(step_id=step_id, assigned=assigned, unchecked_bullets=unchecked)


def index_steps_by_id(plan_text: str) -> dict[str, StepBlock]:
    return {
        step_id: parse_step_block(block_text)
        for step_id, block_text in iter_step_blocks(plan_text)
    }


def emit_error_block(title: str, lines: list[str], action: str) -> None:
    print(f"ERROR: {title}", file=sys.stderr)
    for line in lines:
        print(line, file=sys.stderr)
    print(f"Action: {action}", file=sys.stderr)
    print(file=sys.stderr)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--step", required=True)
    parser.add_argument("--feature-id", required=True)
    parser.add_argument("--runtime-plan", required=True, type=Path)
    parser.add_argument("--worker-id", required=True)
    return parser.parse_args(argv)


def evaluate_findings(
    findings: list[Finding],
    steps_by_id: dict[str, StepBlock],
    worker_id: str,
    asdlc_root: Path,
) -> dict[str, list[str]]:
    """Return error category → list of detail strings."""
    categories: dict[str, list[str]] = {
        "missing_disposition": [],
        "conflicting_disposition": [],
        "missing_follow_up": [],
        "misassigned_follow_up": [],
        "missing_raised": [],
    }

    for finding in findings:
        checked = finding.checked_states
        if len(checked) == 0:
            categories["missing_disposition"].append(finding.finding_id)
            continue
        if len(checked) > 1:
            categories["conflicting_disposition"].append(finding.finding_id)
            continue

        state = checked[0]
        ref = finding.states[state]
        if state is Disposition.FOLLOW_UP_CREATED:
            follow_up = steps_by_id.get(ref)
            if follow_up is None:
                categories["missing_follow_up"].append(
                    f"{finding.finding_id} (expected: ### Step {ref})"
                )
            elif follow_up.assigned != worker_id:
                categories["misassigned_follow_up"].append(
                    f"{finding.finding_id} ({ref} #### Assigned: "
                    f"{follow_up.assigned or '<missing>'}, expected {worker_id})"
                )
        elif state is Disposition.RAISED_TO_COORDINATOR:
            expected_path = (asdlc_root / ref).resolve()
            if not expected_path.exists():
                categories["missing_raised"].append(
                    f"{finding.finding_id} (expected at {ref})"
                )

    return categories


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    review_path = (
        Path.cwd() / WORKER_HOME_DIR / "step_review_results"
        / f"review_result-{args.step}-{args.feature_id}.md"
    )

    try:
        review_text = read_nonempty(review_path, "review result")
        plan_text = read_nonempty(args.runtime_plan, "runtime implementation plan")
        asdlc_root = derive_asdlc_repo_root(args.runtime_plan)
    except ClosureError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    findings = parse_findings(review_text)
    if not findings:
        emit_error_block(
            "Disposition phase needed",
            ["No findings found in review_result (expected `### F-NN` blocks)."],
            "write findings first, then disposition each one.",
        )
        return 1

    steps_by_id = index_steps_by_id(plan_text)
    categories = evaluate_findings(findings, steps_by_id, args.worker_id, asdlc_root)
    current_step = steps_by_id.get(args.step)

    had_errors = False
    if categories["missing_disposition"]:
        had_errors = True
        emit_error_block(
            "Disposition phase needed",
            [
                "Findings without any disposition state checked: "
                + ", ".join(categories["missing_disposition"])
            ],
            "re-run Phase 2 for these findings.",
        )
    if categories["conflicting_disposition"]:
        had_errors = True
        emit_error_block(
            "Conflicting disposition state",
            [
                "Findings with more than one disposition state checked: "
                + ", ".join(categories["conflicting_disposition"])
            ],
            "resolve to exactly one of follow_up_created | raised_to_coordinator | rejected.",
        )
    if categories["missing_follow_up"]:
        had_errors = True
        emit_error_block(
            "Missing follow-up step",
            [
                "Findings marked [x] follow_up_created but no matching step heading in "
                "implementation_plan.md: " + "; ".join(categories["missing_follow_up"])
            ],
            "insert the step block after the current step section.",
        )
    if categories["misassigned_follow_up"]:
        had_errors = True
        emit_error_block(
            "Follow-up step mis-assigned",
            [
                "Findings whose follow-up step is assigned to a different worker: "
                + "; ".join(categories["misassigned_follow_up"])
            ],
            "re-assign the follow-up step to the current worker.",
        )
    if categories["missing_raised"]:
        had_errors = True
        emit_error_block(
            "Missing raised-question file",
            [
                "Findings marked [x] raised_to_coordinator but no matching file in "
                "raised_questions/: " + "; ".join(categories["missing_raised"])
            ],
            "create the file at the expected path; re-run the helper.",
        )
    if current_step is None:
        had_errors = True
        emit_error_block(
            "Target bullets not marked",
            [f"Current step section `### Step {args.step}` not found in implementation_plan.md."],
            "ensure the current step section exists in the ASDLC implementation_plan.md before marking bullets.",
        )
    elif current_step.unchecked_bullets:
        had_errors = True
        emit_error_block(
            "Target bullets not marked",
            ["Current-step target bullets still [ ] in implementation_plan.md:"]
            + [f"  - {bullet}" for bullet in current_step.unchecked_bullets],
            "mark all current-step target bullets [x] after every finding has been dispositioned (one batch).",
        )

    if had_errors:
        return 1

    print("OK: ai_audit closure check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
