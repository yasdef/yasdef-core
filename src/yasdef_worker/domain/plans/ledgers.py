from __future__ import annotations

EMPTY_LEDGER_LINES = frozenset(
    {
        "- None.",
        "- No open questions.",
        "- No blockers.",
        "- No blockers identified.",
    }
)


def ledger_has_entries(content: str | None) -> bool:
    if content is None:
        return False
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line in EMPTY_LEDGER_LINES:
            continue
        return True
    return False

