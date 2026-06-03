#!/usr/bin/env python3
"""Validate an ASDLC design artifact for planning handoff readiness."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REQUIRED_SECTIONS = ("Goal", "In Scope", "Out of Scope")


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


def scalar(section_body: str, label: str) -> str:
    for raw in section_body.splitlines():
        line = re.sub(r"^\s*-\s*", "", raw).strip()
        prefix = f"{label}:"
        if line.startswith(prefix):
            return line[len(prefix) :].strip()
    return ""


def find_bootstrap_section(sections: dict[str, str]) -> tuple[str, str]:
    for heading in (
        "First-Feature Bootstrap (only if needed)",
        "First-Feature Bootstrap",
        "First-Feature Bootstrap Decision",
    ):
        body = sections.get(heading, "")
        if body:
            return heading, body
    return "", ""


def validate(path: Path) -> list[dict[str, str]]:
    errors: list[dict[str, str]] = []
    if not path.exists():
        return [{"code": "file_not_found", "message": f"file not found: {path}"}]
    text = path.read_text(encoding="utf-8")
    sections = markdown_sections(text)

    missing = [section for section in REQUIRED_SECTIONS if section not in sections]
    if missing:
        errors.append(
            {
                "code": "missing_required_sections",
                "message": "missing required sections: " + " ".join(missing),
            }
        )

    heading, bootstrap = find_bootstrap_section(sections)
    if bootstrap:
        bootstrap_required = scalar(bootstrap, "Bootstrap required").lower()
        planning_handoff = scalar(bootstrap, "Planning handoff").lower()
        if heading == "First-Feature Bootstrap Decision":
            legacy = sections.get("Scaffold Creation Handoff", "")
            planning_handoff = scalar(legacy, "Planning requirement").lower() or planning_handoff
        if bootstrap_required and bootstrap_required != "yes":
            errors.append(
                {
                    "code": "invalid_bootstrap_required",
                    "message": "optional bootstrap section must use 'Bootstrap required: yes' when present",
                }
            )
        if bootstrap_required == "yes" and (
            not planning_handoff
            or planning_handoff.startswith("pending")
            or planning_handoff.startswith("unresolved")
        ):
            errors.append(
                {
                    "code": "bootstrap_planning_handoff_required",
                    "message": "bootstrap-required design must include a concrete planning handoff",
                }
            )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("design_file", nargs="?")
    args = parser.parse_args()
    if not args.design_file:
        print("Usage: check_design_readiness.py <design-file>", file=sys.stderr)
        return 2

    path = Path(args.design_file)
    errors = validate(path)
    result = {"file": str(path), "ready": not errors, "errors": errors}
    print(json.dumps(result, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
