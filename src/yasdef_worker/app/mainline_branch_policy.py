from __future__ import annotations

from yasdef_worker.infra.errors import GitOperationFailed, YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.prompts import Prompter
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
        work_is_ancestor = git.is_ancestor(branch_name, start_branch)
        start_is_ancestor = git.is_ancestor(start_branch, branch_name)
        if not (work_is_ancestor or start_is_ancestor):
            raise YasdefError(
                f"{operation} work branch {branch_name} has diverged from {start_branch}; "
                "merge or remove the existing work branch before retrying"
            )
        git.checkout(branch_name)
        if work_is_ancestor and not start_is_ancestor:
            try:
                git.merge_ff(start_branch)
            except GitOperationFailed as merge_exc:
                try:
                    git.checkout(start_branch)
                except GitOperationFailed as rollback_exc:
                    raise YasdefError(
                        f"{operation} failed to fast-forward {branch_name} to {start_branch}: "
                        f"{merge_exc}; rollback to {start_branch} also failed: {rollback_exc}"
                    ) from merge_exc
                raise YasdefError(
                    f"{operation} failed to fast-forward {branch_name} to {start_branch}; "
                    f"restored to {start_branch}: {merge_exc}"
                ) from merge_exc
            output.step(f"fast-forwarded existing branch: {branch_name} to {start_branch}")
        else:
            output.step(f"switched to existing branch: {branch_name}")
    else:
        git.checkout_new(branch_name)
        output.step(f"created and switched to branch: {branch_name}")
    return start_branch


def offer_merge_back(
    git: GitRepo,
    output: UserOutput,
    prompts: Prompter,
    *,
    work_branch: str,
    start_branch: str,
) -> None:
    """Interactively offer to fast-forward merge the work branch into start_branch.

    Default answer is no. On conflict or failure, print a reminder and leave the
    operator on the work branch. Non-interactive callers always get the reminder.
    """
    reminder = (
        f"yasdef finished on branch {work_branch}; "
        f"merge it back into {start_branch} when ready"
    )
    if not prompts.interactive:
        output.warn(reminder)
        return

    want_merge = prompts.confirm(
        f"Merge {work_branch} into {start_branch}?", default=False
    )
    if not want_merge:
        output.warn(reminder)
        return

    try:
        git.checkout(start_branch)
        git.merge_ff(work_branch)
        output.step(f"merged {work_branch} into {start_branch}")
    except GitOperationFailed as exc:
        output.warn(
            f"merge failed ({exc.op}: {exc.stderr or 'see git output above'}); "
            f"resolve manually — {reminder}"
        )
        try:
            git.checkout(work_branch)
        except GitOperationFailed:
            pass
