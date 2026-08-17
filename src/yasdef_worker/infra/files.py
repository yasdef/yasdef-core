from __future__ import annotations

import contextlib
import os
from collections.abc import Sequence
from pathlib import Path

from .errors import YasdefError


def ensure_dir_writable(path: Path | str) -> Path:
    directory = Path(path)
    try:
        directory.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise YasdefError(f"failed to create directory: {directory}: {exc}") from exc

    if not directory.is_dir():
        raise YasdefError(f"path is not a directory: {directory}")
    if not os.access(directory, os.W_OK):
        raise YasdefError(f"directory is not writable: {directory}")
    return directory


def ensure_file_writable_if_missing(path: Path | str) -> Path:
    file_path = Path(path)
    ensure_dir_writable(file_path.parent)

    if file_path.exists():
        if not file_path.is_file():
            raise YasdefError(f"path is not a file: {file_path}")
        if not os.access(file_path, os.W_OK):
            raise YasdefError(f"file exists but is not writable: {file_path}")
        return file_path

    try:
        file_path.touch(exist_ok=False)
    except OSError as exc:
        raise YasdefError(f"failed to create file: {file_path}: {exc}") from exc
    return file_path


def atomic_write_bytes(dest: Path, content: bytes) -> None:
    """Write content through a fresh temp file, then replace dest.

    Replaces a symlink at dest instead of following it.
    """
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


def merge_exclude_entries(exclude_file: Path, entries: Sequence[str]) -> bool:
    """Append missing entries to a git exclude file. Returns True when it changed."""
    if not entries:
        return False
    exclude_file.parent.mkdir(parents=True, exist_ok=True)
    lines = exclude_file.read_text(encoding="utf-8").splitlines() if exclude_file.exists() else []
    present = set(lines)
    changed = False
    for entry in entries:
        if entry not in present:
            lines.append(entry)
            present.add(entry)
            changed = True
    if changed:
        atomic_write_bytes(exclude_file, ("\n".join(lines) + "\n").encode("utf-8"))
    return changed
