from __future__ import annotations

import subprocess
from pathlib import Path
from typing import cast

import pytest

from yasdef_worker.app import coordinator as coordinator_module
from yasdef_worker.app.coordinator import Coordinator, RunOptions
from yasdef_worker.app.pipeline import PipelineResult
from yasdef_worker.domain.phases import MODEL_PHASES, WORKFLOW_PHASES
from yasdef_worker.domain.phase_types import PhaseResult, PhaseStatus
from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.process import ProcessRunner
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.user_output import RecordingUserOutput

WORKER_UUID = "worker-alpha-01"
COMPLETE_MODELS_CONFIG = "".join(f"{phase} | echo | mock-model\n" for phase in MODEL_PHASES)


def test_orchestrator_builds_feature_context_and_expands_canonical_workflow(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _seed_source(source)
    _seed_worker(layout, source)
    repo.add(".asdlc_worker", ".codex")
    repo.commit("seed worker", paths=[".asdlc_worker", ".codex"])
    iterated = _stub_pipeline(monkeypatch)

    result = _coordinator(layout, repo).run(RunOptions())

    assert result.succeeded is True
    assert iterated == [WORKFLOW_PHASES]
    assert layout.feature_sync_file.is_file()


def test_orchestrator_executes_canonical_order_when_rows_are_shuffled(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _seed_source(source)
    _seed_worker(layout, source)
    layout.models_file.write_text(
        "".join(f"| {phase} | echo | mock-model |\n" for phase in reversed(MODEL_PHASES)),
        encoding="utf-8",
    )
    repo.add(".asdlc_worker", ".codex")
    repo.commit("seed worker", paths=[".asdlc_worker", ".codex"])
    iterated = _stub_pipeline(monkeypatch)

    _coordinator(layout, repo).run(RunOptions())

    assert iterated == [WORKFLOW_PHASES]


def test_orchestrator_rejects_run_from_non_mainline_branch(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    repo.checkout_new("feature")
    layout = RuntimeLayout.from_root(repo.root)
    _write_models_config(layout, COMPLETE_MODELS_CONFIG)

    with pytest.raises(YasdefError, match="must start from main or master"):
        _coordinator(layout, repo).run(RunOptions())


def test_orchestrator_rejects_run_with_dirty_working_tree(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    _write_models_config(layout, COMPLETE_MODELS_CONFIG)

    with pytest.raises(YasdefError, match="requires a clean working tree"):
        _coordinator(layout, repo).run(RunOptions())


def test_orchestrator_allows_resume_from_non_mainline_branch(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    repo.checkout_new("step-1.1-feature-branch")
    layout = RuntimeLayout.from_root(repo.root)
    _write_models_config(layout, COMPLETE_MODELS_CONFIG)

    with pytest.raises(YasdefError) as exc_info:
        _coordinator(layout, repo).run(RunOptions(resume_step="1.1"))

    assert "must start from main or master" not in str(exc_info.value)


@pytest.mark.parametrize(
    ("content", "message"),
    [
        ("design | echo | mock-model\n", "missing phase"),
        (COMPLETE_MODELS_CONFIG + "design | echo | again\n", "duplicate 'design' entry"),
        (COMPLETE_MODELS_CONFIG + "implementation codex gpt-5.4\n", "expected"),
    ],
)
def test_orchestrator_rejects_invalid_configuration_before_any_collaborator(
    tmp_path: Path, content: str, message: str
) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    _write_models_config(layout, content)

    with pytest.raises(YasdefError, match=message):
        _exploding_coordinator(layout).run(RunOptions())

    assert not layout.feature_sync_file.exists()


@pytest.mark.parametrize("resume_step", [None, "1.1"])
def test_orchestrator_reports_missing_configuration_path(
    tmp_path: Path, resume_step: str | None
) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)

    with pytest.raises(YasdefError, match="missing model configuration") as exc_info:
        _exploding_coordinator(layout).run(RunOptions(resume_step=resume_step))

    assert str(layout.models_file) in str(exc_info.value)


def test_orchestrator_reports_unreadable_configuration_path(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    layout.models_file.mkdir(parents=True)

    with pytest.raises(YasdefError, match="unreadable model configuration") as exc_info:
        _exploding_coordinator(layout).run(RunOptions())

    assert str(layout.models_file) in str(exc_info.value)


class _Exploding:
    """Fails on any use, so a configuration error cannot hide a run side effect."""

    def __init__(self, label: str) -> None:
        self._label = label

    def __getattr__(self, name: str) -> object:
        raise AssertionError(f"{self._label}.{name} must not run before configuration validates")


def _exploding_coordinator(layout: RuntimeLayout) -> Coordinator:
    return Coordinator(
        layout=layout,
        git=cast(GitRepo, _Exploding("git")),
        prompts=Prompter(interactive=False),
        process=cast(ProcessRunner, _Exploding("process")),
        output=RecordingUserOutput(),
    )


def _coordinator(layout: RuntimeLayout, repo: GitRepo) -> Coordinator:
    return Coordinator(
        layout=layout,
        git=repo,
        prompts=Prompter(interactive=False),
        process=ProcessRunner(),
        output=RecordingUserOutput(),
    )


def _stub_pipeline(monkeypatch: pytest.MonkeyPatch) -> list[tuple[str, ...]]:
    """Isolate the coordinator from phase execution and record the requested workflow."""
    iterated: list[tuple[str, ...]] = []

    class _RecordingPipeline:
        def __init__(self, **_kwargs: object) -> None:
            pass

        def iterate(self, phases: tuple[str, ...]) -> PipelineResult:
            iterated.append(phases)
            return PipelineResult(
                tuple(PhaseResult(phase, PhaseStatus.COMPLETE) for phase in phases)
            )

    monkeypatch.setattr(coordinator_module, "Pipeline", _RecordingPipeline)
    return iterated


def _write_models_config(layout: RuntimeLayout, content: str) -> None:
    layout.models_file.parent.mkdir(parents=True, exist_ok=True)
    layout.models_file.write_text(content, encoding="utf-8")


def _seed_source(source: Path) -> None:
    feature = source / "feature-a"
    feature.mkdir(parents=True)
    (source / "init_progress_definition.yaml").write_text(
        "meta_info:\n  project_id: project-a\n",
        encoding="utf-8",
    )
    (feature / "implementation_plan.md").write_text(
        "\n".join(
            [
                "### Step 1.1 Demo",
                "#### Depends on: none",
                f"#### Assigned: {WORKER_UUID}",
                "- [ ] Do the work",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    (feature / "requirements_ears.md").write_text("REQ-1\n", encoding="utf-8")


def _seed_worker(layout: RuntimeLayout, source: Path) -> None:
    layout.binding_file.parent.mkdir(parents=True, exist_ok=True)
    layout.binding_file.write_text(
        "\n".join(
            [
                f"overmind_source_path: {source}",
                "project_id: project-a",
                f"worker_uuid: {WORKER_UUID}",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    _write_models_config(layout, COMPLETE_MODELS_CONFIG)
    layout.step_designs_dir.mkdir(parents=True, exist_ok=True)
    (layout.step_designs_dir / "step-1.1-feature-a-design.md").write_text(
        "# Feature Design: 1.1 - Demo\n",
        encoding="utf-8",
    )
    layout.step_review_results_dir.mkdir(parents=True, exist_ok=True)
    (layout.step_review_results_dir / "review_result-1.1-feature-a.md").write_text(
        "### F-01\n- [x] rejected: no issues\n",
        encoding="utf-8",
    )
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


def _write_script(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("from __future__ import annotations\n\nraise SystemExit(0)\n", encoding="utf-8")


def _init_repo(path: Path) -> GitRepo:
    path.mkdir(parents=True)
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
