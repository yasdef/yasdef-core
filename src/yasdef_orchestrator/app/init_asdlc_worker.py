from __future__ import annotations

import contextlib
import hashlib
import os
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import Enum
from pathlib import Path

from yasdef_orchestrator import __version__
from yasdef_orchestrator.infra.errors import InstallSafetyError, YasdefError
from yasdef_orchestrator.infra.user_output import UserOutput
from yasdef_orchestrator.infra.yaml_io import read_yaml_file, write_yaml_file

INSTALL_ALLOWLIST: tuple[Path, ...] = (
    Path(".asdlc_worker"),
    Path(".claude/skills"),
    Path(".claude/commands/yasdef"),
    Path(".codex/skills"),
    Path(".github/skills"),
    Path(".agents/skills"),
    Path(".git/info/exclude"),
)


class OverwriteMode(str, Enum):
    ALWAYS = "always"
    SEED_ONLY = "seed-only"
    MANIFEST_GUARDED = "manifest-guarded"


@dataclass(frozen=True, slots=True)
class InstallEntry:
    relative_path: Path
    content: bytes
    mode: OverwriteMode

    @classmethod
    def from_path(cls, *, source: Path, relative_path: Path, mode: OverwriteMode) -> InstallEntry:
        if source.is_symlink():
            raise InstallSafetyError(source, "package data contains a symlink")
        return cls(relative_path=relative_path, content=source.read_bytes(), mode=mode)


@dataclass(frozen=True, slots=True)
class InstalledFile:
    path: str
    sha256: str
    mode: str


class Installer:
    def __init__(
        self,
        *,
        target_root: Path,
        output: UserOutput,
        entries: tuple[InstallEntry, ...],
        force: bool = False,
    ):
        self.target_root = target_root.resolve()
        self.output = output
        self.entries = entries
        self.force = force
        self.manifest_path = self.target_root / ".asdlc_worker" / "install_manifest.yaml"

    def install(self) -> tuple[InstalledFile, ...]:
        self._validate_target_root()
        previous = self._read_previous_manifest()
        installed: list[InstalledFile] = []
        try:
            for entry in self.entries:
                dest = self.target_root / entry.relative_path
                self._validate_dest(dest)
                if self._should_write(entry, dest, previous):
                    _atomic_write_bytes(dest, entry.content)
                installed.append(
                    InstalledFile(
                        path=str(entry.relative_path),
                        sha256=_sha256(entry.content),
                        mode=entry.mode.value,
                    )
                )
            self._write_manifest(installed)
        except Exception:
            self._write_manifest(installed, failed=True)
            raise
        return tuple(installed)

    def _validate_target_root(self) -> None:
        if not ((self.target_root / ".git").exists()):
            raise YasdefError(f"init target must be a git worktree root: {self.target_root}")

    def _validate_dest(self, dest: Path) -> None:
        if dest.is_symlink():
            raise InstallSafetyError(dest, "destination is a symlink")
        resolved_root = self.target_root.resolve()
        resolved = dest.resolve(strict=False)
        if not resolved.is_relative_to(resolved_root):
            raise InstallSafetyError(dest, "destination escapes target root")
        rel = resolved.relative_to(resolved_root)
        if not any(rel == allowed or rel.is_relative_to(allowed) for allowed in INSTALL_ALLOWLIST):
            raise InstallSafetyError(dest, "destination not in installer allowlist")

    def _read_previous_manifest(self) -> dict[str, str]:
        if not self.manifest_path.is_file():
            return {}
        data = read_yaml_file(self.manifest_path)
        files = data.get("files")
        if not isinstance(files, list):
            return {}
        previous: dict[str, str] = {}
        for item in files:
            if isinstance(item, dict):
                path = str(item.get("path") or "")
                sha = str(item.get("sha256") or "")
                if path and sha:
                    previous[path] = sha
        return previous

    def _should_write(
        self,
        entry: InstallEntry,
        dest: Path,
        previous: dict[str, str],
    ) -> bool:
        if entry.mode is OverwriteMode.ALWAYS:
            return True
        if entry.mode is OverwriteMode.SEED_ONLY:
            return not dest.exists()
        if not dest.exists():
            return True
        rel = str(entry.relative_path)
        current_sha = _sha256(dest.read_bytes())
        expected_sha = previous.get(rel)
        if expected_sha is not None and current_sha == expected_sha:
            return True
        if self.force:
            return True
        self.output.warn(f"preserved operator-modified file: {entry.relative_path}")
        return False

    def _write_manifest(self, files: list[InstalledFile], *, failed: bool = False) -> None:
        data: dict[str, object] = {
            "yasdef_orchestrator_version": __version__,
            "installed_at": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "files": [
                {"path": item.path, "sha256": item.sha256, "mode": item.mode}
                for item in files
            ],
        }
        if failed:
            data["failed"] = True
        self.manifest_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.manifest_path.with_suffix(self.manifest_path.suffix + f".tmp.{os.getpid()}")
        write_yaml_file(tmp, data)
        os.replace(tmp, self.manifest_path)


def _atomic_write_bytes(dest: Path, content: bytes) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    tmp = dest.with_name(dest.name + f".tmp.{os.getpid()}")
    try:
        fd = os.open(tmp, flags, 0o644)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
        except Exception:
            with contextlib.suppress(OSError):
                os.close(fd)
            raise
        os.replace(tmp, dest)
    except Exception:
        with contextlib.suppress(FileNotFoundError):
            tmp.unlink()
        raise


def _sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()
