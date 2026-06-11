from __future__ import annotations

import io

import pytest

from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.user_output import RecordingUserOutput, TerminalUserOutput, UserOutput


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


def test_user_output_cannot_be_instantiated_directly() -> None:
    with pytest.raises(TypeError):
        UserOutput()


def test_user_output_subclass_must_implement_full_contract() -> None:
    class IncompleteUserOutput(UserOutput):
        def info(self, msg: str) -> None:
            pass

        def warn(self, msg: str) -> None:
            pass

        def failure(self, msg: str, *, detail: str | None = None) -> None:
            pass

        def step(self, msg: str) -> None:
            pass

    with pytest.raises(TypeError):
        IncompleteUserOutput()


def test_recording_user_output_captures_levels() -> None:
    output = RecordingUserOutput()

    output.info("ok")
    output.warn("careful")
    output.failure("bad", detail="details")
    output.step("phase")
    output.event("phase_started", step="1.1", feature="feature-a")

    assert [event.level for event in output.events] == ["info", "warn", "failure", "step", "event"]
    assert output.events[2].fields == {"detail": "details"}
    assert output.events[4].message == "phase_started"
    assert output.events[4].kind == "phase_started"
    assert output.events[4].fields == {"step": "1.1", "feature": "feature-a"}


def test_terminal_user_output_writes_to_stream() -> None:
    stream = io.StringIO()
    output = TerminalUserOutput(stream)

    output.step("selected feature")
    output.event("phase_started", step="1.1", feature="feature-a")

    assert stream.getvalue() == (
        "yasdef: selected feature\n"
        "phase_started: feature='feature-a' step='1.1'\n"
    )
