from __future__ import annotations

from pathlib import Path

from yasdef_worker.infra.files import ensure_dir_writable, ensure_file_writable_if_missing


def test_ensure_dir_writable_creates_parent(tmp_path: Path) -> None:
    target = tmp_path / "nested" / "dir"

    assert ensure_dir_writable(target) == target
    assert target.is_dir()


def test_ensure_file_writable_if_missing_creates_file(tmp_path: Path) -> None:
    target = tmp_path / "nested" / "file.txt"

    assert ensure_file_writable_if_missing(target) == target
    assert target.is_file()
