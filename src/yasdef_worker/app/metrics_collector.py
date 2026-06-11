from __future__ import annotations

from dataclasses import dataclass

from yasdef_worker.domain.history.records import Metrics
from yasdef_worker.infra.git_repo import GitRepo


@dataclass(slots=True)
class MetricsCollector:
    git: GitRepo

    def collect(self, range_or_ref: str | None = None, *, cached: bool = False) -> Metrics:
        rows = self.git.diff_numstat(range_or_ref, cached=cached)
        loc_added = sum(
            row.added or 0
            for row in rows
            if row.added is not None and not _is_runtime_path(row.path)
        )
        files_added = sum(
            1
            for path in self.git.diff_name_only(range_or_ref, cached=cached, diff_filter="A")
            if not _is_runtime_path(path)
        )
        files_touched = sum(
            1
            for path in self.git.diff_name_only(range_or_ref, cached=cached, diff_filter="M")
            if not _is_runtime_path(path)
        )
        return Metrics(
            loc_added=loc_added,
            files_added=files_added,
            files_touched=files_touched,
        )


def _is_runtime_path(path: str) -> bool:
    return path == ".asdlc_worker" or path.startswith(".asdlc_worker/")
