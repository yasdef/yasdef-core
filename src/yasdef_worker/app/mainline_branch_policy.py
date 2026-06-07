from __future__ import annotations

from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.user_output import UserOutput

MAINLINE_BRANCHES = ("main", "master")


def require_clean_mainline_start(git: GitRepo, *, operation: str) -> str:
    if not git.is_inside_worktree():
        raise YasdefError(f"{operation} requires a git repository")
    current = git.current_branch()
    if current not in MAINLINE_BRANCHES:
        branch = current if current is not None else "detached HEAD"
        raise YasdefError(f"{operation} must start from main or master (current branch: {branch})")
    if git.status_porcelain().strip():
        raise YasdefError(f"{operation} requires a clean working tree before creating a work branch")
    return current


def checkout_work_branch(
    git: GitRepo,
    output: UserOutput,
    *,
    operation: str,
    branch_name: str,
) -> str:
    start_branch = require_clean_mainline_start(git, operation=operation)
    if git.branch_exists(branch_name):
        git.checkout(branch_name)
        output.step(f"switched to existing branch: {branch_name}")
    else:
        git.checkout_new(branch_name)
        output.step(f"created and switched to branch: {branch_name}")
    return start_branch
