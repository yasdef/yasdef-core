#!/usr/bin/env python3
"""Validate ASDLC implementation checklist closure for a step plan."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


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
            return heading, body
    return "", ""


def normalize_ordered_plan_items(body: str) -> list[str]:
    items: list[str] = []
    for raw in body.splitlines():
        line = raw.strip()
        if not line:
            continue
        if re.match(r"^-\s+\[[ xX]\]\s+", line):
            items.append(line)
        elif line.startswith("- "):
            items.append("- [ ] " + line[2:].strip())
    return items


def fr_entries(body: str) -> list[str]:
    entries: list[str] = []
    current_heading = ""
    current_status = ""

    def flush_current() -> None:
        nonlocal current_heading, current_status
        if not current_heading:
            return
        status = re.sub(r"[`\s]+", "", current_status.lower())
        prefix = "- [x] " if status == "done" else "- [ ] "
        entries.append(prefix + current_heading)
        current_heading = ""
        current_status = ""

    for raw in body.splitlines():
        line = raw.strip()
        heading_match = re.match(r"^###\s+(FR-[A-Za-z0-9._-]+(?:\s+.*)?)$", line)
        if heading_match:
            flush_current()
            current_heading = heading_match.group(1)
            continue
        status_match = re.match(r"^-\s+Status:\s*(.*?)\s*$", line)
        if status_match and current_heading:
            current_status = status_match.group(1)
            continue
        if re.match(r"^-\s+\[[ xX]\]\s+FR-[A-Za-z0-9._-]+(?:\s+.*)?$", line):
            flush_current()
            entries.append(line)
            continue
        bullet_match = re.match(r"^-\s+(FR-[A-Za-z0-9._-]+(?:\s+.*)?)$", line)
        if bullet_match:
            flush_current()
            entries.append("- [ ] " + bullet_match.group(1))
            continue
        plain_match = re.match(r"^(FR-[A-Za-z0-9._-]+(?:\s+.*)?)$", line)
        if plain_match:
            flush_current()
            entries.append("- [ ] " + plain_match.group(1))
            continue
    flush_current()
    return entries


def unchecked(items: list[str], pattern: str) -> list[str]:
    compiled = re.compile(pattern)
    return [item for item in items if not compiled.match(item)]


def validate(step: str, step_plan_path: Path) -> dict[str, object]:
    errors: list[dict[str, object]] = []
    text = read_text(step_plan_path)
    if not text.strip():
        errors.append(
            {
                "code": "step_plan_missing",
                "message": f"step plan not found or empty: {step_plan_path}",
            }
        )
        return {"step": step, "step_plan": str(step_plan_path), "ready": False, "errors": errors}

    sections = markdown_sections(text)
    ordered_body = sections.get("Plan (ordered)", "")
    if not ordered_body.strip():
        errors.append(
            {
                "code": "missing_ordered_plan",
                "message": "missing required section body: ## Plan (ordered)",
            }
        )
    ordered_items = normalize_ordered_plan_items(ordered_body)
    if ordered_body.strip() and not ordered_items:
        errors.append(
            {
                "code": "missing_ordered_plan_items",
                "message": "## Plan (ordered) must contain at least one checklist item or plain bullet",
            }
        )
    unchecked_ordered = unchecked(ordered_items, r"^-\s+\[[xX]\]\s+")
    if unchecked_ordered:
        errors.append(
            {
                "code": "unchecked_ordered_plan_items",
                "message": "all ## Plan (ordered) items must be [x]",
                "items": unchecked_ordered,
            }
        )

    fr_heading, fr_body = first_present_section(
        sections,
        ("Functional Requirements (translated from design EARS)", "Functional Requirements"),
    )
    if not fr_body.strip():
        errors.append(
            {
                "code": "missing_functional_requirements",
                "message": "missing required section body: ## Functional Requirements (translated from design EARS)",
            }
        )
    functional_items = fr_entries(fr_body)
    if fr_body.strip() and not functional_items:
        errors.append(
            {
                "code": "missing_functional_requirement_items",
                "message": f"## {fr_heading} must contain at least one FR entry",
            }
        )
    unchecked_functional = unchecked(
        functional_items,
        r"^-\s+\[[xX]\]\s+FR-[A-Za-z0-9._-]+(?:\s+.*)?$",
    )
    if unchecked_functional:
        errors.append(
            {
                "code": "unchecked_functional_requirement_items",
                "message": "all functional requirement items must be [x]",
                "items": unchecked_functional,
            }
        )

    return {
        "step": step,
        "step_plan": str(step_plan_path),
        "ready": not errors,
        "ordered_plan_items": len(ordered_items),
        "functional_requirement_items": len(functional_items),
        "functional_requirements_heading": fr_heading,
        "errors": errors,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--step", required=True)
    parser.add_argument("--step-plan", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = validate(args.step, Path(args.step_plan))
    print(json.dumps(result, indent=2))
    return 0 if result["ready"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
