from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from yasdef_worker.app.mainline_branch_policy import checkout_work_branch, offer_merge_back
from yasdef_worker.domain.workers_registry import (
    WorkerMatch,
    WorkersRegistryError,
    resolve_single_worker_match,
)
from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.user_output import UserOutput
from yasdef_worker.infra.yaml_io import read_yaml_file, write_yaml_file

REGISTER_BRANCH = "register_yasdef_worker_in_coordinator"


@dataclass(frozen=True, slots=True)
class RegisterWorkerResult:
    binding_file: Path
    register_branch: str
    project_id: str
    worker_uuid: str
    worker_match: WorkerMatch
    start_branch: str


class RegisterWorkerOperation:
    def __init__(
        self,
        *,
        layout: RuntimeLayout,
        git: GitRepo,
        output: UserOutput,
        prompts: Prompter | None = None,
    ):
        self.layout = layout
        self.git = git
        self.output = output
        self.prompts = prompts or Prompter(interactive=False)

    def execute(self) -> RegisterWorkerResult:
        start_branch = self._ensure_register_branch()
        source_path = self._prompt_asdlc_project_repo_path()
        project_id = _read_project_id(source_path)
        worker_uuid = self._prompt_worker_uuid()
        worker_match = _resolve_worker_match(source_path, worker_uuid)
        self._warn_missing_agents_guidance(source_path, worker_match)
        self._write_binding(source_path, project_id, worker_uuid, worker_match)
        self._commit_binding_if_changed(worker_uuid, project_id)
        self.output.step("worker registration complete")
        offer_merge_back(
            self.git,
            self.output,
            self.prompts,
            work_branch=REGISTER_BRANCH,
            start_branch=start_branch,
        )
        return RegisterWorkerResult(
            binding_file=self.layout.binding_file,
            register_branch=REGISTER_BRANCH,
            project_id=project_id,
            worker_uuid=worker_uuid,
            worker_match=worker_match,
            start_branch=start_branch,
        )

    def _prompt_asdlc_project_repo_path(self) -> Path:
        raw_path = self.prompts.prompt_non_empty(
            "Enter ASDLC project path (folder with workers.yaml): "
        )
        source_path = Path(raw_path).expanduser()
        if not source_path.exists():
            raise YasdefError(f"ASDLC project path not found: {source_path}")
        if not source_path.is_dir():
            raise YasdefError(f"ASDLC project path is not a directory: {source_path}")
        resolved = source_path.resolve()
        workers_file = resolved / "workers.yaml"
        if not workers_file.is_file():
            raise YasdefError(f"ASDLC project path does not contain workers.yaml: {resolved}")
        definition = resolved / "init_progress_definition.yaml"
        if not definition.is_file():
            raise YasdefError(f"ASDLC project path is missing init_progress_definition.yaml: {resolved}")
        return resolved

    def _prompt_worker_uuid(self) -> str:
        return self.prompts.prompt_non_empty("Enter worker UUID: ")

    def _ensure_register_branch(self) -> str:
        return checkout_work_branch(
            self.git,
            self.output,
            operation="yasdef register",
            branch_name=REGISTER_BRANCH,
        )

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
    data = read_yaml_file(definition)
    meta = data.get("meta_info")
    if isinstance(meta, dict):
        project_id = str(meta.get("project_id") or "").strip()
    else:
        project_id = ""
    if not project_id:
        raise YasdefError("meta_info.project_id is missing or empty")
    return project_id


def _resolve_worker_match(source_path: Path, worker_uuid: str) -> WorkerMatch:
    try:
        return resolve_single_worker_match(read_yaml_file(source_path / "workers.yaml"), worker_uuid)
    except WorkersRegistryError as exc:
        raise YasdefError(str(exc)) from exc
