from __future__ import annotations

import subprocess
from pathlib import Path

from yasdef_orchestrator.app.orchestrator import Orchestrator, RunOptions
from yasdef_orchestrator.infra.git_repo import GitRepo
from yasdef_orchestrator.infra.layout import RuntimeLayout
from yasdef_orchestrator.infra.process import ProcessRunner
from yasdef_orchestrator.infra.prompts import Prompter
from yasdef_orchestrator.infra.user_output import RecordingUserOutput

WORKER_UUID = "worker-alpha-01"


def test_orchestrator_builds_feature_context_and_runs_pipeline(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path / "worker")
    layout = RuntimeLayout.from_root(repo.root)
    source = tmp_path / "source"
    _seed_source(source)
    _seed_worker(layout, source)
    repo.commit("seed worker", paths=[".asdlc_worker", ".codex"])

    result = Orchestrator(
        layout=layout,
        git=repo,
        prompts=Prompter(interactive=False),
        process=ProcessRunner(),
        output=RecordingUserOutput(),
    ).run(RunOptions(phases=("design",)))

    assert result.succeeded is True
    assert repo.current_branch() == "step-1.1-feature-a-plan"
    assert layout.feature_sync_file.is_file()


def _seed_source(source: Path) -> None:
    feature = source / "feature-a"
    feature.mkdir(parents=True)
    (source / "init_progress_definition.yaml").write_text(
        "meta_info:\n  project_id: project-a\n",
        encoding="utf-8",
    )
    (feature / "implementation_plan.md").write_text(
        "\n".join(
            [
                "### Step 1.1 Demo",
                "#### Depends on: none",
                f"#### Assigned: {WORKER_UUID}",
                "- [ ] Do the work",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    (feature / "requirements_ears.md").write_text("REQ-1\n", encoding="utf-8")


def _seed_worker(layout: RuntimeLayout, source: Path) -> None:
    layout.binding_file.parent.mkdir(parents=True, exist_ok=True)
    layout.binding_file.write_text(
        "\n".join(
            [
                f"overmind_source_path: {source}",
                "project_id: project-a",
                f"worker_uuid: {WORKER_UUID}",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    layout.models_file.parent.mkdir(parents=True, exist_ok=True)
    layout.models_file.write_text("design | echo | mock-model\n", encoding="utf-8")
    layout.step_designs_dir.mkdir(parents=True, exist_ok=True)
    (layout.step_designs_dir / "step-1.1-feature-a-design.md").write_text(
        "# Feature Design: 1.1 - Demo\n",
        encoding="utf-8",
    )
    _write_script(
        layout.worker_repo_root
        / ".codex"
        / "skills"
        / "yasdef-worker-design"
        / "scripts"
        / "check_design_readiness.py"
    )


def _write_script(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("from __future__ import annotations\n\nraise SystemExit(0)\n", encoding="utf-8")


def _init_repo(path: Path) -> GitRepo:
    path.mkdir(parents=True)
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
