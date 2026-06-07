from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from yasdef_worker.app.history_writer import HistoryWriter
from yasdef_worker.app.metrics_collector import MetricsCollector
from yasdef_worker.app.post_review import (
    HistoryTokenUsageSource,
    LogTokenUsageSource,
    PlanSyncOperation,
    PostReviewInput,
    PostReviewOperation,
    SyncResult,
    TokenUsageResolver,
)
from yasdef_worker.domain.history.token_usage import TokenUsage
from yasdef_worker.infra.errors import GitOperationFailed, YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.user_output import RecordingUserOutput


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


def test_plan_sync_operation_reports_source_plan_outside_inferred_git_root(tmp_path: Path) -> None:
    source_plan = tmp_path / "repo" / "work-items" / "feature-a" / "implementation_plan.md"
    git = FakeSyncGit(root=tmp_path / "repo" / "other")

    with pytest.raises(YasdefError) as raised:
        PlanSyncOperation(
            git=git,
            source_plan_path=source_plan,
            output=RecordingUserOutput(),
            retry=FakeRetry([]),
            step_number="1.1",
        ).execute()

    message = str(raised.value)
    assert "source implementation_plan.md is not inside the inferred ASDLC source git root" in message
    assert f"Tried source plan: {source_plan}" in message
    assert f"Inferred git root: {git.root}" in message
    assert "<overmind_source_path>/<feature_id>/implementation_plan.md" in message
    assert ".asdlc_worker/project_overmind.yaml" in message


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


def test_token_usage_resolver_reads_phase_logs(tmp_path: Path) -> None:
    layout = RuntimeLayout.from_root(tmp_path)
    layout.logs_dir.mkdir(parents=True)
    (layout.logs_dir / f"{tmp_path.name}-design-latest-log").write_text(
        "noise\nToken usage: total=12 input=8 (+ 2 cached) output=4 (reasoning 1)\n",
        encoding="utf-8",
    )

    usages = TokenUsageResolver((LogTokenUsageSource(layout=layout),)).collect(step="1.1")

    assert [phase for phase, _ in usages] == ["design"]
    assert usages[0][1].total == 12
    assert usages[0][1].input == 8
    assert usages[0][1].cached == 2
    assert usages[0][1].output == 4
    assert usages[0][1].reasoning == 1


def test_log_token_usage_source_uses_log_capture_token_normalization(tmp_path: Path) -> None:
    layout = RuntimeLayout.from_root(tmp_path)
    layout.logs_dir.mkdir(parents=True)
    source = LogTokenUsageSource(layout=layout)
    (layout.logs_dir / f"{tmp_path.name}-user_review-latest-log").write_text(
        "Token usage: total=7 input=4 (+ 0 cached) output=3 (reasoning 0)\n",
        encoding="utf-8",
    )
    (layout.logs_dir / f"{tmp_path.name}-user-review-latest-log").write_text(
        "Token usage: total=99 input=99 (+ 0 cached) output=0 (reasoning 0)\n",
        encoding="utf-8",
    )

    usage = source.usage_for(step="1.1", phase="user_review")

    assert usage is not None
    assert usage.total == 7


def test_log_token_usage_source_reads_debug_step_logs(tmp_path: Path) -> None:
    layout = RuntimeLayout.from_root(tmp_path)
    layout.logs_dir.mkdir(parents=True)
    (layout.logs_dir / f"{tmp_path.name}-ai_audit-1.2a-log").write_text(
        "Token usage: total=5 input=2 (+ 0 cached) output=3 (reasoning 1)\n",
        encoding="utf-8",
    )

    usage = LogTokenUsageSource(layout=layout).usage_for(step="1.2a", phase="ai_audit")

    assert usage is not None
    assert usage.total == 5
    assert usage.reasoning == 1


def test_token_usage_resolver_falls_back_to_history(tmp_path: Path) -> None:
    layout = RuntimeLayout.from_root(tmp_path)
    layout.history_file.parent.mkdir(parents=True)
    layout.history_file.write_text(
        "\n".join(
            [
                "# AI Run History",
                "",
                "## 2026-06-06T00:00:00Z",
                "- Step: 1.1 - Demo",
                "- Token usage: total=3 input=2 (+ 0 cached) output=1 (reasoning 0), including:",
                "  - Phase: planning - total=3 input=2 (+ 0 cached) output=1 (reasoning 0)",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    usages = TokenUsageResolver(
        (
            LogTokenUsageSource(layout=layout),
            HistoryTokenUsageSource(history_path=layout.history_file),
        )
    ).collect(step="1.1")

    assert [phase for phase, _ in usages] == ["planning"]
    assert usages[0][1].total == 3
    assert usages[0][1].input == 2
    assert usages[0][1].output == 1


def test_token_usage_resolver_treats_missing_or_unparseable_logs_as_optional(tmp_path: Path) -> None:
    layout = RuntimeLayout.from_root(tmp_path)
    layout.logs_dir.mkdir(parents=True)
    (layout.logs_dir / f"{tmp_path.name}-design-latest-log").write_text(
        "model output without token accounting\n",
        encoding="utf-8",
    )

    assert TokenUsageResolver.for_layout(layout).collect(step="1.1") == ()


class FakeRetry:
    def __init__(self, decisions: list[str]):
        self.decisions = decisions
        self.seen_steps: list[str] = []

    def on_failure(self, step, err):
        self.seen_steps.append(step.name)
        return self.decisions.pop(0)


class FakeSyncGit:
    def __init__(self, *, always_fail_push: bool = False, root: Path = Path("/tmp/source")):
        self.root = root
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
    repo.add("README.md")
    repo.commit("initial", paths=["README.md"])
    return repo
