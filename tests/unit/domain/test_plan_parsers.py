from __future__ import annotations

from yasdef_worker.domain.plans.ledgers import ledger_has_entries
from yasdef_worker.domain.plans.step_design import (
    extract_step_and_title as extract_design_header,
)
from yasdef_worker.domain.plans.step_design import get_step_from_design_path
from yasdef_worker.domain.plans.step_plan import (
    extract_step_and_title as extract_plan_header,
)
from yasdef_worker.domain.plans.step_plan import (
    get_preferred_step_plan,
    get_step_from_plan_path,
    try_get_step_from_plan_path,
)
from yasdef_worker.domain.plans.step_sorting import make_sort_key, sort_key


def test_sort_key_orders_numeric_step_parts_and_suffixes() -> None:
    steps = ["1.10", "1.2", "1.6c", "1.6", "2", "1.6a"]

    assert sorted(steps, key=sort_key) == ["1.2", "1.6", "1.6a", "1.6c", "1.10", "2"]
    assert make_sort_key("1.6c") == "0000000001.0000000006c"


def test_step_plan_header_and_path_extractors() -> None:
    header = extract_plan_header("preamble\n# Step Plan: 1.6c - Redemption after resolution\n")

    assert header is not None
    assert header.step == "1.6c"
    assert header.title == "Redemption after resolution"
    assert get_step_from_plan_path("/tmp/step-1.6c-feature-demo.md") == "1.6c"
    assert try_get_step_from_plan_path("step-1.6-feature-demo.md") == "1.6"
    assert try_get_step_from_plan_path("feature-demo.md") is None


def test_step_design_header_and_path_extractors() -> None:
    header = extract_design_header("# Feature Design: 1.6 - Example feature\n")

    assert header is not None
    assert header.step == "1.6"
    assert header.title == "Example feature"
    assert get_step_from_design_path("/tmp/step-1.6-feature-demo-design.md") == "1.6"
    assert get_step_from_design_path("/tmp/step-1.6-feature-demo.md") is None


def test_get_preferred_step_plan_prefers_branch_then_latest_feature_plan() -> None:
    paths = (
        "/repo/.asdlc_worker/step_plans/step-1.1-feature-a.md",
        "/repo/.asdlc_worker/step_plans/step-1.2-feature-a.md",
        "/repo/.asdlc_worker/step_plans/step-1.9-feature-b.md",
    )

    assert (
        get_preferred_step_plan(
            current_branch="step-1.1-feature-a-implementation",
            feature_id="feature-a",
            plan_paths=paths,
        )
        == "/repo/.asdlc_worker/step_plans/step-1.1-feature-a.md"
    )
    assert (
        get_preferred_step_plan(
            current_branch="main",
            feature_id="feature-a",
            plan_paths=paths,
        )
        == "/repo/.asdlc_worker/step_plans/step-1.2-feature-a.md"
    )


def test_ledger_has_entries_ignores_empty_markers() -> None:
    assert ledger_has_entries(None) is False
    assert ledger_has_entries("# Open Questions\n\n- No open questions.\n") is False
    assert ledger_has_entries("# Open Questions\n\n## Step 1.1 Demo\n- Is auth required?\n") is True

