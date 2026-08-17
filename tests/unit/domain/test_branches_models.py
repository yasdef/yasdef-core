from __future__ import annotations

import pytest

from yasdef_worker.domain.branches import (
    ai_audit_branch_spec,
    get_step_from_branch_name,
    step_branch_name,
    user_review_branch_spec,
)
from yasdef_worker.domain.models_config import (
    ModelsConfigError,
    list_phases,
    load_model_config,
    parse_models_config,
    validate_models_config,
)
from yasdef_worker.domain.phases import MODEL_PHASES, WORKFLOW_PHASES, canonical_phase_name
from yasdef_worker.domain.phase_types import PhaseResult, PhaseStatus

COMPLETE_CONFIG = """
# Phase | Command | Model | Extra Arg
design | codex | gpt-5.4 | --config | model_reasoning_effort='high'
planning | codex | gpt-5.4 |

implementation | codex | gpt-5.4
user-review | claude | claude-sonnet-4-6 |
ai-audit | echo | mock-model | --flag |
"""


def _without(phase: str) -> str:
    return "\n".join(
        line for line in COMPLETE_CONFIG.splitlines() if not line.strip().startswith(phase)
    )


def test_step_branch_names_and_specs() -> None:
    assert step_branch_name("1.1", "feature-demo", "planning") == "step-1.1-feature-demo-plan"
    assert step_branch_name("1.1", "feature-demo", "user_review") == (
        "step-1.1-feature-demo-user-review"
    )

    user_review = user_review_branch_spec("1.1", "feature-demo")
    assert user_review.target == "step-1.1-feature-demo-user-review"
    assert user_review.source_required is True
    assert user_review.source_branch == "step-1.1-feature-demo-implementation"

    ai_audit = ai_audit_branch_spec("1.1", "feature-demo")
    assert ai_audit.target == "step-1.1-feature-demo-ai-audit"
    assert ai_audit.source_branch == "step-1.1-feature-demo-user-review"


def test_get_step_from_branch_name_requires_feature_qualified_shape() -> None:
    assert get_step_from_branch_name("step-1.1-feature-demo-implementation") == "1.1"
    assert get_step_from_branch_name("step-1.6c-feature-demo-implementation") == "1.6c"
    assert get_step_from_branch_name("step-12.4-feature-demo-ai-audit") == "12.4"
    assert get_step_from_branch_name("step-1.1-review") is None
    assert get_step_from_branch_name("step-1.1-feature-demo-review") is None
    assert get_step_from_branch_name("step-1.1-implementation") is None
    assert get_step_from_branch_name("feature-demo") is None


def test_models_config_parses_comments_aliases_and_runner_rows() -> None:
    rows = parse_models_config(COMPLETE_CONFIG)

    assert rows[0].phase == "design"
    assert rows[0].cmd == "codex"
    assert rows[0].extras == ("--config", "model_reasoning_effort='high'")
    assert rows[3].phase == "user_review"
    assert rows[4].phase == "ai_audit"
    assert rows[4].extras == ("--flag",)
    assert list_phases(COMPLETE_CONFIG) == MODEL_PHASES
    assert load_model_config(COMPLETE_CONFIG, "AI-AUDIT").cmd == "echo"


def test_validate_models_config_returns_canonical_order_regardless_of_row_order() -> None:
    shuffled = "\n".join(
        [
            "ai-audit | echo | mock-model",
            "design | echo | mock-model",
            "user-review | echo | mock-model",
            "implementation | echo | mock-model",
            "planning | echo | mock-model",
        ]
    )

    assert tuple(row.phase for row in validate_models_config(shuffled)) == MODEL_PHASES


def test_validate_models_config_accepts_markdown_style_outer_pipes() -> None:
    piped = "\n".join(f"| {phase} | echo | mock-model |" for phase in MODEL_PHASES)

    assert tuple(row.phase for row in validate_models_config(piped)) == MODEL_PHASES


@pytest.mark.parametrize("phase", MODEL_PHASES)
def test_validate_models_config_rejects_missing_required_phase(phase: str) -> None:
    with pytest.raises(ModelsConfigError, match=f"missing phase\\(s\\): {phase}"):
        validate_models_config(_without(phase.replace("_", "-")))


def test_validate_models_config_rejects_duplicate_phase() -> None:
    content = COMPLETE_CONFIG + "design | echo | duplicate\n"

    with pytest.raises(ModelsConfigError, match="duplicate 'design' entry"):
        validate_models_config(content)


def test_models_config_rejects_row_with_too_few_fields() -> None:
    with pytest.raises(ModelsConfigError, match="models config line 1: expected"):
        parse_models_config("implementation | codex gpt-5.4\n")


@pytest.mark.parametrize(
    ("row", "field"),
    [
        ("| | codex | gpt-5.4 |", "phase"),
        ("design |  | gpt-5.4", "command"),
        ("| design | codex |  |", "model"),
    ],
)
def test_models_config_rejects_empty_required_field(row: str, field: str) -> None:
    with pytest.raises(ModelsConfigError, match=f"empty {field} field"):
        parse_models_config(row + "\n")


def test_phase_registry_canonicalizes_aliases_and_distinguishes_workflow_phases() -> None:
    assert canonical_phase_name("user-review") == "user_review"
    assert canonical_phase_name("post-review") == "post_review"
    assert MODEL_PHASES == ("design", "planning", "implementation", "user_review", "ai_audit")
    assert WORKFLOW_PHASES == (*MODEL_PHASES, "post_review")


def test_models_config_rejects_unknown_phase_names() -> None:
    with pytest.raises(ModelsConfigError, match="unsupported phase name"):
        parse_models_config("audit-review | codex | gpt-5.4\n")

    with pytest.raises(ModelsConfigError, match="unsupported phase name"):
        load_model_config("design | codex | gpt-5.4\n", "audit-review")


def test_models_config_rejects_non_model_workflow_phase() -> None:
    with pytest.raises(ModelsConfigError, match="unsupported phase name"):
        parse_models_config("post-review | echo | mock-model\n")


def test_missing_model_config_raises_user_facing_error() -> None:
    with pytest.raises(ModelsConfigError):
        load_model_config("design | codex | gpt-5.4\n", "planning")


def test_phase_result_completion_property() -> None:
    assert PhaseResult("design", PhaseStatus.COMPLETE).is_complete is True
    assert PhaseResult("design", PhaseStatus.INCOMPLETE).is_complete is False
