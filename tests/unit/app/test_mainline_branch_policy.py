from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

from yasdef_worker.app.mainline_branch_policy import checkout_work_branch
from yasdef_worker.infra.errors import GitOperationFailed, YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.user_output import RecordingUserOutput


def test_checkout_work_branch_restores_mainline_when_fast_forward_fails(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repo = _init_repo(tmp_path / "repo")
    repo.checkout_new("init_yasdef_worker")
    repo.checkout("main")
    _commit_file(repo, "mainline.txt", "advance mainline\n")

    def fail_fast_forward(branch: str) -> None:
        raise GitOperationFailed("merge", ["git", "merge", branch], 128, "simulated failure")

    monkeypatch.setattr(repo, "merge_ff", fail_fast_forward)
    output = RecordingUserOutput()

    with pytest.raises(YasdefError, match="restored to main"):
        checkout_work_branch(
            repo,
            output,
            operation="yasdef init",
            branch_name="init_yasdef_worker",
        )

    assert repo.current_branch() == "main"
    assert output.events == []


def test_checkout_work_branch_reports_merge_and_rollback_failures(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repo = _init_repo(tmp_path / "repo")
    repo.checkout_new("init_yasdef_worker")
    repo.checkout("main")
    _commit_file(repo, "mainline.txt", "advance mainline\n")
    real_checkout = repo.checkout

    def fail_fast_forward(branch: str) -> None:
        raise GitOperationFailed("merge", ["git", "merge", branch], 128, "merge failed")

    def fail_rollback(branch: str) -> None:
        if branch == "main":
            raise GitOperationFailed(
                "checkout", ["git", "checkout", branch], 128, "rollback failed"
            )
        real_checkout(branch)

    monkeypatch.setattr(repo, "merge_ff", fail_fast_forward)
    monkeypatch.setattr(repo, "checkout", fail_rollback)
    output = RecordingUserOutput()

    with pytest.raises(YasdefError) as raised:
        checkout_work_branch(
            repo,
            output,
            operation="yasdef init",
            branch_name="init_yasdef_worker",
        )

    message = str(raised.value)
    assert "merge failed" in message
    assert "rollback to main also failed" in message
    assert "rollback failed" in message
    assert repo.current_branch() == "init_yasdef_worker"
    assert output.events == []


def test_checkout_work_branch_does_not_merge_when_work_branch_is_ahead(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repo = _init_repo(tmp_path / "repo")
    repo.checkout_new("init_yasdef_worker")
    _commit_file(repo, "work.txt", "work branch commit\n")
    repo.checkout("main")
    output = RecordingUserOutput()

    def unexpected_merge(_branch: str) -> None:
        raise AssertionError("merge_ff must not run when the work branch is ahead")

    monkeypatch.setattr(repo, "merge_ff", unexpected_merge)

    checkout_work_branch(
        repo,
        output,
        operation="yasdef init",
        branch_name="init_yasdef_worker",
    )

    assert repo.current_branch() == "init_yasdef_worker"
    assert output.events[-1].message == "switched to existing branch: init_yasdef_worker"


def test_checkout_work_branch_does_not_merge_when_branch_tips_are_equal(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repo = _init_repo(tmp_path / "repo")
    repo.checkout_new("init_yasdef_worker")
    repo.checkout("main")
    output = RecordingUserOutput()

    def unexpected_merge(_branch: str) -> None:
        raise AssertionError("merge_ff must not run when branch tips are equal")

    monkeypatch.setattr(repo, "merge_ff", unexpected_merge)

    checkout_work_branch(
        repo,
        output,
        operation="yasdef init",
        branch_name="init_yasdef_worker",
    )

    assert repo.current_branch() == "init_yasdef_worker"
    assert output.events[-1].message == "switched to existing branch: init_yasdef_worker"


def _init_repo(path: Path) -> GitRepo:
    path.mkdir(parents=True)
    git_env = {
        **os.environ,
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
    }
    subprocess.run(
        ["git", "init", "-q", "-b", "main"],
        cwd=path,
        env=git_env,
        check=True,
    )
    repo = GitRepo(
        path,
        env={
            "GIT_AUTHOR_NAME": "Test User",
            "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test User",
            "GIT_COMMITTER_EMAIL": "test@example.com",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
        },
    )
    _commit_file(repo, "README.md", "seed\n")
    return repo


def _commit_file(repo: GitRepo, name: str, content: str) -> None:
    repo.root.joinpath(name).write_text(content, encoding="utf-8")
    repo.add(name)
    repo.commit(f"add {name}")
