from __future__ import annotations

from dataclasses import dataclass

from yasdef_worker.domain.branches import (
    BranchSpec,
    ai_audit_branch_spec,
    implementation_branch_spec,
    step_branch_name,
    user_review_branch_spec,
)
from yasdef_worker.infra.errors import PhasePreconditionError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.user_output import UserOutput


@dataclass(slots=True)
class BranchManager:
    git: GitRepo
    output: UserOutput

    def ensure_plan_branch(self, *, step: str, feature_id: str) -> str:
        target = step_branch_name(step, feature_id, "planning")
        self.ensure_branch(BranchSpec(target=target), phase="planning")
        return target

    def ensure_implementation_branch(self, *, step: str, feature_id: str) -> str:
        spec = implementation_branch_spec(step, feature_id)
        self.ensure_branch(spec, phase="implementation")
        return spec.target

    def ensure_user_review_branch(self, *, step: str, feature_id: str) -> str:
        spec = user_review_branch_spec(step, feature_id)
        self.ensure_branch(spec, phase="user_review")
        return spec.target

    def ensure_ai_audit_branch(self, *, step: str, feature_id: str) -> str:
        spec = ai_audit_branch_spec(step, feature_id)
        self.ensure_branch(spec, phase="ai_audit")
        return spec.target

    def ensure_branch(self, spec: BranchSpec, *, phase: str) -> None:
        if not self.git.is_inside_worktree():
            raise PhasePreconditionError(phase, "phase execution requires a git repository")

        current = self.git.current_branch()
        if current == spec.target:
            return

        if spec.source_required:
            self._prepare_required_source(spec, phase=phase, current=current)

        if self.git.branch_exists(spec.target):
            self.git.checkout(spec.target)
            self.output.step(f"switched to existing branch: {spec.target}")
            return

        self.git.checkout_new(spec.target)
        if spec.source_branch:
            self.output.step(f"created and switched to branch: {spec.target} from {spec.source_branch}")
        else:
            self.output.step(f"created and switched to branch: {spec.target}")

    def _prepare_required_source(
        self,
        spec: BranchSpec,
        *,
        phase: str,
        current: str | None,
    ) -> None:
        source = spec.source_branch
        if source is None:
            raise PhasePreconditionError(phase, "source branch is required but was not specified")
        if not self.git.branch_exists(source):
            raise PhasePreconditionError(phase, f"required source branch not found: {source}")
        if current == source:
            return
        if spec.source_dirty_check and self.git.status_porcelain(untracked="no").strip():
            raise PhasePreconditionError(
                phase,
                f"working tree must be clean before switching to source branch {source}",
            )
        self.git.checkout(source)
        self.output.step(f"switched to source branch: {source}")
