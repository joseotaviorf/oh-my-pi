"""Shared serialization and atomic I/O for eval summary JSON files."""

from __future__ import annotations

import json
import os
import tempfile
from collections.abc import Iterable
from pathlib import Path

from tars_evals.gate import GateResult, SampleResult

_HEADER_KEYS = ("passed", "total", "passed_count", "pass_rate")
_SAMPLE_KEYS = ("dataset", "id", "judge_score", "status", "reasoning")


class SummaryParseError(ValueError):
    """Friendly parse failure for a per-dataset summary.json."""


def load_json_object(path: Path, *, error_cls: type[Exception] = SummaryParseError) -> dict:
    """Read ``path`` and return the parsed JSON root when it is an object."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise error_cls(f"{path}: cannot read file: {error}") from error

    try:
        data = json.loads(text)
    except json.JSONDecodeError as error:
        raise error_cls(f"{path}: invalid JSON: {error}") from error

    if not isinstance(data, dict):
        raise error_cls(f"{path}: summary root must be an object")
    return data


def missing_keys(data: dict, keys: Iterable[str]) -> list[str]:
    """Return required keys absent from ``data``."""
    return [key for key in keys if key not in data]


def sample_result_to_dict(result: SampleResult) -> dict[str, object]:
    return {
        "dataset": result.dataset,
        "id": result.id,
        "judge_score": result.judge_score,
        "status": result.status,
        "reasoning": result.reasoning,
    }


def per_dataset_summary_dict(stem: str, gate: GateResult) -> dict[str, object]:
    return {
        "stem": stem,
        "passed": gate.passed,
        "total": gate.total,
        "passed_count": gate.passed_count,
        "pass_rate": gate.pass_rate,
        # Not in _HEADER_KEYS: build_rollup re-derives the suite verdict from
        # the samples, so these are for humans reading a single stem's file.
        "error_count": gate.error_count,
        "inconclusive": gate.inconclusive,
        "samples": [sample_result_to_dict(r) for r in gate.results],
    }


def gate_summary_dict(gate: GateResult) -> dict[str, object]:
    return {
        "passed": gate.passed,
        "total": gate.total,
        "passed_count": gate.passed_count,
        "pass_rate": gate.pass_rate,
        "reason": gate.reason,
        "error_count": gate.error_count,
        "inconclusive": gate.inconclusive,
        "samples": [sample_result_to_dict(r) for r in gate.results],
    }


def write_json_atomic(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
    )
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)
            handle.write("\n")
        os.replace(tmp_path, path)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise


def load_per_dataset_summary(
    path: Path, *, expected_stem: str
) -> tuple[dict[str, object], list[SampleResult]]:
    data = load_json_object(path)

    if "stem" not in data:
        raise SummaryParseError(f"{path}: missing field 'stem'")
    stem = data["stem"]
    if stem != expected_stem:
        raise SummaryParseError(
            f"{path}: stem mismatch: expected {expected_stem}, got {stem}"
        )

    for key in _HEADER_KEYS:
        if key not in data:
            raise SummaryParseError(f"{path}: missing field '{key}'")

    if "samples" not in data:
        raise SummaryParseError(f"{path}: missing field 'samples'")
    samples_raw = data["samples"]
    if not isinstance(samples_raw, list):
        raise SummaryParseError(f"{path}: field 'samples' must be a list")

    results: list[SampleResult] = []
    for index, sample in enumerate(samples_raw):
        results.append(_parse_sample(path, index, sample))

    header = {key: data[key] for key in _HEADER_KEYS}
    return header, results


def _parse_sample(path: Path, index: int, sample: object) -> SampleResult:
    if not isinstance(sample, dict):
        raise SummaryParseError(
            f"{path}: samples[{index}] must be an object"
        )
    for key in _SAMPLE_KEYS:
        if key not in sample:
            raise SummaryParseError(
                f"{path}: samples[{index}] missing field '{key}'"
            )
    try:
        return SampleResult(
            dataset=str(sample["dataset"]),
            id=str(sample["id"]),
            judge_score=sample["judge_score"],
            status=str(sample["status"]),
            reasoning=str(sample["reasoning"]),
        )
    except TypeError as error:
        raise SummaryParseError(
            f"{path}: samples[{index}] invalid fields: {error}"
        ) from error
