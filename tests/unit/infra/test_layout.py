from __future__ import annotations

from pathlib import Path

import pytest

from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.layout import RuntimeLayout


def test_runtime_layout_from_root_populates_expected_paths(tmp_path: Path) -> None:
    layout = RuntimeLayout.from_root(tmp_path)

    assert layout.worker_repo_root == tmp_path.resolve()
    assert layout.asdlc_home == tmp_path.resolve() / ".asdlc_worker"
    assert layout.models_file == tmp_path.resolve() / ".asdlc_worker" / "setup" / "models.md"
    assert layout.codex_skills_dir == tmp_path.resolve() / ".codex" / "skills"
    assert layout.claude_commands_dir == tmp_path.resolve() / ".claude" / "commands" / "yasdef"
    assert layout.skill_dirs() == (
        tmp_path.resolve() / ".codex" / "skills",
        tmp_path.resolve() / ".claude" / "skills",
        tmp_path.resolve() / ".github" / "skills",
        tmp_path.resolve() / ".agents" / "skills",
    )


def test_runtime_layout_resolves_existing_skill_path_across_installed_prefixes(
    tmp_path: Path,
) -> None:
    layout = RuntimeLayout.from_root(tmp_path)
    script = (
        layout.claude_skills_dir
        / "yasdef-worker-plan"
        / "scripts"
        / "check_planning_readiness.py"
    )
    script.parent.mkdir(parents=True)
    script.write_text("", encoding="utf-8")

    assert layout.existing_skill_path(
        "yasdef-worker-plan",
        "scripts",
        "check_planning_readiness.py",
    ) == script


def test_discover_reads_worker_binding(tmp_path: Path) -> None:
    runtime = tmp_path / ".asdlc_worker"
    runtime.mkdir()
    (runtime / "asdlc_worker.yaml").write_text(
        f"worker_repo_root: '{tmp_path}'\n",
        encoding="utf-8",
    )
    nested = tmp_path / "a" / "b"
    nested.mkdir(parents=True)

    layout = RuntimeLayout.discover(nested)

    assert layout.worker_repo_root == tmp_path.resolve()


def test_discover_ignores_scripts_layout_without_worker_binding(tmp_path: Path) -> None:
    helper = tmp_path / ".asdlc_worker" / "scripts" / "helpers" / "runtime_layout.sh"
    helper.parent.mkdir(parents=True)
    helper.write_text("", encoding="utf-8")

    with pytest.raises(YasdefError, match=r"\.asdlc_worker/asdlc_worker\.yaml"):
        RuntimeLayout.discover(helper)
