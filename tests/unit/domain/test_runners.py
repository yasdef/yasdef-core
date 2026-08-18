from __future__ import annotations

import pytest

from yasdef_worker.domain.runners import (
    ClaudeRunner,
    CodexRunner,
    CopilotRunner,
    EchoRunner,
    UnknownModelRunnerError,
    get_runner,
)


def test_codex_runner_builds_exact_argv_with_extras() -> None:
    argv = CodexRunner().build_argv(
        model="gpt-5.5",
        extras=["--config", "model_reasoning_effort='high'"],
        prompt="SAMPLE PROMPT",
    )

    assert argv == [
        "codex",
        "-m",
        "gpt-5.5",
        "--config",
        "model_reasoning_effort='high'",
        "SAMPLE PROMPT",
    ]


def test_claude_runner_builds_exact_argv_with_extras() -> None:
    argv = ClaudeRunner().build_argv(
        model="claude-opus-4-7",
        extras=["--allowed-tools", "Bash,Read"],
        prompt="SAMPLE PROMPT",
    )

    assert argv == [
        "claude",
        "--model",
        "claude-opus-4-7",
        "--allowed-tools",
        "Bash,Read",
        "SAMPLE PROMPT",
    ]


def test_copilot_runner_builds_exact_argv_without_extras() -> None:
    runner = CopilotRunner()

    assert runner.needs_tty is True
    assert runner.captures_log is True
    assert runner.build_argv(
        model="claude-haiku-4.5",
        extras=[],
        prompt="SAMPLE PROMPT",
    ) == [
        "copilot",
        "--model",
        "claude-haiku-4.5",
        "-i",
        "SAMPLE PROMPT",
    ]


def test_copilot_runner_keeps_extras_in_order_before_interactive_prompt() -> None:
    argv = CopilotRunner().build_argv(
        model="claude-haiku-4.5",
        extras=["--effort", "high", "--allow-tool", "shell(ls)"],
        prompt="SAMPLE PROMPT\nwith multiple lines",
    )

    assert argv == [
        "copilot",
        "--model",
        "claude-haiku-4.5",
        "--effort",
        "high",
        "--allow-tool",
        "shell(ls)",
        "-i",
        "SAMPLE PROMPT\nwith multiple lines",
    ]
    assert argv[-2] == "-i"
    assert argv.count("SAMPLE PROMPT\nwith multiple lines") == 1


def test_echo_runner_builds_codex_shape_for_test_runner() -> None:
    runner = EchoRunner()

    assert runner.needs_tty is False
    assert runner.captures_log is True
    assert runner.build_argv(model="mock-model", extras=[], prompt="SAMPLE PROMPT") == [
        "echo",
        "-m",
        "mock-model",
        "SAMPLE PROMPT",
    ]


def test_runner_registry_uses_only_known_runners() -> None:
    assert isinstance(get_runner("codex"), CodexRunner)
    assert isinstance(get_runner("claude"), ClaudeRunner)
    assert isinstance(get_runner("copilot"), CopilotRunner)
    assert isinstance(get_runner("  copilot  "), CopilotRunner)
    assert get_runner("echo").build_argv(model="m", extras=[], prompt="p") == ["echo", "-m", "m", "p"]
    with pytest.raises(UnknownModelRunnerError):
        get_runner("unsupported-runner")


@pytest.mark.parametrize("cmd", ["Copilot", "COPILOT", "copilot-cli", "github-copilot"])
def test_runner_registry_rejects_near_miss_copilot_commands(cmd: str) -> None:
    with pytest.raises(UnknownModelRunnerError, match="unsupported model runner command"):
        get_runner(cmd)
