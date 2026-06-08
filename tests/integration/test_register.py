"""Integration tests for `yasdef register` — ports register_worker_tests.sh."""
from __future__ import annotations

from pathlib import Path

import yaml

from .conftest import git, seed_repo, write_project_repo, yasdef

WORKER_UUID = "11111111-1111-1111-1111-111111111111"
PROJECT_ID = "project-alpha"


def _init_worker_runtime(repo: Path) -> None:
    asdlc = repo / ".asdlc_worker"
    asdlc.mkdir(parents=True, exist_ok=True)
    asdlc.joinpath("asdlc_worker.yaml").write_text(
        f"worker_repo_root: '{repo.resolve()}'\n",
        encoding="utf-8",
    )
    git("add", ".asdlc_worker/asdlc_worker.yaml", cwd=repo)
    git("commit", "-qm", "init worker runtime", cwd=repo)


def _run_register(
    worker_root: Path,
    project_path: Path,
    worker_uuid: str = WORKER_UUID,
) -> "subprocess.CompletedProcess[str]":
    import subprocess

    return yasdef(
        "register",
        cwd=worker_root,
        input=f"{project_path}\n{worker_uuid}\nn\n",
        interactive=True,
    )


def test_register_success_writes_binding(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "repo")
    _init_worker_runtime(repo)
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)

    result = _run_register(repo, project)
    assert result.returncode == 0, result.stderr

    binding_path = repo / ".asdlc_worker" / "project_overmind.yaml"
    assert binding_path.is_file()

    data = yaml.safe_load(binding_path.read_text())
    assert data["project_id"] == PROJECT_ID
    assert data["worker_uuid"] == WORKER_UUID
    assert data["class"] == "platform"
    assert data["status"] == "ready"
    assert Path(data["overmind_source_path"]).resolve() == project.resolve()

    current = git("branch", "--show-current", cwd=repo).stdout.strip()
    assert current == "register_yasdef_worker_in_coordinator"
    tracked = git("ls-tree", "-r", "--name-only", "HEAD", cwd=repo).stdout
    assert ".asdlc_worker/project_overmind.yaml" in tracked


def test_register_fails_outside_initialized_worker_repo_before_prompting(tmp_path: Path) -> None:
    result = yasdef(
        "register",
        cwd=tmp_path,
        input="/no/such/project\nworker\n",
        interactive=True,
    )
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "worker runtime is not initialized" in combined
    assert "yasdef init <path-to-your-worker-repo>" in combined
    assert "Enter ASDLC project repo path" not in combined


def test_register_fails_when_project_path_input_empty(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "repo")
    _init_worker_runtime(repo)

    result = yasdef("register", cwd=repo, input="\n", interactive=True)
    assert result.returncode != 0
    assert "Input cannot be empty" in result.stdout + result.stderr


def test_register_fails_when_project_path_missing(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "repo")
    _init_worker_runtime(repo)

    result = _run_register(repo, tmp_path / "nonexistent")
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "ASDLC project repo path not found" in combined


def test_register_fails_when_workers_yaml_missing(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "repo")
    _init_worker_runtime(repo)
    project = tmp_path / "project"
    project.mkdir()
    project.joinpath("init_progress_definition.yaml").write_text(
        f"meta_info:\n  project_id: '{PROJECT_ID}'\n",
        encoding="utf-8",
    )

    result = _run_register(repo, project)
    assert result.returncode != 0
    assert "workers.yaml" in result.stdout + result.stderr


def test_register_fails_when_definition_missing(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "repo")
    _init_worker_runtime(repo)
    project = tmp_path / "project"
    project.mkdir()
    project.joinpath("workers.yaml").write_text(
        f"workers:\n  - uuid: '{WORKER_UUID}'\n    class: 'platform'\n    status: 'ready'\n",
        encoding="utf-8",
    )

    result = _run_register(repo, project)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "init_progress_definition" in combined


def test_register_fails_when_meta_project_id_missing(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "repo")
    _init_worker_runtime(repo)
    project = tmp_path / "project"
    project.mkdir()
    project.joinpath("workers.yaml").write_text(
        f"workers:\n  - uuid: '{WORKER_UUID}'\n    class: 'platform'\n    status: 'ready'\n",
        encoding="utf-8",
    )
    project.joinpath("init_progress_definition.yaml").write_text(
        f"project_id: '{PROJECT_ID}'\n",
        encoding="utf-8",
    )

    result = _run_register(repo, project)
    assert result.returncode != 0
    assert "meta_info.project_id is missing or empty" in result.stdout + result.stderr


def test_register_fails_when_worker_uuid_input_empty(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "repo")
    _init_worker_runtime(repo)
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)

    result = yasdef("register", cwd=repo, input=f"{project}\n\n", interactive=True)
    assert result.returncode != 0
    assert "Input cannot be empty" in result.stdout + result.stderr


def test_register_fails_when_uuid_not_in_workers_yaml(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "repo")
    _init_worker_runtime(repo)
    other_uuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=other_uuid)
    result = _run_register(repo, project, worker_uuid=WORKER_UUID)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "no registered worker" in combined.lower() or WORKER_UUID in combined


def test_register_accepts_noncanonical_worker_uuid(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "repo")
    _init_worker_runtime(repo)
    worker_uuid = "worker-alpha"
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=worker_uuid)

    result = _run_register(repo, project, worker_uuid=worker_uuid)
    assert result.returncode == 0, result.stderr

    data = yaml.safe_load((repo / ".asdlc_worker" / "project_overmind.yaml").read_text())
    assert data["worker_uuid"] == worker_uuid


def test_register_rewrites_binding_deterministically(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "repo")
    _init_worker_runtime(repo)
    project = write_project_repo(tmp_path / "project", project_id=PROJECT_ID, worker_uuid=WORKER_UUID)

    first_result = _run_register(repo, project)
    assert first_result.returncode == 0, first_result.stderr
    first = (repo / ".asdlc_worker" / "project_overmind.yaml").read_text()
    git("checkout", "master", cwd=repo)

    second_result = _run_register(repo, project)
    assert second_result.returncode == 0, second_result.stderr
    second = (repo / ".asdlc_worker" / "project_overmind.yaml").read_text()
    assert first == second


def test_register_fails_on_dirty_working_tree(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "repo")
    _init_worker_runtime(repo)
    (repo / "README.md").write_text("dirty\n")

    result = yasdef("register", cwd=repo, input="", interactive=True)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "clean working tree" in combined
    assert "Enter ASDLC project repo path" not in combined
    assert git("branch", "--show-current", cwd=repo).stdout.strip() == "master"
