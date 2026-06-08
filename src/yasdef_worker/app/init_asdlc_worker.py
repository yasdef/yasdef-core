from __future__ import annotations

import contextlib
import hashlib
import os
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import Enum
from importlib import resources
from importlib.resources.abc import Traversable
from pathlib import Path

from yasdef_worker.app.mainline_branch_policy import checkout_work_branch, offer_merge_back
from yasdef_worker import __version__
from yasdef_worker.infra.errors import InstallSafetyError, YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.user_output import UserOutput
from yasdef_worker.infra.yaml_io import read_yaml_file, write_yaml_file

INSTALL_ALLOWLIST: tuple[Path, ...] = (
    Path(".asdlc_worker"),
    Path(".claude/skills"),
    Path(".claude/commands/yasdef"),
    Path(".codex/skills"),
    Path(".github/skills"),
    Path(".agents/skills"),
    Path(".git/info/exclude"),
)

SKILL_NAMES: tuple[str, ...] = (
    "yasdef-worker-design",
    "yasdef-worker-plan",
    "yasdef-worker-implementation",
    "yasdef-worker-user-review",
    "yasdef-worker-ai-audit",
)

SKILL_TARGET_PREFIXES: tuple[str, ...] = (".claude", ".codex", ".github", ".agents")

RUNTIME_EXCLUDE_ENTRIES: tuple[str, ...] = (
    ".asdlc_worker/golden_examples",
    ".asdlc_worker/setup",
    ".asdlc_worker/templates",
    ".asdlc_worker/logs",
    ".asdlc_worker/feature_meta_sync.yaml",
)

INIT_BRANCH = "init_yasdef_worker"


class OverwriteMode(str, Enum):
    ALWAYS = "always"
    SEED_ONLY = "seed-only"
    MANIFEST_GUARDED = "manifest-guarded"


@dataclass(frozen=True, slots=True)
class InstallEntry:
    relative_path: Path
    content: bytes
    mode: OverwriteMode


@dataclass(frozen=True, slots=True)
class InstalledFile:
    path: str
    sha256: str
    mode: str


def default_install_entries(target_root: Path) -> tuple[InstallEntry, ...]:
    root = target_root.resolve()
    data_root = resources.files("yasdef_worker") / "_data"
    if not data_root.is_dir():
        raise YasdefError("packaged installer data is missing: yasdef_worker/_data")

    entries: list[InstallEntry] = [
        InstallEntry(
            Path(".asdlc_worker/asdlc_worker.yaml"),
            f"worker_repo_root: '{_yaml_single_quote(root)}'\n".encode("utf-8"),
            OverwriteMode.ALWAYS,
        )
    ]

    _extend_tree_entries(entries, data_root / "setup", Path(".asdlc_worker/setup"))
    _extend_tree_entries(entries, data_root / "templates", Path(".asdlc_worker/templates"))
    _extend_tree_entries(
        entries,
        data_root / "golden_examples",
        Path(".asdlc_worker/golden_examples"),
    )
    _extend_tree_entries(entries, data_root / "commands" / "yasdef", Path(".claude/commands/yasdef"))

    runtime = data_root / "runtime"
    if runtime.is_dir():
        for source, rel in _walk_files(runtime):
            name = rel.name.removesuffix("_INITIAL.md") + ".md"
            entries.append(
                InstallEntry(
                    Path(".asdlc_worker") / rel.parent / name,
                    _read_package_bytes(source),
                    OverwriteMode.SEED_ONLY,
                )
            )

    skills = data_root / "skills"
    for prefix in SKILL_TARGET_PREFIXES:
        _extend_tree_entries(
            entries,
            skills,
            Path(prefix) / "skills",
            rewrite_skill_prefix=None if prefix == ".claude" else prefix,
        )

    return tuple(entries)


def default_exclude_entries() -> tuple[str, ...]:
    entries = list(RUNTIME_EXCLUDE_ENTRIES)
    for prefix in SKILL_TARGET_PREFIXES:
        entries.extend(f"{prefix}/skills/{skill}" for skill in SKILL_NAMES)
    entries.append(".claude/commands/yasdef")
    return tuple(entries)


class Installer:
    def __init__(
        self,
        *,
        target_root: Path,
        output: UserOutput,
        entries: tuple[InstallEntry, ...],
        exclude_entries: tuple[str, ...] = (),
        git: GitRepo | None = None,
        prompts: Prompter | None = None,
        force: bool = False,
    ):
        self.target_root = target_root.resolve()
        self.output = output
        self.entries = entries
        self.exclude_entries = exclude_entries
        self.git = git
        self.prompts = prompts
        self.force = force
        self.manifest_path = self.target_root / ".asdlc_worker" / "install_manifest.yaml"

    def install(self) -> tuple[InstalledFile, ...]:
        self._validate_target_root()
        start_branch = self._prepare_install_branch()
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
            self._merge_exclude_entries()
            self._write_manifest(installed)
            self._commit_durable_files(installed)
            self._announce_complete(installed)
            self._offer_merge_back(start_branch)
        except Exception:
            self._write_manifest(installed, failed=True)
            raise
        return tuple(installed)

    def _validate_target_root(self) -> None:
        if not ((self.target_root / ".git").exists()):
            raise YasdefError(f"init target must be a git worktree root: {self.target_root}")

    def _prepare_install_branch(self) -> str | None:
        if self.git is None:
            return None
        return checkout_work_branch(
            self.git,
            self.output,
            operation="yasdef init",
            branch_name=INIT_BRANCH,
        )

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
            "yasdef_worker_version": __version__,
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

    def _merge_exclude_entries(self) -> None:
        if not self.exclude_entries:
            return
        exclude_file = self.target_root / ".git" / "info" / "exclude"
        self._validate_dest(exclude_file)
        exclude_file.parent.mkdir(parents=True, exist_ok=True)
        if exclude_file.exists():
            existing = exclude_file.read_text(encoding="utf-8")
            lines = existing.splitlines()
        else:
            lines = []
        present = set(lines)
        changed = False
        for entry in self.exclude_entries:
            if entry not in present:
                lines.append(entry)
                present.add(entry)
                changed = True
        if changed:
            _atomic_write_bytes(exclude_file, ("\n".join(lines) + "\n").encode("utf-8"))

    def _commit_durable_files(self, installed: list[InstalledFile]) -> None:
        if self.git is None:
            return
        paths = [
            item.path
            for item in installed
            if not _is_excluded_install_path(item.path)
        ]
        paths.append(str(self.manifest_path.relative_to(self.target_root)))
        if not paths:
            return
        self.git.add(*paths, force=True)
        if self.git.has_staged_changes(paths=paths):
            self.git.commit("asdlc worker added", paths=paths)

    def _offer_merge_back(self, start_branch: str | None) -> None:
        if start_branch is None or self.git is None:
            return
        offer_merge_back(
            self.git,
            self.output,
            self.prompts or Prompter(interactive=False),
            work_branch=INIT_BRANCH,
            start_branch=start_branch,
        )

    def _announce_complete(self, installed: list[InstalledFile]) -> None:
        self.output.step(f"worker runtime install complete ({len(installed)} files)")


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


def _extend_tree_entries(
    entries: list[InstallEntry],
    source_root: Traversable,
    dest_root: Path,
    *,
    rewrite_skill_prefix: str | None = None,
) -> None:
    if not source_root.is_dir():
        return
    for source, rel in _walk_files(source_root):
        content = _read_package_bytes(source)
        if rewrite_skill_prefix is not None and source.name == "SKILL.md":
            content = content.replace(
                b".claude/skills/",
                f"{rewrite_skill_prefix}/skills/".encode("utf-8"),
            )
        entries.append(InstallEntry(dest_root / rel, content, OverwriteMode.MANIFEST_GUARDED))


def _walk_files(root: Traversable, prefix: Path = Path()) -> tuple[tuple[Traversable, Path], ...]:
    files: list[tuple[Traversable, Path]] = []
    for child in root.iterdir():
        rel = prefix / child.name
        _refuse_package_symlink(child)
        if child.is_dir():
            files.extend(_walk_files(child, rel))
        elif child.is_file():
            files.append((child, rel))
    return tuple(files)


def _read_package_bytes(source: Traversable) -> bytes:
    _refuse_package_symlink(source)
    return source.read_bytes()


def _refuse_package_symlink(source: Traversable) -> None:
    if isinstance(source, Path) and source.is_symlink():
        raise InstallSafetyError(source, "package data contains a symlink")


def _is_excluded_install_path(path: str) -> bool:
    return (
        path.startswith(".claude/skills/")
        or path.startswith(".codex/skills/")
        or path.startswith(".github/skills/")
        or path.startswith(".agents/skills/")
        or path.startswith(".claude/commands/yasdef/")
        or path.startswith(".asdlc_worker/setup/")
        or path.startswith(".asdlc_worker/templates/")
        or path.startswith(".asdlc_worker/golden_examples/")
    )


def _yaml_single_quote(value: Path) -> str:
    return str(value).replace("'", "''")
