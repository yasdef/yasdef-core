from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path

from yasdef_worker.app.resume import analyze_resume, step_gate_counts
from yasdef_worker.domain.phase_types import PhaseStatus
from yasdef_worker.domain.plans.implementation_plan import ImplementationPlan
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout


@dataclass(frozen=True, slots=True)
class Feature:
    feature_id: str


def test_resume_analysis_starts_at_first_incomplete_phase(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    plan = _plan(plan_checked=True, implementation_checked=False, review_checked=False)
    _write_design_and_step_plan(layout)

    analysis = analyze_resume(
        step="1.1",
        feature=Feature("feature-a"),
        plan=plan,
        layout=layout,
        git=repo,
    )

    assert [(state.phase, state.status) for state in analysis.states[:3]] == [
        ("design", PhaseStatus.COMPLETE),
        ("planning", PhaseStatus.COMPLETE),
        ("implementation", PhaseStatus.INCOMPLETE),
    ]
    assert analysis.start_phase == "implementation"
    assert analysis.phases_to_execute() == (
        "implementation",
        "user_review",
        "ai_audit",
        "post_review",
    )


def test_resume_analysis_reports_all_done(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    plan = _plan(plan_checked=True, implementation_checked=True, review_checked=True)
    _write_design_and_step_plan(layout)
    layout.step_review_results_dir.mkdir(parents=True)
    (layout.step_review_results_dir / "review_result-1.1-feature-a.md").write_text(
        "review\n",
        encoding="utf-8",
    )
    layout.history_file.parent.mkdir(parents=True, exist_ok=True)
    layout.history_file.write_text("- Step: 1.1 - Demo\n", encoding="utf-8")

    analysis = analyze_resume(
        step="1.1",
        feature=Feature("feature-a"),
        plan=plan,
        layout=layout,
        git=repo,
    )

    assert analysis.all_done is True
    assert analysis.phases_to_execute() == ()
    assert "Selected start phase: none (all phases complete)" in analysis.dry_run_report("1.1")


def test_resume_analysis_blocks_on_invalid_implementation_state(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    plan = _plan(plan_checked=True, implementation_checked=False, review_checked=False)
    layout.step_designs_dir.mkdir(parents=True)
    (layout.step_designs_dir / "step-1.1-feature-a-design.md").write_text("design\n", encoding="utf-8")

    analysis = analyze_resume(
        step="1.1",
        feature=Feature("feature-a"),
        plan=plan,
        layout=layout,
        git=repo,
    )

    assert analysis.blocked is True
    assert analysis.start_phase == "planning"
    assert "missing" in (analysis.block_reason or "")
    assert analysis.phases_to_execute() == ()


def test_step_gate_counts_ignore_tag_prefixes() -> None:
    plan = ImplementationPlan.parse(
        "\n".join(
            [
                "### Step 1.1 Demo",
                "#### Depends on: none",
                "#### Assigned: worker",
                "- [x] [REQ-1] Plan and discuss the step.",
                "- [ ] Implement the behavior.",
                "- [x] Review step implementation.",
            ]
        )
    )

    counts = step_gate_counts(plan, "1.1")

    assert counts.plan_checked is True
    assert counts.review_checked is True
    assert counts.implementation_total == 1
    assert counts.implementation_checked == 0


def _write_design_and_step_plan(layout: RuntimeLayout) -> None:
    layout.step_designs_dir.mkdir(parents=True)
    layout.step_plans_dir.mkdir(parents=True)
    (layout.step_designs_dir / "step-1.1-feature-a-design.md").write_text("design\n", encoding="utf-8")
    (layout.step_plans_dir / "step-1.1-feature-a.md").write_text("plan\n", encoding="utf-8")


def _plan(*, plan_checked: bool, implementation_checked: bool, review_checked: bool) -> ImplementationPlan:
    plan_marker = "x" if plan_checked else " "
    implementation_marker = "x" if implementation_checked else " "
    review_marker = "x" if review_checked else " "
    return ImplementationPlan.parse(
        "\n".join(
            [
                "### Step 1.1 Demo",
                "#### Depends on: none",
                "#### Assigned: worker",
                f"- [{plan_marker}] Plan and discuss the step.",
                f"- [{implementation_marker}] Implement the behavior.",
                f"- [{review_marker}] Review step implementation.",
            ]
        )
    )


def _init_repo(path: Path) -> GitRepo:
    subprocess.run(["git", "init", "-b", "main", str(path)], check=True, capture_output=True)
    repo = GitRepo(
        path,
        env={
            "GIT_AUTHOR_NAME": "Test User",
            "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test User",
            "GIT_COMMITTER_EMAIL": "test@example.com",
        },
    )
    (path / "README.md").write_text("hello\n", encoding="utf-8")
    repo.add("README.md")
    repo.commit("initial", paths=["README.md"])
    return repo
