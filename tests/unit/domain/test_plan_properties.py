from __future__ import annotations

import pytest

from yasdef_orchestrator.domain.plans.implementation_plan import ImplementationPlan
from yasdef_orchestrator.domain.plans.step_sorting import sort_key

hypothesis = pytest.importorskip("hypothesis")
st = pytest.importorskip("hypothesis.strategies")

given = hypothesis.given


_STEP_PART = st.integers(min_value=0, max_value=200).map(str)
_STEP_SUFFIX = st.sampled_from(["", "a", "b", "c"])
_STEP = st.lists(
    st.tuples(_STEP_PART, _STEP_SUFFIX).map(lambda pair: f"{pair[0]}{pair[1]}"),
    min_size=1,
    max_size=4,
).map(".".join)
_CHECK = st.sampled_from([" ", "x", "X"])


@given(st.lists(_STEP, min_size=1, max_size=30))
def test_sort_key_matches_numeric_order_for_plain_numeric_steps(steps: list[str]) -> None:
    numeric_steps = [step for step in steps if all(part.isdigit() for part in step.split("."))]

    assert sorted(numeric_steps, key=sort_key) == sorted(
        numeric_steps,
        key=lambda step: tuple(int(part) for part in step.split(".")),
    )


@given(_STEP, st.lists(_CHECK, min_size=1, max_size=8))
def test_implementation_plan_parser_accepts_marker_case_and_line_endings(
    step: str,
    markers: list[str],
) -> None:
    bullet_lines = [f"- [{marker}] Bullet {index}\r" for index, marker in enumerate(markers)]
    content = "\ufeff# Plan\r\n" + "\r\n".join(
        [
            f"### Step {step} Generated\r",
            "#### Depends on: none\r",
            "#### Assigned: 11111111-1111-1111-1111-111111111111\r",
            *bullet_lines,
        ]
    )

    plan = ImplementationPlan.parse(content)
    parsed_step = plan.step(step)

    assert parsed_step is not None
    assert len(parsed_step.bullets) == len(markers)
    assert parsed_step.checked_count == sum(1 for marker in markers if marker.lower() == "x")
