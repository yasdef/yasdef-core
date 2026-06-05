#!/usr/bin/env python3
"""Build ai_audit context from a step design artifact."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


WORKER_HOME_DIR = ".asdlc_worker"
SKILL_REL_PATH = ".codex/skills/yasdef-worker-ai-audit"
PROJECTS_DIR = "projects"
RAISED_QUESTIONS_DIR = "raised_questions"

REQUIRED_SECTION_HEADINGS = (
    "Target Bullets (excluding planning/review)",
    "Selected EARS Requirements (for planning translation)",
    "Goal",
    "In Scope",
    "Out of Scope",
    "Linked Artifacts (in scope)",
)

H2_HEADING_RE = re.compile(r"^##\s+(.+?)\s*$")
H1_HEADING_RE = re.compile(r"^#\s+(.+?)\s*$")


class ContextError(Exception):
    """Raised when required context inputs are missing or inconsistent."""


def first_h1(text: str) -> str:
    for line in text.splitlines():
        match = H1_HEADING_RE.match(line)
        if match:
            return match.group(1).strip()
    return ""


def markdown_sections(text: str) -> dict[str, str]:
    """Split markdown into `##`-delimited sections (heading → body text)."""
    sections: dict[str, list[str]] = {}
    current: str | None = None
    for line in text.splitlines():
        heading = H2_HEADING_RE.match(line)
        if heading:
            current = heading.group(1).strip()
            sections.setdefault(current, [])
            continue
        if current is not None:
            sections[current].append(line)
    return {key: "\n".join(value).strip() for key, value in sections.items()}


def read_nonempty(path: Path, label: str) -> str:
    if not path.is_file():
        raise ContextError(f"{label} not found: {path}")
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        raise ContextError(f"{label} is empty: {path}")
    return text


def require_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise ContextError(f"{label} not found: {path}")


def relative_to_root(path: Path, root: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path)


def validate_design_identity(step: str, feature_id: str, design_path: Path, design_text: str) -> None:
    expected_name = f"step-{step}-{feature_id}-design.md"
    if design_path.name != expected_name:
        raise ContextError(
            f"EXPECTED design filename {expected_name}, GOT {design_path.name}. "
            f"EXPECTED design for step {step} feature {feature_id}."
        )

    title = first_h1(design_text)
    if not re.search(rf"(?<!\d){re.escape(step)}(?!\d)", title):
        raise ContextError(
            f"EXPECTED design title to include step {step}, GOT '{title or '<missing>'}'"
        )


def derive_asdlc_repo_root(runtime_plan: Path) -> Path:
    """Return the ASDLC repo root from `<root>/projects/<project>/<feature>/implementation_plan.md`."""
    resolved = runtime_plan.resolve()
    parts = resolved.parts
    if len(parts) < 5 or parts[-1] != "implementation_plan.md":
        raise ContextError(
            "runtime plan must point at "
            f"<asdlc-repo>/{PROJECTS_DIR}/<project>/<feature>/implementation_plan.md: {runtime_plan}"
        )
    if parts[-4] != PROJECTS_DIR:
        raise ContextError(
            "runtime plan must sit under "
            f"<asdlc-repo>/{PROJECTS_DIR}/<project>/<feature>/: {runtime_plan}"
        )
    return Path(*parts[:-4])


def git_status_short(cwd: Path) -> str:
    result = subprocess.run(
        ["git", "status", "--short", "--untracked-files=all"],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or "unknown error"
        return f"- (git status failed: {message})"
    output = result.stdout.strip()
    return output if output else "- (clean working tree)"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--step", required=True)
    parser.add_argument("--feature-id", required=True)
    parser.add_argument("--design", required=True, type=Path)
    parser.add_argument("--runtime-plan", required=True, type=Path)
    parser.add_argument("--worker-id", required=True)
    return parser.parse_args(argv)


def emit_section(heading: str, body: str) -> None:
    print(f"## {heading}")
    print(body if body.strip() else "- (missing in design file)")
    print()


def emit_context(args: argparse.Namespace, root: Path) -> None:
    design_text = read_nonempty(args.design, "step design artifact")
    require_file(args.runtime_plan, "runtime implementation plan")
    validate_design_identity(args.step, args.feature_id, args.design, design_text)

    asdlc_repo_root = derive_asdlc_repo_root(args.runtime_plan)
    sections = markdown_sections(design_text)

    review_result_path = (
        root / WORKER_HOME_DIR / "step_review_results"
        / f"review_result-{args.step}-{args.feature_id}.md"
    )
    raised_questions_dir = args.runtime_plan.parent / RAISED_QUESTIONS_DIR
    skill_root = root / SKILL_REL_PATH
    agents_path = root / "AGENTS.md"

    print(f"# YASDEF AI Audit Context: Step {args.step}")
    print()

    print("## Inputs")
    print(f"- Step: {args.step}")
    print(f"- Feature id: {args.feature_id}")
    print(f"- Design artifact: {relative_to_root(args.design, root)}")
    print(f"- Runtime implementation plan: {args.runtime_plan}")
    print(f"- Worker id: {args.worker_id}")
    print(f"- asdlc_repo_path: {asdlc_repo_root}")
    print()

    for heading in REQUIRED_SECTION_HEADINGS:
        emit_section(heading, sections.get(heading, ""))

    print("## Step Delta File List")
    print(git_status_short(root))
    print()

    print("## Pointers")
    print(f"- AGENTS.md: {relative_to_root(agents_path, root)}")
    print(f"- Review result output: {relative_to_root(review_result_path, root)}")
    print(f"- Audit result template: {relative_to_root(skill_root / 'assets' / 'audit_result_TEMPLATE.md', root)}")
    print(
        f"- Audit result golden example: "
        f"{relative_to_root(skill_root / 'assets' / 'audit_result_GOLDEN_EXAMPLE.md', root)}"
    )
    print(
        f"- Raised question template: "
        f"{relative_to_root(skill_root / 'assets' / 'raised_question_TEMPLATE.md', root)}"
    )
    print(
        f"- Raised question golden example: "
        f"{relative_to_root(skill_root / 'assets' / 'raised_question_GOLDEN_EXAMPLE.md', root)}"
    )
    print(
        f"- Closure helper: "
        f"{relative_to_root(skill_root / 'scripts' / 'check_ai_audit_closure.py', root)}"
    )
    print(f"- Raised questions directory (ASDLC repo): {raised_questions_dir}")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    root = Path.cwd()
    try:
        emit_context(args, root)
    except ContextError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
