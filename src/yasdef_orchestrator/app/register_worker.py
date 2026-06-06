from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from yasdef_orchestrator.domain.workers_registry import WorkerMatch, resolve_single_worker_match
from yasdef_orchestrator.infra.errors import YasdefError
from yasdef_orchestrator.infra.git_repo import GitRepo
from yasdef_orchestrator.infra.layout import RuntimeLayout
from yasdef_orchestrator.infra.user_output import UserOutput
from yasdef_orchestrator.infra.yaml_io import read_yaml_file, write_yaml_file

RUNTIME_BRANCH = "overmind"


@dataclass(frozen=True, slots=True)
class RegisterWorkerInput:
    worker_uuid: str
    overmind_source_path: Path


@dataclass(frozen=True, slots=True)
class RegisterWorkerResult:
    binding_file: Path
    runtime_branch: str
    project_id: str
    worker_uuid: str
    worker_match: WorkerMatch


class RegisterWorkerOperation:
    def __init__(
        self,
        *,
        layout: RuntimeLayout,
        git: GitRepo,
        output: UserOutput,
    ):
        self.layout = layout
        self.git = git
        self.output = output

    def execute(self, request: RegisterWorkerInput) -> RegisterWorkerResult:
        worker_uuid = request.worker_uuid.strip()
        if not worker_uuid:
            raise YasdefError("worker UUID must not be empty")
        source_path = request.overmind_source_path.expanduser().resolve()
        if not source_path.is_dir():
            raise YasdefError(f"overmind repo path is not a directory: {source_path}")

        project_id = _read_project_id(source_path)
        worker_match = resolve_single_worker_match(read_yaml_file(source_path / "workers.yaml"), worker_uuid)
        self._warn_missing_agents_guidance(source_path, worker_match)
        self._ensure_runtime_branch()
        self._write_binding(source_path, project_id, worker_uuid, worker_match)
        self._commit_binding_if_changed(worker_uuid, project_id)
        self.output.step("worker registration complete")
        return RegisterWorkerResult(
            binding_file=self.layout.binding_file,
            runtime_branch=RUNTIME_BRANCH,
            project_id=project_id,
            worker_uuid=worker_uuid,
            worker_match=worker_match,
        )

    def _ensure_runtime_branch(self) -> None:
        if not self.git.is_inside_worktree():
            raise YasdefError("worker registration requires a git repository")
        if self.git.current_branch() == RUNTIME_BRANCH:
            return
        if self.git.status_porcelain().strip():
            raise YasdefError("uncommitted changes detected, commit changes and rerun")
        if self.git.branch_exists(RUNTIME_BRANCH):
            self.git.checkout(RUNTIME_BRANCH)
        else:
            self.git.checkout_new(RUNTIME_BRANCH)

    def _write_binding(
        self,
        source_path: Path,
        project_id: str,
        worker_uuid: str,
        worker_match: WorkerMatch,
    ) -> None:
        self.layout.binding_file.parent.mkdir(parents=True, exist_ok=True)
        write_yaml_file(
            self.layout.binding_file,
            {
                "overmind_source_path": str(source_path),
                "project_id": project_id,
                "worker_uuid": worker_uuid,
                "class": worker_match.worker_class,
                "status": worker_match.status,
            },
        )

    def _commit_binding_if_changed(self, worker_uuid: str, project_id: str) -> None:
        rel = str(self.layout.binding_file.relative_to(self.layout.worker_repo_root))
        self.git.add(rel)
        if not self.git.diff_name_only(cached=True):
            return
        self.git.commit(f"Bind worker {worker_uuid} to ASDLC project {project_id}")

    def _warn_missing_agents_guidance(self, source_path: Path, worker_match: WorkerMatch) -> None:
        if (self.layout.worker_repo_root / "AGENTS.md").is_file():
            return
        blueprint = source_path / f"project_stack_blueprint_{worker_match.worker_class}.md"
        if blueprint.is_file():
            self.output.warn(f"create AGENTS.md using {blueprint}")
        else:
            self.output.warn("create AGENTS.md before implementation work")


def _read_project_id(source_path: Path) -> str:
    definition = source_path / "init_progress_definition.yaml"
    if not definition.is_file():
        raise YasdefError(f"project repo is missing init_progress_definition.yaml: {source_path}")
    data = read_yaml_file(definition)
    meta = data.get("meta_info")
    if isinstance(meta, dict):
        project_id = str(meta.get("project_id") or "").strip()
    else:
        project_id = str(data.get("project_id") or "").strip()
    if not project_id:
        raise YasdefError("meta_info.project_id is missing or empty")
    return project_id
