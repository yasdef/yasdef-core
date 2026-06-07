from __future__ import annotations

import argparse
from pathlib import Path

from yasdef_orchestrator.app.history_writer import HistoryWriter
from yasdef_orchestrator.app.metrics_collector import MetricsCollector
from yasdef_orchestrator.app.post_review import (
    PlanSyncOperation,
    PostReviewInput,
    PostReviewOperation,
    RetryPolicy,
    TokenUsageResolver,
)
from yasdef_orchestrator.infra.git_repo import GitRepo
from yasdef_orchestrator.infra.yaml_io import read_yaml_file

from ._shared import EXIT_SUCCESS, add_repo_argument, git_from_layout, layout_from_args, output, prompter


def add_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("post-review", help="write post-review history and sync plan")
    add_repo_argument(parser)
    parser.add_argument("--step", required=True, help="implementation-plan step number")
    parser.add_argument("--feature-id", required=True, help="feature directory/id")
    parser.add_argument("--title", required=True, help="step title for history.md")
    parser.add_argument("--step-plan", type=Path, default=None, help="step plan path")
    parser.add_argument("--no-plan-sync", action="store_true", help="skip source plan sync")
    parser.add_argument("--metrics-ref", default="HEAD", help="git ref/range for metrics collection")
    parser.add_argument(
        "--working-tree-metrics",
        action="store_true",
        help="collect unstaged working-tree metrics instead of cached metrics",
    )
    parser.set_defaults(handler=handle)


def handle(args: argparse.Namespace) -> int:
    layout = layout_from_args(args)
    git = git_from_layout(layout)
    user_output = output()
    sync = None
    if not args.no_plan_sync:
        source_plan = _default_source_plan(layout.binding_file, args.feature_id)
        sync = PlanSyncOperation(
            git=GitRepo(source_plan.parent.parent),
            source_plan_path=source_plan,
            output=user_output,
            retry=RetryPolicy(prompter(), user_output),
            step_number=args.step,
        )
    PostReviewOperation(
        layout=layout,
        git=git,
        history=HistoryWriter(layout),
        metrics=MetricsCollector(git),
        output=user_output,
        plan_sync=sync,
    ).execute(
        PostReviewInput(
            step=args.step,
            feature_id=args.feature_id,
            title=args.title,
            step_plan_path=args.step_plan
            or layout.step_plans_dir / f"step-{args.step}-{args.feature_id}.md",
            phase_usages=TokenUsageResolver.for_layout(layout).collect(step=args.step),
            metrics_ref=args.metrics_ref,
            metrics_cached=not args.working_tree_metrics,
        )
    )
    return EXIT_SUCCESS


def _default_source_plan(binding_file: Path, feature_id: str) -> Path:
    data = read_yaml_file(binding_file)
    source = Path(str(data.get("overmind_source_path") or "")).expanduser().resolve()
    return source / feature_id / "implementation_plan.md"
