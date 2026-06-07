from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from yasdef_orchestrator.app.init_asdlc_worker import (
    INIT_BRANCH,
    InstallEntry,
    Installer,
    OverwriteMode,
    default_exclude_entries,
    default_install_entries,
)
from yasdef_orchestrator.infra.errors import InstallSafetyError, YasdefError
from yasdef_orchestrator.infra.user_output import RecordingUserOutput
from yasdef_orchestrator.infra.yaml_io import read_yaml_file


def test_installer_writes_allowed_file_and_manifest(tmp_path: Path) -> None:
    _init_repo(tmp_path)
    output = RecordingUserOutput()

    installed = Installer(
        target_root=tmp_path,
        output=output,
        entries=(
            InstallEntry(
                Path(".asdlc_worker/setup/models.md"),
                b"design | echo | mock\n",
                OverwriteMode.SEED_ONLY,
            ),
        ),
    ).install()

    assert (tmp_path / ".asdlc_worker/setup/models.md").read_text(encoding="utf-8")
    assert installed[0].path == ".asdlc_worker/setup/models.md"
    manifest = read_yaml_file(tmp_path / ".asdlc_worker/install_manifest.yaml")
    assert manifest["files"][0]["mode"] == "seed-only"
    assert output.events[-1].level == "step"
    assert output.events[-1].message == "worker runtime install complete (1 files)"
    assert not [event for event in output.events if event.level == "warn" and "merge it back" in event.message]


def test_installer_rejects_destination_outside_allowlist(tmp_path: Path) -> None:
    _init_repo(tmp_path)

    with pytest.raises(InstallSafetyError, match="allowlist"):
        Installer(
            target_root=tmp_path,
            output=RecordingUserOutput(),
            entries=(InstallEntry(Path("README.md"), b"bad\n", OverwriteMode.ALWAYS),),
        ).install()


def test_installer_rejects_path_traversal(tmp_path: Path) -> None:
    _init_repo(tmp_path)

    with pytest.raises(InstallSafetyError, match="allowlist"):
        Installer(
            target_root=tmp_path,
            output=RecordingUserOutput(),
            entries=(InstallEntry(Path(".asdlc_worker/../README.md"), b"bad\n", OverwriteMode.ALWAYS),),
        ).install()


def test_installer_refuses_destination_symlinks(tmp_path: Path) -> None:
    _init_repo(tmp_path)
    source = tmp_path / "source.txt"
    source.write_text("source\n", encoding="utf-8")

    dest = tmp_path / ".asdlc_worker/templates/dest.txt"
    dest.parent.mkdir(parents=True)
    dest.symlink_to(source)
    with pytest.raises(InstallSafetyError, match="destination is a symlink"):
        Installer(
            target_root=tmp_path,
            output=RecordingUserOutput(),
            entries=(InstallEntry(Path(".asdlc_worker/templates/dest.txt"), b"new\n", OverwriteMode.ALWAYS),),
        ).install()


def test_seed_only_preserves_existing_operator_file(tmp_path: Path) -> None:
    _init_repo(tmp_path)
    path = tmp_path / ".asdlc_worker/history.md"
    path.parent.mkdir(parents=True)
    path.write_text("operator\n", encoding="utf-8")

    Installer(
        target_root=tmp_path,
        output=RecordingUserOutput(),
        entries=(InstallEntry(Path(".asdlc_worker/history.md"), b"seed\n", OverwriteMode.SEED_ONLY),),
    ).install()

    assert path.read_text(encoding="utf-8") == "operator\n"


def test_manifest_guarded_preserves_modified_file_unless_forced(tmp_path: Path) -> None:
    _init_repo(tmp_path)
    rel = Path(".codex/skills/yasdef-worker-design/SKILL.md")
    output = RecordingUserOutput()
    Installer(
        target_root=tmp_path,
        output=output,
        entries=(InstallEntry(rel, b"v1\n", OverwriteMode.MANIFEST_GUARDED),),
    ).install()
    dest = tmp_path / rel
    dest.write_text("operator edit\n", encoding="utf-8")

    Installer(
        target_root=tmp_path,
        output=output,
        entries=(InstallEntry(rel, b"v2\n", OverwriteMode.MANIFEST_GUARDED),),
    ).install()

    assert dest.read_text(encoding="utf-8") == "operator edit\n"
    assert any(event.level == "warn" and "preserved operator-modified file" in event.message for event in output.events)

    Installer(
        target_root=tmp_path,
        output=output,
        entries=(InstallEntry(rel, b"v2\n", OverwriteMode.MANIFEST_GUARDED),),
        force=True,
    ).install()

    assert dest.read_text(encoding="utf-8") == "v2\n"


def test_installer_merges_exclude_entries_without_duplicates(tmp_path: Path) -> None:
    _init_repo(tmp_path)
    exclude_file = tmp_path / ".git/info/exclude"
    exclude_file.write_text(
        "# existing git excludes\noperator.tmp\n.asdlc_worker/logs\n",
        encoding="utf-8",
    )

    Installer(
        target_root=tmp_path,
        output=RecordingUserOutput(),
        entries=(),
        exclude_entries=(
            ".asdlc_worker/logs",
            ".asdlc_worker/feature_meta_sync.yaml",
        ),
    ).install()

    lines = exclude_file.read_text(encoding="utf-8").splitlines()
    assert "# existing git excludes" in lines
    assert "operator.tmp" in lines
    assert lines.count(".asdlc_worker/logs") == 1
    assert lines.count(".asdlc_worker/feature_meta_sync.yaml") == 1

    Installer(
        target_root=tmp_path,
        output=RecordingUserOutput(),
        entries=(),
        exclude_entries=(
            ".asdlc_worker/logs",
            ".asdlc_worker/feature_meta_sync.yaml",
        ),
    ).install()

    rerun_lines = exclude_file.read_text(encoding="utf-8").splitlines()
    assert rerun_lines.count(".asdlc_worker/logs") == 1
    assert rerun_lines.count(".asdlc_worker/feature_meta_sync.yaml") == 1


def test_default_exclude_entries_cover_generated_runtime_paths_without_legacy_scripts() -> None:
    entries = default_exclude_entries()

    assert ".asdlc_worker/logs" in entries
    assert ".asdlc_worker/feature_meta_sync.yaml" in entries
    assert ".asdlc_worker/setup" in entries
    assert ".asdlc_worker/templates" in entries
    assert ".asdlc_worker/golden_examples" in entries
    assert ".codex/skills/yasdef-worker-design" in entries
    assert ".claude/commands/yasdef" in entries
    assert ".asdlc_worker/install_manifest.yaml" not in entries
    assert ".asdlc_worker/scripts" not in entries
    assert ".asdlc_worker/scripts/helpers" not in entries


def test_installer_force_adds_and_commits_durable_installed_files(tmp_path: Path) -> None:
    _init_repo(tmp_path)
    git = FakeCommitGit()
    output = RecordingUserOutput()

    Installer(
        target_root=tmp_path,
        output=output,
        entries=(
            InstallEntry(Path(".asdlc_worker/history.md"), b"history\n", OverwriteMode.SEED_ONLY),
            InstallEntry(Path(".asdlc_worker/setup/models.md"), b"models\n", OverwriteMode.MANIFEST_GUARDED),
            InstallEntry(
                Path(".codex/skills/yasdef-worker-design/SKILL.md"),
                b"skill\n",
                OverwriteMode.MANIFEST_GUARDED,
            ),
            InstallEntry(
                Path(".claude/commands/yasdef/design.md"),
                b"command\n",
                OverwriteMode.MANIFEST_GUARDED,
            ),
        ),
        git=git,
    ).install()

    assert git.created_branch == INIT_BRANCH
    assert git.add_force is True
    assert git.add_paths == [
        ".asdlc_worker/history.md",
        ".asdlc_worker/install_manifest.yaml",
    ]
    assert git.commit_message == "asdlc worker added"
    assert git.commit_paths == git.add_paths
    assert output.events[-1].level == "warn"
    assert INIT_BRANCH in output.events[-1].message
    assert "main" in output.events[-1].message


def test_installer_rejects_non_mainline_start_branch(tmp_path: Path) -> None:
    _init_repo(tmp_path)
    git = FakeCommitGit(current_branch="feature")

    with pytest.raises(YasdefError, match="must start from main or master"):
        Installer(
            target_root=tmp_path,
            output=RecordingUserOutput(),
            entries=(),
            git=git,
        ).install()


def test_installer_requires_git_root(tmp_path: Path) -> None:
    with pytest.raises(YasdefError, match="git worktree root"):
        Installer(
            target_root=tmp_path,
            output=RecordingUserOutput(),
            entries=(),
        ).install()


def test_default_install_entries_reads_package_data(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    package_root = tmp_path / "package"
    data_root = package_root / "_data"
    (data_root / "setup").mkdir(parents=True)
    (data_root / "setup" / "models.md").write_text("design | echo | mock\n", encoding="utf-8")
    (data_root / "runtime").mkdir()
    (data_root / "runtime" / "history_INITIAL.md").write_text("# History\n", encoding="utf-8")
    skill = data_root / "skills" / "yasdef-worker-design"
    skill.mkdir(parents=True)
    (skill / "SKILL.md").write_text(".claude/skills/yasdef-worker-design\n", encoding="utf-8")
    command = data_root / "commands" / "yasdef"
    command.mkdir(parents=True)
    (command / "design.md").write_text("/design\n", encoding="utf-8")

    monkeypatch.setattr(
        "yasdef_orchestrator.app.init_asdlc_worker.resources.files",
        lambda package: package_root,
    )

    entries = default_install_entries(tmp_path / "target")
    by_path = {entry.relative_path: entry for entry in entries}

    assert Path(".asdlc_worker/asdlc_worker.yaml") in by_path
    assert Path(".asdlc_worker/setup/models.md") in by_path
    assert by_path[Path(".asdlc_worker/history.md")].mode is OverwriteMode.SEED_ONLY
    assert Path(".claude/commands/yasdef/design.md") in by_path
    assert b".codex/skills/yasdef-worker-design" in by_path[
        Path(".codex/skills/yasdef-worker-design/SKILL.md")
    ].content


def test_default_install_entries_refuses_symlinked_package_data(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    package_root = tmp_path / "package"
    data_root = package_root / "_data"
    (data_root / "setup").mkdir(parents=True)
    source = tmp_path / "models-source.md"
    source.write_text("design | echo | mock\n", encoding="utf-8")
    (data_root / "setup" / "models.md").symlink_to(source)

    monkeypatch.setattr(
        "yasdef_orchestrator.app.init_asdlc_worker.resources.files",
        lambda package: package_root,
    )

    with pytest.raises(InstallSafetyError, match="package data contains a symlink"):
        default_install_entries(tmp_path / "target")


def _init_repo(path: Path) -> None:
    subprocess.run(["git", "init", "-b", "main", str(path)], check=True, capture_output=True)


class FakeCommitGit:
    def __init__(self, *, current_branch: str | None = "main", dirty: bool = False) -> None:
        self._current_branch = current_branch
        self.dirty = dirty
        self.created_branch = ""
        self.checked_out_branch = ""
        self.add_paths: list[str] = []
        self.add_force = False
        self.commit_message = ""
        self.commit_paths: list[str] = []

    def is_inside_worktree(self) -> bool:
        return True

    def current_branch(self) -> str | None:
        return self._current_branch

    def status_porcelain(self) -> str:
        return " M dirty.txt\n" if self.dirty else ""

    def branch_exists(self, name: str) -> bool:
        return False

    def checkout(self, name: str) -> None:
        self.checked_out_branch = name
        self._current_branch = name

    def checkout_new(self, name: str) -> None:
        self.created_branch = name
        self._current_branch = name

    def add(self, *paths: str, force: bool = False) -> None:
        self.add_paths = list(paths)
        self.add_force = force

    def has_staged_changes(self, *, paths: list[str] | None = None) -> bool:
        return True

    def commit(self, message: str, *, paths: list[str] | None = None) -> None:
        self.commit_message = message
        self.commit_paths = list(paths or [])
