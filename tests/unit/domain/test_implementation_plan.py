from __future__ import annotations

import pytest

from yasdef_orchestrator.domain.plans.feature_selector import (
    analyze_for_worker,
    plan_has_assigned_step_for_worker,
)
from yasdef_orchestrator.domain.plans.implementation_plan import (
    ImplementationPlan,
    ImplementationPlanError,
    array_contains_ci,
    step_exists_in_implementation_plan,
)

WORKER = "11111111-1111-1111-1111-111111111111"
OTHER = "22222222-2222-2222-2222-222222222222"


def test_implementation_plan_parses_steps_and_analyzes_first_unchecked() -> None:
    plan = ImplementationPlan.parse(
        f"""
### Step 1.1 Bootstrap
#### Depends on: none
#### Assigned: {WORKER}
- [x] Plan and discuss the step
- [x] Implement bootstrap

### Step 1.2 API
#### Depends on: 1.1
#### Assigned: {WORKER}
- [x] Plan and discuss the step
- [ ] Implement API

### Step 1.3 UI
#### Depends on: 1.2
#### Assigned: {WORKER}
- [ ] Implement UI

### Step 1.4 Other worker
#### Assigned: {OTHER}
- [ ] Not ours
"""
    )

    assert plan.has_step("1.2") is True
    assert step_exists_in_implementation_plan(plan, "1.3") is True
    step = plan.step("1.2")
    assert step is not None
    assert step.unchecked_count == 1
    assert plan.steps_assigned_to(WORKER)[0].number == "1.1"

    analysis = analyze_for_worker(plan, WORKER, target_step="1.3")
    assert analysis.assigned_any is True
    assert analysis.target_match is True
    assert analysis.first_unchecked == "1.2"
    assert analysis.blocked_by is None
    assert plan_has_assigned_step_for_worker(plan, WORKER, "1.3") is True


def test_implementation_plan_reports_blocked_first_unchecked_step() -> None:
    plan = ImplementationPlan.parse(
        f"""
### Step 1.1 Foundation
#### Assigned: {WORKER}
- [ ] Finish foundation

### Step 1.2 Blocked
#### Depends on: 1.1
#### Assigned: {WORKER}
- [ ] Implement dependent work
"""
    )

    analysis = analyze_for_worker(plan, WORKER)

    assert analysis.first_unchecked == "1.1"
    assert analysis.blocked_by is None

    blocked_only_plan = ImplementationPlan.parse(
        f"""
### Step 1.1 Foundation
#### Assigned: {OTHER}
- [ ] Finish foundation

### Step 1.2 Blocked
#### Depends on: 1.1
#### Assigned: {WORKER}
- [ ] Implement dependent work
"""
    )

    blocked_analysis = analyze_for_worker(blocked_only_plan, WORKER)
    assert blocked_analysis.first_unchecked is None
    assert blocked_analysis.blocked_by == "1.1"


def test_steps_with_zero_unchecked_bullets_are_not_selected() -> None:
    plan = ImplementationPlan.parse(
        f"""
### Step 1.1 Done
#### Assigned: {WORKER}
- [x] Complete
"""
    )

    analysis = analyze_for_worker(plan, WORKER)

    assert analysis.assigned_any is True
    assert analysis.first_unchecked is None


def test_malformed_dependency_raises_structured_error() -> None:
    plan = ImplementationPlan.parse(
        f"""
### Step 1.1 Broken
#### Depends on: 9.9
#### Assigned: {WORKER}
- [ ] Work
"""
    )

    with pytest.raises(ImplementationPlanError, match="depends on 9.9"):
        analyze_for_worker(plan, WORKER)


def test_dependency_with_zero_bullets_raises_structured_error() -> None:
    plan = ImplementationPlan.parse(
        f"""
### Step 1.1 Empty
#### Assigned: {OTHER}

### Step 1.2 Blocked
#### Depends on: 1.1
#### Assigned: {WORKER}
- [ ] Work
"""
    )

    with pytest.raises(ImplementationPlanError, match="zero bullets"):
        analyze_for_worker(plan, WORKER)


def test_unrelated_worker_invalid_dependency_does_not_block_current_worker_analysis() -> None:
    plan = ImplementationPlan.parse(
        f"""
### Step 1.1 Current worker ready
#### Assigned: {WORKER}
- [ ] Work

### Step 1.2 Other worker broken
#### Depends on: 9.9
#### Assigned: {OTHER}
- [ ] Other work
"""
    )

    analysis = analyze_for_worker(plan, WORKER)

    assert analysis.first_unchecked == "1.1"
    assert analysis.blocked_by is None


def test_unrelated_worker_zero_bullet_dependency_does_not_block_current_worker_analysis() -> None:
    plan = ImplementationPlan.parse(
        f"""
### Step 1.1 Current worker ready
#### Assigned: {WORKER}
- [ ] Work

### Step 1.2 Empty dep
#### Assigned: {OTHER}

### Step 1.3 Other worker blocked
#### Depends on: 1.2
#### Assigned: {OTHER}
- [ ] Other work
"""
    )

    analysis = analyze_for_worker(plan, WORKER)

    assert analysis.first_unchecked == "1.1"
    assert analysis.blocked_by is None


def test_array_contains_ci_matches_bash_helper() -> None:
    assert array_contains_ci("User_Review", ("design", "user_review")) is True
    assert array_contains_ci("audit", ("design", "user_review")) is False
