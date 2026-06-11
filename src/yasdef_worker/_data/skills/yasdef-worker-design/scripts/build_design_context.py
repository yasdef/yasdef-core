#!/usr/bin/env python3
"""Build step-scoped ASDLC design context and initialize the design artifact."""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from pathlib import Path


ROOT = Path.cwd()
WORKER_HOME = ROOT / ".asdlc_worker"
SKILL_DIR = Path(__file__).resolve().parents[1]
ASSETS_DIR = SKILL_DIR / "assets"


def die(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def die_system(message: str) -> None:
    print(f"ERROR (system): {message}", file=sys.stderr)
    raise SystemExit(2)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT.resolve()))
    except ValueError:
        return str(path)


def trim_scalar(value: str) -> str:
    value = value.strip()
    if (value.startswith("'") and value.endswith("'")) or (
        value.startswith('"') and value.endswith('"')
    ):
        value = value[1:-1]
    return value.replace("''", "'")


def yaml_scalar(text: str, key: str) -> str:
    pattern = re.compile(rf"^\s*{re.escape(key)}:\s*(.*?)\s*$", re.MULTILINE)
    match = pattern.search(text)
    return trim_scalar(match.group(1)) if match else ""


def get_step_title(plan_text: str, step: str) -> str:
    pattern = re.compile(rf"^### Step {re.escape(step)}\s+(.*?)\s*$", re.MULTILINE)
    match = pattern.search(plan_text)
    return match.group(1).strip() if match else ""


def get_step_section(plan_text: str, step: str) -> str:
    lines = plan_text.splitlines()
    out: list[str] = []
    in_step = False
    step_heading = f"### Step {step}"
    for line in lines:
        if line.startswith("### Step "):
            if in_step:
                break
            if line == step_heading or line.startswith(step_heading + " "):
                in_step = True
        if in_step:
            if line.startswith("## ") and not line.startswith("### "):
                break
            out.append(line)
    return "\n".join(out).strip()


def target_bullets(step_section: str) -> str:
    bullets: list[str] = []
    for line in step_section.splitlines():
        if not re.match(r"^- \[[ xX]\] ", line):
            continue
        body = re.sub(r"^- \[[ xX]\] ", "", line)
        normalized = re.sub(r"^\[[^]]+\]\s*", "", body).lower()
        if normalized.startswith("plan and discuss the step"):
            continue
        if normalized.startswith("review step implementation"):
            continue
        bullets.append("- [ ] " + body)
    return "\n".join(bullets)


def req_ids_from_step(step_section: str) -> list[str]:
    ids = sorted(
        {match.group(1) for match in re.finditer(r"\[REQ-([0-9]+(?:\.[0-9]+)?)\]", step_section)},
        key=lambda value: [int(p) for p in value.split(".")],
    )
    return ids


def requirement_section(ears_text: str, req_id: str) -> str:
    lines = ears_text.splitlines()
    out: list[str] = []
    in_req = False
    req_heading = f"### Requirement {req_id}"
    for line in lines:
        if line.startswith("### Requirement "):
            if in_req:
                break
            if line == req_heading or line.startswith(req_heading + " "):
                in_req = True
        elif in_req and line.startswith("## ") and not line.startswith("### "):
            break
        if in_req:
            out.append(line)
    return "\n".join(out).strip()


def selected_requirements(ears_text: str, req_ids: list[str]) -> str:
    if not req_ids:
        return "No REQ tags found in step bullets. Select EARS blocks manually in the design artifact."
    sections: list[str] = []
    for req_id in req_ids:
        section = requirement_section(ears_text, req_id)
        if not section and "." in req_id:
            section = requirement_section(ears_text, req_id.split(".", 1)[0])
        sections.append(section or f"Requirement {req_id} not found in requirements EARS.")
    return "\n\n".join(sections).strip()


def linked_artifact_ids(req_text: str) -> list[str]:
    return sorted(
        {match.group(0) for match in re.finditer(r"LAR-[0-9]+", req_text)},
        key=lambda value: int(value.split("-", 1)[1]),
    )


def linked_artifact_registry(ears_text: str) -> dict[str, dict[str, str]]:
    registry: dict[str, dict[str, str]] = {}
    in_registry = False
    current: dict[str, str] | None = None
    for raw in ears_text.splitlines():
        line = raw.rstrip()
        if line.strip() == "## Linked Artifacts":
            in_registry = True
            continue
        if in_registry and line.startswith("## "):
            break
        if not in_registry:
            continue
        match = re.match(r"\s*-\s*id:\s*(.*?)\s*$", line)
        if match:
            current = {"id": trim_scalar(match.group(1))}
            registry[current["id"]] = current
            continue
        match = re.match(r"\s+([A-Za-z0-9_-]+):\s*(.*?)\s*$", line)
        if match and current is not None:
            current[match.group(1)] = trim_scalar(match.group(2))
    return registry


def linked_artifact_shortlist(ears_text: str, req_text: str) -> str:
    registry = linked_artifact_registry(ears_text)
    lines: list[str] = []
    for lar_id in linked_artifact_ids(req_text):
        entry = registry.get(lar_id)
        if not entry:
            lines.append(f"- {lar_id} | NOT FOUND IN REGISTRY")
            continue
        lines.append(
            "- {id} | {type} | {title} | {locator}".format(
                id=lar_id,
                type=entry.get("type", ""),
                title=entry.get("title", ""),
                locator=entry.get("locator", ""),
            ).rstrip()
        )
    return "\n".join(lines)


def section_for_step(path: Path, step: str, fallback: str) -> str:
    text = read_text(path)
    if not text:
        return fallback
    lines = text.splitlines()
    out: list[str] = []
    in_step = False
    step_heading = f"## Step {step}"
    for line in lines:
        if line.startswith("## Step "):
            if in_step:
                break
            if line == step_heading or line.startswith(step_heading + " "):
                in_step = True
        if in_step:
            out.append(line)
    return "\n".join(out).strip() or fallback


def template_body(template_path: Path) -> str:
    text = read_text(template_path)
    if not text:
        return ""
    parts = text.split("\n---\n", 1)
    return parts[1].lstrip("\n") if len(parts) == 2 else text


def initialize_design(path: Path, template_path: Path, step: str, title: str, bullets: str, req_text: str) -> None:
    if path.exists():
        return
    body = template_body(template_path)
    if not body:
        die_system(f"Feature design template not found or empty: {template_path}")
    today = dt.date.today().isoformat()
    replacements = {
        "# Feature Design: <step> - <step title>": f"# Feature Design: {step} - {title}",
        "Date: <YYYY-MM-DD>": f"Date: {today}",
        "- <target bullets from step (excluding planning/review)>": bullets
        or f"- (none found; verify step {step} bullets)",
        "- <selected EARS requirement excerpts used to translate step-plan functional requirements>": req_text
        or "- (none found; add selected EARS blocks)",
    }
    output_lines = [replacements.get(line, line) for line in body.splitlines()]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(output_lines).rstrip() + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--step", required=True)
    parser.add_argument("--design-out", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--ears", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan_path = Path(args.plan)
    ears_path = Path(args.ears)
    design_out = Path(args.design_out)
    template_path = ASSETS_DIR / "feature_design_TEMPLATE.md"
    golden_path = ASSETS_DIR / "feature_design_GOLDEN_EXAMPLE.md"

    plan_text = read_text(plan_path)
    ears_text = read_text(ears_path)
    if not plan_text:
        die(f"implementation plan not found or empty: {plan_path}")
    if not ears_text:
        die(f"requirements EARS not found or empty: {ears_path}")

    title = get_step_title(plan_text, args.step)
    if not title:
        die(f"step {args.step} not found in {plan_path}")
    step_section = get_step_section(plan_text, args.step)
    bullets = target_bullets(step_section)
    req_text = selected_requirements(ears_text, req_ids_from_step(step_section))
    lar_section = linked_artifact_shortlist(ears_text, req_text)

    initialize_design(design_out, template_path, args.step, title, bullets, req_text)

    blocker_section = section_for_step(
        WORKER_HOME / "blocker_log.md",
        args.step,
        f"## Step {args.step} (missing)\n- No blocker log section found.",
    )
    open_questions_section = section_for_step(
        WORKER_HOME / "open_questions.md",
        args.step,
        f"## Step {args.step} (missing)\n- No open questions section found.",
    )
    feature_meta = read_text(WORKER_HOME / "feature_meta_sync.yaml").strip()
    project_binding = read_text(WORKER_HOME / "project_overmind.yaml")
    worker_class = yaml_scalar(project_binding, "class") or "(unknown)"

    print(f"# YASDEF Design Context: Step {args.step} - {title}")
    print()
    print("## Paths")
    print(f"- Design artifact: {rel(design_out)}")
    print(f"- Implementation plan: {rel(plan_path)}")
    print(f"- Requirements EARS: {rel(ears_path)}")
    print(f"- Worker class: {worker_class}")
    print()
    print("## Step Section")
    print(step_section)
    print()
    print("## Target Bullets (excluding planning/review)")
    print(bullets or "- (none found; verify step bullets)")
    print()
    print("## Selected EARS Requirements")
    print(req_text)
    print()
    print("## Linked Artifacts (in scope)")
    print(lar_section or "- None.")
    print()
    print("## Blockers")
    print(blocker_section)
    print()
    print("## Open Questions")
    print(open_questions_section)
    print()
    print("## Feature Metadata")
    print(feature_meta or "- .asdlc_worker/feature_meta_sync.yaml missing")
    print()
    print("## Current Design Artifact")
    print(read_text(design_out).rstrip())
    print()
    print("## Feature Design Golden Example")
    golden = read_text(golden_path).strip()
    if not golden:
        die_system(f"Feature design golden example not found or empty: {golden_path}")
    print(golden)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
