#!/usr/bin/env python3
"""Build implementation context for a single ASDLC step."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path.cwd()


STEP_PLAN_SECTIONS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("Plan (ordered)", ("Plan (ordered)",)),
    (
        "Functional Requirements (translated from design EARS)",
        ("Functional Requirements (translated from design EARS)", "Functional Requirements"),
    ),
    ("Applicable UR Shortlist", ("Applicable UR Shortlist",)),
    ("Architecture / Helper Flow", ("Architecture / Helper Flow",)),
    ("Implementation Notes / Constraints", ("Implementation Notes / Constraints",)),
    ("Tests", ("Tests",)),
    ("Risks / Edge Cases", ("Risks / Edge Cases",)),
    ("Decisions Needed", ("Decisions Needed",)),
    ("Linked Artifacts (in scope)", ("Linked Artifacts (in scope)",)),
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


def first_present_section(sections: dict[str, str], headings: tuple[str, ...]) -> tuple[str, str]:
    for heading in headings:
        body = sections.get(heading, "")
        if body.strip():
            return heading, body.strip()
    return headings[0], ""


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


def is_none_marker(line: str) -> bool:
    value = re.sub(r"^[\s-]+", "", line).strip().lower()
    return value in {"none.", "none", "(none)"} or value.startswith("(missing")


def anti_regression_checklist(ur_body: str) -> str:
    out: list[str] = []
    seen_ids: set[str] = set()
    seen_lines: set[str] = set()
    for raw in ur_body.splitlines():
        line = raw.strip()
        if not line.startswith("- ") or is_none_marker(line):
            continue
        match = re.search(r"UR-[A-Za-z0-9_-]+", line)
        if match:
            ur_id = match.group(0)
            if ur_id in seen_ids:
                continue
            seen_ids.add(ur_id)
        elif line in seen_lines:
            continue
        else:
            seen_lines.add(line)
        out.append(line)
        if len(out) >= 8:
            break
    return "\n".join(out) if out else "- None."


def accepted_decisions(body: str) -> str:
    lines: list[str] = []
    include_continuation = False
    for raw in body.splitlines():
        line = raw.rstrip()
        if line.startswith("- "):
            include_continuation = "accepted" in line.lower()
            if include_continuation:
                lines.append(line)
            continue
        if include_continuation and line.startswith("  - "):
            lines.append(line)
    return "\n".join(lines) if lines else "- None explicitly marked as Accepted."


def print_labeled_section(label: str, body: str) -> None:
    print(label)
    print(body if body.strip() else "- (missing in step plan)")
    print()


def print_phase_contract(step: str) -> None:
    print("## Phase Contract")
    print("- Artifact precedence: step plan is the primary execution source; design supplies scope boundary only.")
    print("- Scope boundary: use design `## Goal`, `## In Scope`, and `## Out of Scope`; do not use design `## Non-goals`.")
    print("- Execution state machine: step plan `## Plan (ordered)` only.")
    print("- Functional contract: implement step-plan translated FRs.")
    print("- Checklist updates: mark ordered bullets and FRs `[x]` only when implemented and verified.")
    print("- LAR rule: fetch in-scope locators before implementing dependent FRs; ask the user on fetch failure or ambiguity.")
    print("- Verification timing: targeted checks during implementation; full `AGENTS.md` gate once after all ordered bullets are `[x]`.")
    print("- Completion protocol: run `check_implementation_readiness.py` before the completion line.")
    print("- Runtime plan gating: do not use `implementation_plan.md` target bullets as implementation-phase proof state.")
    print(f"- Readiness command: `uv run python .codex/skills/yasdef-worker-implementation/scripts/check_implementation_readiness.py --step {step} --step-plan <step-plan-file>`.")
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
    source_headings: dict[str, str] = {}
    for label, headings in STEP_PLAN_SECTIONS:
        heading, body = first_present_section(step_sections, headings)
        extracted[label] = body
        source_headings[label] = heading

    ordered_plan = normalize_ordered_plan(extracted["Plan (ordered)"])
    if not ordered_plan:
        ordered_plan = "- (missing in step plan)"

    print(f"# YASDEF Implementation Context: Step {args.step}")
    print()
    print("## Inputs")
    print(f"- Step: {args.step}")
    print(f"- Feature id: {args.feature_id}")
    print(f"- Step plan: {rel(step_plan_path)}")
    print(f"- Design artifact: {rel(design_path)}")
    print(f"- Runtime implementation plan: {rel(runtime_plan_path)}")
    print()

    print_phase_contract(args.step)

    print("## Anti-regression Checklist (from step-plan `## Applicable UR Shortlist`, max 8)")
    print(anti_regression_checklist(extracted["Applicable UR Shortlist"]))
    print()

    print("## Execution List (step plan `## Plan (ordered)`)")
    print(ordered_plan)
    print()

    print("## Step-plan Execution Context")
    print()
    for label, _headings in STEP_PLAN_SECTIONS:
        if label == "Plan (ordered)":
            continue
        if label == "Decisions Needed":
            print_labeled_section("### Accepted Decisions (from `## Decisions Needed`)", accepted_decisions(extracted[label]))
            print_labeled_section("### Decisions Needed (full section)", extracted[label])
            continue
        heading = source_headings[label]
        body = extracted[label]
        if label.startswith("Functional Requirements") and heading == "Functional Requirements":
            print_labeled_section("### Functional Requirements", body)
        else:
            print_labeled_section(f"### {label}", body)

    print("## Scope Contract (design by reference only)")
    print()
    for heading in ("Goal", "In Scope", "Out of Scope"):
        print(f"### {heading}")
        print(design_sections.get(heading, "").strip() or "- (missing in design artifact)")
        print()

    print("## Intentionally Excluded Design Sections")
    print("- `## Non-goals`")
    print("- `## Proposal / Design Details`")
    print("- `## Risks and Mitigations`")
    print("- `## Applicable ADR Shortlist`")
    print("- `## Applicable AGENTS.md Constraints`")
    print("- `## References in Current Codebase`")
    print("- design UR rules")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
