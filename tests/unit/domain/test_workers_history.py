from __future__ import annotations

import pytest

from yasdef_worker.domain.history.records import HistoryRecord, Metrics
from yasdef_worker.domain.history.token_usage import TokenUsage, extract_token_usage_line
from yasdef_worker.domain.workers_registry import (
    WorkersRegistryError,
    find_worker_matches,
    resolve_single_worker_match,
)


def test_workers_registry_finds_uuid_matches_from_loaded_yaml_dict() -> None:
    worker_uuid = "11111111-1111-1111-1111-111111111111"
    data = {
        "workers": [
            {"uuid": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "class": "backend", "status": "busy"},
            {"uuid": worker_uuid.upper(), "class": "platform", "status": "ready"},
        ]
    }

    matches = find_worker_matches(data, worker_uuid)

    assert matches == (
        resolve_single_worker_match(data, worker_uuid),
    )
    assert matches[0].uuid == worker_uuid
    assert matches[0].worker_class == "platform"
    assert matches[0].status == "ready"


def test_workers_registry_rejects_missing_fields_and_duplicates() -> None:
    uuid = "11111111-1111-1111-1111-111111111111"

    with pytest.raises(WorkersRegistryError, match="missing required"):
        find_worker_matches({"workers": [{"uuid": uuid, "class": "backend"}]}, uuid)

    with pytest.raises(WorkersRegistryError, match="multiple entries"):
        resolve_single_worker_match(
            {
                "workers": [
                    {"uuid": uuid, "class": "backend", "status": "ready"},
                    {"uuid": uuid, "class": "platform", "status": "ready"},
                ]
            },
            uuid,
        )


def test_token_usage_extracts_latest_line_and_formats_human_values() -> None:
    content = (
        "noise\n"
        "Token usage: total=1 input=1 (+ 0 cached) output=0 (reasoning 0)\n"
        "\x1b[0mToken usage: total=12,345 input=10,000 (+ 2,000 cached) "
        "output=345 (reasoning 123)\r\n"
    )

    line = extract_token_usage_line(content)
    usage = TokenUsage.parse(content)

    assert line == "total=12,345 input=10,000 (+ 2,000 cached) output=345 (reasoning 123)"
    assert usage is not None
    assert usage.total == 12345
    assert usage.input == 10000
    assert usage.cached == 2000
    assert usage.output == 345
    assert usage.reasoning == 123
    assert usage.format_human() == (
        "total=12,345 input=10,000 (+ 2,000 cached) output=345 (reasoning 123)"
    )


def test_token_usage_and_metrics_addition() -> None:
    usage = TokenUsage(total=1, input=2, cached=3, output=4, reasoning=5) + TokenUsage(
        total=10, input=20, cached=30, output=40, reasoning=50
    )
    metrics = Metrics(loc_added=5, files_added=1, files_touched=2) + Metrics(
        loc_added=7, files_added=3, files_touched=4
    )

    assert usage == TokenUsage(total=11, input=22, cached=33, output=44, reasoning=55, raw="")
    assert metrics.loc_added == 12
    assert metrics.files_added == 4
    assert metrics.files_touched == 6
    assert "new lines of code added: 12" in metrics.format_human()


def test_history_record_formats_step_line() -> None:
    record = HistoryRecord(
        step="1.1",
        title="Demo",
        step_plan=".asdlc_worker/step_plans/step-1.1-demo.md",
        token_usage=TokenUsage(total=1),
        metrics=Metrics(loc_added=1),
    )

    assert record.format_step_line() == "- Step: 1.1 - Demo"

