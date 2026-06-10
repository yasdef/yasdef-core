from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .errors import YasdefError
from .yaml_io import read_yaml_file


@dataclass(frozen=True, slots=True)
class RuntimeLayout:
    worker_repo_root: Path
    asdlc_home: Path
    scripts_dir: Path
    helpers_dir: Path
    models_file: Path
    history_file: Path
    decisions_file: Path
    blocker_log_file: Path
    open_questions_file: Path
    user_review_file: Path
    binding_file: Path
    worker_binding_file: Path
    feature_sync_file: Path
    templates_dir: Path
    golden_examples_dir: Path
    logs_dir: Path
    step_designs_dir: Path
    step_plans_dir: Path
    step_open_questions_dir: Path
    step_blockers_dir: Path
    step_review_results_dir: Path
    overmind_dir: Path
    codex_skills_dir: Path
    claude_skills_dir: Path
    github_skills_dir: Path
    agents_skills_dir: Path
    claude_commands_dir: Path

    @classmethod
    def from_root(cls, worker_repo_root: Path | str) -> RuntimeLayout:
        root = Path(worker_repo_root).resolve()
        home = root / ".asdlc_worker"
        scripts = home / "scripts"
        return cls(
            worker_repo_root=root,
            asdlc_home=home,
            scripts_dir=scripts,
            helpers_dir=scripts / "helpers",
            models_file=home / "setup" / "models.md",
            history_file=home / "history.md",
            decisions_file=home / "decisions.md",
            blocker_log_file=home / "blocker_log.md",
            open_questions_file=home / "open_questions.md",
            user_review_file=home / "user_review.md",
            binding_file=home / "project_overmind.yaml",
            worker_binding_file=home / "asdlc_worker.yaml",
            feature_sync_file=home / "feature_meta_sync.yaml",
            templates_dir=home / "templates",
            golden_examples_dir=home / "golden_examples",
            logs_dir=home / "logs",
            step_designs_dir=home / "step_designs",
            step_plans_dir=home / "step_plans",
            step_open_questions_dir=home / "step_open_questions",
            step_blockers_dir=home / "step_blockers",
            step_review_results_dir=home / "step_review_results",
            overmind_dir=home / "overmind",
            codex_skills_dir=root / ".codex" / "skills",
            claude_skills_dir=root / ".claude" / "skills",
            github_skills_dir=root / ".github" / "skills",
            agents_skills_dir=root / ".agents" / "skills",
            claude_commands_dir=root / ".claude" / "commands" / "yasdef",
        )

    @classmethod
    def discover(cls, caller: Path | str | None = None) -> RuntimeLayout:
        start = Path(caller).resolve() if caller is not None else Path.cwd().resolve()
        if start.is_file():
            start = start.parent

        binding = _find_worker_binding(start)
        if binding is None:
            raise YasdefError(
                "failed to discover runtime layout: no .asdlc_worker/asdlc_worker.yaml found"
            )

        data = read_yaml_file(binding)
        root_value = data.get("worker_repo_root")
        if isinstance(root_value, str) and root_value.strip():
            return cls.from_root(root_value)
        return cls.from_root(binding.parent.parent)

    def skill_dirs(self) -> tuple[Path, ...]:
        return (
            self.codex_skills_dir,
            self.claude_skills_dir,
            self.github_skills_dir,
            self.agents_skills_dir,
        )

    def skill_path_candidates(self, skill_name: str, *parts: str) -> tuple[Path, ...]:
        return tuple(skill_dir / skill_name / Path(*parts) for skill_dir in self.skill_dirs())

    def existing_skill_path(self, skill_name: str, *parts: str) -> Path | None:
        for candidate in self.skill_path_candidates(skill_name, *parts):
            if candidate.is_file():
                return candidate
        return None


def _find_worker_binding(start: Path) -> Path | None:
    for directory in (start, *start.parents):
        candidate = directory / ".asdlc_worker" / "asdlc_worker.yaml"
        if candidate.exists():
            return candidate
    return None
