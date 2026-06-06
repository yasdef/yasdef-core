from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from yasdef_orchestrator.app.register_worker import (
    RUNTIME_BRANCH,
    RegisterWorkerInput,
    RegisterWorkerOperation,
)
from yasdef_orchestrator.infra.errors import YasdefError
from yasdef_orchestrator.infra.git_repo import GitRepo
from yasdef_orchestrator.infra.layout import RuntimeLayout
from yasdef_orchestrator.infra.user_output import RecordingUserOutput
from yasdef_orchestrator.infra.yaml_io import read_yaml_file

WORKER_UUID = "worker-alpha-01"


def test_register_worker_writes_binding_on_runtime_branch_and_commits(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)

    result = RegisterWorkerOperation(
        layout=layout,
        git=repo,
        output=RecordingUserOutput(),
    ).execute(RegisterWorkerInput(worker_uuid=WORKER_UUID, overmind_source_path=source))

    binding = read_yaml_file(layout.binding_file)
    assert result.runtime_branch == RUNTIME_BRANCH
    assert repo.current_branch() == RUNTIME_BRANCH
    assert binding == {
        "overmind_source_path": str(source.resolve()),
        "project_id": "project-a",
        "worker_uuid": WORKER_UUID,
        "class": "backend",
        "status": "ready",
    }
    assert repo.diff_name_only("HEAD~1..HEAD") == [".asdlc_worker/project_overmind.yaml"]


def test_register_worker_rejects_dirty_worktree_before_branch_switch(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)
    (repo.root / "dirty.txt").write_text("dirty\n", encoding="utf-8")

    with pytest.raises(YasdefError, match="uncommitted changes"):
        RegisterWorkerOperation(
            layout=layout,
            git=repo,
            output=RecordingUserOutput(),
        ).execute(RegisterWorkerInput(worker_uuid=WORKER_UUID, overmind_source_path=source))


def test_register_worker_rejects_unknown_worker_uuid(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)

    with pytest.raises(ValueError, match="no registered worker"):
        RegisterWorkerOperation(
            layout=layout,
            git=repo,
            output=RecordingUserOutput(),
        ).execute(
            RegisterWorkerInput(
                worker_uuid="worker-beta-02",
                overmind_source_path=source,
            )
        )


def _write_project(source: Path) -> None:
    source.mkdir(parents=True)
    (source / "init_progress_definition.yaml").write_text(
        "meta_info:\n  project_id: project-a\n",
        encoding="utf-8",
    )
    (source / "workers.yaml").write_text(
        "\n".join(
            [
                "workers:",
                f"  - uuid: {WORKER_UUID}",
                "    class: backend",
                "    status: ready",
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
    repo.commit("initial", paths=["README.md"])
    return repo
