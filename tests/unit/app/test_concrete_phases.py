from __future__ import annotations

import io
import subprocess
from dataclasses import dataclass
from pathlib import Path

from yasdef_worker.app.phases import (
    AiAuditPhase,
    DesignPhase,
    ImplementationPhase,
    ModelConfigRunnerFactory,
    PhaseContext,
    PlanningPhase,
    UserReviewPhase,
)
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


def test_concrete_phases_run_once_with_echo_runner_and_expected_branches(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    _seed_runtime(layout)
    repo.add(".asdlc_worker", ".codex")
    repo.commit("seed runtime", paths=[".asdlc_worker", ".codex"])

    output = io.StringIO()
    ctx = PhaseContext(
        layout=layout,
        git=repo,
        runner_factory=ModelConfigRunnerFactory(layout.models_file),
        prompts=Prompter(interactive=False),
        process=ProcessRunner(),
        log_capture=LogCapture(layout, project="demo"),
        templates=TemplateLoader(layout),
        output=RecordingUserOutput(),
        feature=Feature(step="1.2a", feature_id="feature-demo"),
        process_output=output,
    )

    assert DesignPhase(ctx).execute().is_complete
    assert repo.current_branch() == "step-1.2a-feature-demo-plan"
    assert (layout.logs_dir / "demo-design-latest-log").is_file()

    assert PlanningPhase(ctx).execute().is_complete
    assert repo.current_branch() == "step-1.2a-feature-demo-plan"
    assert (layout.logs_dir / "demo-planning-latest-log").is_file()

    assert ImplementationPhase(ctx).execute().is_complete
    assert repo.current_branch() == "step-1.2a-feature-demo-implementation"
    (tmp_path / "implementation.txt").write_text("done\n", encoding="utf-8")
    repo.add("implementation.txt")
    repo.commit("implementation", paths=["implementation.txt"])

    assert UserReviewPhase(ctx).execute().is_complete
    assert repo.current_branch() == "step-1.2a-feature-demo-user-review"
    (tmp_path / "review.txt").write_text("reviewed\n", encoding="utf-8")
    repo.add("review.txt")
    repo.commit("review", paths=["review.txt"])

    assert AiAuditPhase(ctx).execute().is_complete
    assert repo.current_branch() == "step-1.2a-feature-demo-ai-audit"
    assert "yasdef-worker-ai-audit" in output.getvalue()


def test_planning_phase_does_not_recheck_ledgers_after_model_run(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    _seed_runtime(layout)
    PlanningPhase(ctx := _ctx(layout, repo, io.StringIO())).open_questions_path().write_text(
        "- Need user answer.\n",
        encoding="utf-8",
    )
    repo.add(".asdlc_worker", ".codex")
    repo.commit("seed runtime", paths=[".asdlc_worker", ".codex"])

    result = PlanningPhase(ctx).execute()

    assert result.is_complete


def _ctx(layout: RuntimeLayout, repo: GitRepo, output: io.StringIO) -> PhaseContext:
    return PhaseContext(
        layout=layout,
        git=repo,
        runner_factory=ModelConfigRunnerFactory(layout.models_file),
        prompts=Prompter(interactive=False),
        process=ProcessRunner(),
        log_capture=LogCapture(layout, project="demo"),
        templates=TemplateLoader(layout),
        output=RecordingUserOutput(),
        feature=Feature(step="1.2a", feature_id="feature-demo"),
        process_output=output,
    )


def _seed_runtime(layout: RuntimeLayout, *, skill_prefix: str = ".codex") -> None:
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
    layout.step_designs_dir.mkdir(parents=True, exist_ok=True)
    layout.step_plans_dir.mkdir(parents=True, exist_ok=True)
    layout.step_open_questions_dir.mkdir(parents=True, exist_ok=True)
    layout.step_blockers_dir.mkdir(parents=True, exist_ok=True)
    layout.step_review_results_dir.mkdir(parents=True, exist_ok=True)
    layout.overmind_dir.mkdir(parents=True, exist_ok=True)
    (layout.overmind_dir / "implementation_plan.md").write_text("plan\n", encoding="utf-8")
    (layout.overmind_dir / "reqirements_ears.md").write_text("ears\n", encoding="utf-8")
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
    skills_root = layout.worker_repo_root / skill_prefix / "skills"
    _write_script(
        skills_root
        / "yasdef-worker-design"
        / "scripts"
        / "check_design_readiness.py"
    )
    _write_script(
        skills_root
        / "yasdef-worker-plan"
        / "scripts"
        / "check_planning_readiness.py"
    )
    _write_script(
        skills_root
        / "yasdef-worker-implementation"
        / "scripts"
        / "build_implementation_context.py"
    )
    _write_script(
        skills_root
        / "yasdef-worker-implementation"
        / "scripts"
        / "check_implementation_readiness.py"
    )
    user_review_skill = skills_root / "yasdef-worker-user-review" / "SKILL.md"
    user_review_skill.parent.mkdir(parents=True, exist_ok=True)
    user_review_skill.write_text("skill\n", encoding="utf-8")
    audit_root = skills_root / "yasdef-worker-ai-audit"
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
