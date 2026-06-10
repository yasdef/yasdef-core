"""Shared fixtures for integration tests that invoke the installed yasdef CLI."""
from __future__ import annotations

import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

import pytest

GIT_ENV = {
    "GIT_AUTHOR_NAME": "Test User",
    "GIT_AUTHOR_EMAIL": "test@example.com",
    "GIT_COMMITTER_NAME": "Test User",
    "GIT_COMMITTER_EMAIL": "test@example.com",
}

CANONICAL_WORKER_UUID = "11111111-1111-1111-1111-111111111111"
CANONICAL_PROJECT_ID = "project-run"
CANONICAL_FEATURE_ID = "feature-alpha"


@dataclass(frozen=True, slots=True)
class CanonicalScenario:
    name: str
    worker: Path
    project: Path
    project_id: str
    worker_uuid: str
    feature_id: str
    step: str


ScenarioFactory = Callable[[str], CanonicalScenario]


def git(*args: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        text=True,
        capture_output=True,
        env={**__import__("os").environ, **GIT_ENV},
        check=True,
    )


def seed_repo(path: Path, *, branch: str = "master") -> Path:
    """Create a minimal git repo with one seed commit."""
    path.mkdir(parents=True, exist_ok=True)
    git("init", "-q", "-b", branch, cwd=path)
    git("config", "user.name", "Test User", cwd=path)
    git("config", "user.email", "test@example.com", cwd=path)
    (path / "README.md").write_text("seed\n")
    git("add", "README.md", cwd=path)
    git("commit", "-qm", "seed", cwd=path)
    return path


def write_project_repo(
    path: Path,
    *,
    project_id: str,
    worker_uuid: str,
    worker_class: str = "platform",
    worker_status: str = "ready",
) -> Path:
    """Write an overmind project repo with workers.yaml and init_progress_definition.yaml."""
    path.mkdir(parents=True, exist_ok=True)
    path.joinpath("workers.yaml").write_text(
        f"""version: 1
workers:
  - uuid: '{worker_uuid}'
    class: '{worker_class}'
    status: '{worker_status}'
""",
        encoding="utf-8",
    )
    path.joinpath("init_progress_definition.yaml").write_text(
        f"meta_info:\n  project_id: '{project_id}'\nsteps: []\n",
        encoding="utf-8",
    )
    return path


def write_feature(
    project_path: Path,
    *,
    feature_id: str,
    worker_uuid: str,
    step: str = "1.1",
    checked: bool = False,
    step_title: str = "Do the thing",
) -> Path:
    """Write a feature directory with implementation_plan.md and requirements_ears.md."""
    feature_dir = project_path / feature_id
    feature_dir.mkdir(parents=True, exist_ok=True)
    checkbox = "[x]" if checked else "[ ]"
    plan = (
        f"### Step {step} {step_title}\n"
        f"#### Assigned: {worker_uuid}\n"
        f"- {checkbox} task one\n"
    )
    feature_dir.joinpath("implementation_plan.md").write_text(plan, encoding="utf-8")
    feature_dir.joinpath("requirements_ears.md").write_text(
        f"# Requirements\nWhen {feature_id} then do work.\n",
        encoding="utf-8",
    )
    return feature_dir


_MODELS_MD_ECHO = (
    "design | echo | test-model\n"
    "planning | echo | test-model\n"
    "implementation | echo | test-model\n"
    "user_review | echo | test-model\n"
    "ai_audit | echo | test-model\n"
)


def write_binding(
    worker_root: Path,
    *,
    project_path: Path,
    project_id: str,
    worker_uuid: str,
) -> None:
    """Write a minimal worker runtime directory suitable for `yasdef run --dry-run`.

    Files are committed so that the working tree is clean when yasdef run starts.
    """
    binding_dir = worker_root / ".asdlc_worker"
    binding_dir.mkdir(parents=True, exist_ok=True)
    binding_dir.joinpath("project_overmind.yaml").write_text(
        f"overmind_source_path: '{project_path.resolve()}'\n"
        f"project_id: '{project_id}'\n"
        f"worker_uuid: '{worker_uuid}'\n"
        f"class: 'platform'\n"
        f"status: 'ready'\n",
        encoding="utf-8",
    )
    binding_dir.joinpath("asdlc_worker.yaml").write_text(
        f"worker_repo_root: '{worker_root.resolve()}'\n",
        encoding="utf-8",
    )
    setup_dir = binding_dir / "setup"
    setup_dir.mkdir(exist_ok=True)
    setup_dir.joinpath("models.md").write_text(_MODELS_MD_ECHO, encoding="utf-8")
    git("add", "-A", cwd=worker_root)
    git("commit", "-qm", "add worker binding", cwd=worker_root)


def create_design_artifact(worker_root: Path, *, step: str, feature_id: str) -> Path:
    """Create and commit a minimal design artifact so later phases can run."""
    designs_dir = worker_root / ".asdlc_worker" / "step_designs"
    designs_dir.mkdir(parents=True, exist_ok=True)
    artifact = designs_dir / f"step-{step}-{feature_id}-design.md"
    artifact.write_text(
        f"# Design: Step {step} {feature_id}\n\nDesign content.\n",
        encoding="utf-8",
    )
    git("add", "-A", cwd=worker_root)
    git("commit", "-qm", f"add design artifact {step}", cwd=worker_root)
    return artifact


def write_feature_meta_sync(
    worker_root: Path,
    *,
    project_id: str,
    worker_uuid: str,
    feature_id: str,
    selected_step: str,
) -> None:
    """Write feature_meta_sync.yaml and commit it so the working tree stays clean."""
    sync_file = worker_root / ".asdlc_worker" / "feature_meta_sync.yaml"
    sync_file.parent.mkdir(parents=True, exist_ok=True)
    sync_file.write_text(
        f"project_id: '{project_id}'\n"
        f"worker_uuid: '{worker_uuid}'\n"
        f"feature_id: '{feature_id}'\n"
        f"selected_step: '{selected_step}'\n",
        encoding="utf-8",
    )
    git("add", "-A", cwd=worker_root)
    git("commit", "-qm", "add feature meta sync", cwd=worker_root)


def write_project_git_repo(
    path: Path,
    *,
    project_id: str,
    worker_uuid: str,
    worker_class: str = "platform",
    worker_status: str = "ready",
) -> tuple[Path, Path]:
    """Create a project directory that is also a git repo with a bare remote.

    The repo is initialised, files committed, and pushed so that
    ``git pull --rebase`` on it succeeds (nothing to pull, exits 0).
    Returns (local_path, bare_remote_path).
    """
    import os

    bare = path.parent / (path.name + ".git")
    bare.mkdir(parents=True)
    subprocess.run(
        ["git", "init", "--bare", "-q", "-b", "master", str(bare)],
        check=True,
        env={**os.environ, **GIT_ENV},
    )

    path.mkdir(parents=True, exist_ok=True)
    git("init", "-q", "-b", "master", cwd=path)
    git("config", "user.name", "Test User", cwd=path)
    git("config", "user.email", "test@example.com", cwd=path)
    write_project_repo(path, project_id=project_id, worker_uuid=worker_uuid,
                       worker_class=worker_class, worker_status=worker_status)
    subprocess.run(
        ["git", "-C", str(path), "remote", "add", "origin", str(bare)],
        check=True,
        env={**os.environ, **GIT_ENV},
    )
    git("add", "-A", cwd=path)
    git("commit", "-qm", "initial project setup", cwd=path)
    git("push", "-u", "origin", "master", cwd=path)
    return path, bare


def yasdef(
    *args: str,
    cwd: Path | None = None,
    input: str | None = None,
    interactive: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Run the yasdef CLI and return the completed process (non-raising).

    Pass interactive=True to set YASDEF_INTERACTIVE=1 so the Prompter treats
    stdin-as-pipe as an interactive session (needed for integration tests that
    test prompt-driven paths without a real PTY).
    """
    import os

    env = dict(os.environ)
    if interactive:
        env["YASDEF_INTERACTIVE"] = "1"
    return subprocess.run(
        ["yasdef", *args],
        cwd=cwd,
        text=True,
        capture_output=True,
        input=input,
        env=env,
        check=False,
    )


@pytest.fixture()
def tmp_worker_repo(tmp_path: Path) -> Path:
    """A seeded git repo suitable as a worker repo root."""
    return seed_repo(tmp_path / "worker")


@pytest.fixture()
def tmp_project(tmp_path: Path) -> Path:
    """An empty overmind project directory (not a git repo)."""
    p = tmp_path / "project"
    p.mkdir()
    return p


@pytest.fixture()
def canonical_scenario(tmp_path: Path) -> ScenarioFactory:
    """Build a named canonical integration scenario from tests/fixtures/repos/."""

    def build(name: str) -> CanonicalScenario:
        if name == "happy-path-clean-state":
            return _build_happy_path_clean_state(tmp_path / name)
        if name == "resume-mid-plan":
            return _build_resume_mid_plan(tmp_path / name)
        raise ValueError(f"unknown canonical scenario: {name}")

    return build


def _build_happy_path_clean_state(base: Path) -> CanonicalScenario:
    worker = seed_repo(base / "worker")
    project = write_project_repo(
        base / "project",
        project_id=CANONICAL_PROJECT_ID,
        worker_uuid=CANONICAL_WORKER_UUID,
    )
    write_feature(
        project,
        feature_id=CANONICAL_FEATURE_ID,
        worker_uuid=CANONICAL_WORKER_UUID,
        step="1.1",
    )
    write_binding(
        worker,
        project_path=project,
        project_id=CANONICAL_PROJECT_ID,
        worker_uuid=CANONICAL_WORKER_UUID,
    )
    create_design_artifact(worker, step="1.1", feature_id=CANONICAL_FEATURE_ID)
    return CanonicalScenario(
        name="happy-path-clean-state",
        worker=worker,
        project=project,
        project_id=CANONICAL_PROJECT_ID,
        worker_uuid=CANONICAL_WORKER_UUID,
        feature_id=CANONICAL_FEATURE_ID,
        step="1.1",
    )


def _build_resume_mid_plan(base: Path) -> CanonicalScenario:
    worker = seed_repo(base / "worker")
    project = write_project_repo(
        base / "project",
        project_id=CANONICAL_PROJECT_ID,
        worker_uuid=CANONICAL_WORKER_UUID,
    )
    write_feature(
        project,
        feature_id="feature-a",
        worker_uuid=CANONICAL_WORKER_UUID,
        step="1.1",
    )
    write_feature(
        project,
        feature_id="feature-b",
        worker_uuid=CANONICAL_WORKER_UUID,
        step="2.1",
    )
    write_binding(
        worker,
        project_path=project,
        project_id=CANONICAL_PROJECT_ID,
        worker_uuid=CANONICAL_WORKER_UUID,
    )
    create_design_artifact(worker, step="2.1", feature_id="feature-b")
    return CanonicalScenario(
        name="resume-mid-plan",
        worker=worker,
        project=project,
        project_id=CANONICAL_PROJECT_ID,
        worker_uuid=CANONICAL_WORKER_UUID,
        feature_id="feature-b",
        step="2.1",
    )
