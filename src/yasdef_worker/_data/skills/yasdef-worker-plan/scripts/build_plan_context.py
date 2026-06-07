#!/usr/bin/env python3
"""Build planning context for a single ASDLC step and initialize missing artifacts."""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from pathlib import Path


ROOT = Path.cwd()
SKILL_DIR = Path(__file__).resolve().parents[1]
ASSETS_DIR = SKILL_DIR / "assets"
TEMPLATE_PATH = ASSETS_DIR / "step_plan_TEMPLATE.md"
GOLDEN_PATH = ASSETS_DIR / "step_plan_GOLDEN_EXAMPLE.md"


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


def split_template_body(text: str) -> str:
    parts = text.split("\n---\n", 1)
    return parts[1].lstrip("\n") if len(parts) == 2 else text


def section_body(text: str, heading: str) -> str:
    pattern = re.compile(
        rf"(?ms)^##\s+{re.escape(heading)}\s*$\n(.*?)(?=^##\s+|\Z)"
    )
    match = pattern.search(text)
    return match.group(1).strip() if match else ""


def first_present_section(text: str, headings: tuple[str, ...]) -> tuple[str, str]:
    for heading in headings:
        body = section_body(text, heading)
        if body:
            return heading, body
    return "", ""


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
            # Stop at the next level-2 section, but keep the current level-3
            # step heading and any level-3 content inside the step block.
            is_level_2_heading = line.startswith("## ") and not line.startswith("### ")
            if is_level_2_heading:
                break
            out.append(line)
    return "\n".join(out).strip()


def ensure_file(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_text("", encoding="utf-8")


def initialize_step_plan(
    *,
    path: Path,
    step: str,
    title: str,
    design_path: Path,
    open_questions_path: Path,
    blockers_path: Path,
) -> None:
    if path.exists():
        return

    template_text = read_text(TEMPLATE_PATH)
    if not template_text.strip():
        die_system(f"step plan template not found or empty: {TEMPLATE_PATH}")

    body = split_template_body(template_text)
    today = dt.date.today().isoformat()
    replacements = {
        "# Step Plan: <step> - <step title>": f"# Step Plan: {step} - {title}",
        "Date: <YYYY-MM-DD>": f"Date: {today}",
        "Feature design: <design path>": f"Feature design: {rel(design_path)}",
        "- Review per-step open questions: `<open questions path>`": (
            f"- Review per-step open questions: `{rel(open_questions_path)}`"
        ),
        "- Review per-step blockers: `<blockers path>`": (
            f"- Review per-step blockers: `{rel(blockers_path)}`"
        ),
    }
    rendered = body
    for source_line, value in replacements.items():
        rendered = rendered.replace(source_line, value)

    required_placeholders = ("<step>", "<step title>", "<YYYY-MM-DD>", "<design path>", "<open questions path>", "<blockers path>")
    unresolved_required = [token for token in required_placeholders if token in rendered]
    if unresolved_required:
        die_system(
            "step plan template rendered with unresolved required placeholders: "
            + ", ".join(unresolved_required)
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(rendered.rstrip() + "\n", encoding="utf-8")


def print_labeled_section(label: str, body: str) -> None:
    print(label)
    print(body if body.strip() else "(none)")
    print()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--step", required=True)
    parser.add_argument("--feature-id", required=True)
    parser.add_argument("--design", required=True)
    parser.add_argument("--plan-out", required=True)
    parser.add_argument("--runtime-plan", required=True)
    parser.add_argument("--open-questions", required=True)
    parser.add_argument("--blockers", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    design_path = Path(args.design)
    plan_out_path = Path(args.plan_out)
    runtime_plan_path = Path(args.runtime_plan)
    open_questions_path = Path(args.open_questions)
    blockers_path = Path(args.blockers)
    runtime_ears_path = runtime_plan_path.parent / "reqirements_ears.md"

    design_text = read_text(design_path)
    if not design_text.strip():
        die(f"design artifact not found or empty: {design_path}")

    runtime_plan_text = read_text(runtime_plan_path)
    if not runtime_plan_text.strip():
        die(f"runtime implementation plan not found or empty: {runtime_plan_path}")

    step_title = get_step_title(runtime_plan_text, args.step)
    if not step_title:
        die(f"step {args.step} not found in {runtime_plan_path}")

    step_section = get_step_section(runtime_plan_text, args.step)
    ensure_file(open_questions_path)
    ensure_file(blockers_path)
    initialize_step_plan(
        path=plan_out_path,
        step=args.step,
        title=step_title,
        design_path=design_path,
        open_questions_path=open_questions_path,
        blockers_path=blockers_path,
    )

    step_plan_text = read_text(plan_out_path)
    if not step_plan_text.strip():
        die_system(f"step plan not found or empty after initialization: {plan_out_path}")

    target_bullets = section_body(design_text, "Target Bullets (excluding planning/review)")
    if not target_bullets:
        target_bullets = section_body(design_text, "Target Bullets")
    selected_ears_heading, selected_ears = first_present_section(
        design_text,
        (
            "Selected EARS Requirements (for planning translation)",
            "Selected EARS Requirements",
            "Linked Requirements (EARS excerpts)",
        ),
    )
    bootstrap_heading, bootstrap = first_present_section(
        design_text,
        (
            "First-Feature Bootstrap (only if needed)",
            "First-Feature Bootstrap",
            "First-Feature Bootstrap Decision",
        ),
    )
    things_to_decide_heading, things_to_decide = first_present_section(
        design_text,
        (
            "Things to Decide (for final planning discussion)",
            "Things to Decide",
        ),
    )
    agents = section_body(design_text, "Applicable AGENTS.md Constraints")
    ur_heading, ur_rules = first_present_section(
        design_text,
        (
            "Applicable UR Shortlist",
            "Applicable User Review Rules",
        ),
    )
    adr = section_body(design_text, "Applicable ADR Shortlist")
    lars = section_body(design_text, "Linked Artifacts (in scope)")

    print(f"# YASDEF Planning Context: Step {args.step} - {step_title}")
    print()
    print("## Inputs")
    print(f"- Step: {args.step}")
    print(f"- Feature id: {args.feature_id}")
    print(f"- Design artifact: {rel(design_path)}")
    print(f"- Step plan output: {rel(plan_out_path)}")
    print(f"- Runtime implementation plan: {rel(runtime_plan_path)}")
    print(f"- Requirements EARS path (pointer only): {rel(runtime_ears_path)}")
    print(f"- Open questions ledger: {rel(open_questions_path)}")
    print(f"- Blockers ledger: {rel(blockers_path)}")
    print()
    print_labeled_section("## Runtime Step Section", step_section)
    print_labeled_section(
        "## Design Target Bullets", target_bullets or "(missing in design artifact)"
    )
    print_labeled_section(
        f"## Design {selected_ears_heading or 'Selected EARS Requirements'}",
        selected_ears or "(missing in design artifact)",
    )
    print_labeled_section(
        f"## Design {bootstrap_heading or 'First-Feature Bootstrap'}",
        bootstrap or "(not present)",
    )
    print_labeled_section(
        f"## Design {things_to_decide_heading or 'Things to Decide'}",
        things_to_decide or "(none)",
    )
    print_labeled_section(
        "## Design Applicable AGENTS.md Constraints",
        agents or "(missing in design artifact)",
    )
    print_labeled_section(
        f"## Design {ur_heading or 'Applicable User Review Rules'}",
        ur_rules or "(missing in design artifact)",
    )
    print_labeled_section(
        "## Design Applicable ADR Shortlist", adr or "(missing in design artifact)"
    )
    print_labeled_section("## Design Linked Artifacts (in scope)", lars or "(none)")
    print_labeled_section("## Current Step Plan", step_plan_text.strip())
    print_labeled_section(
        "## Current Open Questions Ledger", read_text(open_questions_path).strip() or "(clean)"
    )
    print_labeled_section(
        "## Current Blockers Ledger", read_text(blockers_path).strip() or "(clean)"
    )
    print_labeled_section(
        "## Step Plan Golden Example",
        read_text(GOLDEN_PATH).strip() or "(missing golden example)",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
