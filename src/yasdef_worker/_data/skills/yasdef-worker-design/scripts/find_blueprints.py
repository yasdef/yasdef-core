#!/usr/bin/env python3
"""Find project-level bootstrap artifacts and filter them by worker class.

Discovers project_stack_blueprint_*.md and project_agents_md_claude_md_*.md next
to the ASDLC feature folder, and reports project-root AGENTS.md/CLAUDE.md state.

Run from an ASDLC feature folder that contains implementation_plan.md and
requirements_ears.md; falls back to dirname(ASDLC_RUNTIME_PLAN_PATH) when set.

Worker binding discovery walks up from this script's own location, so it assumes
the skill bundle is a real copy installed by `yasdef init` (editable tool
installs still copy the skill files). A manually symlink-installed skill bundle
is unsupported: the walk-up starts from the link target and the class may resolve
as unbound.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

GUIDANCE_FILENAMES = ("AGENTS.md", "CLAUDE.md")


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


def _find_binding_file() -> Path | None:
    start = Path(__file__).resolve().parent
    for directory in (start, *start.parents):
        candidate = directory / ".asdlc_worker" / "project_overmind.yaml"
        if candidate.is_file():
            return candidate
    return None


def _read_class_scalar(yaml_path: Path | None) -> str:
    if yaml_path is None or not yaml_path.is_file():
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


def _guidance_state(path: Path) -> str:
    if path.is_symlink():
        return "present"
    if path.is_dir():
        return "invalid-directory"
    if path.is_file():
        return "present"
    return "absent"


def _report_candidates(
    project_root: Path,
    normalized: str,
    *,
    pattern: str,
    label: str,
    direction_hint: str,
) -> None:
    candidates = sorted(project_root.glob(pattern))

    if not candidates:
        print(f"Relevant {label} result: no {label} files found under project-level root.")
        return

    print(f"All {label} candidates:")
    for candidate in candidates:
        print(f"  - {candidate}")

    if not normalized:
        print(
            f"Relevant {label} result: unresolved because project class is missing or "
            f"unsupported. {direction_hint}"
        )
        return

    matched = [item for item in candidates if _matches_class(normalized, item.name)]
    irrelevant = [item for item in candidates if not _matches_class(normalized, item.name)]

    if matched:
        print(f"Relevant {label} candidates for class {normalized}:")
        for candidate in matched:
            print(f"  - {candidate}")
    if irrelevant:
        print(f"Irrelevant {label} candidates for class {normalized}:")
        for candidate in irrelevant:
            print(f"  - {candidate}")

    if not matched:
        print(f"Relevant {label} result: no class-matching {label} found. {direction_hint}")
    else:
        print(f"Relevant {label} result: found {len(matched)} class-matching {label} candidate(s).")


def main() -> None:
    feature_dir = _resolve_feature_dir()
    project_root = feature_dir.parent
    binding_file = _find_binding_file()
    worker_root = binding_file.parent.parent if binding_file is not None else None

    raw_class = _read_class_scalar(binding_file)
    normalized = _normalize_class(raw_class)

    print("Blueprint helper result")
    print(f"Feature folder: {feature_dir}")
    print(f"Project-level search root: {project_root}")
    print(f"Binding file: {binding_file or 'unresolved'}")
    print(f"Raw project class: {raw_class or 'unresolved'}")
    print(f"Normalized project class: {normalized or 'unresolved'}")
    print(f"Worker repo root: {worker_root or 'unresolved'}")
    for filename in GUIDANCE_FILENAMES:
        state = _guidance_state(worker_root / filename) if worker_root is not None else "unresolved"
        print(f"Project {filename} state: {state}")

    _report_candidates(
        project_root,
        normalized,
        pattern="project_stack_blueprint_*.md",
        label="blueprint",
        direction_hint="Ask the user to choose the stack/scaffold direction.",
    )
    _report_candidates(
        project_root,
        normalized,
        pattern="project_agents_md_claude_md_*.md",
        label="agents guidance",
        direction_hint="Ask the user for agent-guidance direction.",
    )


if __name__ == "__main__":
    main()
