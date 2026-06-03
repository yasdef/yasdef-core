#!/usr/bin/env python3
"""Validate a step plan for ASDLC planning closure readiness."""

from __future__ import annotations

import argparse
import json
import re
import sys
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
        if body:
            return heading, body
    return "", ""


def normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def scalar(section_body: str, label: str) -> str:
    for raw in section_body.splitlines():
        line = re.sub(r"^\s*-\s*", "", raw).strip()
        prefix = f"{label}:"
        if line.startswith(prefix):
            return line[len(prefix) :].strip()
    return ""


def ledger_has_entries(path: Path | None) -> bool:
    if path is None or not path.exists():
        return False
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line in {"- None.", "- No open questions.", "- No blockers."}:
            continue
        if line:
            return True
    return False


def parse_selected_req_ids(selected_ears_body: str) -> list[str]:
    ids = []
    seen: set[str] = set()
    for match in re.finditer(r"REQ-([0-9]+(?:\.[0-9]+)?)", selected_ears_body):
        req_id = match.group(1)
        if req_id not in seen:
            seen.add(req_id)
            ids.append(req_id)
    return ids


def parse_fr_entries(body: str) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []

    for raw_line in body.splitlines():
        line = raw_line.strip()

        bullet_match = re.match(r"^- \[[ xX]\] (FR-[^ ]+)", line)
        if bullet_match:
            entries.append(
                {
                    "id": bullet_match.group(1),
                    "line": line,
                    "refs": re.findall(r"EARS\[(?:REQ|NFR)-([0-9]+(?:\.[0-9]+)?)\]", line),
                }
            )
    return entries


def parse_plan_lines(body: str) -> list[str]:
    return [line.strip() for line in body.splitlines() if re.match(r"^- \[[ xX]\] ", line)]


def parse_decision_items(body: str) -> list[str]:
    items: list[str] = []
    for raw in body.splitlines():
        line = raw.strip()
        if not line.startswith("- "):
            continue
        item = line[2:].strip()
        if item.lower() in {"none.", "(none)"}:
            continue
        items.append(item)
    return items


def validate_ur_shortlist(body: str, errors: list[dict[str, str]]) -> None:
    if not body.strip():
        errors.append(
            {
                "code": "missing_ur_shortlist",
                "message": "missing required section body: ## Applicable UR Shortlist",
            }
        )
        return
    lines = [line.strip() for line in body.splitlines() if line.strip()]
    if lines == ["- None."]:
        return
    ur_ids: list[str] = []
    for line in lines:
        if not line.startswith("- "):
            errors.append(
                {
                    "code": "invalid_ur_shortlist",
                    "message": f"non-bullet content found in Applicable UR Shortlist: {line}",
                }
            )
            return
        matches = re.findall(r"UR-[0-9]{4}", line)
        if not matches:
            errors.append(
                {
                    "code": "invalid_ur_shortlist",
                    "message": f"shortlist entry missing UR-xxxx id: {line}",
                }
            )
            return
        ur_ids.extend(matches)
    if len(ur_ids) > 8:
        errors.append(
            {
                "code": "ur_shortlist_too_large",
                "message": f"Applicable UR Shortlist contains {len(ur_ids)} UR ids; max is 8",
            }
        )


def empty_result(
    design_path: Path,
    step_plan_path: Path,
    errors: list[dict[str, str]],
    open_questions: Path | None,
    blockers: Path | None,
) -> dict[str, object]:
    return {
        "design": str(design_path),
        "step_plan": str(step_plan_path),
        "ready": False,
        "errors": errors,
        "ledgers": {
            "open_questions_dirty": ledger_has_entries(open_questions),
            "blockers_dirty": ledger_has_entries(blockers),
        },
    }


def validate(design_path: Path, step_plan_path: Path, open_questions: Path | None, blockers: Path | None) -> dict[str, object]:
    errors: list[dict[str, str]] = []

    design_text = read_text(design_path)
    if not design_text.strip():
        errors.append(
            {
                "code": "design_missing",
                "message": f"design artifact not found or empty: {design_path}",
            }
        )
        return empty_result(design_path, step_plan_path, errors, open_questions, blockers)

    step_plan_text = read_text(step_plan_path)
    if not step_plan_text.strip():
        errors.append(
            {
                "code": "step_plan_missing",
                "message": f"step plan not found or empty: {step_plan_path}",
            }
        )
        return empty_result(design_path, step_plan_path, errors, open_questions, blockers)

    design_sections = markdown_sections(design_text)
    step_plan_sections = markdown_sections(step_plan_text)

    if "Target Bullets" in step_plan_sections or "Target Bullets (excluding planning/review)" in step_plan_sections:
        errors.append(
            {
                "code": "forbidden_section",
                "message": "deprecated section present in step plan: ## Target Bullets",
            }
        )
    if "Requirement Tags" in step_plan_sections:
        errors.append(
            {
                "code": "forbidden_section",
                "message": "deprecated section present in step plan: ## Requirement Tags",
            }
        )

    plan_match = re.search(r"^##\s+Plan \(ordered\)\s*$", step_plan_text, re.MULTILINE)
    fr_match = re.search(
        r"^##\s+Functional Requirements \(translated from design EARS\)\s*$",
        step_plan_text,
        re.MULTILINE,
    )
    if not plan_match:
        errors.append(
            {
                "code": "missing_plan_section",
                "message": "missing required section: ## Plan (ordered)",
            }
        )
    if not fr_match:
        errors.append(
            {
                "code": "missing_fr_section",
                "message": "missing required section: ## Functional Requirements (translated from design EARS)",
            }
        )
    if plan_match and fr_match and fr_match.start() < plan_match.start():
        errors.append(
            {
                "code": "invalid_section_order",
                "message": "## Functional Requirements (translated from design EARS) must appear after ## Plan (ordered)",
            }
        )

    ur_body = step_plan_sections.get("Applicable UR Shortlist", "")
    validate_ur_shortlist(ur_body, errors)

    fr_entries = parse_fr_entries(step_plan_sections.get("Functional Requirements (translated from design EARS)", ""))
    if not fr_entries:
        errors.append(
            {
                "code": "missing_fr_bullets",
                "message": "Functional Requirements section must contain FR checklist bullets",
            }
        )
    req_refs_per_fr: dict[str, list[str]] = {}
    for entry in fr_entries:
        fr_id = str(entry["id"])
        refs = [str(ref) for ref in entry["refs"]]
        req_refs_per_fr[fr_id] = refs
        if len(refs) != 1:
            errors.append(
                {
                    "code": "invalid_fr_ears_mapping",
                    "message": f"{fr_id} must map to exactly one EARS source item",
                }
            )

    selected_heading, selected_ears = first_present_section(
        design_sections,
        (
            "Selected EARS Requirements (for planning translation)",
            "Selected EARS Requirements",
            "Linked Requirements (EARS excerpts)",
        ),
    )
    selected_req_ids = parse_selected_req_ids(selected_ears)
    if not selected_ears.strip():
        errors.append(
            {
                "code": "missing_selected_ears",
                "message": "design artifact missing selected EARS requirements section content",
            }
        )
    else:
        seen_refs = {refs[0] for refs in req_refs_per_fr.values() if len(refs) == 1}
        for req_id in selected_req_ids:
            if req_id not in seen_refs and req_id.split(".", 1)[0] not in seen_refs:
                errors.append(
                    {
                        "code": "missing_ears_translation",
                        "message": f"selected EARS item REQ-{req_id} has no translated FR",
                    }
                )

    decision_heading, decision_body = first_present_section(
        design_sections,
        ("Things to Decide (for final planning discussion)", "Things to Decide"),
    )
    design_decisions = parse_decision_items(decision_body)
    plan_decisions = step_plan_sections.get("Decisions Needed", "")
    normalized_plan_decisions = normalize(plan_decisions)
    for item in design_decisions:
        base = item.split(":", 1)[0].strip()
        if normalize(base) not in normalized_plan_decisions:
            errors.append(
                {
                    "code": "missing_decision_outcome",
                    "message": f"design decision lacks explicit outcome in step plan: {base}",
                }
            )
            continue
        if not re.search(
            rf"{re.escape(normalize(base))}.*\b(accepted|deferred|blocked)\b",
            normalized_plan_decisions,
        ):
            errors.append(
                {
                    "code": "missing_decision_outcome",
                    "message": f"design decision lacks Accepted/Deferred/Blocked outcome: {base}",
                }
            )

    bootstrap_heading, bootstrap_body = first_present_section(
        design_sections,
        (
            "First-Feature Bootstrap (only if needed)",
            "First-Feature Bootstrap",
            "First-Feature Bootstrap Decision",
        ),
    )
    bootstrap_required = scalar(bootstrap_body, "Bootstrap required").lower()
    if bootstrap_required == "yes":
        scaffold_body = step_plan_sections.get("Scaffold Bootstrap Plan", "")
        if not scaffold_body.strip():
            errors.append(
                {
                    "code": "missing_scaffold_plan",
                    "message": "bootstrap-required design needs section: ## Scaffold Bootstrap Plan",
                }
            )
        plan_lines = parse_plan_lines(step_plan_sections.get("Plan (ordered)", ""))
        if not plan_lines:
            errors.append(
                {
                    "code": "missing_plan_bullets",
                    "message": "bootstrap-required planning needs ordered plan bullets",
                }
            )
        else:
            first_plan = plan_lines[0].lower()
            if not re.search(r"scaffold|bootstrap|initialize", first_plan):
                errors.append(
                    {
                        "code": "bootstrap_ordering",
                        "message": "bootstrap-required planning must place scaffold creation first in ## Plan (ordered)",
                    }
                )

    return {
        "design": str(design_path),
        "step_plan": str(step_plan_path),
        "selected_ears_heading": selected_heading or "",
        "decision_heading": decision_heading or "",
        "bootstrap_heading": bootstrap_heading or "",
        "ready": not errors,
        "errors": errors,
        "ledgers": {
            "open_questions_dirty": ledger_has_entries(open_questions),
            "blockers_dirty": ledger_has_entries(blockers),
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--design", required=True)
    parser.add_argument("--step-plan", required=True)
    parser.add_argument("--open-questions")
    parser.add_argument("--blockers")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = validate(
        Path(args.design),
        Path(args.step_plan),
        Path(args.open_questions) if args.open_questions else None,
        Path(args.blockers) if args.blockers else None,
    )
    print(json.dumps(result, indent=2))
    return 0 if result["ready"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
