#!/usr/bin/env python3
"""Find project_stack_blueprint_*.md files and filter by worker class.

Port of ai/scripts/helpers/helper_find_blueprints.sh.
Run from the worker repo root; reads binding from .asdlc_worker/project_overmind.yaml.
"""
from __future__ import annotations

import sys
from pathlib import Path


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
    try:
        from yasdef_worker.infra.layout import RuntimeLayout
        from yasdef_worker.infra.yaml_io import read_yaml_file

        layout = RuntimeLayout.discover()
        binding_file = layout.binding_file
        project_root: Path | None = None
        worker_class = ""

        if binding_file.is_file():
            data = read_yaml_file(binding_file)
            source = str(data.get("overmind_source_path") or "").strip()
            if source:
                project_root = Path(source).expanduser().resolve()
            worker_class = str(data.get("class") or "").strip()
    except Exception as exc:
        print(f"Blueprint lookup failed: {exc}", file=sys.stderr)
        sys.exit(1)

    if project_root is None or not project_root.is_dir():
        print("Blueprint lookup failed: could not resolve bound project root.", file=sys.stderr)
        sys.exit(1)

    normalized = _normalize_class(worker_class)
    all_blueprints = sorted(project_root.glob("project_stack_blueprint_*.md"))

    print("Blueprint helper result")
    print(f"Project-level search root: {project_root}")
    print(f"Raw project class: {worker_class or 'unresolved'}")
    print(f"Normalized project class: {normalized or 'unresolved'}")

    if not all_blueprints:
        print("Blueprint search result: no blueprint files found under project-level root.")
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
