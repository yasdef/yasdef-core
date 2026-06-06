from __future__ import annotations

import pytest

from yasdef_orchestrator.domain.branches import (
    ai_audit_branch_spec,
    get_step_from_branch_name,
    step_branch_name,
    user_review_branch_spec,
)
from yasdef_orchestrator.domain.models_config import (
    ModelsConfigError,
    list_phases,
    load_model_config,
    parse_models_config,
)
from yasdef_orchestrator.domain.phase_types import PhaseResult, PhaseStatus


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
    content = """
    # Phase | Command | Model | Extra Arg
    design | codex | gpt-5.4 | --config | model_reasoning_effort='high'
    user-review | claude | claude-sonnet-4-6 |
    ai-audit | echo | mock-model | --flag |
    design | echo | duplicate |
    """

    rows = parse_models_config(content)

    assert rows[0].phase == "design"
    assert rows[0].cmd == "codex"
    assert rows[0].extras == ("--config", "model_reasoning_effort='high'")
    assert rows[1].phase == "user_review"
    assert rows[2].phase == "ai_audit"
    assert list_phases(content) == ("design", "user_review", "ai_audit")
    assert load_model_config(content, "AI-AUDIT").cmd == "echo"


def test_models_config_rejects_unknown_phase_names() -> None:
    with pytest.raises(ModelsConfigError, match="unsupported phase name"):
        parse_models_config("audit-review | codex | gpt-5.4\n")

    with pytest.raises(ModelsConfigError, match="unsupported phase name"):
        load_model_config("design | codex | gpt-5.4\n", "audit-review")


def test_missing_model_config_raises_user_facing_error() -> None:
    with pytest.raises(ModelsConfigError):
        load_model_config("design | codex | gpt-5.4\n", "planning")


def test_phase_result_completion_property() -> None:
    assert PhaseResult("design", PhaseStatus.COMPLETE).is_complete is True
    assert PhaseResult("design", PhaseStatus.INCOMPLETE).is_complete is False
