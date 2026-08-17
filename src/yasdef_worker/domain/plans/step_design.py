from __future__ import annotations

import re
from dataclasses import dataclass


GUIDANCE_STATES: tuple[str, ...] = ("present", "absent", "invalid-directory")
GUIDANCE_DISPOSITIONS: tuple[str, ...] = (
    "both-present-no-action",
    "regenerate-both-approved",
    "leave-unchanged-declined",
)

BOOTSTRAP_HEADINGS: tuple[str, ...] = (
    "First-Feature Bootstrap (only if needed)",
    "First-Feature Bootstrap",
    "First-Feature Bootstrap Decision",
)


@dataclass(frozen=True, slots=True)
class StepDesignHeader:
    step: str
    title: str


@dataclass(frozen=True, slots=True)
class BootstrapGuidanceDecision:
    agents_state: str
    claude_state: str
    disposition: str
    source: str

    @property
    def regenerate_approved(self) -> bool:
        return self.disposition == "regenerate-both-approved"


_FEATURE_DESIGN_HEADER_RE = re.compile(r"^# Feature Design: ([^\s]+) - (.*)$")
_STEP_DESIGN_PATH_RE = re.compile(r"^step-(.+)-design\.md$")
_HEADING_RE = re.compile(r"^##\s+(.+?)\s*$")


def extract_step_and_title(content: str) -> StepDesignHeader | None:
    for raw in content.splitlines():
        match = _FEATURE_DESIGN_HEADER_RE.match(raw.rstrip("\r"))
        if match is not None:
            return StepDesignHeader(match.group(1), match.group(2))
    return None


def get_step_from_design_path(path: str) -> str | None:
    base = path.rsplit("/", 1)[-1]
    match = _STEP_DESIGN_PATH_RE.match(base)
    if match is None:
        return None
    return match.group(1).split("-", 1)[0]


def markdown_sections(content: str) -> dict[str, str]:
    sections: dict[str, list[str]] = {}
    current: str | None = None
    for raw in content.splitlines():
        match = _HEADING_RE.match(raw.rstrip("\r"))
        if match is not None:
            current = match.group(1).strip()
            sections.setdefault(current, [])
            continue
        if current is not None:
            sections[current].append(raw)
    return {key: "\n".join(value).strip() for key, value in sections.items()}


def section_scalar(section_body: str, label: str) -> str:
    prefix = f"{label}:"
    for raw in section_body.splitlines():
        line = re.sub(r"^\s*[-*]\s*", "", raw).strip()
        if line.startswith(prefix):
            return line[len(prefix) :].strip()
    return ""


def bootstrap_section(content: str) -> str:
    sections = markdown_sections(content)
    for heading in BOOTSTRAP_HEADINGS:
        body = sections.get(heading, "")
        if body:
            return body
    return ""


def parse_bootstrap_guidance(content: str) -> BootstrapGuidanceDecision | None:
    """Read the agent-guidance reconciliation decision from a bootstrap design.

    Returns None when the design is not bootstrap-required.
    """
    body = bootstrap_section(content)
    if not body or section_scalar(body, "Bootstrap required").lower() != "yes":
        return None
    return BootstrapGuidanceDecision(
        agents_state=section_scalar(body, "Project AGENTS.md state").lower(),
        claude_state=section_scalar(body, "Project CLAUDE.md state").lower(),
        disposition=section_scalar(body, "Agent-guidance disposition").lower(),
        source=section_scalar(body, "Agent-guidance source"),
    )


def guidance_decision_errors(decision: BootstrapGuidanceDecision) -> list[str]:
    """Validate a bootstrap guidance decision against its recorded file states."""
    errors: list[str] = []
    states = {
        "Project AGENTS.md state": decision.agents_state,
        "Project CLAUDE.md state": decision.claude_state,
    }
    for label, state in states.items():
        if not state:
            errors.append(f"bootstrap-required design must record '{label}'")
        elif state not in GUIDANCE_STATES:
            errors.append(f"'{label}' must be one of {', '.join(GUIDANCE_STATES)}")

    if "invalid-directory" in states.values():
        errors.append(
            "a project-root guidance path is a directory: resolve it and rerun the lookup "
            "before recording a disposition"
        )
        return errors

    if not decision.disposition:
        errors.append("bootstrap-required design must record 'Agent-guidance disposition'")
        return errors
    if decision.disposition not in GUIDANCE_DISPOSITIONS:
        errors.append(
            "'Agent-guidance disposition' must be one of " + ", ".join(GUIDANCE_DISPOSITIONS)
        )
        return errors

    both_present = decision.agents_state == "present" and decision.claude_state == "present"
    if both_present and decision.disposition != "both-present-no-action":
        errors.append(
            "both project-root guidance files are present: disposition must be both-present-no-action"
        )
    if not both_present and decision.disposition == "both-present-no-action":
        errors.append(
            "both-present-no-action requires both project-root guidance files to be present"
        )
    if decision.regenerate_approved and not decision.source:
        errors.append("regenerate-both-approved requires one 'Agent-guidance source'")
    return errors

