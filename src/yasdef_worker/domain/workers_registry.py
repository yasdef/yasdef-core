from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass


class WorkersRegistryError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class WorkerMatch:
    uuid: str
    worker_class: str
    status: str


YamlValue = Mapping[str, object] | Sequence[object] | str | int | float | bool | None


def find_worker_matches(data: Mapping[str, object], target_uuid: str) -> tuple[WorkerMatch, ...]:
    workers_value = data.get("workers")
    if workers_value is None:
        raise WorkersRegistryError("missing 'workers:' key")
    if not isinstance(workers_value, list):
        raise WorkersRegistryError("'workers:' must be a list")

    target = target_uuid.lower()
    matches: list[WorkerMatch] = []
    for entry in workers_value:
        if not isinstance(entry, dict):
            raise WorkersRegistryError("malformed workers list")
        uuid_value = _string_value(entry.get("uuid")).lower()
        if uuid_value != target:
            continue
        worker_class = _string_value(entry.get("class"))
        status = _string_value(entry.get("status"))
        if not worker_class or not status:
            raise WorkersRegistryError(
                f"matched worker UUID '{target_uuid}' is missing required 'class' or 'status'"
            )
        matches.append(WorkerMatch(uuid=uuid_value, worker_class=worker_class, status=status))
    return tuple(matches)


def resolve_single_worker_match(data: Mapping[str, object], target_uuid: str) -> WorkerMatch:
    matches = find_worker_matches(data, target_uuid)
    if not matches:
        raise WorkersRegistryError(f"no registered worker found for UUID '{target_uuid}'")
    if len(matches) > 1:
        raise WorkersRegistryError(
            f"worker UUID '{target_uuid}' resolved to multiple entries; ensure it appears once"
        )
    return matches[0]


def _string_value(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    return str(value).strip()

