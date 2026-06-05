from __future__ import annotations

import io

import pytest

from yasdef_orchestrator.infra.errors import YasdefError
from yasdef_orchestrator.infra.prompts import Prompter
from yasdef_orchestrator.infra.user_output import RecordingUserOutput, TerminalUserOutput


def test_prompter_confirm_uses_default_when_non_interactive() -> None:
    prompter = Prompter(stdin=io.StringIO(""), stderr=io.StringIO(), interactive=False)

    assert prompter.confirm("Proceed?", default=True)


def test_prompter_confirm_refuses_non_interactive_without_default() -> None:
    prompter = Prompter(stdin=io.StringIO(""), stderr=io.StringIO(), interactive=False)

    with pytest.raises(YasdefError):
        prompter.confirm("Proceed?")


def test_prompter_choose_numbered_returns_zero_based_index() -> None:
    prompter = Prompter(stdin=io.StringIO("2\n"), stderr=io.StringIO(), interactive=True)

    assert prompter.choose_numbered("Pick", ["one", "two"]) == 1


def test_recording_user_output_captures_levels() -> None:
    output = RecordingUserOutput()

    output.info("ok")
    output.warn("careful")
    output.failure("bad", detail="details")
    output.step("phase")

    assert [event.level for event in output.events] == ["info", "warn", "failure", "step"]
    assert output.events[2].fields == {"detail": "details"}


def test_terminal_user_output_writes_to_stream() -> None:
    stream = io.StringIO()
    output = TerminalUserOutput(stream)

    output.step("selected feature")

    assert stream.getvalue() == "orchestrator: selected feature\n"
