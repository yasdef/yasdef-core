from __future__ import annotations

import uuid
from pathlib import Path
from typing import Any

import yaml

YamlMap = dict[str, Any]


def read_yaml_file(path: Path | str) -> YamlMap:
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"expected YAML mapping in {path}")
    return data


def dump_yaml(data: YamlMap) -> str:
    return yaml.safe_dump(
        data,
        allow_unicode=False,
        default_flow_style=False,
        sort_keys=False,
    )


def write_yaml_file(path: Path | str, data: YamlMap) -> None:
    Path(path).write_text(dump_yaml(data), encoding="utf-8")


def is_valid_uuid(value: str) -> bool:
    try:
        uuid.UUID(value)
    except (TypeError, ValueError):
        return False
    return True
