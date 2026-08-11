"""Schema preservation and hardening for summary JSON I/O."""
from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest
from tars_evals.gate import GateResult, SampleResult, evaluate_gate
from tars_evals.summary_io import (
    SummaryParseError,
    gate_summary_dict,
    load_json_object,
    load_per_dataset_summary,
    missing_keys,
    per_dataset_summary_dict,
    write_json_atomic,
)


def _sample(
    *,
    dataset: str = "alpha",
    id: str = "s1",
    judge_score: int | None = 5,
    status: str = "PASS",
    reasoning: str = "ok",
) -> SampleResult:
    return SampleResult(dataset, id, judge_score, status, reasoning)


def test_load_json_object_rejects_non_object_root(tmp_path: Path):
    path = tmp_path / "summary.json"
    path.write_text("[]")

    with pytest.raises(SummaryParseError, match="must be an object"):
        load_json_object(path)


def test_missing_keys_reports_absent_header_fields():
    assert missing_keys({"passed": True}, ("passed", "total")) == ["total"]


def test_sample_result_roundtrip_via_per_dataset_summary():
    results = [
        _sample(),
        _sample(id="s2", judge_score=None, status="NO-SQL", reasoning="no SQL"),
    ]
    gate = evaluate_gate(results, 0.5)
    payload = per_dataset_summary_dict("alpha", gate)

    assert list(payload) == [
        "stem",
        "passed",
        "total",
        "passed_count",
        "pass_rate",
        "samples",
    ]
    roundtripped = [SampleResult(**s) for s in payload["samples"]]  # type: ignore[arg-type]
    assert roundtripped == results
    for sample in payload["samples"]:  # type: ignore[union-attr]
        assert list(sample) == [
            "dataset",
            "id",
            "judge_score",
            "status",
            "reasoning",
        ]


def test_per_dataset_summary_dict_matches_current_schema():
    results = [_sample()]
    gate = GateResult(
        passed=True,
        total=1,
        passed_count=1,
        pass_rate=1.0,
        results=results,
        reason="",
    )
    payload = per_dataset_summary_dict("alpha", gate)
    assert payload == {
        "stem": "alpha",
        "passed": True,
        "total": 1,
        "passed_count": 1,
        "pass_rate": 1.0,
        "samples": [
            {
                "dataset": "alpha",
                "id": "s1",
                "judge_score": 5,
                "status": "PASS",
                "reasoning": "ok",
            }
        ],
    }


def test_gate_summary_dict_matches_rollup_schema():
    results = [_sample(status="FAIL", judge_score=2, reasoning="bad")]
    gate = evaluate_gate(results, 0.9)
    payload = gate_summary_dict(gate)
    assert list(payload) == [
        "passed",
        "total",
        "passed_count",
        "pass_rate",
        "reason",
        "samples",
    ]
    assert "aitools_sha" not in payload
    assert "stem" not in payload
    assert payload["passed"] is False
    assert payload["reason"]
    assert [SampleResult(**s) for s in payload["samples"]] == results  # type: ignore[arg-type]


def test_write_json_atomic_replaces_on_success(tmp_path: Path):
    target = tmp_path / "summary.json"
    target.write_text('{"old": true}\n')
    payload = {"stem": "alpha", "passed": True}

    write_json_atomic(target, payload)

    assert json.loads(target.read_text()) == payload
    assert list(tmp_path.iterdir()) == [target]


def test_write_json_atomic_preserves_original_on_failure(tmp_path: Path):
    target = tmp_path / "summary.json"
    original = '{"old": true}\n'
    target.write_text(original)
    payload = {"stem": "alpha", "passed": False}

    with patch("tars_evals.summary_io.os.replace", side_effect=OSError("boom")):
        with pytest.raises(OSError, match="boom"):
            write_json_atomic(target, payload)

    assert target.read_text() == original


def test_load_per_dataset_summary_happy_path(tmp_path: Path):
    path = tmp_path / "summary.json"
    results = [_sample()]
    gate = evaluate_gate(results, 0.5)
    write_json_atomic(path, per_dataset_summary_dict("alpha", gate))

    header, loaded = load_per_dataset_summary(path, expected_stem="alpha")

    assert header == {
        "passed": True,
        "total": 1,
        "passed_count": 1,
        "pass_rate": 1.0,
    }
    assert loaded == results


def test_load_per_dataset_summary_invalid_json(tmp_path: Path):
    path = tmp_path / "summary.json"
    path.write_text('{"stem": "alpha",')

    with pytest.raises(SummaryParseError, match="invalid JSON") as exc_info:
        load_per_dataset_summary(path, expected_stem="alpha")

    message = str(exc_info.value)
    assert str(path) in message
    assert isinstance(exc_info.value.__cause__, json.JSONDecodeError)


def test_load_per_dataset_summary_truncated_json(tmp_path: Path):
    path = tmp_path / "summary.json"
    path.write_text("{")

    with pytest.raises(SummaryParseError, match="invalid JSON"):
        load_per_dataset_summary(path, expected_stem="alpha")


def test_load_per_dataset_summary_missing_stem(tmp_path: Path):
    path = tmp_path / "summary.json"
    path.write_text(
        json.dumps(
            {
                "passed": True,
                "total": 0,
                "passed_count": 0,
                "pass_rate": 0.0,
                "samples": [],
            }
        )
    )

    with pytest.raises(SummaryParseError, match="missing field 'stem'"):
        load_per_dataset_summary(path, expected_stem="alpha")


def test_load_per_dataset_summary_missing_samples(tmp_path: Path):
    path = tmp_path / "summary.json"
    path.write_text(
        json.dumps(
            {
                "stem": "alpha",
                "passed": True,
                "total": 0,
                "passed_count": 0,
                "pass_rate": 0.0,
            }
        )
    )

    with pytest.raises(SummaryParseError, match="missing field 'samples'"):
        load_per_dataset_summary(path, expected_stem="alpha")


def test_load_per_dataset_summary_stem_mismatch(tmp_path: Path):
    path = tmp_path / "summary.json"
    path.write_text(
        json.dumps(
            {
                "stem": "beta",
                "passed": True,
                "total": 0,
                "passed_count": 0,
                "pass_rate": 0.0,
                "samples": [],
            }
        )
    )

    with pytest.raises(SummaryParseError, match="stem mismatch"):
        load_per_dataset_summary(path, expected_stem="alpha")


def test_load_per_dataset_summary_bad_sample(tmp_path: Path):
    path = tmp_path / "summary.json"
    path.write_text(
        json.dumps(
            {
                "stem": "alpha",
                "passed": True,
                "total": 1,
                "passed_count": 1,
                "pass_rate": 1.0,
                "samples": [
                    {
                        "dataset": "alpha",
                        "id": "s1",
                        "judge_score": 5,
                        "reasoning": "ok",
                    }
                ],
            }
        )
    )

    with pytest.raises(SummaryParseError, match=r"samples\[0\].*status"):
        load_per_dataset_summary(path, expected_stem="alpha")
