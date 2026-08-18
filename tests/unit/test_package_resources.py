from __future__ import annotations

from importlib.metadata import version
from importlib import resources

from yasdef_worker import __version__
from yasdef_worker.domain.models_config import (
    ModelConfig,
    ModelsConfigError,
    parse_models_config,
    validate_models_config,
)
from yasdef_worker.domain.phases import MODEL_PHASES
from yasdef_worker.domain.runners import CopilotRunner, get_runner


def test_runtime_version_matches_distribution_metadata() -> None:
    assert __version__ == version("yasdef-worker")


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


def test_packaged_generic_golden_examples_match_documented_set() -> None:
    golden_examples = resources.files("yasdef_worker").joinpath("_data", "golden_examples")

    assert sorted(child.name for child in golden_examples.iterdir() if child.is_file()) == [
        "blocker_log_GOLDEN_EXAMPLE.md",
        "decisions_GOLDEN_EXAMPLE.md",
        "history_GOLDEN_EXAMPLE.md",
        "open_questions_GOLDEN_EXAMPLE.md",
        "user_review_GOLDEN_EXAMPLE.md",
    ]


def _packaged_models_config_text() -> str:
    return (
        resources.files("yasdef_worker")
        .joinpath("_data", "setup", "models.md")
        .read_text(encoding="utf-8")
    )


def test_packaged_models_config_defaults_to_copilot_with_claude_haiku() -> None:
    rows = validate_models_config(_packaged_models_config_text())

    assert tuple(row.phase for row in rows) == MODEL_PHASES
    for row in rows:
        assert row.cmd == "copilot", row.phase
        assert row.model == "claude-haiku-4.5", row.phase
        assert row.extras == (), row.phase
        assert isinstance(get_runner(row.cmd), CopilotRunner)


def test_packaged_models_config_documents_a_complete_commented_copilot_example() -> None:
    copilot_examples: dict[str, ModelConfig] = {}
    for line in _packaged_models_config_text().splitlines():
        if not line.lstrip().startswith("#"):
            continue
        try:
            rows = parse_models_config(line.lstrip().lstrip("#"))
        except ModelsConfigError:
            continue
        for row in rows:
            if row.cmd == "copilot":
                copilot_examples[row.phase] = row

    assert set(copilot_examples) == set(MODEL_PHASES)
    for phase in MODEL_PHASES:
        assert copilot_examples[phase].model == "claude-haiku-4.5", phase
        assert copilot_examples[phase].extras == (), phase
