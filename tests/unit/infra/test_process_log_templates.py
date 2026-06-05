from __future__ import annotations

import io
import sys
import time
from pathlib import Path

import pytest

from yasdef_orchestrator.infra.layout import RuntimeLayout
from yasdef_orchestrator.infra.log_capture import LogCapture
from yasdef_orchestrator.infra.process import PHASE_CLOSE_MARKER, ProcessRunner
from yasdef_orchestrator.infra.templates import TemplateLoader


def test_process_runner_writes_log_and_output(tmp_path: Path) -> None:
    log_path = tmp_path / "logs" / "run.log"
    output = io.StringIO()

    completed = ProcessRunner().run_with_log(
        [sys.executable, "-c", "print('hello')"],
        log_path,
        output=output,
    )

    assert completed.returncode == 0
    assert log_path.read_text(encoding="utf-8").strip() == "hello"
    assert output.getvalue().strip() == "hello"


def test_process_runner_can_terminate_on_live_close_marker(tmp_path: Path) -> None:
    log_path = tmp_path / "logs" / "run.log"
    output = io.StringIO()
    started = time.monotonic()

    completed = ProcessRunner().run_with_log(
        [
            sys.executable,
            "-c",
            (
                "import time; "
                "print('before', flush=True); "
                f"print('{PHASE_CLOSE_MARKER}', flush=True); "
                "time.sleep(10)"
            ),
        ],
        log_path,
        output=output,
        close_marker=PHASE_CLOSE_MARKER,
    )

    assert completed.returncode == 0
    assert time.monotonic() - started < 3
    assert PHASE_CLOSE_MARKER in log_path.read_text(encoding="utf-8")
    assert PHASE_CLOSE_MARKER in output.getvalue()


def test_log_capture_paths(tmp_path: Path) -> None:
    layout = RuntimeLayout.from_root(tmp_path)
    capture = LogCapture(layout, debug=True, project="demo")
    log_path = capture.path_for("User Review", "1.2a")

    assert log_path.name == "demo-user_review-1.2a-log"


def test_template_loader_prefers_repo_override(tmp_path: Path) -> None:
    layout = RuntimeLayout.from_root(tmp_path)
    prompt_dir = layout.templates_dir / "prompts"
    prompt_dir.mkdir(parents=True)
    (prompt_dir / "design.md").write_text("Step {step}", encoding="utf-8")

    assert TemplateLoader(layout).load("design") == "Step {step}"


def test_template_loader_raises_for_missing_default(tmp_path: Path) -> None:
    layout = RuntimeLayout.from_root(tmp_path)

    with pytest.raises(FileNotFoundError):
        TemplateLoader(layout).load("missing")
