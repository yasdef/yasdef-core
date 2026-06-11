#!/usr/bin/env python3
"""Find project_stack_blueprint_*.md files and filter by worker class.

Port of ai/scripts/helpers/helper_find_blueprints.sh.
Run from an ASDLC feature folder that contains implementation_plan.md and
requirements_ears.md; falls back to dirname(ASDLC_RUNTIME_PLAN_PATH) when set.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path


def _resolve_feature_dir() -> Path:
    cwd = Path.cwd()
    has_plan = (cwd / "implementation_plan.md").is_file()
    has_ears = (cwd / "requirements_ears.md").is_file() or (cwd / "reqirements_ears.md").is_file()
    if has_plan and has_ears:
        return cwd

    runtime_plan = os.environ.get("ASDLC_RUNTIME_PLAN_PATH", "")
    if runtime_plan:
        candidate = Path(runtime_plan).parent
        if candidate.is_dir():
            return candidate

    print(
        "Blueprint lookup failed: run this helper from an ASDLC feature folder "
        "with implementation_plan.md and requirements_ears.md, or ensure "
        "ASDLC_RUNTIME_PLAN_PATH is set.",
        file=sys.stderr,
    )
    sys.exit(1)


def _read_class_scalar(yaml_path: Path) -> str:
    if not yaml_path.is_file():
        return ""
    text = yaml_path.read_text(encoding="utf-8")
    m = re.search(r"^\s*class\s*:\s*(.*?)\s*$", text, re.MULTILINE)
    if not m:
        return ""
    raw = m.group(1).strip()
    raw = re.sub(r"\s*#.*$", "", raw).strip()
    if len(raw) >= 2 and ((raw[0] == "'" and raw[-1] == "'") or (raw[0] == '"' and raw[-1] == '"')):
        raw = raw[1:-1]
    return raw


def _normalize_class(raw: str) -> str:
    raw = raw.strip().lower()
    if raw in ("back", "backend", "api", "server"):
        return "back"
    if raw in ("front", "frontend", "front-end", "web", "ui"):
        return "front"
    if raw in ("mobile", "ios", "android", "react-native"):
        return "mobile"
    return ""


def _matches_class(normalized: str, filename: str) -> bool:
    name = filename.lower()
    if normalized == "back":
        return "back" in name or "backend" in name
    if normalized == "front":
        return "front" in name or "frontend" in name or "web" in name
    if normalized == "mobile":
        return "mobile" in name or "ios" in name or "android" in name
    return False


def main() -> None:
    feature_dir = _resolve_feature_dir()
    project_root = feature_dir.parent
    binding_file = project_root / ".asdlc_worker" / "project_overmind.yaml"

    raw_class = _read_class_scalar(binding_file)
    normalized = _normalize_class(raw_class)

    all_blueprints = sorted(project_root.glob("project_stack_blueprint_*.md"))

    print("Blueprint helper result")
    print(f"Feature folder: {feature_dir}")
    print(f"Project-level search root: {project_root}")
    print(f"Binding file: {binding_file}")
    print(f"Raw project class: {raw_class or 'unresolved'}")
    print(f"Normalized project class: {normalized or 'unresolved'}")

    if not all_blueprints:
        print("Relevant blueprint result: no blueprint files found under project-level root.")
        return

    print("All blueprint candidates:")
    for bp in all_blueprints:
        print(f"  - {bp}")

    if not normalized:
        print(
            "Relevant blueprint result: unresolved because project class is missing or "
            "unsupported. Ask the user to choose the stack/scaffold direction."
        )
        return

    matched = [bp for bp in all_blueprints if _matches_class(normalized, bp.name)]
    irrelevant = [bp for bp in all_blueprints if not _matches_class(normalized, bp.name)]

    if matched:
        print(f"Relevant blueprint candidates for class {normalized}:")
        for bp in matched:
            print(f"  - {bp}")
    if irrelevant:
        print(f"Irrelevant blueprint candidates for class {normalized}:")
        for bp in irrelevant:
            print(f"  - {bp}")

    if not matched:
        print(
            "Relevant blueprint result: no class-matching blueprint found. "
            "Ask the user to choose the stack/scaffold direction."
        )
    else:
        print(f"Relevant blueprint result: found {len(matched)} class-matching blueprint candidate(s).")


if __name__ == "__main__":
    main()
