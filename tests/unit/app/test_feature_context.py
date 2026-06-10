from __future__ import annotations

import io
import subprocess
from pathlib import Path

import pytest

from yasdef_worker.app.feature_context import FeatureContextBuilder
from yasdef_worker.infra.errors import FeatureExhausted, YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.user_output import RecordingUserOutput
from yasdef_worker.infra.yaml_io import read_yaml_file

WORKER_UUID = "worker-alpha-01"


def test_feature_context_reuses_valid_feature_meta_sync(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)
    _write_feature(source, "feature-a", step="1.1")
    _write_binding(layout, source)
    layout.feature_sync_file.write_text(
        "\n".join(
            [
                "project_id: project-a",
                f"worker_uuid: {WORKER_UUID}",
                "feature_id: feature-a",
                "selected_step: 1.1",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    state = FeatureContextBuilder(
        layout=layout,
        git=repo,
        prompts=Prompter(interactive=False),
        output=RecordingUserOutput(),
    ).build()

    assert state.selection_mode == "resume_reuse"
    assert state.feature_id == "feature-a"
    assert state.step == "1.1"
    assert state.source_plan_path == source / "feature-a" / "implementation_plan.md"


def test_feature_context_selects_single_candidate_and_writes_metadata(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)
    _write_feature(source, "feature-a", step="1.1")
    _write_feature(source, "feature-complete", step="1.2", checked=True)
    _write_binding(layout, source)

    state = FeatureContextBuilder(
        layout=layout,
        git=repo,
        prompts=Prompter(interactive=False),
        output=RecordingUserOutput(),
    ).build()

    assert state.selection_mode == "auto_single"
    assert state.feature_id == "feature-a"
    assert state.step == "1.1"
    assert read_yaml_file(layout.feature_sync_file) == {
        "project_id": "project-a",
        "worker_uuid": WORKER_UUID,
        "feature_id": "feature-a",
        "selected_step": "1.1",
    }


def test_feature_context_raises_controlled_stop_for_interactive_exhausted_feature(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)
    _write_feature(source, "feature-a", step="1.1", checked=True)
    _write_binding(layout, source)
    layout.feature_sync_file.write_text(
        "\n".join(
            [
                "project_id: project-a",
                f"worker_uuid: {WORKER_UUID}",
                "feature_id: feature-a",
                "selected_step: 1.1",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    output = RecordingUserOutput()

    with pytest.raises(FeatureExhausted) as raised:
        FeatureContextBuilder(
            layout=layout,
            git=repo,
            prompts=RecordingPrompter(selection=0),
            output=output,
        ).build()

    assert raised.value.exit_code == 0
    assert raised.value.feature_id == "feature-a"
    assert not layout.feature_sync_file.exists()
    assert [event.level for event in output.events] == ["warn", "step"]


def test_feature_context_prompts_when_multiple_candidates_exist(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)
    _write_feature(source, "feature-a", step="1.1")
    _write_feature(source, "feature-b", step="2.1")
    _write_binding(layout, source)
    prompter = Prompter(stdin=io.StringIO("2\n"), stderr=io.StringIO(), interactive=True)

    state = FeatureContextBuilder(
        layout=layout,
        git=repo,
        prompts=prompter,
        output=RecordingUserOutput(),
    ).build()

    assert state.selection_mode == "user_prompt"
    assert state.feature_id == "feature-b"
    assert state.step == "2.1"


def test_feature_context_resume_step_filters_candidate_features(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)
    _write_feature(source, "feature-a", step="1.1")
    _write_feature(source, "feature-b", step="2.1")
    _write_binding(layout, source)

    state = FeatureContextBuilder(
        layout=layout,
        git=repo,
        prompts=Prompter(interactive=False),
        output=RecordingUserOutput(),
        resume_step="2.1",
    ).build()

    assert state.selection_mode == "auto_single"
    assert state.feature_id == "feature-b"
    assert state.step == "2.1"


def test_feature_context_marks_current_feature_first_in_prompt(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)
    _write_feature(source, "feature-a", step="1.1")
    _write_feature(source, "feature-b", step="2.1")
    _write_binding(layout, source)
    layout.feature_sync_file.write_text(
        "\n".join(
            [
                "project_id: project-a",
                f"worker_uuid: {WORKER_UUID}",
                "feature_id: feature-b",
                "selected_step: 2.1",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    prompter = RecordingPrompter(selection=0)

    state = FeatureContextBuilder(
        layout=layout,
        git=repo,
        prompts=prompter,
        output=RecordingUserOutput(),
    ).build()

    assert prompter.options == ["feature-b (current)", "feature-a"]
    assert state.feature_id == "feature-b"
    assert state.selection_mode == "user_prompt"


def test_feature_context_builder_is_single_use(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)
    _write_feature(source, "feature-a", step="1.1")
    _write_binding(layout, source)
    builder = FeatureContextBuilder(
        layout=layout,
        git=repo,
        prompts=Prompter(interactive=False),
        output=RecordingUserOutput(),
    )

    builder.build()

    with pytest.raises(YasdefError, match="cannot be reused"):
        builder.build()


def test_feature_context_reports_blocked_assigned_step(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)
    feature = source / "feature-a"
    feature.mkdir()
    (feature / "implementation_plan.md").write_text(
        "\n".join(
            [
                "### Step 1.0 Prereq",
                "#### Depends on: none",
                "#### Assigned: other-worker",
                "- [ ] Finish prerequisite",
                "### Step 1.1 Demo",
                "#### Depends on: 1.0",
                f"#### Assigned: {WORKER_UUID}",
                "- [ ] Do the work",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    (feature / "requirements_ears.md").write_text("REQ-1\n", encoding="utf-8")
    _write_binding(layout, source)

    with pytest.raises(
        YasdefError,
        match=(
            f"Next possible assigned step for your worker {WORKER_UUID} "
            "is blocked by step '1.0' under project 'project-a'"
        ),
    ):
        FeatureContextBuilder(
            layout=layout,
            git=repo,
            prompts=Prompter(interactive=False),
            output=RecordingUserOutput(),
        ).build()


def test_feature_context_reports_no_assigned_steps(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)
    _write_feature(source, "feature-a", step="1.1", worker_uuid="worker-beta-02")
    _write_binding(layout, source)

    with pytest.raises(YasdefError, match=f"no assigned steps for worker UUID '{WORKER_UUID}'"):
        FeatureContextBuilder(
            layout=layout,
            git=repo,
            prompts=Prompter(interactive=False),
            output=RecordingUserOutput(),
        ).build()


def _write_project(source: Path) -> None:
    source.mkdir(parents=True)
    (source / "init_progress_definition.yaml").write_text(
        "meta_info:\n  project_id: project-a\n",
        encoding="utf-8",
    )


def _write_feature(
    source: Path,
    feature_id: str,
    *,
    step: str,
    checked: bool = False,
    worker_uuid: str = WORKER_UUID,
) -> None:
    feature = source / feature_id
    feature.mkdir()
    marker = "x" if checked else " "
    (feature / "implementation_plan.md").write_text(
        "\n".join(
            [
                f"### Step {step} Demo",
                "#### Depends on: none",
                f"#### Assigned: {worker_uuid}",
                f"- [{marker}] Do the work",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    (feature / "requirements_ears.md").write_text("REQ-1\n", encoding="utf-8")


def _write_binding(layout: RuntimeLayout, source: Path) -> None:
    layout.binding_file.parent.mkdir(parents=True, exist_ok=True)
    layout.binding_file.write_text(
        "\n".join(
            [
                f"overmind_source_path: {source}",
                "project_id: project-a",
                f"worker_uuid: {WORKER_UUID}",
                "class: implementation",
                "status: active",
            ]
        )
        + "\n",
        encoding="utf-8",
    )


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


class RecordingPrompter:
    interactive = True

    def __init__(self, *, selection: int):
        self.selection = selection
        self.options: list[str] = []

    def choose_numbered(self, prompt: str, options) -> int:
        self.options = list(options)
        return self.selection
