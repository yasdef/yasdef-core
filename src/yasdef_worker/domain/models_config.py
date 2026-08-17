from __future__ import annotations

from dataclasses import dataclass

from yasdef_worker.domain.phases import MODEL_PHASES, PhaseNameError, canonical_phase_name

ROW_SHAPE = "<phase> | <command> | <model> | <args... optional>"


@dataclass(frozen=True, slots=True)
class ModelConfig:
    phase: str
    cmd: str
    model: str
    extras: tuple[str, ...] = ()


class ModelsConfigError(ValueError):
    pass


def parse_models_config(content: str) -> tuple[ModelConfig, ...]:
    """Parse every active row in file order, rejecting malformed rows instead of skipping them."""
    rows: list[ModelConfig] = []
    for number, raw in enumerate(content.splitlines(), start=1):
        line = raw.rstrip("\r").strip()
        if not line or line.startswith("#"):
            continue
        rows.append(_parse_row(line, number))
    return tuple(rows)


def validate_models_config(content: str) -> tuple[ModelConfig, ...]:
    """Return the complete model pipeline in canonical order, or raise with a diagnostic.

    Row order in the file is presentation only: any ordering of the required rows is
    accepted, and the returned tuple always follows ``MODEL_PHASES``.
    """
    by_phase: dict[str, ModelConfig] = {}
    for row in parse_models_config(content):
        if row.phase in by_phase:
            raise ModelsConfigError(
                f"duplicate '{row.phase}' entry in models config; "
                f"each required phase must appear exactly once ({_required_phases()})"
            )
        by_phase[row.phase] = row
    missing = tuple(phase for phase in MODEL_PHASES if phase not in by_phase)
    if missing:
        raise ModelsConfigError(
            f"incomplete models config, missing phase(s): {', '.join(missing)}; "
            f"one row is required for each of {_required_phases()} (row order does not matter)"
        )
    return tuple(by_phase[phase] for phase in MODEL_PHASES)


def list_phases(content: str) -> tuple[str, ...]:
    return tuple(row.phase for row in validate_models_config(content))


def load_model_config(content: str, phase: str) -> ModelConfig:
    target = _canonical_model_phase_name(phase)
    for row in parse_models_config(content):
        if row.phase == target:
            return row
    raise ModelsConfigError(
        f"invalid or missing '{phase}' entry in models config (expected: {ROW_SHAPE})"
    )


def _parse_row(line: str, number: int) -> ModelConfig:
    parts = [part.strip(" \t") for part in _strip_outer_pipes(line).split("|")]
    if len(parts) < 3:
        raise ModelsConfigError(
            f"models config line {number}: expected '{ROW_SHAPE}', "
            f"got {len(parts)} field(s): {line}"
        )
    phase, cmd, model = parts[0], parts[1], parts[2]
    for label, value in (("phase", phase), ("command", cmd), ("model", model)):
        if not value:
            raise ModelsConfigError(
                f"models config line {number}: empty {label} field, expected '{ROW_SHAPE}': {line}"
            )
    try:
        canonical = _canonical_model_phase_name(phase)
    except ModelsConfigError as exc:
        raise ModelsConfigError(f"models config line {number}: {exc}") from exc
    return ModelConfig(canonical, cmd, model, tuple(part for part in parts[3:] if part))


def _strip_outer_pipes(line: str) -> str:
    """Accept one optional leading and trailing pipe so Markdown-style rows stay valid."""
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return line


def _required_phases() -> str:
    return ", ".join(MODEL_PHASES)


def _canonical_model_phase_name(value: str) -> str:
    try:
        phase = canonical_phase_name(value)
    except PhaseNameError as exc:
        raise ModelsConfigError(str(exc)) from exc
    if phase == "post_review":
        raise ModelsConfigError(f"unsupported phase name: {value}")
    return phase
