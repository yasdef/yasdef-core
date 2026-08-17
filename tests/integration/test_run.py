"""Integration tests for `yasdef run` — ports orchestrator_assignment_tests.sh,
orchestrator_resume_tests.sh, and feature-context exhausted/blocked scenarios."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

from .conftest import (
    GIT_ENV,
    create_design_artifact,
    ScenarioFactory,
    git,
    seed_repo,
    write_binding,
    write_feature,
    write_feature_meta_sync,
    write_project_git_repo,
    write_project_repo,
    yasdef,
)

WORKER_UUID = "11111111-1111-1111-1111-111111111111"
PROJECT_ID = "project-run"
FEATURE_ID = "feature-alpha"


def _yasdef_run(
    worker_root: Path,
    *extra_args: str,
    input: str | None = None,
    interactive: bool = False,
) -> "subprocess.CompletedProcess[str]":
    """Run `yasdef run --repo <root> <extra_args>` and return the result."""
    return yasdef(
        "run", "--repo", str(worker_root), *extra_args,
        input=input, interactive=interactive,
    )


# The echo runner produces no phase artifacts, so a valid complete pipeline always stops
# at the implementation precondition. The cases below assert startup behavior — feature
# selection, bound-project sync, and logging — not end-to-end phase execution.
STOPS_AT_IMPLEMENTATION = "implementation phase precondition failed: step plan not found"


def _assert_started_pipeline(
    result: "subprocess.CompletedProcess[str]",
    *,
    feature_id: str,
    mode: str | None = None,
) -> str:
    """Assert the run selected the expected feature and entered phase execution."""
    combined = result.stdout + result.stderr
    expected = f"selected feature '{feature_id}'"
    if mode is not None:
        expected += f" (mode={mode}"
    assert expected in combined, combined
    assert STOPS_AT_IMPLEMENTATION in combined, combined
    return combined


def _assert_resumed_pipeline(
    result: "subprocess.CompletedProcess[str]",
    *,
    feature_id: str,
    step: str,
    phase: str,
    mode: str = "auto_single",
) -> str:
    """Assert `--resume` narrowed candidates to one feature and started at `phase`."""
    combined = _assert_started_pipeline(result, feature_id=feature_id, mode=mode)
    assert f"resuming step {step} from phase: {phase}" in combined, combined
    return combined


# ---------------------------------------------------------------------------
# Model pipeline configuration (crp-142)
# ---------------------------------------------------------------------------


def _write_models_config(worker_root: Path, content: str) -> None:
    models = worker_root / ".asdlc_worker" / "setup" / "models.md"
    models.write_text(content, encoding="utf-8")
    git("add", "-A", cwd=worker_root)
    git("commit", "-qm", "reconfigure models", cwd=worker_root)


def _assert_no_run_side_effects(worker_root: Path, project: Path, result: "subprocess.CompletedProcess[str]") -> None:
    combined = result.stdout + result.stderr
    assert "selected feature" not in combined, combined
    assert "switched to branch" not in combined, combined
    assert not (worker_root / ".asdlc_worker" / "feature_meta_sync.yaml").exists()
    assert not (worker_root / ".asdlc_worker" / "logs").exists()
    assert git("branch", "--format=%(refname:short)", cwd=worker_root).stdout.split() == ["master"]
    assert project.is_dir()


def test_run_rejects_partial_models_config_before_any_side_effect(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    _write_models_config(worker, "design | echo | test-model\nplanning | echo | test-model\n")

    result = _yasdef_run(worker)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "missing phase(s): implementation, user_review, ai_audit" in combined, combined
    _assert_no_run_side_effects(worker, project, result)


def test_run_rejects_missing_models_config_with_actionable_path(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    models = worker / ".asdlc_worker" / "setup" / "models.md"
    models.unlink()
    git("add", "-A", cwd=worker)
    git("commit", "-qm", "remove models config", cwd=worker)

    result = _yasdef_run(worker)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "missing model configuration" in combined, combined
    assert str(models) in combined, combined
    _assert_no_run_side_effects(worker, project, result)


def test_run_rejects_models_config_that_configures_post_review(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    models = worker / ".asdlc_worker" / "setup" / "models.md"
    _write_models_config(
        worker, models.read_text(encoding="utf-8") + "post-review | echo | test-model\n"
    )

    result = _yasdef_run(worker)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "unsupported phase name: post-review" in combined, combined
    _assert_no_run_side_effects(worker, project, result)


# ---------------------------------------------------------------------------
# Feature assignment / candidate discovery
# ---------------------------------------------------------------------------


def test_single_feature_auto_selected(canonical_scenario: ScenarioFactory) -> None:
    scenario = canonical_scenario("happy-path-clean-state")

    result = _yasdef_run(scenario.worker)
    combined = _assert_started_pipeline(
        result, feature_id=scenario.feature_id, mode="auto_single"
    )
    assert scenario.step in combined


def test_git_directory_skipped_during_feature_enumeration(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    # .git inside the project dir should not be scanned as a feature
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    create_design_artifact(worker, step="1.1", feature_id=FEATURE_ID)

    result = _yasdef_run(worker)
    # A single real feature is selected, so `.git` was not enumerated as a candidate.
    _assert_started_pipeline(result, feature_id=FEATURE_ID, mode="auto_single")


def test_completed_feature_skipped(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1", checked=True)
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)

    result = _yasdef_run(worker)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "no assigned steps" in combined or "no candidate" in combined


def test_fails_when_no_assigned_worker_steps_exist(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    other_uuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=other_uuid, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)

    result = _yasdef_run(worker)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "no assigned steps" in combined or "no candidate" in combined


def test_fails_when_project_definition_missing(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    (project / "init_progress_definition.yaml").unlink()
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)

    result = _yasdef_run(worker)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "init_progress_definition" in combined


def test_fails_when_project_id_mismatch(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id="other-project", worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)

    result = _yasdef_run(worker)
    assert result.returncode != 0


def test_resume_step_filters_candidate_features(canonical_scenario: ScenarioFactory) -> None:
    scenario = canonical_scenario("resume-mid-plan")

    # The fixture assigns two features (feature-a/1.1, feature-b/2.1); `--resume 2.1`
    # must narrow that to exactly one, hence mode=auto_single rather than a prompt.
    result = _yasdef_run(scenario.worker, "--resume", scenario.step)
    _assert_resumed_pipeline(
        result,
        feature_id=scenario.feature_id,
        step=scenario.step,
        phase="planning",
    )


# ---------------------------------------------------------------------------
# Exhausted cached-feature behavior (FR-E.1)
# ---------------------------------------------------------------------------


def test_fast_path_exhausted_feature_noninteractive_exits_nonzero(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1", checked=True)
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature_meta_sync(
        worker,
        project_id=PROJECT_ID,
        worker_uuid=WORKER_UUID,
        feature_id=FEATURE_ID,
        selected_step="1.1",
    )

    # Non-interactive (no YASDEF_INTERACTIVE): must fail with removal instructions
    result = _yasdef_run(worker)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert FEATURE_ID in combined
    assert "exhausted" in combined
    assert "feature_meta_sync.yaml" in combined
    assert "candidate features" not in combined


def test_fast_path_exhausted_feature_interactive_choice_delete(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1", checked=True)
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    sync_file = worker / ".asdlc_worker" / "feature_meta_sync.yaml"
    write_feature_meta_sync(
        worker,
        project_id=PROJECT_ID,
        worker_uuid=WORKER_UUID,
        feature_id=FEATURE_ID,
        selected_step="1.1",
    )

    # Choice 1 = Delete the sync file (interactive=True forces Prompter into interactive mode)
    result = _yasdef_run(worker, input="1\n", interactive=True)
    assert result.returncode == 0, result.stderr
    combined = result.stdout + result.stderr
    assert "deleted" in combined
    assert not sync_file.exists()


def test_fast_path_exhausted_feature_interactive_choice_keep(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1", checked=True)
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    sync_file = worker / ".asdlc_worker" / "feature_meta_sync.yaml"
    write_feature_meta_sync(
        worker,
        project_id=PROJECT_ID,
        worker_uuid=WORKER_UUID,
        feature_id=FEATURE_ID,
        selected_step="1.1",
    )

    # Choice 2 = Keep the sync file (interactive=True forces Prompter into interactive mode)
    result = _yasdef_run(worker, input="2\n", interactive=True)
    assert result.returncode == 0, result.stderr
    assert sync_file.exists(), "sync file must be preserved when user chooses to keep"
    content = sync_file.read_text()
    assert FEATURE_ID in content


# ---------------------------------------------------------------------------
# Fast-path reuse (valid cached feature)
# ---------------------------------------------------------------------------


def test_fast_path_reuses_valid_cached_feature_noninteractive(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature_meta_sync(
        worker,
        project_id=PROJECT_ID,
        worker_uuid=WORKER_UUID,
        feature_id=FEATURE_ID,
        selected_step="1.1",
    )
    create_design_artifact(worker, step="1.1", feature_id=FEATURE_ID)

    result = _yasdef_run(worker)
    _assert_started_pipeline(result, feature_id=FEATURE_ID, mode="resume_reuse")


def test_fast_path_ignored_when_project_id_mismatched(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    # Stale meta_sync with wrong project_id — should fall through to slow-path
    write_feature_meta_sync(
        worker,
        project_id="stale-project",
        worker_uuid=WORKER_UUID,
        feature_id=FEATURE_ID,
        selected_step="1.1",
    )
    create_design_artifact(worker, step="1.1", feature_id=FEATURE_ID)

    result = _yasdef_run(worker)
    # Stale cache is ignored, so selection falls through to normal discovery.
    _assert_started_pipeline(result, feature_id=FEATURE_ID, mode="auto_single")


def test_fast_path_blocked_feature_exits_with_blocker_message(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)

    # feature with step 2.1 that depends on 1.1 (assigned to another worker; incomplete)
    feature_dir = project / "feature-blocked"
    feature_dir.mkdir()
    plan_text = (
        "### Step 1.1 Upstream step\n"
        "#### Assigned: other-uuid\n"
        "- [ ] other team work\n"
        "\n"
        "### Step 2.1 Blocked step\n"
        "#### Depends on: 1.1\n"
        f"#### Assigned: {WORKER_UUID}\n"
        "- [ ] blocked work\n"
    )
    feature_dir.joinpath("implementation_plan.md").write_text(plan_text)
    feature_dir.joinpath("requirements_ears.md").write_text("# Requirements\n")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature_meta_sync(
        worker,
        project_id=PROJECT_ID,
        worker_uuid=WORKER_UUID,
        feature_id="feature-blocked",
        selected_step="2.1",
    )

    result = _yasdef_run(worker)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "block" in combined.lower() or "1.1" in combined


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------


def test_run_two_fresh_repos_select_same_feature(tmp_path: Path) -> None:
    """Same repo layout → same feature selection output (determinism check)."""
    def _make_fresh(base: Path) -> Path:
        w = seed_repo(base / "worker")
        p = write_project_repo(base / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
        write_feature(p, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
        write_binding(w, project_path=p, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
        create_design_artifact(w, step="1.1", feature_id=FEATURE_ID)
        return w

    w1 = _make_fresh(tmp_path / "run1")
    w2 = _make_fresh(tmp_path / "run2")
    r1 = _yasdef_run(w1, "--resume", "1.1")
    r2 = _yasdef_run(w2, "--resume", "1.1")
    # Each run must independently reach the same correct state, so two identically
    # broken runs cannot satisfy the determinism check.
    for result in (r1, r2):
        _assert_resumed_pipeline(result, feature_id=FEATURE_ID, step="1.1", phase="planning")
    assert r1.returncode == r2.returncode


def test_resume_missing_step_exits_nonzero(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)

    result = _yasdef_run(worker, "--resume", "9.9")
    assert result.returncode != 0


# ---------------------------------------------------------------------------
# Debug log mode (ports orchestrator_debug_tests.sh)
# ---------------------------------------------------------------------------


def test_run_without_debug_creates_latest_log(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    create_design_artifact(worker, step="1.1", feature_id=FEATURE_ID)

    result = _yasdef_run(worker)
    _assert_started_pipeline(result, feature_id=FEATURE_ID, mode="auto_single")

    logs_dir = worker / ".asdlc_worker" / "logs"
    assert (logs_dir / "worker-design-latest-log").is_file()
    assert not (logs_dir / "worker-design-1.1-log").is_file()


def test_run_with_debug_creates_step_specific_log(tmp_path: Path) -> None:
    worker = seed_repo(tmp_path / "worker")
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    create_design_artifact(worker, step="1.1", feature_id=FEATURE_ID)

    result = _yasdef_run(worker, "--debug")
    _assert_started_pipeline(result, feature_id=FEATURE_ID, mode="auto_single")

    logs_dir = worker / ".asdlc_worker" / "logs"
    assert (logs_dir / "worker-design-1.1-log").is_file()
    assert not (logs_dir / "worker-design-latest-log").is_file()


# ---------------------------------------------------------------------------
# Bound project git sync (ports orchestrator_git_sync_*.sh)
# ---------------------------------------------------------------------------


def test_run_pulls_bound_project_repo_before_feature_selection(tmp_path: Path) -> None:
    """When the project is a git repo with a remote, yasdef run does git pull --rebase
    before feature selection and picks up commits added to the remote."""
    project, bare = write_project_git_repo(
        tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID
    )
    # Add a new feature commit directly to the bare remote (simulating a collaborator push)
    clone = tmp_path / "collaborator"
    subprocess.run(["git", "clone", "-q", str(bare), str(clone)], check=True,
                   env={**os.environ, **GIT_ENV})
    git("config", "user.name", "Test User", cwd=clone)
    git("config", "user.email", "test@example.com", cwd=clone)
    write_feature(clone, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    git("add", "-A", cwd=clone)
    git("commit", "-qm", "add feature via collaborator", cwd=clone)
    git("push", cwd=clone)

    worker = seed_repo(tmp_path / "worker")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)
    create_design_artifact(worker, step="1.1", feature_id=FEATURE_ID)

    # yasdef run should pull the new feature commit, then select the feature
    result = _yasdef_run(worker)
    _assert_started_pipeline(result, feature_id=FEATURE_ID, mode="auto_single")

    # The feature files are now present in the local project repo (pulled)
    assert (project / FEATURE_ID / "implementation_plan.md").is_file()


def test_run_fails_when_bound_project_pull_rebase_fails(tmp_path: Path) -> None:
    """When the project is a git repo but pull --rebase fails (no upstream configured),
    yasdef run exits nonzero with a sync-failure message."""
    project, _ = write_project_git_repo(
        tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID
    )
    write_feature(project, feature_id=FEATURE_ID, worker_uuid=WORKER_UUID, step="1.1")
    git("add", "-A", cwd=project)
    git("commit", "-qm", "add feature", cwd=project)
    # Remove the remote so pull --rebase has no upstream
    subprocess.run(["git", "-C", str(project), "remote", "remove", "origin"], check=True,
                   env={**os.environ, **GIT_ENV})

    worker = seed_repo(tmp_path / "worker")
    write_binding(worker, project_path=project, project_id=PROJECT_ID, worker_uuid=WORKER_UUID)

    result = _yasdef_run(worker)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "sync" in combined.lower() or "rebase" in combined.lower() or "pull" in combined.lower()
