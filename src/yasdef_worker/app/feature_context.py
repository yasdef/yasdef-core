from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from yasdef_worker.domain.plans.feature_selector import analyze_for_worker
from yasdef_worker.domain.plans.implementation_plan import ImplementationPlan
from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.user_output import UserOutput
from yasdef_worker.infra.yaml_io import read_yaml_file, write_yaml_file

SelectionMode = Literal["resume_reuse", "auto_single", "user_prompt"]


@dataclass(frozen=True, slots=True)
class ProjectBinding:
    overmind_source_path: Path
    project_id: str
    worker_uuid: str
    worker_class: str
    worker_status: str


@dataclass(frozen=True, slots=True)
class FeatureRunState:
    binding: ProjectBinding
    feature_id: str
    feature_path: Path
    source_plan_path: Path
    source_ears_path: Path
    step: str
    selection_mode: SelectionMode

    @property
    def worker_uuid(self) -> str:
        return self.binding.worker_uuid


@dataclass(frozen=True, slots=True)
class _Candidate:
    feature_id: str
    feature_path: Path
    source_plan_path: Path
    source_ears_path: Path
    step: str


@dataclass(frozen=True, slots=True)
class _Discovery:
    candidates: tuple[_Candidate, ...]
    assigned_any: bool
    blocked_by: str | None


class FeatureContextBuilder:
    def __init__(
        self,
        *,
        layout: RuntimeLayout,
        git: GitRepo,
        prompts: Prompter,
        output: UserOutput,
        resume_step: str | None = None,
    ):
        self.layout = layout
        self.git = git
        self.prompts = prompts
        self.output = output
        self.resume_step = resume_step
        self._built = False
        self._candidate_cache: tuple[_Candidate, ...] = ()

    def build(self) -> FeatureRunState:
        if self._built:
            raise YasdefError("feature context builder cannot be reused")
        self._built = True

        binding = self._load_binding()
        reused = self._try_fast_path(binding)
        if reused is not None and (self.resume_step is not None or not self.prompts.interactive):
            self._write_meta_sync(reused)
            self.output.step(
                f"selected feature '{reused.feature_id}' "
                f"(mode={reused.selection_mode}, project={binding.project_id}, step={reused.step})"
            )
            return reused

        self._validate_runtime_git()
        candidate = self._select_candidate(binding)
        state = FeatureRunState(
            binding=binding,
            feature_id=candidate.feature_id,
            feature_path=candidate.feature_path,
            source_plan_path=candidate.source_plan_path,
            source_ears_path=candidate.source_ears_path,
            step=candidate.step,
            selection_mode="auto_single",
        )
        if len(self._candidate_cache) > 1:
            state = FeatureRunState(
                binding=state.binding,
                feature_id=state.feature_id,
                feature_path=state.feature_path,
                source_plan_path=state.source_plan_path,
                source_ears_path=state.source_ears_path,
                step=state.step,
                selection_mode="user_prompt",
            )
        self._write_meta_sync(state)
        self.output.step(
            f"selected feature '{state.feature_id}' "
            f"(mode={state.selection_mode}, project={binding.project_id}, step={state.step})"
        )
        return state

    def _load_binding(self) -> ProjectBinding:
        if not self.layout.binding_file.is_file():
            raise YasdefError(f"required binding file is missing: {self.layout.binding_file}")
        data = read_yaml_file(self.layout.binding_file)
        overmind_source_path = _required_str(data, "overmind_source_path")
        project_id = _required_str(data, "project_id")
        worker_uuid = _required_str(data, "worker_uuid")
        source_path = Path(overmind_source_path).expanduser().resolve()
        if not source_path.is_dir():
            raise YasdefError(f"bound overmind project repo does not exist: {source_path}")
        _validate_project_id(source_path, project_id)
        return ProjectBinding(
            overmind_source_path=source_path,
            project_id=project_id,
            worker_uuid=worker_uuid,
            worker_class=str(data.get("class") or "").strip(),
            worker_status=str(data.get("status") or "").strip(),
        )

    def _try_fast_path(self, binding: ProjectBinding) -> FeatureRunState | None:
        data = self._current_feature_metadata(binding)
        if data is None:
            return None
        feature_id = str(data.get("feature_id") or "").strip()
        if not feature_id:
            return None
        feature_path = binding.overmind_source_path / feature_id
        source_plan = feature_path / "implementation_plan.md"
        source_ears = feature_path / "requirements_ears.md"
        if not _usable_feature_files(source_plan, source_ears):
            return None

        plan = ImplementationPlan.parse(source_plan.read_text(encoding="utf-8"), source_name=str(source_plan))
        if self.resume_step is not None:
            step = self.resume_step
            plan_step = plan.step(step)
            if plan_step is None or plan_step.assigned_uuid != binding.worker_uuid:
                return None
        else:
            selected_step = str(data.get("selected_step") or "").strip()
            analysis = analyze_for_worker(plan, binding.worker_uuid)
            step = analysis.first_unchecked or selected_step
            if not step:
                return None

        return FeatureRunState(
            binding=binding,
            feature_id=feature_id,
            feature_path=feature_path,
            source_plan_path=source_plan,
            source_ears_path=source_ears,
            step=step,
            selection_mode="resume_reuse",
        )

    def _current_feature_id(self, binding: ProjectBinding) -> str | None:
        data = self._current_feature_metadata(binding)
        if data is None:
            return None
        feature_id = str(data.get("feature_id") or "").strip()
        return feature_id or None

    def _current_feature_metadata(self, binding: ProjectBinding) -> dict[str, object] | None:
        if not self.layout.feature_sync_file.is_file():
            return None
        data = read_yaml_file(self.layout.feature_sync_file)
        if str(data.get("project_id") or "") != binding.project_id:
            return None
        if str(data.get("worker_uuid") or "") != binding.worker_uuid:
            return None
        return data

    def _validate_runtime_git(self) -> None:
        if not self.git.is_inside_worktree():
            raise YasdefError("feature routing requires a git repository")

    def _select_candidate(self, binding: ProjectBinding) -> _Candidate:
        discovery = self._find_candidates(binding)
        self._candidate_cache = _order_candidates(discovery.candidates, self._current_feature_id(binding))
        if not self._candidate_cache:
            if discovery.blocked_by is not None:
                raise YasdefError(
                    f"Next possible assigned step for your worker {binding.worker_uuid} "
                    f"is blocked by step '{discovery.blocked_by}' under project "
                    f"'{binding.project_id}'"
                )
            if not discovery.assigned_any:
                raise YasdefError(
                    f"no assigned steps for worker UUID '{binding.worker_uuid}' "
                    f"under project '{binding.project_id}'"
                )
            raise YasdefError(
                f"no candidate features under project '{binding.project_id}' "
                f"for worker UUID '{binding.worker_uuid}'"
            )
        if len(self._candidate_cache) == 1:
            return self._candidate_cache[0]
        current_feature_id = self._current_feature_id(binding)
        selected = self.prompts.choose_numbered(
            "Select feature",
            [
                _candidate_label(candidate, current_feature_id)
                for candidate in self._candidate_cache
            ],
        )
        return self._candidate_cache[selected]

    def _find_candidates(self, binding: ProjectBinding) -> _Discovery:
        candidates: list[_Candidate] = []
        assigned_any = False
        blocked_by: str | None = None
        for feature_path in sorted(path for path in binding.overmind_source_path.iterdir() if path.is_dir()):
            if feature_path.name == ".git":
                continue
            source_plan = feature_path / "implementation_plan.md"
            source_ears = feature_path / "requirements_ears.md"
            if not _usable_feature_files(source_plan, source_ears):
                continue
            plan = ImplementationPlan.parse(
                source_plan.read_text(encoding="utf-8"),
                source_name=str(source_plan),
            )
            analysis = analyze_for_worker(plan, binding.worker_uuid, self.resume_step)
            assigned_any = assigned_any or analysis.assigned_any
            if analysis.blocked_by is not None and blocked_by is None:
                blocked_by = analysis.blocked_by
            if self.resume_step is not None:
                if analysis.target_match:
                    candidates.append(
                        _Candidate(
                            feature_path.name,
                            feature_path,
                            source_plan,
                            source_ears,
                            self.resume_step,
                        )
                    )
            elif analysis.first_unchecked is not None:
                candidates.append(
                    _Candidate(
                        feature_path.name,
                        feature_path,
                        source_plan,
                        source_ears,
                        analysis.first_unchecked,
                    )
                )
        return _Discovery(tuple(candidates), assigned_any, blocked_by)

    def _write_meta_sync(self, state: FeatureRunState) -> None:
        self.layout.feature_sync_file.parent.mkdir(parents=True, exist_ok=True)
        write_yaml_file(
            self.layout.feature_sync_file,
            {
                "project_id": state.binding.project_id,
                "worker_uuid": state.binding.worker_uuid,
                "feature_id": state.feature_id,
                "selected_step": state.step,
            },
        )


def _required_str(data: dict[str, object], key: str) -> str:
    value = str(data.get(key) or "").strip()
    if not value:
        raise YasdefError(f"binding file is invalid: missing {key}")
    return value


def _usable_feature_files(source_plan: Path, source_ears: Path) -> bool:
    return (
        source_plan.is_file()
        and source_ears.is_file()
        and bool(source_ears.read_text(encoding="utf-8").strip())
    )


def _validate_project_id(source_path: Path, expected_project_id: str) -> None:
    definition = source_path / "init_progress_definition.yaml"
    if not definition.is_file():
        raise YasdefError(f"bound overmind project repo is missing init_progress_definition.yaml: {source_path}")
    data = read_yaml_file(definition)
    meta = data.get("meta_info")
    if isinstance(meta, dict):
        actual = str(meta.get("project_id") or "").strip()
    else:
        actual = str(data.get("project_id") or "").strip()
    if not actual:
        raise YasdefError("init_progress_definition.yaml is missing project_id")
    if actual != expected_project_id:
        raise YasdefError(
            f"bound project_id '{expected_project_id}' does not match "
            f"init_progress_definition.yaml project_id '{actual}'"
        )


def _order_candidates(
    candidates: tuple[_Candidate, ...],
    current_feature_id: str | None,
) -> tuple[_Candidate, ...]:
    if current_feature_id is None:
        return candidates
    current = tuple(candidate for candidate in candidates if candidate.feature_id == current_feature_id)
    others = tuple(candidate for candidate in candidates if candidate.feature_id != current_feature_id)
    return current + others


def _candidate_label(candidate: _Candidate, current_feature_id: str | None) -> str:
    if candidate.feature_id == current_feature_id:
        return f"{candidate.feature_id} (current)"
    return candidate.feature_id
