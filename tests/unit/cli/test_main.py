from __future__ import annotations

import io
import importlib
from pathlib import Path
from types import SimpleNamespace

import pytest

from yasdef_worker.cli import init as init_cmd
from yasdef_worker.cli import _shared
from yasdef_worker.cli import post_review as post_review_cmd
from yasdef_worker.cli import run as run_cmd
from yasdef_worker.cli import uninstall as uninstall_cmd
from yasdef_worker.domain.history.token_usage import TokenUsage
from yasdef_worker.infra.errors import FeatureExhausted, YasdefError

cli_main = importlib.import_module("yasdef_worker.cli.main")


def test_root_help_lists_subcommands() -> None:
    help_text = cli_main.build_parser().format_help()

    assert "run" in help_text
    assert "post-review" in help_text
    assert "init" in help_text
    assert "register" in help_text
    assert "uninstall" in help_text


@pytest.mark.parametrize("command", ["run", "post-review", "init", "register", "uninstall"])
def test_subcommand_help_exits_cleanly(command: str) -> None:
    with pytest.raises(SystemExit) as raised:
        cli_main.main([command, "--help"])

    assert raised.value.code == 0


def test_cli_shared_factories_accept_explicit_streams() -> None:
    stdin = io.StringIO("y\n")
    stderr = io.StringIO()

    prompter = _shared.prompter(stdin=stdin, stderr=stderr)
    assert prompter.stdin is stdin
    assert prompter.stderr is stderr

    _shared.output(stderr=stderr).step("done")

    assert "yasdef: done" in stderr.getvalue()


def test_run_command_builds_orchestrator_options(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    seen: dict[str, object] = {}

    class FakeCoordinator:
        def __init__(self, **kwargs: object):
            seen["init"] = kwargs

        def run(self, options: object) -> object:
            seen["options"] = options
            return SimpleNamespace(succeeded=True)

    monkeypatch.setattr(run_cmd, "Coordinator", FakeCoordinator)

    assert (
        cli_main.main(
            [
                "run",
                "--repo",
                str(tmp_path),
                "--resume",
                "1.1",
                "--dry-run",
                "--debug",
            ]
        )
        == 0
    )

    options = seen["options"]
    assert options.resume_step == "1.1"
    assert options.dry_run is True
    assert options.debug is True


def test_run_command_returns_success_for_controlled_feature_exhaustion(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    class FakeCoordinator:
        def __init__(self, **kwargs: object):
            pass

        def run(self, options: object) -> object:
            raise FeatureExhausted("feature-a", tmp_path / ".asdlc_worker" / "feature_sync.yaml")

    monkeypatch.setattr(run_cmd, "Coordinator", FakeCoordinator)

    assert cli_main.main(["run", "--repo", str(tmp_path)]) == 0
    assert "ERROR:" not in capsys.readouterr().err


@pytest.mark.parametrize(
    "argv",
    (
        ["run", "--resume"],
        ["run", "--step", "1.1"],
        ["run", "--phase", "design"],
    ),
)
def test_run_command_rejects_removed_step_forms(argv: list[str]) -> None:
    with pytest.raises(SystemExit) as raised:
        cli_main.main(argv)

    assert raised.value.code == 2


def test_post_review_rejects_removed_source_plan_option(tmp_path: Path) -> None:
    with pytest.raises(SystemExit) as raised:
        cli_main.main(
            [
                "post-review",
                "--repo",
                str(tmp_path),
                "--step",
                "1.1",
                "--feature-id",
                "feature-a",
                "--title",
                "Demo",
                "--source-plan",
                str(tmp_path / "implementation_plan.md"),
            ]
        )

    assert raised.value.code == 2


def test_init_command_uses_packaged_entries(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    seen: dict[str, object] = {}

    class FakeInstaller:
        def __init__(self, **kwargs: object):
            seen["init"] = kwargs

        def install(self) -> tuple[object, ...]:
            return (object(),)

    def fake_entries(target: Path) -> tuple[object, ...]:
        seen["target"] = target
        return (object(),)

    def fake_excludes() -> tuple[str, ...]:
        return (".asdlc_worker/logs",)

    monkeypatch.setattr(init_cmd, "Installer", FakeInstaller)
    monkeypatch.setattr(init_cmd, "default_install_entries", fake_entries)
    monkeypatch.setattr(init_cmd, "default_exclude_entries", fake_excludes)

    assert cli_main.main(["init", "--force", str(tmp_path)]) == 0

    assert seen["target"] == tmp_path.resolve()
    assert seen["init"]["target_root"] == tmp_path.resolve()
    assert seen["init"]["entries"]
    assert seen["init"]["exclude_entries"] == (".asdlc_worker/logs",)
    assert seen["init"]["force"] is True


def test_cli_boundary_reports_yasdef_error(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    def fail(_args: object) -> int:
        raise YasdefError("expected failure")

    monkeypatch.setattr(init_cmd, "handle", fail)

    assert cli_main.main(["init", str(tmp_path)]) == 1
    assert "ERROR: expected failure" in capsys.readouterr().err


def test_post_review_command_passes_collected_phase_usages(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    seen: dict[str, object] = {}

    class FakeResolver:
        @classmethod
        def for_layout(cls, layout: object) -> FakeResolver:
            seen["resolver_layout"] = layout
            return cls()

        def collect(self, *, step: str) -> tuple[tuple[str, TokenUsage], ...]:
            seen["resolver_step"] = step
            return (("design", TokenUsage(total=2, input=1, output=1)),)

    class FakePostReviewOperation:
        def __init__(self, **kwargs: object):
            seen["operation"] = kwargs

        def execute(self, review: object) -> object:
            seen["review"] = review
            return object()

    monkeypatch.setattr(post_review_cmd, "TokenUsageResolver", FakeResolver)
    monkeypatch.setattr(post_review_cmd, "PostReviewOperation", FakePostReviewOperation)

    assert (
        cli_main.main(
            [
                "post-review",
                "--repo",
                str(tmp_path),
                "--step",
                "1.1",
                "--feature-id",
                "feature-a",
                "--title",
                "Demo",
                "--no-plan-sync",
            ]
        )
        == 0
    )

    assert seen["resolver_step"] == "1.1"
    review = seen["review"]
    assert review.phase_usages == (("design", TokenUsage(total=2, input=1, output=1)),)


def test_uninstall_yes_skips_confirmation(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: dict[str, object] = {}

    class FailingPrompter:
        def confirm(self, *args: object, **kwargs: object) -> bool:
            raise AssertionError("prompt should not be called")

    def fake_run(argv: list[str], *, check: bool) -> object:
        seen["argv"] = argv
        seen["check"] = check
        return object()

    monkeypatch.setattr(uninstall_cmd, "_detect_uninstall_argv", lambda: ["uv", "tool", "uninstall", "yasdef-worker"])
    monkeypatch.setattr(uninstall_cmd, "prompter", lambda: FailingPrompter())
    monkeypatch.setattr(uninstall_cmd.subprocess, "run", fake_run)

    assert cli_main.main(["uninstall", "--yes"]) == 0
    assert seen == {"argv": ["uv", "tool", "uninstall", "yasdef-worker"], "check": True}


def test_uninstall_prompts_and_runs_when_confirmed(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: dict[str, object] = {}

    class ConfirmingPrompter:
        def confirm(self, prompt: str, *, default: bool | None = None) -> bool:
            seen["prompt"] = prompt
            seen["default"] = default
            return True

    def fake_run(argv: list[str], *, check: bool) -> object:
        seen["argv"] = argv
        seen["check"] = check
        return object()

    monkeypatch.setattr(uninstall_cmd, "_detect_uninstall_argv", lambda: ["pipx", "uninstall", "yasdef-worker"])
    monkeypatch.setattr(uninstall_cmd, "prompter", lambda: ConfirmingPrompter())
    monkeypatch.setattr(uninstall_cmd.subprocess, "run", fake_run)

    assert cli_main.main(["uninstall"]) == 0
    assert seen["default"] is False
    assert "pipx uninstall yasdef-worker" in str(seen["prompt"])
    assert seen["argv"] == ["pipx", "uninstall", "yasdef-worker"]
    assert seen["check"] is True


def test_uninstall_cancel_returns_error_without_running(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: dict[str, object] = {}

    class DenyingPrompter:
        def confirm(self, prompt: str, *, default: bool | None = None) -> bool:
            seen["prompt"] = prompt
            seen["default"] = default
            return False

    def fake_run(argv: list[str], *, check: bool) -> object:
        raise AssertionError("uninstall command should not run")

    monkeypatch.setattr(uninstall_cmd, "_detect_uninstall_argv", lambda: ["uv", "tool", "uninstall", "yasdef-worker"])
    monkeypatch.setattr(uninstall_cmd, "prompter", lambda: DenyingPrompter())
    monkeypatch.setattr(uninstall_cmd.subprocess, "run", fake_run)

    assert cli_main.main(["uninstall"]) == 1
    assert seen["default"] is False
