from __future__ import annotations

from dataclasses import dataclass

from yasdef_worker.domain.phases import PhaseNameError, canonical_phase_name


@dataclass(frozen=True, slots=True)
class ModelConfig:
    phase: str
    cmd: str
    model: str
    extras: tuple[str, ...] = ()


class ModelsConfigError(ValueError):
    pass


def parse_models_config(content: str) -> tuple[ModelConfig, ...]:
    rows: list[ModelConfig] = []
    for raw in content.splitlines():
        line = raw.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = [_trim(part) for part in line.split("|")]
        if len(parts) < 3:
            continue
        phase, cmd, model = parts[0], parts[1], parts[2]
        if not phase:
            continue
        extras = tuple(part for part in parts[3:] if part)
        rows.append(ModelConfig(_canonical_model_phase_name(phase), cmd, model, extras))
    return tuple(rows)


def list_phases(content: str) -> tuple[str, ...]:
    phases: list[str] = []
    seen: set[str] = set()
    for row in parse_models_config(content):
        key = row.phase.lower()
        if key not in seen:
            seen.add(key)
            phases.append(row.phase)
    return tuple(phases)


def load_model_config(content: str, phase: str) -> ModelConfig:
    target = _canonical_model_phase_name(phase).lower()
    for row in parse_models_config(content):
        if row.phase.lower() == target:
            if not row.cmd or not row.model:
                break
            return row
    raise ModelsConfigError(
        f"invalid or missing '{phase}' entry in models config "
        f"(expected: {phase} | <command> | <model> | <args... optional>)"
    )


def _trim(value: str) -> str:
    return value.strip(" \t")


def _canonical_model_phase_name(value: str) -> str:
    try:
        phase = canonical_phase_name(value)
    except PhaseNameError as exc:
        raise ModelsConfigError(str(exc)) from exc
    if phase == "post_review":
        raise ModelsConfigError(f"unsupported phase name: {value}")
    return phase
