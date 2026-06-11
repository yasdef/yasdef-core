from __future__ import annotations

import io
import subprocess
from pathlib import Path

import pytest

from yasdef_worker.app.register_worker import (
    REGISTER_BRANCH,
    RegisterWorkerOperation,
)
from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.user_output import RecordingUserOutput
from yasdef_worker.infra.yaml_io import read_yaml_file

WORKER_UUID = "worker-alpha-01"


def test_register_worker_writes_binding_on_register_branch_and_commits(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)
    output = RecordingUserOutput()

    result = RegisterWorkerOperation(
        layout=layout,
        git=repo,
        output=output,
        prompts=_prompts(source, WORKER_UUID),
    ).execute()

    binding = read_yaml_file(layout.binding_file)
    assert result.register_branch == REGISTER_BRANCH
    assert result.start_branch == "main"
    assert repo.current_branch() == REGISTER_BRANCH
    assert binding == {
        "overmind_source_path": str(source.resolve()),
        "project_id": "project-a",
        "worker_uuid": WORKER_UUID,
        "class": "backend",
        "status": "ready",
    }
    assert repo.diff_name_only("HEAD~1..HEAD") == [".asdlc_worker/project_overmind.yaml"]
    assert output.events[-1].level == "warn"
    assert REGISTER_BRANCH in output.events[-1].message
    assert "main" in output.events[-1].message


def test_register_worker_rejects_dirty_worktree_before_branch_switch(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    (repo.root / "dirty.txt").write_text("dirty\n", encoding="utf-8")

    with pytest.raises(YasdefError, match="clean working tree"):
        RegisterWorkerOperation(
            layout=layout,
            git=repo,
            output=RecordingUserOutput(),
            prompts=Prompter(stdin=io.StringIO(""), stderr=io.StringIO(), interactive=True),
        ).execute()


def test_register_worker_rejects_non_mainline_start_branch(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    repo.checkout_new("feature")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)

    with pytest.raises(YasdefError, match="must start from main or master"):
        RegisterWorkerOperation(
            layout=layout,
            git=repo,
            output=RecordingUserOutput(),
            prompts=_prompts(source, WORKER_UUID),
        ).execute()


def test_register_worker_rejects_unknown_worker_uuid(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _write_project(source)

    with pytest.raises(YasdefError, match="no registered worker"):
        RegisterWorkerOperation(
            layout=layout,
            git=repo,
            output=RecordingUserOutput(),
            prompts=_prompts(source, "worker-beta-02"),
        ).execute()


def _prompts(source: Path, worker_uuid: str) -> Prompter:
    return Prompter(
        stdin=io.StringIO(f"{source}\n{worker_uuid}\n"),
        stderr=io.StringIO(),
        interactive=True,
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
    repo.add("README.md")
    repo.commit("initial", paths=["README.md"])
    return repo
