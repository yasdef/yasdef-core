from __future__ import annotations

import os
import subprocess
import tempfile
from contextlib import AbstractContextManager, suppress
from dataclasses import dataclass
from pathlib import Path
from types import TracebackType

from .errors import GitOperationFailed


@dataclass(frozen=True, slots=True)
class NumstatRow:
    added: int | None
    deleted: int | None
    path: str


class GitRepo:
    def __init__(self, root: Path | str, *, env: dict[str, str] | None = None):
        self.root = Path(root)
        self.env = dict(env or {})

    def current_branch(self) -> str | None:
        result = self._run(["branch", "--show-current"], check=False)
        branch = result.stdout.strip()
        return branch or None

    def branch_exists(self, name: str) -> bool:
        return self._run(["show-ref", "--verify", "--quiet", f"refs/heads/{name}"], check=False).returncode == 0

    def is_inside_worktree(self) -> bool:
        result = self._run(["rev-parse", "--is-inside-work-tree"], check=False)
        return result.returncode == 0 and result.stdout.strip() == "true"

    def is_detached(self) -> bool:
        return self.current_branch() is None

    def merge_base(self, a: str, b: str) -> str | None:
        result = self._run(["merge-base", a, b], check=False)
        return result.stdout.strip() if result.returncode == 0 else None

    def is_ancestor(self, ancestor: str, descendant: str) -> bool:
        return self._run(["merge-base", "--is-ancestor", ancestor, descendant], check=False).returncode == 0

    def status_porcelain(self, *, untracked: str = "all") -> str:
        return self._run(["status", "--porcelain", f"--untracked-files={untracked}"]).stdout

    def show_ref_exists(self, ref: str) -> bool:
        return self._run(["show-ref", "--verify", "--quiet", ref], check=False).returncode == 0

    def diff_numstat(self, range_or_cached: str | None = None, *, cached: bool = False) -> list[NumstatRow]:
        argv = ["diff", "--numstat"]
        if cached:
            argv.append("--cached")
        if range_or_cached:
            argv.append(range_or_cached)
        rows: list[NumstatRow] = []
        for line in self._run(argv).stdout.splitlines():
            added, deleted, path = line.split("\t", 2)
            rows.append(NumstatRow(_parse_numstat_int(added), _parse_numstat_int(deleted), path))
        return rows

    def diff_name_only(
        self,
        range_or_cached: str | None = None,
        *,
        cached: bool = False,
        diff_filter: str | None = None,
    ) -> list[str]:
        argv = ["diff", "--name-only"]
        if cached:
            argv.append("--cached")
        if diff_filter:
            argv.append(f"--diff-filter={diff_filter}")
        if range_or_cached:
            argv.append(range_or_cached)
        output = self._run(argv).stdout
        return [line for line in output.splitlines() if line]

    def checkout(self, name: str) -> None:
        self._run(["checkout", name], op="checkout")

    def checkout_new(self, name: str) -> None:
        self._run(["checkout", "-b", name], op="checkout")

    def add(self, *paths: str) -> None:
        self._run(["add", *paths], op="add")

    def commit(self, message: str, *, paths: list[str] | None = None) -> None:
        if paths:
            self.add(*paths)
        self._run(["commit", "-m", message], op="commit")

    def push(self) -> None:
        self._run(["push"], op="push")

    def pull_rebase(self) -> None:
        self._run(["pull", "--rebase"], op="pull --rebase")

    def rebase(self, onto: str, *, autostash: bool = True) -> None:
        argv = ["rebase"]
        if autostash:
            argv.append("--autostash")
        argv.append(onto)
        self._run(argv, op="rebase")

    def with_snapshot_index(self) -> AbstractContextManager[GitRepo]:
        return _SnapshotIndex(self)

    def _run(
        self,
        args: list[str],
        *,
        check: bool = True,
        op: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        argv = ["git", "-C", str(self.root), *args]
        env = os.environ.copy()
        env.update(self.env)
        completed = subprocess.run(argv, text=True, capture_output=True, env=env, check=False)
        if check and completed.returncode != 0:
            raise GitOperationFailed(op or args[0], argv, completed.returncode, completed.stderr.strip())
        return completed


class _SnapshotIndex(AbstractContextManager[GitRepo]):
    def __init__(self, repo: GitRepo):
        self.repo = repo
        self._tmp_name: str | None = None

    def __enter__(self) -> GitRepo:
        tmp = tempfile.NamedTemporaryFile(prefix="yasdef-git-index-", delete=False)
        tmp.close()
        self._tmp_name = tmp.name
        env = dict(self.repo.env)
        env["GIT_INDEX_FILE"] = self._tmp_name
        snapshot = GitRepo(self.repo.root, env=env)
        snapshot._run(["read-tree", "HEAD"], op="read-tree")
        return snapshot

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> bool | None:
        if self._tmp_name is not None:
            with suppress(FileNotFoundError):
                Path(self._tmp_name).unlink()
        return None


def _parse_numstat_int(value: str) -> int | None:
    if value == "-":
        return None
    return int(value)
