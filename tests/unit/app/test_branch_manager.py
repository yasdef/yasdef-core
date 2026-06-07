from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from yasdef_worker.app.branch_manager import BranchManager
from yasdef_worker.infra.errors import PhasePreconditionError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.user_output import RecordingUserOutput


def test_branch_manager_walks_phase_sources(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    manager = BranchManager(repo, RecordingUserOutput())

    plan = manager.ensure_plan_branch(step="1.2a", feature_id="feature-demo")
    implementation = manager.ensure_implementation_branch(step="1.2a", feature_id="feature-demo")
    (tmp_path / "implementation.txt").write_text("done\n", encoding="utf-8")
    repo.add("implementation.txt")
    repo.commit("implementation", paths=["implementation.txt"])

    user_review = manager.ensure_user_review_branch(step="1.2a", feature_id="feature-demo")
    (tmp_path / "review.txt").write_text("reviewed\n", encoding="utf-8")
    repo.add("review.txt")
    repo.commit("review", paths=["review.txt"])

    ai_audit = manager.ensure_ai_audit_branch(step="1.2a", feature_id="feature-demo")

    assert plan == "step-1.2a-feature-demo-plan"
    assert implementation == "step-1.2a-feature-demo-implementation"
    assert user_review == "step-1.2a-feature-demo-user-review"
    assert ai_audit == "step-1.2a-feature-demo-ai-audit"
    assert repo.current_branch() == ai_audit
    assert repo.is_ancestor(implementation, user_review)
    assert repo.is_ancestor(user_review, ai_audit)


def test_branch_manager_requires_user_review_source_branch(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    manager = BranchManager(repo, RecordingUserOutput())

    with pytest.raises(PhasePreconditionError, match="required source branch not found"):
        manager.ensure_user_review_branch(step="1.2a", feature_id="feature-demo")


def test_branch_manager_refuses_dirty_switch_to_required_source(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    manager = BranchManager(repo, RecordingUserOutput())
    manager.ensure_implementation_branch(step="1.2a", feature_id="feature-demo")
    repo.checkout("main")
    (tmp_path / "dirty.txt").write_text("dirty\n", encoding="utf-8")

    with pytest.raises(PhasePreconditionError, match="working tree must be clean"):
        manager.ensure_user_review_branch(step="1.2a", feature_id="feature-demo")


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
