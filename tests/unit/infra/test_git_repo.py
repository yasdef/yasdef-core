from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from yasdef_worker.infra.errors import GitOperationFailed
from yasdef_worker.infra.git_repo import GitRepo


def init_repo(path: Path) -> GitRepo:
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


def test_git_repo_branch_and_status_operations(tmp_path: Path) -> None:
    repo = init_repo(tmp_path)

    assert repo.is_inside_worktree()
    assert repo.current_branch() == "main"
    assert repo.branch_exists("main")
    assert repo.show_ref_exists("refs/heads/main")

    repo.checkout_new("feature")

    assert repo.current_branch() == "feature"
    assert repo.is_ancestor("main", "feature")


def test_git_repo_diff_helpers(tmp_path: Path) -> None:
    repo = init_repo(tmp_path)
    (tmp_path / "new.txt").write_text("one\ntwo\n", encoding="utf-8")
    repo.add("new.txt")

    rows = repo.diff_numstat(cached=True)
    names = repo.diff_name_only(cached=True, diff_filter="A")

    assert rows[0].added == 2
    assert rows[0].path == "new.txt"
    assert names == ["new.txt"]


def test_git_repo_force_add_and_commit_pathspec_only(tmp_path: Path) -> None:
    repo = init_repo(tmp_path)
    (tmp_path / ".git/info/exclude").write_text("ignored.txt\n", encoding="utf-8")
    (tmp_path / "ignored.txt").write_text("ignored\n", encoding="utf-8")
    (tmp_path / "other.txt").write_text("other\n", encoding="utf-8")

    repo.add("other.txt")
    repo.add("ignored.txt", force=True)
    assert repo.has_staged_changes(paths=["ignored.txt"]) is True

    repo.commit("commit ignored only", paths=["ignored.txt"])

    committed = subprocess.run(
        ["git", "-C", str(tmp_path), "ls-tree", "-r", "--name-only", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    assert "ignored.txt" in committed
    assert "other.txt" not in committed
    assert repo.diff_name_only(cached=True) == ["other.txt"]


def test_git_repo_commit_pathspec_does_not_stage_untracked_files(tmp_path: Path) -> None:
    repo = init_repo(tmp_path)
    (tmp_path / "new.txt").write_text("new\n", encoding="utf-8")

    with pytest.raises(GitOperationFailed, match="git commit failed"):
        repo.commit("should not stage", paths=["new.txt"])


def test_git_repo_has_staged_changes_raises_on_git_error(tmp_path: Path) -> None:
    repo = init_repo(tmp_path)

    with pytest.raises(GitOperationFailed, match="diff --cached --quiet"):
        repo.has_staged_changes(paths=[":(badmagic)"])


def test_git_repo_snapshot_index_does_not_touch_real_index(tmp_path: Path) -> None:
    repo = init_repo(tmp_path)
    (tmp_path / "snapshot.txt").write_text("snapshot\n", encoding="utf-8")

    with repo.with_snapshot_index() as snapshot:
        snapshot.add("snapshot.txt")
        assert snapshot.diff_name_only(cached=True) == ["snapshot.txt"]

    assert repo.diff_name_only(cached=True) == []
