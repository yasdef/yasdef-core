"""Materialize an approved project AGENTS.md/CLAUDE.md bootstrap decision.

Runs before the scaffold implementation model starts (implementation preflight),
so the implementation session can load the generated guidance at startup and a
resume after a failed materialization still installs it.
"""
from __future__ import annotations

import contextlib
import os
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from yasdef_worker.domain.plans.step_design import (
    BootstrapGuidanceDecision,
    guidance_decision_errors,
    parse_bootstrap_guidance,
)
from yasdef_worker.domain.worker_class import filename_matches_class, normalize_worker_class
from yasdef_worker.infra.errors import YasdefError
from yasdef_worker.infra.files import atomic_write_bytes, merge_exclude_entries
from yasdef_worker.infra.user_output import UserOutput
from yasdef_worker.infra.yaml_io import read_yaml_file

GUIDANCE_FILENAMES: tuple[str, ...] = ("AGENTS.md", "CLAUDE.md")
GUIDANCE_ARTIFACT_GLOB = "project_agents_md_claude_md_*.md"
BACKUP_ROOT_REL = Path(".asdlc_worker") / "agent_guidance_backups"
BACKUP_EXCLUDE_ENTRY = ".asdlc_worker/agent_guidance_backups"


@dataclass(frozen=True, slots=True)
class GuidanceOutcome:
    disposition: str
    written: tuple[Path, ...] = ()
    backup_dir: Path | None = None

    @property
    def wrote_files(self) -> bool:
        return bool(self.written)


def materialize_for_feature(
    *,
    design_file: Path,
    worker_root: Path,
    source_plan_path: Path,
    binding_file: Path,
    output: UserOutput,
) -> GuidanceOutcome:
    """Resolve project root and worker class from the feature context, then materialize.

    The bound project folder is the parent of the feature folder that holds the
    runtime implementation plan.
    """
    worker_class = ""
    if binding_file.is_file():
        worker_class = normalize_worker_class(str(read_yaml_file(binding_file).get("class") or ""))
    return materialize_agent_guidance(
        design_file=design_file,
        worker_root=worker_root,
        project_root=source_plan_path.parent.parent,
        worker_class=worker_class,
        output=output,
    )


def materialize_agent_guidance(
    *,
    design_file: Path,
    worker_root: Path,
    project_root: Path,
    worker_class: str,
    output: UserOutput,
) -> GuidanceOutcome:
    """Install the approved knowledgebase artifact as both project-root guidance files.

    Performs no write for a non-bootstrap design, `both-present-no-action`, or
    `leave-unchanged-declined`.
    """
    if not design_file.is_file():
        return GuidanceOutcome(disposition="")

    decision = parse_bootstrap_guidance(design_file.read_text(encoding="utf-8"))
    if decision is None:
        return GuidanceOutcome(disposition="")

    errors = guidance_decision_errors(decision)
    if errors:
        raise YasdefError(
            "bootstrap design records an unusable agent-guidance decision:\n"
            + "\n".join(f"- {error}" for error in errors)
        )
    if not decision.regenerate_approved:
        return GuidanceOutcome(disposition=decision.disposition)

    source = _resolve_source(decision, project_root=project_root, worker_class=worker_class)
    payload = source.read_bytes()

    destinations = tuple(worker_root / name for name in GUIDANCE_FILENAMES)
    _refuse_directories(destinations)

    existing = tuple(dest for dest in destinations if dest.is_symlink() or dest.exists())
    backup_dir = _create_backup(worker_root, existing) if existing else None
    # Exclude the backup before touching any root path so a later pair-write
    # failure cannot leave a retained recovery copy visible to git staging.
    if backup_dir is not None:
        _exclude_backup_root(worker_root, output)

    _install_and_verify_pair(destinations, payload, backup_dir=backup_dir)

    if backup_dir is not None:
        output.step(f"backed up previous project guidance to {backup_dir}")
    output.step(f"installed project AGENTS.md and CLAUDE.md from {source}")
    return GuidanceOutcome(
        disposition=decision.disposition,
        written=destinations,
        backup_dir=backup_dir,
    )


def _resolve_source(
    decision: BootstrapGuidanceDecision,
    *,
    project_root: Path,
    worker_class: str,
) -> Path:
    candidates = [
        path
        for path in sorted(project_root.glob(GUIDANCE_ARTIFACT_GLOB))
        if path.is_file() and filename_matches_class(worker_class, path.name)
    ]
    if len(candidates) != 1:
        raise YasdefError(
            f"approved agent-guidance regeneration needs exactly one class-matching "
            f"{GUIDANCE_ARTIFACT_GLOB} artifact under {project_root}, found {len(candidates)}"
        )

    recorded = Path(decision.source.strip())
    if not recorded.is_absolute():
        recorded = project_root / recorded
    if recorded.resolve() != candidates[0].resolve():
        raise YasdefError(
            f"recorded agent-guidance source {decision.source} does not match the unique "
            f"class-matching artifact {candidates[0]}"
        )
    return candidates[0]


def _refuse_directories(destinations: tuple[Path, ...]) -> None:
    for dest in destinations:
        if dest.is_dir() and not dest.is_symlink():
            raise YasdefError(
                f"project guidance path is a directory: {dest}. "
                "Remove or rename it explicitly, then rerun the design phase."
            )


def _create_backup(worker_root: Path, existing: tuple[Path, ...]) -> Path:
    backup_dir = worker_root / BACKUP_ROOT_REL / _operation_id()
    try:
        backup_dir.mkdir(parents=True, exist_ok=False)
    except OSError as exc:
        raise YasdefError(f"failed to create guidance backup directory {backup_dir}: {exc}") from exc

    for path in existing:
        target = backup_dir / path.name
        try:
            if path.is_symlink():
                os.symlink(os.readlink(path), target)
            else:
                atomic_write_bytes(target, path.read_bytes())
        except OSError as exc:
            raise YasdefError(
                f"failed to back up {path} to {target}: {exc}. "
                "Project guidance files were left unchanged."
            ) from exc
        _verify_backup_entry(path, target)
    return backup_dir


def _verify_backup_entry(source: Path, target: Path) -> None:
    if source.is_symlink():
        if not target.is_symlink() or os.readlink(target) != os.readlink(source):
            raise YasdefError(f"guidance backup verification failed for symlink {source}")
        return
    if not target.is_file() or target.read_bytes() != source.read_bytes():
        raise YasdefError(f"guidance backup verification failed for {source}")


def _install_and_verify_pair(
    destinations: tuple[Path, ...], payload: bytes, *, backup_dir: Path | None
) -> None:
    """Replace and verify both paths as one transaction.

    Writing and verification share the same rollback: on any write error,
    verification mismatch, or read failure, every replaced path is restored from
    its backup or removed when it was originally absent.
    """
    written: list[Path] = []
    try:
        for dest in destinations:
            atomic_write_bytes(dest, payload)
            written.append(dest)
        _verify_pair(destinations, payload)
    except (OSError, YasdefError) as exc:
        _rollback(written, backup_dir)
        raise YasdefError(
            f"failed to install project guidance pair: {exc}. "
            "Pre-operation project guidance state was restored where possible."
        ) from exc


def _rollback(written: list[Path], backup_dir: Path | None) -> None:
    # Best-effort: suppress secondary IO errors so the primary failure surfaces.
    for dest in written:
        with contextlib.suppress(OSError):
            backup = backup_dir / dest.name if backup_dir is not None else None
            if backup is not None and (backup.is_symlink() or backup.exists()):
                dest.unlink(missing_ok=True)
                if backup.is_symlink():
                    os.symlink(os.readlink(backup), dest)
                else:
                    atomic_write_bytes(dest, backup.read_bytes())
            else:
                dest.unlink(missing_ok=True)


def _verify_pair(destinations: tuple[Path, ...], payload: bytes) -> None:
    for dest in destinations:
        if dest.is_symlink() or not dest.is_file() or dest.read_bytes() != payload:
            raise YasdefError(f"project guidance verification failed for {dest}")


def _exclude_backup_root(worker_root: Path, output: UserOutput) -> None:
    git_dir = worker_root / ".git"
    if not git_dir.is_dir():
        output.warn(
            f"could not add {BACKUP_EXCLUDE_ENTRY} to git excludes: {git_dir} is not a git directory"
        )
        return
    merge_exclude_entries(git_dir / "info" / "exclude", (BACKUP_EXCLUDE_ENTRY,))


def _operation_id() -> str:
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    return f"{stamp}-{uuid.uuid4().hex[:8]}"
