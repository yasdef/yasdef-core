"""Integration tests for `yasdef post-review` — ports post_review_metrics_tests.sh
and the plan-sync portions of orchestrator_git_sync_*.sh."""
from __future__ import annotations

from pathlib import Path

from .conftest import GIT_ENV, git, seed_repo, write_binding, write_project_repo, yasdef

WORKER_UUID = "22222222-2222-2222-2222-222222222222"
PROJECT_ID = "project-pr"
FEATURE_ID = "feature-pr"


def _yasdef_post_review(
    worker_root: Path,
    *,
    step: str,
    feature_id: str,
    title: str,
    no_plan_sync: bool = True,
) -> "subprocess.CompletedProcess[str]":
    args = [
        "post-review",
        "--repo", str(worker_root),
        "--step", step,
        "--feature-id", feature_id,
        "--title", title,
    ]
    if no_plan_sync:
        args.append("--no-plan-sync")
    return yasdef(*args)


def _write_review_artifact(worker_root: Path, *, step: str, feature_id: str) -> Path:
    review_dir = worker_root / ".asdlc_worker" / "step_review_results"
    review_dir.mkdir(parents=True, exist_ok=True)
    artifact = review_dir / f"review_result-{step}-{feature_id}.md"
    artifact.write_text(f"# Review Result\n- Step: {step} test step\n", encoding="utf-8")
    git("add", "-A", cwd=worker_root)
    git("commit", "-qm", f"add review artifact {step}", cwd=worker_root)
    return artifact


def _make_project_git_repo(
    path: Path,
    *,
    project_id: str,
    worker_uuid: str,
    feature_id: str,
    step: str = "1.1",
) -> tuple[Path, Path]:
    """Create a project git repo with a bare remote and push initial state.

    Returns (local_project_path, bare_remote_path).
    The implementation_plan.md is already committed and pushed, so plan sync
    (stage → pull → push) succeeds even with no local modifications.
    """
    bare = path.parent / (path.name + ".git")
    bare.mkdir(parents=True)
    git("init", "--bare", "-q", "-b", "master", cwd=bare)

    path.mkdir(parents=True, exist_ok=True)
    git("init", "-q", "-b", "master", cwd=path)
    git("config", "user.name", "Test User", cwd=path)
    git("config", "user.email", "test@example.com", cwd=path)

    path.joinpath("workers.yaml").write_text(
        f"version: 1\nworkers:\n  - uuid: '{worker_uuid}'\n    class: 'platform'\n    status: 'ready'\n",
        encoding="utf-8",
    )
    path.joinpath("init_progress_definition.yaml").write_text(
        f"meta_info:\n  project_id: '{project_id}'\nsteps: []\n",
        encoding="utf-8",
    )
    feature_dir = path / feature_id
    feature_dir.mkdir()
    feature_dir.joinpath("implementation_plan.md").write_text(
        f"### Step {step} Title\n#### Assigned: {worker_uuid}\n- [ ] task\n",
        encoding="utf-8",
    )
    feature_dir.joinpath("requirements_ears.md").write_text("# Requirements\n", encoding="utf-8")

    import os
    env = {**os.environ, **GIT_ENV}
    import subprocess
    subprocess.run(["git", "-C", str(path), "remote", "add", "origin", str(bare)], check=True, env=env)
    git("add", "-A", cwd=path)
    git("commit", "-qm", "initial project setup", cwd=path)
    git("push", "-u", "origin", "master", cwd=path)
    return path, bare


# ---------------------------------------------------------------------------
# Post-review history metrics
# ---------------------------------------------------------------------------


def test_post_review_writes_history_entry(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    _write_review_artifact(worker, step="1.1", feature_id=FEATURE_ID)

    result = _yasdef_post_review(worker, step="1.1", feature_id=FEATURE_ID, title="First step")
    assert result.returncode == 0, result.stderr

    history = worker / ".asdlc_worker" / "history.md"
    assert history.is_file()
    content = history.read_text()
    assert "Step: 1.1" in content
    assert "First step" in content


def test_post_review_fails_when_review_artifact_missing(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)

    result = _yasdef_post_review(worker, step="1.1", feature_id=FEATURE_ID, title="Missing artifact")
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "review_result" in combined or "missing" in combined.lower() or "cannot" in combined.lower()


def test_post_review_second_run_replaces_history_entry(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    _write_review_artifact(worker, step="1.1", feature_id=FEATURE_ID)

    _yasdef_post_review(worker, step="1.1", feature_id=FEATURE_ID, title="First run")
    result = _yasdef_post_review(worker, step="1.1", feature_id=FEATURE_ID, title="Second run")
    assert result.returncode == 0, result.stderr

    content = (worker / ".asdlc_worker" / "history.md").read_text()
    assert content.count("Step: 1.1") == 1
    assert "Second run" in content
    assert "First run" not in content


# ---------------------------------------------------------------------------
# Plan sync (stage → pull --rebase → push)
# ---------------------------------------------------------------------------


def test_post_review_plan_sync_succeeds_with_configured_remote(tmp_path: Path) -> None:
    project, _ = _make_project_git_repo(
        tmp_path / "project",
        project_id=PROJECT_ID,
        worker_uuid=WORKER_UUID,
        feature_id=FEATURE_ID,
    )
    worker = seed_repo(tmp_path / "worker")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    _write_review_artifact(worker, step="1.1", feature_id=FEATURE_ID)

    result = _yasdef_post_review(
        worker, step="1.1", feature_id=FEATURE_ID, title="Sync step", no_plan_sync=False
    )
    assert result.returncode == 0, result.stderr
    content = (worker / ".asdlc_worker" / "history.md").read_text()
    assert "Step: 1.1" in content


def test_post_review_plan_sync_noninteractive_aborts_when_project_not_git(tmp_path: Path) -> None:
    """Non-git project dir → git add fails → noninteractive aborts → exit nonzero.
    History is still written because history.write_record() runs before plan sync."""
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    _write_review_artifact(worker, step="1.1", feature_id=FEATURE_ID)

    result = _yasdef_post_review(
        worker, step="1.1", feature_id=FEATURE_ID, title="No remote", no_plan_sync=False
    )
    assert result.returncode != 0
    assert (worker / ".asdlc_worker" / "history.md").is_file()
