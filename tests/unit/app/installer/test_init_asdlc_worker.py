from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from yasdef_orchestrator.app.init_asdlc_worker import (
    InstallEntry,
    Installer,
    OverwriteMode,
)
from yasdef_orchestrator.infra.errors import InstallSafetyError, YasdefError
from yasdef_orchestrator.infra.user_output import RecordingUserOutput
from yasdef_orchestrator.infra.yaml_io import read_yaml_file


def test_installer_writes_allowed_file_and_manifest(tmp_path: Path) -> None:
    _init_repo(tmp_path)

    installed = Installer(
        target_root=tmp_path,
        output=RecordingUserOutput(),
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


def test_installer_refuses_source_and_destination_symlinks(tmp_path: Path) -> None:
    _init_repo(tmp_path)
    source = tmp_path / "source.txt"
    source.write_text("source\n", encoding="utf-8")
    source_link = tmp_path / "source-link.txt"
    source_link.symlink_to(source)

    with pytest.raises(InstallSafetyError, match="package data contains a symlink"):
        InstallEntry.from_path(
            source=source_link,
            relative_path=Path(".asdlc_worker/templates/source.txt"),
            mode=OverwriteMode.ALWAYS,
        )

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
    assert output.events[-1].level == "warn"

    Installer(
        target_root=tmp_path,
        output=output,
        entries=(InstallEntry(rel, b"v2\n", OverwriteMode.MANIFEST_GUARDED),),
        force=True,
    ).install()

    assert dest.read_text(encoding="utf-8") == "v2\n"


def test_installer_requires_git_root(tmp_path: Path) -> None:
    with pytest.raises(YasdefError, match="git worktree root"):
        Installer(
            target_root=tmp_path,
            output=RecordingUserOutput(),
            entries=(),
        ).install()


def _init_repo(path: Path) -> None:
    subprocess.run(["git", "init", "-b", "main", str(path)], check=True, capture_output=True)
