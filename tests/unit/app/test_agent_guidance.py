from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

from yasdef_worker.app import agent_guidance
from yasdef_worker.app.agent_guidance import (
    BACKUP_EXCLUDE_ENTRY,
    GuidanceOutcome,
    materialize_agent_guidance,
)
from yasdef_worker.app.phases import DesignPhase, ImplementationPhase, ModelConfigRunnerFactory, PhaseContext
from yasdef_worker.app.pipeline import Pipeline
from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.log_capture import LogCapture
from yasdef_worker.infra.process import ProcessRunner
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.templates import TemplateLoader
from yasdef_worker.infra.user_output import RecordingUserOutput

KNOWLEDGEBASE = "# Project guidance\n\nUse the packaged stack.\n"
SOURCE_NAME = "project_agents_md_claude_md_backend.md"


@dataclass(frozen=True, slots=True)
class Feature:
    step: str
    feature_id: str
    source_plan_path: Path
    source_ears_path: Path
    worker_uuid: str = "worker-uuid"


def design_text(
    *,
    agents_state: str,
    claude_state: str,
    disposition: str,
    source: str | None = SOURCE_NAME,
) -> str:
    lines = [
        "# Feature Design: 1.1 - Bootstrap",
        "## Goal",
        "- Scaffold.",
        "## In Scope",
        "- Scaffold.",
        "## Out of Scope",
        "- Later work.",
        "## First-Feature Bootstrap (only if needed)",
        "- Bootstrap required: yes",
        "- Planning handoff: Create the runnable scaffold.",
        f"- Project AGENTS.md state: {agents_state}",
        f"- Project CLAUDE.md state: {claude_state}",
        f"- Agent-guidance disposition: {disposition}",
    ]
    if source is not None:
        lines.append(f"- Agent-guidance source: {source}")
    return "\n".join(lines) + "\n"


def materialize(worker: Path, project: Path, design: Path) -> GuidanceOutcome:
    return materialize_agent_guidance(
        design_file=design,
        worker_root=worker,
        project_root=project,
        worker_class="back",
        output=RecordingUserOutput(),
    )


@pytest.fixture
def scenario(tmp_path: Path) -> tuple[Path, Path, Path]:
    """Worker repo root, bound project folder, and the design artifact path."""
    worker = tmp_path / "worker"
    project = tmp_path / "project"
    (worker / ".asdlc_worker" / "step_designs").mkdir(parents=True)
    (worker / ".git" / "info").mkdir(parents=True)
    project.mkdir()
    (project / SOURCE_NAME).write_text(KNOWLEDGEBASE, encoding="utf-8")
    (project / "project_agents_md_claude_md_frontend.md").write_text("other\n", encoding="utf-8")
    design = worker / ".asdlc_worker" / "step_designs" / "step-1.1-feature-demo-design.md"
    return worker, project, design


def backups(worker: Path) -> list[Path]:
    root = worker / ".asdlc_worker" / "agent_guidance_backups"
    return sorted(root.iterdir()) if root.is_dir() else []


def exclude_lines(worker: Path) -> list[str]:
    exclude = worker / ".git" / "info" / "exclude"
    return exclude.read_text(encoding="utf-8").splitlines() if exclude.is_file() else []


def test_approval_backs_up_existing_file_and_overwrites_both_outputs(
    scenario: tuple[Path, Path, Path],
) -> None:
    worker, project, design = scenario
    (worker / "AGENTS.md").write_text("local notes\n", encoding="utf-8")
    design.write_text(
        design_text(agents_state="present", claude_state="absent", disposition="regenerate-both-approved"),
        encoding="utf-8",
    )

    outcome = materialize(worker, project, design)

    assert (worker / "AGENTS.md").read_text(encoding="utf-8") == KNOWLEDGEBASE
    assert (worker / "CLAUDE.md").read_text(encoding="utf-8") == KNOWLEDGEBASE
    assert outcome.backup_dir is not None
    assert (outcome.backup_dir / "AGENTS.md").read_text(encoding="utf-8") == "local notes\n"
    assert not (outcome.backup_dir / "CLAUDE.md").exists()
    assert BACKUP_EXCLUDE_ENTRY in exclude_lines(worker)


def test_approval_replaces_symlink_without_following_it(scenario: tuple[Path, Path, Path]) -> None:
    worker, project, design = scenario
    external = worker.parent / "global_guidance.md"
    external.write_text("global\n", encoding="utf-8")
    (worker / "CLAUDE.md").symlink_to(external)
    design.write_text(
        design_text(agents_state="absent", claude_state="present", disposition="regenerate-both-approved"),
        encoding="utf-8",
    )

    outcome = materialize(worker, project, design)

    assert not (worker / "CLAUDE.md").is_symlink()
    assert (worker / "CLAUDE.md").read_text(encoding="utf-8") == KNOWLEDGEBASE
    assert (worker / "AGENTS.md").read_bytes() == (worker / "CLAUDE.md").read_bytes()
    assert external.read_text(encoding="utf-8") == "global\n"
    assert outcome.backup_dir is not None
    backup = outcome.backup_dir / "CLAUDE.md"
    assert backup.is_symlink() and os.readlink(backup) == str(external)


def test_directory_at_destination_fails_without_touching_either_path(
    scenario: tuple[Path, Path, Path],
) -> None:
    worker, project, design = scenario
    (worker / "AGENTS.md").mkdir()
    (worker / "CLAUDE.md").write_text("keep me\n", encoding="utf-8")
    design.write_text(
        design_text(agents_state="absent", claude_state="present", disposition="regenerate-both-approved"),
        encoding="utf-8",
    )

    with pytest.raises(YasdefError, match="is a directory"):
        materialize(worker, project, design)

    assert (worker / "AGENTS.md").is_dir()
    assert (worker / "CLAUDE.md").read_text(encoding="utf-8") == "keep me\n"
    assert backups(worker) == []


def test_recorded_invalid_directory_state_is_rejected(scenario: tuple[Path, Path, Path]) -> None:
    worker, project, design = scenario
    design.write_text(
        design_text(
            agents_state="invalid-directory",
            claude_state="absent",
            disposition="regenerate-both-approved",
        ),
        encoding="utf-8",
    )

    with pytest.raises(YasdefError, match="unusable agent-guidance decision"):
        materialize(worker, project, design)


def test_backup_failure_aborts_before_replacing_root_paths(
    scenario: tuple[Path, Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    worker, project, design = scenario
    (worker / "AGENTS.md").write_text("local notes\n", encoding="utf-8")
    design.write_text(
        design_text(agents_state="present", claude_state="absent", disposition="regenerate-both-approved"),
        encoding="utf-8",
    )

    def fail_mkdir(*args: object, **kwargs: object) -> None:
        raise OSError("backup device is full")

    monkeypatch.setattr(Path, "mkdir", fail_mkdir)

    with pytest.raises(YasdefError, match="failed to create guidance backup directory"):
        materialize(worker, project, design)

    monkeypatch.undo()
    assert (worker / "AGENTS.md").read_text(encoding="utf-8") == "local notes\n"
    assert not (worker / "CLAUDE.md").exists()
    assert BACKUP_EXCLUDE_ENTRY not in exclude_lines(worker)


def test_backup_never_overwrites_an_earlier_backup(scenario: tuple[Path, Path, Path]) -> None:
    worker, project, design = scenario
    (worker / "AGENTS.md").write_text("first\n", encoding="utf-8")
    design.write_text(
        design_text(agents_state="present", claude_state="absent", disposition="regenerate-both-approved"),
        encoding="utf-8",
    )

    first = materialize(worker, project, design)
    (worker / "AGENTS.md").write_text("second\n", encoding="utf-8")
    second = materialize(worker, project, design)

    assert first.backup_dir != second.backup_dir
    assert len(backups(worker)) == 2
    assert first.backup_dir is not None
    assert (first.backup_dir / "AGENTS.md").read_text(encoding="utf-8") == "first\n"


def test_both_absent_approval_writes_pair_without_backup_or_exclude(
    scenario: tuple[Path, Path, Path],
) -> None:
    worker, project, design = scenario
    design.write_text(
        design_text(agents_state="absent", claude_state="absent", disposition="regenerate-both-approved"),
        encoding="utf-8",
    )

    outcome = materialize(worker, project, design)

    assert (worker / "AGENTS.md").read_text(encoding="utf-8") == KNOWLEDGEBASE
    assert (worker / "CLAUDE.md").read_text(encoding="utf-8") == KNOWLEDGEBASE
    assert outcome.backup_dir is None
    assert backups(worker) == []
    assert BACKUP_EXCLUDE_ENTRY not in exclude_lines(worker)


def test_declined_disposition_changes_nothing(scenario: tuple[Path, Path, Path]) -> None:
    worker, project, design = scenario
    (worker / "AGENTS.md").write_text("local notes\n", encoding="utf-8")
    design.write_text(
        design_text(
            agents_state="present",
            claude_state="absent",
            disposition="leave-unchanged-declined",
            source=None,
        ),
        encoding="utf-8",
    )

    outcome = materialize(worker, project, design)

    assert not outcome.wrote_files
    assert (worker / "AGENTS.md").read_text(encoding="utf-8") == "local notes\n"
    assert not (worker / "CLAUDE.md").exists()
    assert backups(worker) == []
    assert BACKUP_EXCLUDE_ENTRY not in exclude_lines(worker)


def test_both_present_disposition_changes_nothing(scenario: tuple[Path, Path, Path]) -> None:
    worker, project, design = scenario
    (worker / "AGENTS.md").write_text("agents\n", encoding="utf-8")
    (worker / "CLAUDE.md").write_text("claude\n", encoding="utf-8")
    design.write_text(
        design_text(
            agents_state="present",
            claude_state="present",
            disposition="both-present-no-action",
            source=None,
        ),
        encoding="utf-8",
    )

    outcome = materialize(worker, project, design)

    assert not outcome.wrote_files
    assert (worker / "AGENTS.md").read_text(encoding="utf-8") == "agents\n"
    assert (worker / "CLAUDE.md").read_text(encoding="utf-8") == "claude\n"
    assert backups(worker) == []


def test_approved_regeneration_requires_one_unambiguous_source(
    scenario: tuple[Path, Path, Path],
) -> None:
    worker, project, design = scenario
    (project / "project_agents_md_claude_md_back_extra.md").write_text("second\n", encoding="utf-8")
    design.write_text(
        design_text(agents_state="absent", claude_state="absent", disposition="regenerate-both-approved"),
        encoding="utf-8",
    )

    with pytest.raises(YasdefError, match="exactly one class-matching"):
        materialize(worker, project, design)

    assert not (worker / "AGENTS.md").exists()
    assert not (worker / "CLAUDE.md").exists()


def test_failed_pair_write_does_not_report_success(
    scenario: tuple[Path, Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    worker, project, design = scenario
    (worker / "AGENTS.md").write_text("local notes\n", encoding="utf-8")
    design.write_text(
        design_text(agents_state="present", claude_state="absent", disposition="regenerate-both-approved"),
        encoding="utf-8",
    )

    real_replace = os.replace

    def fail_second_replace(src: object, dst: object) -> None:
        if str(dst).endswith("CLAUDE.md"):
            raise OSError("disk full")
        real_replace(src, dst)  # type: ignore[arg-type]

    monkeypatch.setattr(os, "replace", fail_second_replace)

    with pytest.raises(YasdefError, match="failed to install project guidance pair"):
        materialize(worker, project, design)

    monkeypatch.undo()
    assert (worker / "AGENTS.md").read_text(encoding="utf-8") == "local notes\n"
    assert not (worker / "CLAUDE.md").exists()
    # The retained backup must already be git-excluded even though the pair write failed.
    retained = backups(worker)
    assert len(retained) == 1
    assert (retained[0] / "AGENTS.md").read_text(encoding="utf-8") == "local notes\n"
    assert BACKUP_EXCLUDE_ENTRY in exclude_lines(worker)


def test_verification_mismatch_restores_pre_operation_state(
    scenario: tuple[Path, Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    """Both paths are replaced, then CLAUDE.md ends up with the wrong bytes, so the
    real verification fails. The transaction must restore pre-operation state."""
    worker, project, design = scenario
    (worker / "AGENTS.md").write_text("local notes\n", encoding="utf-8")
    design.write_text(
        design_text(agents_state="present", claude_state="absent", disposition="regenerate-both-approved"),
        encoding="utf-8",
    )

    real_write = agent_guidance.atomic_write_bytes

    def corrupt_root_claude(dest: Path, content: bytes) -> None:
        if dest.name == "CLAUDE.md" and "agent_guidance_backups" not in dest.parts:
            real_write(dest, content + b"CORRUPT")
        else:
            real_write(dest, content)

    monkeypatch.setattr(agent_guidance, "atomic_write_bytes", corrupt_root_claude)

    with pytest.raises(YasdefError, match="failed to install project guidance pair"):
        materialize(worker, project, design)

    monkeypatch.undo()
    assert (worker / "AGENTS.md").read_text(encoding="utf-8") == "local notes\n"
    assert not (worker / "CLAUDE.md").exists()
    assert BACKUP_EXCLUDE_ENTRY in exclude_lines(worker)


def test_verification_read_failure_restores_pre_operation_state(
    scenario: tuple[Path, Path, Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    """A read failure surfacing during verification must roll back like a mismatch."""
    worker, project, design = scenario
    (worker / "AGENTS.md").write_text("local notes\n", encoding="utf-8")
    design.write_text(
        design_text(agents_state="present", claude_state="absent", disposition="regenerate-both-approved"),
        encoding="utf-8",
    )

    def read_failure(destinations: tuple[Path, ...], payload: bytes) -> None:
        raise YasdefError("project guidance verification failed for CLAUDE.md") from OSError("read error")

    monkeypatch.setattr(agent_guidance, "_verify_pair", read_failure)

    with pytest.raises(YasdefError, match="failed to install project guidance pair"):
        materialize(worker, project, design)

    monkeypatch.undo()
    assert (worker / "AGENTS.md").read_text(encoding="utf-8") == "local notes\n"
    assert not (worker / "CLAUDE.md").exists()


def test_approved_guidance_exists_before_implementation_process_launches(tmp_path: Path) -> None:
    worker = tmp_path / "worker"
    project = tmp_path / "project"
    project.mkdir(parents=True)
    (project / SOURCE_NAME).write_text(KNOWLEDGEBASE, encoding="utf-8")
    repo = _init_repo(worker)
    layout = RuntimeLayout.from_root(worker)
    _seed_runtime(layout, project)

    launches: list[tuple[str, bool, bool]] = []

    class RecordingProcessRunner(ProcessRunner):
        def run_with_log(self, argv: list[str], log_path: Path, **kwargs: object) -> None:
            launches.append(
                (
                    log_path.name,
                    (worker / "AGENTS.md").is_file(),
                    (worker / "CLAUDE.md").is_file(),
                )
            )

    ctx = PhaseContext(
        layout=layout,
        git=repo,
        runner_factory=ModelConfigRunnerFactory(layout.models_file),
        prompts=Prompter(interactive=False),
        process=RecordingProcessRunner(),
        log_capture=LogCapture(layout, project="demo"),
        templates=TemplateLoader(layout),
        output=RecordingUserOutput(),
        feature=Feature(
            step="1.1",
            feature_id="feature-demo",
            source_plan_path=project / "feature-demo" / "implementation_plan.md",
            source_ears_path=project / "feature-demo" / "requirements_ears.md",
        ),
    )

    result = Pipeline(
        ctx=ctx,
        phase_types={"design": DesignPhase, "implementation": ImplementationPhase},
    ).iterate(("design", "implementation"))

    assert result.succeeded, result.stop_reason
    design_launch, implementation_launch = launches
    assert design_launch[1:] == (False, False)
    assert implementation_launch[1:] == (True, True)
    assert (worker / "AGENTS.md").read_text(encoding="utf-8") == KNOWLEDGEBASE
    assert (worker / "CLAUDE.md").read_text(encoding="utf-8") == KNOWLEDGEBASE


def test_resume_into_implementation_materializes_before_launch(tmp_path: Path) -> None:
    """A resume that skips design (its artifact already exists) must still install
    approved guidance: implementation preflight is the guard, not design postflight."""
    worker = tmp_path / "worker"
    project = tmp_path / "project"
    project.mkdir(parents=True)
    (project / SOURCE_NAME).write_text(KNOWLEDGEBASE, encoding="utf-8")
    repo = _init_repo(worker)
    layout = RuntimeLayout.from_root(worker)
    _seed_runtime(layout, project)

    launches: list[tuple[bool, bool]] = []

    class RecordingProcessRunner(ProcessRunner):
        def run_with_log(self, argv: list[str], log_path: Path, **kwargs: object) -> None:
            launches.append(((worker / "AGENTS.md").is_file(), (worker / "CLAUDE.md").is_file()))

    ctx = PhaseContext(
        layout=layout,
        git=repo,
        runner_factory=ModelConfigRunnerFactory(layout.models_file),
        prompts=Prompter(interactive=False),
        process=RecordingProcessRunner(),
        log_capture=LogCapture(layout, project="demo"),
        templates=TemplateLoader(layout),
        output=RecordingUserOutput(),
        feature=Feature(
            step="1.1",
            feature_id="feature-demo",
            source_plan_path=project / "feature-demo" / "implementation_plan.md",
            source_ears_path=project / "feature-demo" / "requirements_ears.md",
        ),
    )

    # Design was recorded and materialization never ran (files absent).
    assert not (worker / "AGENTS.md").exists()
    result = Pipeline(
        ctx=ctx,
        phase_types={"implementation": ImplementationPhase},
    ).iterate(("implementation",))

    assert result.succeeded, result.stop_reason
    assert launches == [(True, True)]
    assert (worker / "AGENTS.md").read_text(encoding="utf-8") == KNOWLEDGEBASE
    assert (worker / "CLAUDE.md").read_text(encoding="utf-8") == KNOWLEDGEBASE


def _seed_runtime(layout: RuntimeLayout, project: Path) -> None:
    layout.models_file.parent.mkdir(parents=True, exist_ok=True)
    layout.models_file.write_text(
        "design | echo | mock-model\nimplementation | echo | mock-model\n",
        encoding="utf-8",
    )
    layout.binding_file.write_text(
        f"overmind_source_path: '{project}'\nclass: 'backend'\n",
        encoding="utf-8",
    )
    layout.step_designs_dir.mkdir(parents=True, exist_ok=True)
    layout.step_plans_dir.mkdir(parents=True, exist_ok=True)
    (project / "feature-demo").mkdir(parents=True, exist_ok=True)
    (project / "feature-demo" / "implementation_plan.md").write_text("plan\n", encoding="utf-8")
    (project / "feature-demo" / "requirements_ears.md").write_text("ears\n", encoding="utf-8")
    (layout.step_designs_dir / "step-1.1-feature-demo-design.md").write_text(
        design_text(agents_state="absent", claude_state="absent", disposition="regenerate-both-approved"),
        encoding="utf-8",
    )
    (layout.step_plans_dir / "step-1.1-feature-demo.md").write_text(
        "# Step Plan: 1.1 - Demo\n",
        encoding="utf-8",
    )
    scripts = layout.claude_skills_dir / "yasdef-worker-implementation" / "scripts"
    scripts.mkdir(parents=True, exist_ok=True)
    for name in ("build_implementation_context.py", "check_implementation_readiness.py"):
        (scripts / name).write_text("raise SystemExit(0)\n", encoding="utf-8")


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
