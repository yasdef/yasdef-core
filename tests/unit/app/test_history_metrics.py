from __future__ import annotations

import subprocess
from datetime import UTC, datetime
from pathlib import Path

from yasdef_orchestrator.app.history_writer import HistoryWriter, total_usage
from yasdef_orchestrator.app.metrics_collector import MetricsCollector
from yasdef_orchestrator.domain.history.records import HistoryRecord, Metrics
from yasdef_orchestrator.domain.history.token_usage import TokenUsage
from yasdef_orchestrator.infra.git_repo import GitRepo
from yasdef_orchestrator.infra.layout import RuntimeLayout


def test_history_writer_replaces_existing_step_section(tmp_path: Path) -> None:
    layout = RuntimeLayout.from_root(tmp_path)
    writer = HistoryWriter(
        layout,
        now=lambda: datetime(2026, 6, 6, 12, 0, tzinfo=UTC),
    )
    layout.history_file.parent.mkdir(parents=True)
    layout.history_file.write_text(
        "# AI Run History\n\n"
        "## 2026-01-01T00:00:00Z\n"
        "- Step: 1.1 - Old\n"
        "- Token usage: old\n"
        "\n"
        "## 2026-01-02T00:00:00Z\n"
        "- Step: 1.2 - Keep\n",
        encoding="utf-8",
    )
    record = HistoryRecord(
        step="1.1",
        title="Demo",
        step_plan=str(layout.worker_repo_root / ".asdlc_worker" / "step_plans" / "step-1.1-demo.md"),
        token_usage=TokenUsage(total=3, input=2, output=1),
        metrics=Metrics(loc_added=10, files_added=1, files_touched=2),
        phase_usages=(
            ("design", TokenUsage(total=1, input=1)),
            ("planning", TokenUsage(total=2, input=1, output=1)),
        ),
    )

    writer.write_record(record)
    content = layout.history_file.read_text(encoding="utf-8")

    assert "Old" not in content
    assert "- Step: 1.2 - Keep" in content
    assert "## 2026-06-06T12:00:00Z" in content
    assert "- Step: 1.1 - Demo" in content
    assert "  - Phase: design - total=1 input=1 (+ 0 cached) output=0 (reasoning 0)" in content
    assert "- Step plan: .asdlc_worker/step_plans/step-1.1-demo.md" in content


def test_total_usage_sums_phase_usage() -> None:
    assert total_usage(
        (
            ("design", TokenUsage(total=1, input=2)),
            ("planning", TokenUsage(total=3, input=4, cached=5)),
        )
    ) == TokenUsage(total=4, input=6, cached=5)


def test_metrics_collector_counts_staged_changes_excluding_runtime(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    (tmp_path / "README.md").write_text("hello\nnew\n", encoding="utf-8")
    (tmp_path / "app.py").write_text("print('hi')\n", encoding="utf-8")
    runtime = tmp_path / ".asdlc_worker"
    runtime.mkdir()
    (runtime / "history.md").write_text("runtime\n", encoding="utf-8")
    repo.add("README.md", "app.py", ".asdlc_worker/history.md")

    metrics = MetricsCollector(repo).collect("HEAD", cached=True)

    assert metrics.loc_added == 2
    assert metrics.files_added == 1
    assert metrics.files_touched == 1


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
