from __future__ import annotations

import os
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
