from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Literal, Protocol

from yasdef_worker.app.history_writer import HistoryWriter, total_usage
from yasdef_worker.app.metrics_collector import MetricsCollector
from yasdef_worker.domain.history.records import HistoryRecord
from yasdef_worker.domain.history.token_usage import TokenUsage
from yasdef_worker.infra.errors import GitOperationFailed, YasdefError
from yasdef_worker.infra.git_repo import GitRepo
from yasdef_worker.infra.layout import RuntimeLayout
from yasdef_worker.infra.log_capture import normalize_log_token
from yasdef_worker.infra.prompts import Prompter
from yasdef_worker.infra.user_output import UserOutput

RetryDecision = Literal["retry", "finish", "abort"]
DEFAULT_USAGE_PHASES = ("design", "planning", "implementation", "user_review", "ai_audit")


class SyncResult(str, Enum):
    OK = "ok"
    SKIPPED = "skipped"


@dataclass(frozen=True, slots=True)
class PlanSyncStep:
    name: str
    run: Callable[[], None]


class RetryPolicy:
    def __init__(
        self,
        prompts: Prompter,
        output: UserOutput,
        *,
        non_interactive_default: RetryDecision = "abort",
    ):
        self.prompts = prompts
        self.output = output
        self.non_interactive_default = non_interactive_default

    def on_failure(self, step: PlanSyncStep, err: Exception) -> RetryDecision:
        self.output.failure(f"plan sync step failed: {step.name}", detail=str(err))
        if not self.prompts.interactive:
            return self.non_interactive_default
        selected = self.prompts.choose_numbered(
            f"Plan sync step '{step.name}' failed. What next?",
            ["retry", "finish without sync", "abort"],
        )
        return ("retry", "finish", "abort")[selected]


class TokenUsageSource(Protocol):
    def usage_for(self, *, step: str, phase: str) -> TokenUsage | None:
        raise NotImplementedError


class LogTokenUsageSource:
    def __init__(self, *, layout: RuntimeLayout):
        self.layout = layout
        self.project = layout.worker_repo_root.name

    def usage_for(self, *, step: str, phase: str) -> TokenUsage | None:
        for candidate in self._candidate_paths(step, phase):
            try:
                content = candidate.read_bytes().decode("utf-8", errors="replace")
            except OSError:
                continue
            usage = TokenUsage.parse(content)
            if usage is not None:
                return usage
        return None

    def _candidate_paths(self, step: str, phase: str) -> tuple[Path, ...]:
        phase_token = normalize_log_token(phase)
        step_token = normalize_log_token(step)
        return (
            self.layout.logs_dir / f"{self.project}-{phase_token}-latest-log",
            self.layout.logs_dir / f"{self.project}-{phase_token}-{step_token}-log",
        )


class HistoryTokenUsageSource:
    def __init__(self, *, history_path: Path):
        self.history_path = history_path

    def usage_for(self, *, step: str, phase: str) -> TokenUsage | None:
        try:
            content = self.history_path.read_text(encoding="utf-8")
        except OSError:
            return None
        latest: TokenUsage | None = None
        for section in _history_sections(content):
            if _section_step(section) != step:
                continue
            usage = _section_phase_usage(section, phase)
            if usage is not None:
                latest = usage
        return latest


class TokenUsageResolver:
    def __init__(self, sources: tuple[TokenUsageSource, ...]):
        self.sources = sources

    @classmethod
    def for_layout(cls, layout: RuntimeLayout) -> TokenUsageResolver:
        return cls(
            (
                LogTokenUsageSource(layout=layout),
                HistoryTokenUsageSource(history_path=layout.history_file),
            )
        )

    def collect(
        self,
        *,
        step: str,
        phases: tuple[str, ...] = DEFAULT_USAGE_PHASES,
    ) -> tuple[tuple[str, TokenUsage], ...]:
        usages: list[tuple[str, TokenUsage]] = []
        for phase in phases:
            usage = self.usage_for(step=step, phase=phase)
            if usage is not None:
                usages.append((phase, usage))
        return tuple(usages)

    def usage_for(self, *, step: str, phase: str) -> TokenUsage | None:
        for source in self.sources:
            usage = source.usage_for(step=step, phase=phase)
            if usage is not None:
                return usage
        return None


class PlanSyncOperation:
    def __init__(
        self,
        *,
        git: GitRepo,
        source_plan_path: Path,
        output: UserOutput,
        retry: RetryPolicy,
        step_number: str,
    ):
        self.git = git
        self.source_plan_path = source_plan_path
        self.output = output
        self.retry = retry
        self.step_number = step_number

    def execute(self) -> SyncResult:
        for step in (
            PlanSyncStep("stage", self._stage),
            PlanSyncStep("rebase", self.git.pull_rebase),
            PlanSyncStep("push", self.git.push),
        ):
            while True:
                try:
                    step.run()
                    break
                except GitOperationFailed as exc:
                    decision = self.retry.on_failure(step, exc)
                    if decision == "retry":
                        continue
                    if decision == "finish":
                        return SyncResult.SKIPPED
                    raise
        return SyncResult.OK

    def _stage(self) -> None:
        rel = self._source_plan_relpath()
        self.git.add(rel)
        if self.git.diff_name_only(cached=True):
            self.git.commit(f"Post-review sync: step {self.step_number} implementation plan")
            self.output.step(f"committed source plan update for step {self.step_number}")
        else:
            self.output.step(f"no source plan changes to commit for step {self.step_number}")

    def _source_plan_relpath(self) -> str:
        source_plan = self.source_plan_path.resolve()
        git_root = self.git.root.resolve()
        try:
            return str(source_plan.relative_to(git_root))
        except ValueError as exc:
            raise YasdefError(
                "source implementation_plan.md is not inside the inferred ASDLC source git root.\n"
                f"Tried source plan: {source_plan}\n"
                f"Inferred git root: {git_root}\n"
                "post-review plan sync expects the bound ASDLC source layout "
                "<overmind_source_path>/<feature_id>/implementation_plan.md, "
                "and infers the git root as the parent of the feature directory.\n"
                "Check .asdlc_worker/project_overmind.yaml and the bound ASDLC repo layout, "
                "then rerun post-review."
            ) from exc


@dataclass(frozen=True, slots=True)
class PostReviewInput:
    step: str
    feature_id: str
    title: str
    step_plan_path: Path
    phase_usages: tuple[tuple[str, TokenUsage], ...] = ()
    metrics_ref: str | None = "HEAD"
    metrics_cached: bool = True


class PostReviewOperation:
    def __init__(
        self,
        *,
        layout: RuntimeLayout,
        git: GitRepo,
        history: HistoryWriter,
        metrics: MetricsCollector,
        output: UserOutput,
        plan_sync: PlanSyncOperation | None = None,
    ):
        self.layout = layout
        self.git = git
        self.history = history
        self.metrics = metrics
        self.output = output
        self.plan_sync = plan_sync

    def execute(self, review: PostReviewInput) -> HistoryRecord:
        artifact = self.layout.step_review_results_dir / f"review_result-{review.step}-{review.feature_id}.md"
        if not artifact.is_file():
            raise YasdefError(f"cannot start post_review: missing review artifact {artifact}")

        collected_metrics = self.metrics.collect(review.metrics_ref, cached=review.metrics_cached)
        record = HistoryRecord(
            step=review.step,
            title=review.title,
            step_plan=str(review.step_plan_path),
            token_usage=total_usage(review.phase_usages),
            metrics=collected_metrics,
            phase_usages=review.phase_usages,
        )
        self.history.write_record(record)
        self.output.step(f"updated history for step {review.step}")
        if self.plan_sync is not None:
            self.plan_sync.execute()
        return record


def _history_sections(content: str) -> tuple[str, ...]:
    sections: list[str] = []
    current: list[str] | None = None
    for line in content.splitlines():
        if line.startswith("## "):
            if current is not None:
                sections.append("\n".join(current))
            current = [line]
        elif current is not None:
            current.append(line)
    if current is not None:
        sections.append("\n".join(current))
    return tuple(sections)


def _section_step(section: str) -> str | None:
    for line in section.splitlines():
        if line.startswith("- Step: "):
            return line.removeprefix("- Step: ").strip().split(" ", 1)[0]
    return None


def _section_phase_usage(section: str, phase: str) -> TokenUsage | None:
    phase_prefix = f"  - Phase: {phase} - "
    for line in section.splitlines():
        if line.startswith(phase_prefix):
            return TokenUsage.parse(f"Token usage: {line.removeprefix(phase_prefix)}")
    return None
