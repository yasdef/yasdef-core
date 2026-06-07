from __future__ import annotations

from importlib import resources


def test_packaged_resource_roots_are_readable() -> None:
    package_root = resources.files("yasdef_worker")

    for rel in (
        "_data/skills/yasdef-worker-design/SKILL.md",
        "_data/commands/yasdef/design.md",
        "_data/templates/history_TEMPLATE.md",
        "_data/golden_examples/history_GOLDEN_EXAMPLE.md",
        "_data/setup/models.md",
        "_data/runtime/history_INITIAL.md",
        "templates/prompts/design.md",
        "templates/prompts/planning.md",
        "templates/prompts/implementation.md",
        "templates/prompts/user_review.md",
        "templates/prompts/ai_audit.md",
    ):
        resource = package_root.joinpath(*rel.split("/"))
        assert resource.is_file(), rel
        resource.read_text(encoding="utf-8")
