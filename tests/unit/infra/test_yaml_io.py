from __future__ import annotations

from pathlib import Path

from yasdef_worker.infra.yaml_io import dump_yaml, is_valid_uuid, read_yaml_file, write_yaml_file


def test_yaml_round_trip_preserves_mapping_order(tmp_path: Path) -> None:
    target = tmp_path / "binding.yaml"
    data = {
        "worker_repo_root": "/tmp/example",
        "worker_uuid": "123e4567-e89b-12d3-a456-426614174000",
    }

    write_yaml_file(target, data)

    assert read_yaml_file(target) == data
    assert dump_yaml(data).splitlines()[0] == "worker_repo_root: /tmp/example"


def test_is_valid_uuid() -> None:
    assert is_valid_uuid("123e4567-e89b-12d3-a456-426614174000")
    assert not is_valid_uuid("not-a-uuid")
