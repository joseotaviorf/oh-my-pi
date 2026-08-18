"""Loads config.yaml — the single source of truth for which model runs the
tars eval (tars_model) and which model grades it (judge_model,
judge_threshold). Connection settings (base URL, API key, skill dir) stay in
.env; this file only ever holds non-secret model selection.
"""

from dataclasses import dataclass
from pathlib import Path

import yaml

from tars_evals.gate import DEFAULT_MAX_ERROR_RATE


@dataclass(frozen=True)
class EvalConfig:
    tars_model: str
    judge_model: str
    judge_threshold: int
    # Reasoning effort for the judge model (low|medium|high), or None for no
    # extended thinking. Optional — absent/blank in config.yaml means None.
    judge_reasoning_effort: str | None = None
    # Judge generate temperature. Default 0.0 when the key is absent (pin for
    # deterministic grading). Explicit null/blank means omit temperature so
    # providers that reject non-default values (e.g. gpt-5.6-luna) use theirs.
    judge_temperature: float | None = 0.0
    # Suite gate: the run passes only when (passed / total) is STRICTLY greater
    # than this (see gate.py). Default 0.9.
    gate_pass_rate: float = 0.9
    # Above this share of samples that never produced a verdict, the run is
    # reported as INCONCLUSIVE (harness/infra broke) instead of as a quality
    # regression — see gate.evaluate_gate. Default 0.1.
    max_error_rate: float = DEFAULT_MAX_ERROR_RATE


def _parse_judge_temperature(raw: dict) -> float | None:
    """Absent key → 0.0; explicit null/blank → None (omit); else float."""
    if "judge_temperature" not in raw:
        return 0.0
    value = raw["judge_temperature"]
    if value is None or value == "":
        return None
    return float(value)


def load_config(path: Path) -> EvalConfig:
    """Load and validate config.yaml.

    Raises:
        KeyError: if a required field is missing.
    """
    raw = yaml.safe_load(Path(path).read_text())
    reasoning_effort = raw.get("judge_reasoning_effort") or None
    gate_pass_rate = float(raw.get("gate_pass_rate", 0.9))
    max_error_rate = float(raw.get("max_error_rate", DEFAULT_MAX_ERROR_RATE))
    return EvalConfig(
        tars_model=raw["tars_model"],
        judge_model=raw["judge_model"],
        judge_threshold=int(raw["judge_threshold"]),
        judge_reasoning_effort=reasoning_effort,
        judge_temperature=_parse_judge_temperature(raw),
        gate_pass_rate=gate_pass_rate,
        max_error_rate=max_error_rate,
    )
