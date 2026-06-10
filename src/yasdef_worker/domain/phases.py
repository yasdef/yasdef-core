from __future__ import annotations

MODEL_PHASES = ("design", "planning", "implementation", "user_review", "ai_audit")
WORKFLOW_PHASES = (*MODEL_PHASES, "post_review")

PHASE_ALIASES = {
    "design": "design",
    "planning": "planning",
    "implementation": "implementation",
    "user-review": "user_review",
    "user_review": "user_review",
    "ai-audit": "ai_audit",
    "ai_audit": "ai_audit",
    "post-review": "post_review",
    "post_review": "post_review",
}


class PhaseNameError(ValueError):
    pass


def canonical_phase_name(value: str) -> str:
    normalized = value.strip().lower()
    phase = PHASE_ALIASES.get(normalized)
    if phase is None:
        raise PhaseNameError(f"unsupported phase name: {value}")
    return phase
