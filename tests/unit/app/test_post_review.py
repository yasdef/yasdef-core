from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from yasdef_orchestrator.app.history_writer import HistoryWriter
from yasdef_orchestrator.app.metrics_collector import MetricsCollector
from yasdef_orchestrator.app.post_review import (
    PlanSyncOperation,
    PostReviewInput,
    PostReviewOperation,
    SyncResult,
)
from yasdef_orchestrator.domain.history.token_usage import TokenUsage
from yasdef_orchestrator.infra.errors import GitOperationFailed, YasdefError
from yasdef_orchestrator.infra.git_repo import GitRepo
from yasdef_orchestrator.infra.layout import RuntimeLayout
from yasdef_orchestrator.infra.user_output import RecordingUserOutput


def test_plan_sync_operation_retries_failed_step_and_finishes() -> None:
    git = FakeSyncGit()
    retry = FakeRetry(["retry"])

    result = PlanSyncOperation(
        git=git,
        source_plan_path=git.root / "feature-a" / "implementation_plan.md",
        output=RecordingUserOutput(),
        retry=retry,
        step_number="1.1",
    ).execute()

    assert result is SyncResult.OK
    assert git.push_attempts == 2
    assert retry.seen_steps == ["push"]


def test_plan_sync_operation_can_skip_after_failure() -> None:
    git = FakeSyncGit(always_fail_push=True)
    retry = FakeRetry(["finish"])

    result = PlanSyncOperation(
        git=git,
        source_plan_path=git.root / "feature-a" / "implementation_plan.md",
        output=RecordingUserOutput(),
        retry=retry,
        step_number="1.1",
    ).execute()

    assert result is SyncResult.SKIPPED


def test_post_review_operation_writes_history_with_metrics(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)
    layout.step_review_results_dir.mkdir(parents=True)
    layout.step_plans_dir.mkdir(parents=True)
    review = layout.step_review_results_dir / "review_result-1.1-feature-a.md"
    step_plan = layout.step_plans_dir / "step-1.1-feature-a.md"
    review.write_text("review\n", encoding="utf-8")
    step_plan.write_text("# Step Plan: 1.1 - Demo\n", encoding="utf-8")
    (tmp_path / "app.py").write_text("print('hi')\n", encoding="utf-8")
    repo.add("app.py", ".asdlc_worker/step_review_results/review_result-1.1-feature-a.md")

    record = PostReviewOperation(
        layout=layout,
        git=repo,
        history=HistoryWriter(layout),
        metrics=MetricsCollector(repo),
        output=RecordingUserOutput(),
    ).execute(
        PostReviewInput(
            step="1.1",
            feature_id="feature-a",
            title="Demo",
            step_plan_path=step_plan,
            phase_usages=(("design", TokenUsage(total=1, input=1)),),
        )
    )

    content = layout.history_file.read_text(encoding="utf-8")
    assert record.metrics.files_added == 1
    assert "- Step: 1.1 - Demo" in content
    assert "- New lines of code added: 1" in content


def test_post_review_operation_requires_review_artifact(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    layout = RuntimeLayout.from_root(tmp_path)

    with pytest.raises(YasdefError, match="missing review artifact"):
        PostReviewOperation(
            layout=layout,
            git=repo,
            history=HistoryWriter(layout),
            metrics=MetricsCollector(repo),
            output=RecordingUserOutput(),
        ).execute(
            PostReviewInput(
                step="1.1",
                feature_id="feature-a",
                title="Demo",
                step_plan_path=layout.step_plans_dir / "step-1.1-feature-a.md",
            )
        )


class FakeRetry:
    def __init__(self, decisions: list[str]):
        self.decisions = decisions
        self.seen_steps: list[str] = []

    def on_failure(self, step, err):
        self.seen_steps.append(step.name)
        return self.decisions.pop(0)


class FakeSyncGit:
    def __init__(self, *, always_fail_push: bool = False):
        self.root = Path("/tmp/source")
        self.push_attempts = 0
        self.always_fail_push = always_fail_push

    def add(self, *paths: str) -> None:
        return None

    def diff_name_only(self, *args, **kwargs):
        return ["feature-a/implementation_plan.md"]

    def commit(self, message: str) -> None:
        return None

    def pull_rebase(self) -> None:
        return None

    def push(self) -> None:
        self.push_attempts += 1
        if self.always_fail_push or self.push_attempts == 1:
            raise GitOperationFailed("push", ["git", "push"], 1, "failed")


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
    repo.commit("initial", paths=["README.md"])
    return repo
