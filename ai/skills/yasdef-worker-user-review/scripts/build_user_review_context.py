#!/usr/bin/env python3
"""Build user review context for a single ASDLC step."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path.cwd()
SKILL_ROOT = ROOT / ".codex" / "skills" / "yasdef-worker-user-review"
ASDLC_HOME = ROOT / ".asdlc_worker"
BLOCKER_LOG_PATH = ASDLC_HOME / "blocker_log.md"
OPEN_QUESTIONS_PATH = ASDLC_HOME / "open_questions.md"
USER_REVIEW_PATH = ASDLC_HOME / "user_review.md"


STEP_PLAN_SECTIONS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("Plan (ordered)", ("Plan (ordered)",)),
    (
        "Functional Requirements",
        ("Functional Requirements (translated from design EARS)", "Functional Requirements"),
    ),
    ("Applicable UR Shortlist", ("Applicable UR Shortlist",)),
)

ASSET_POINTERS: tuple[tuple[str, Path], ...] = (
    ("UR template", SKILL_ROOT / "assets" / "user_review_TEMPLATE.md"),
    ("Review Brief template", SKILL_ROOT / "assets" / "review_brief_TEMPLATE.md"),
    ("Review Brief golden example", SKILL_ROOT / "assets" / "review_brief_GOLDEN_EXAMPLE.md"),
    ("User review golden example", SKILL_ROOT / "assets" / "user_review_GOLDEN_EXAMPLE.md"),
)


def die(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_required(path: Path, label: str) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        text = ""
    if not text.strip():
        die(f"{label} not found or empty: {path}")
    return text


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT.resolve()))
    except ValueError:
        return str(path)


def markdown_sections(text: str) -> dict[str, str]:
    sections: dict[str, list[str]] = {}
    current: str | None = None
    for line in text.splitlines():
        match = re.match(r"^##\s+(.+?)\s*$", line)
        if match:
            current = match.group(1).strip()
            sections.setdefault(current, [])
            continue
        if current is not None:
            sections[current].append(line)
    return {key: "\n".join(value).strip() for key, value in sections.items()}


def first_present_section(sections: dict[str, str], headings: tuple[str, ...]) -> str:
    for heading in headings:
        body = sections.get(heading, "")
        if body.strip():
            return body.strip()
    return ""


def normalize_ordered_plan(body: str) -> str:
    items: list[str] = []
    for raw in body.splitlines():
        line = raw.strip()
        if not line:
            continue
        if re.match(r"^-\s+\[[ xX]\]\s+", line):
            items.append(line)
        elif line.startswith("- "):
            items.append("- [ ] " + line[2:].strip())
    return "\n".join(items)


def normalize_ur_shortlist(body: str) -> str:
    if not body.strip():
        return "- (missing in step plan)"

    lines = [line.rstrip() for line in body.splitlines() if line.strip()]
    if len(lines) == 1 and re.sub(r"^[\s-]+", "", lines[0]).strip().lower() in {"none", "none.", "(none)"}:
        return "- None."

    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("- "):
            out.append(stripped)
        elif out and stripped.startswith("  - "):
            out.append(stripped)
        if sum(1 for entry in out if entry.startswith("- ")) >= 8:
            break

    return "\n".join(out) if out else "- (missing in step plan)"


def accepted_decisions(step_sections: dict[str, str]) -> str:
    accepted_body = step_sections.get("Accepted Decisions", "").strip()
    if accepted_body:
        return accepted_body

    decisions_body = step_sections.get("Decisions Needed", "").strip()
    if not decisions_body:
        return "- (missing in step plan)"

    lines: list[str] = []
    include_continuation = False
    for raw in decisions_body.splitlines():
        line = raw.rstrip()
        if line.startswith("- "):
            include_continuation = "accepted" in line.lower()
            if include_continuation:
                lines.append(line)
            continue
        if include_continuation and line.startswith("  - "):
            lines.append(line)
    return "\n".join(lines) if lines else "- None explicitly marked as Accepted."


def extract_step_ledger_section(path: Path, step: str, label: str) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return f"## Step {step} (missing)\n- {label} not found."

    lines = text.splitlines()
    step_re = re.compile(rf"^## Step {re.escape(step)}(?:\b| )")
    header_re = re.compile(r"^## Step ")
    capture = False
    captured: list[str] = []
    for line in lines:
        if step_re.match(line):
            capture = True
        elif capture and header_re.match(line):
            break
        if capture:
            captured.append(line)
    if not captured:
        return f"## Step {step} (missing)\n- No {label} section found."
    return "\n".join(captured).strip()


def print_labeled_section(label: str, body: str) -> None:
    print(label)
    print(body if body.strip() else "- (missing in step plan)")
    print()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--step", required=True)
    parser.add_argument("--feature-id", required=True)
    parser.add_argument("--step-plan", required=True)
    parser.add_argument("--design", required=True)
    parser.add_argument("--runtime-plan", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    step_plan_path = Path(args.step_plan)
    design_path = Path(args.design)
    runtime_plan_path = Path(args.runtime_plan)

    step_plan_text = read_required(step_plan_path, "step plan")
    design_text = read_required(design_path, "design artifact")
    read_required(runtime_plan_path, "runtime implementation plan")

    step_sections = markdown_sections(step_plan_text)
    design_sections = markdown_sections(design_text)

    extracted: dict[str, str] = {}
    for label, headings in STEP_PLAN_SECTIONS:
        extracted[label] = first_present_section(step_sections, headings)

    ordered_plan = normalize_ordered_plan(extracted["Plan (ordered)"])
    if not ordered_plan:
        ordered_plan = "- (missing in step plan)"

    print(f"# YASDEF User Review Context: Step {args.step}")
    print()
    print("## Inputs")
    print(f"- Step: {args.step}")
    print(f"- Feature id: {args.feature_id}")
    print(f"- Step plan: {rel(step_plan_path)}")
    print(f"- Design artifact: {rel(design_path)}")
    print(f"- Runtime implementation plan: {rel(runtime_plan_path)}")
    print()

    print("## Review Contract")
    print()
    print_labeled_section("### Plan (ordered)", ordered_plan)
    print_labeled_section(
        "### Functional Requirements (translated from design EARS)",
        extracted["Functional Requirements"] or "- (missing in step plan)",
    )
    print_labeled_section("### Accepted Decisions", accepted_decisions(step_sections))
    print_labeled_section(
        "### Applicable UR Shortlist (from step plan, max 8)",
        normalize_ur_shortlist(extracted["Applicable UR Shortlist"]),
    )

    print("## Scope Contract (design by reference only)")
    print()
    for heading in ("Goal", "In Scope", "Out of Scope"):
        print(f"### {heading}")
        print(design_sections.get(heading, "").strip() or "- (missing in design artifact)")
        print()

    print("## Current Step Ledgers")
    print()
    print("### Blocker Log")
    print(extract_step_ledger_section(BLOCKER_LOG_PATH, args.step, "blocker log"))
    print()
    print("### Open Questions")
    print(extract_step_ledger_section(OPEN_QUESTIONS_PATH, args.step, "open questions"))
    print()

    print("## Durable Rule Assets")
    print(f"- Full user review rules: {rel(USER_REVIEW_PATH)}")
    for label, path in ASSET_POINTERS:
        print(f"- {label}: {rel(path)}")
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
