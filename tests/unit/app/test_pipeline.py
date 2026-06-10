from __future__ import annotations

import io
import subprocess
from dataclasses import dataclass
from pathlib import Path

from yasdef_worker.app.pipeline import DEFAULT_PHASES, Pipeline
from yasdef_worker.app.phases import ModelConfigRunnerFactory, PhaseContext, PlanningPhase
from yasdef_worker.domain.phases import MODEL_PHASES
from yasdef_worker.domain.phase_types import PhaseStatus
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.log_capture import LogCapture
from yasdef_worker.infra.process import ProcessRunner
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.templates import TemplateLoader
from yasdef_worker.infra.user_output import RecordingUserOutput


@dataclass(frozen=True, slots=True)
class Feature:
    step: str
    feature_id: str
    worker_uuid: str = "worker-uuid"


def test_default_pipeline_phases_follow_model_phase_registry() -> None:
    assert tuple(DEFAULT_PHASES) == MODEL_PHASES
    assert "post_review" not in DEFAULT_PHASES


def test_pipeline_runs_concrete_echo_phases_in_order(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    _seed_runtime(layout)
    repo.add(".asdlc_worker", ".codex")
    repo.commit("seed runtime", paths=[".asdlc_worker", ".codex"])
    ctx = _ctx(layout, repo, Prompter(interactive=False), io.StringIO())

    result = Pipeline(ctx=ctx).iterate(
        ("design", "planning", "implementation", "user_review", "ai_audit")
    )

    assert result.succeeded is True
    assert [phase.phase for phase in result.executed] == [
        "design",
        "planning",
        "implementation",
        "user_review",
        "ai_audit",
    ]
    assert repo.current_branch() == "step-1.2a-feature-demo-ai-audit"


def test_pipeline_stops_when_user_denies_confirmed_phase(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    _seed_runtime(layout)
    ctx = _ctx(layout, repo, Prompter(stdin=io.StringIO("n\n"), stderr=io.StringIO(), interactive=True), io.StringIO())

    result = Pipeline(ctx=ctx).iterate(("planning",))

    assert result.stopped is True
    assert result.executed[0].status is PhaseStatus.SKIPPED
    assert "user denied" in result.stop_reason


def test_pipeline_stops_when_user_denies_design_phase(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    _seed_runtime(layout)
    ctx = _ctx(
        layout,
        repo,
        Prompter(stdin=io.StringIO("n\n"), stderr=io.StringIO(), interactive=True),
        io.StringIO(),
    )

    result = Pipeline(ctx=ctx).iterate(("design", "planning"))

    assert result.stopped is True
    assert result.executed[0].phase == "design"
    assert result.executed[0].status is PhaseStatus.SKIPPED
    assert repo.current_branch() == "main"


def test_pipeline_stops_when_user_denies_implementation_after_planning(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    _seed_runtime(layout)
    repo.add(".asdlc_worker", ".codex")
    repo.commit("seed runtime", paths=[".asdlc_worker", ".codex"])
    ctx = _ctx(
        layout,
        repo,
        Prompter(stdin=io.StringIO("y\nn\n"), stderr=io.StringIO(), interactive=True),
        io.StringIO(),
    )

    result = Pipeline(ctx=ctx).iterate(("planning", "implementation"))

    assert result.stopped is True
    assert [phase.phase for phase in result.executed] == ["planning", "implementation"]
    assert result.executed[0].status is PhaseStatus.COMPLETE
    assert result.executed[1].status is PhaseStatus.SKIPPED
    assert repo.current_branch() == "step-1.2a-feature-demo-plan"


def test_pipeline_does_not_recheck_planning_ledgers_after_model_run(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    _seed_runtime(layout)
    PlanningPhase(_ctx(layout, repo, Prompter(interactive=False), io.StringIO())).blockers_path().write_text(
        "- Blocked.\n",
        encoding="utf-8",
    )
    repo.add(".asdlc_worker", ".codex")
    repo.commit("seed runtime", paths=[".asdlc_worker", ".codex"])
    ctx = _ctx(layout, repo, Prompter(interactive=False), io.StringIO())

    result = Pipeline(ctx=ctx).iterate(("planning", "implementation"))

    assert result.stopped is False
    assert [phase.phase for phase in result.executed] == ["planning", "implementation"]
    assert all(phase.status is PhaseStatus.COMPLETE for phase in result.executed)


def test_pipeline_converts_phase_precondition_error_to_stopped_result(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    _seed_runtime(layout)
    (layout.step_plans_dir / "step-1.2a-feature-demo.md").unlink()
    repo.add(".asdlc_worker", ".codex")
    repo.commit("seed runtime", paths=[".asdlc_worker", ".codex"])
    ctx = _ctx(layout, repo, Prompter(interactive=False), io.StringIO())

    result = Pipeline(ctx=ctx).iterate(("implementation",))

    assert result.stopped is True
    assert result.executed[0].phase == "implementation"
    assert result.executed[0].status is PhaseStatus.FAILED
    assert "step plan not found" in result.stop_reason


def test_pipeline_converts_branch_precondition_error_to_stopped_result(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    _seed_runtime(layout)
    repo.add(".asdlc_worker", ".codex")
    repo.commit("seed runtime", paths=[".asdlc_worker", ".codex"])
    ctx = _ctx(layout, repo, Prompter(interactive=False), io.StringIO())

    result = Pipeline(ctx=ctx).iterate(("user_review",))

    assert result.stopped is True
    assert result.executed[0].phase == "user_review"
    assert result.executed[0].status is PhaseStatus.FAILED
    assert "required source branch not found" in result.stop_reason


def _ctx(layout: RuntimeLayout, repo: GitRepo, prompts: Prompter, output: io.StringIO) -> PhaseContext:
    return PhaseContext(
        layout=layout,
        git=repo,
        runner_factory=ModelConfigRunnerFactory(layout.models_file),
        prompts=prompts,
        process=ProcessRunner(),
        log_capture=LogCapture(layout, project="demo"),
        templates=TemplateLoader(layout),
        output=RecordingUserOutput(),
        feature=Feature(step="1.2a", feature_id="feature-demo"),
        process_output=output,
    )


def _seed_runtime(layout: RuntimeLayout) -> None:
    layout.models_file.parent.mkdir(parents=True, exist_ok=True)
    layout.models_file.write_text(
        "\n".join(
            [
                "design | echo | mock-model",
                "planning | echo | mock-model",
                "implementation | echo | mock-model",
                "user_review | echo | mock-model",
                "ai_audit | echo | mock-model",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    for directory in [
        layout.step_designs_dir,
        layout.step_plans_dir,
        layout.step_open_questions_dir,
        layout.step_blockers_dir,
        layout.step_review_results_dir,
        layout.overmind_dir,
    ]:
        directory.mkdir(parents=True, exist_ok=True)
    (layout.overmind_dir / "implementation_plan.md").write_text("plan\n", encoding="utf-8")
    (layout.overmind_dir / "requirements_ears.md").write_text("ears\n", encoding="utf-8")
    (
        layout.step_designs_dir / "step-1.2a-feature-demo-design.md"
    ).write_text("# Feature Design: 1.2a - Demo\n", encoding="utf-8")
    (layout.step_plans_dir / "step-1.2a-feature-demo.md").write_text(
        "# Step Plan: 1.2a - Demo\n",
        encoding="utf-8",
    )
    (
        layout.step_open_questions_dir / "step-1.2a-feature-demo-open-questions.md"
    ).write_text("- None.\n", encoding="utf-8")
    (
        layout.step_blockers_dir / "step-1.2a-feature-demo-blockers.md"
    ).write_text("- No blockers.\n", encoding="utf-8")
    _write_script(
        layout.worker_repo_root
        / ".codex"
        / "skills"
        / "yasdef-worker-design"
        / "scripts"
        / "check_design_readiness.py"
    )
    _write_script(
        layout.worker_repo_root
        / ".codex"
        / "skills"
        / "yasdef-worker-plan"
        / "scripts"
        / "check_planning_readiness.py"
    )
    _write_script(
        layout.worker_repo_root
        / ".codex"
        / "skills"
        / "yasdef-worker-implementation"
        / "scripts"
        / "build_implementation_context.py"
    )
    _write_script(
        layout.worker_repo_root
        / ".codex"
        / "skills"
        / "yasdef-worker-implementation"
        / "scripts"
        / "check_implementation_readiness.py"
    )
    user_review_skill = (
        layout.worker_repo_root / ".codex" / "skills" / "yasdef-worker-user-review" / "SKILL.md"
    )
    user_review_skill.parent.mkdir(parents=True, exist_ok=True)
    user_review_skill.write_text("skill\n", encoding="utf-8")
    audit_root = layout.worker_repo_root / ".codex" / "skills" / "yasdef-worker-ai-audit"
    (audit_root / "SKILL.md").parent.mkdir(parents=True, exist_ok=True)
    (audit_root / "SKILL.md").write_text("skill\n", encoding="utf-8")
    for name in [
        "check_ai_audit_entry.py",
        "build_ai_audit_context.py",
        "check_ai_audit_closure.py",
    ]:
        _write_script(audit_root / "scripts" / name)


def _write_script(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("from __future__ import annotations\n\nraise SystemExit(0)\n", encoding="utf-8")


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
