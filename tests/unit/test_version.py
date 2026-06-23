from __future__ import annotations

from pathlib import Path
import tomllib

import yasdef_worker


def test_package_version_matches_project_metadata() -> None:
    pyproject = Path(__file__).parents[2] / "pyproject.toml"
    project = tomllib.loads(pyproject.read_text(encoding="utf-8"))["project"]

    assert yasdef_worker.__version__ == project["version"]
