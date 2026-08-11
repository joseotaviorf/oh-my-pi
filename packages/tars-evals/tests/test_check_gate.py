import importlib.util
import json
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "check_gate.py"


def _load_check_gate():
    spec = importlib.util.spec_from_file_location("test_check_gate_script", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _write(path: Path, payload: dict) -> Path:
    path.write_text(json.dumps(payload))
    return path


def test_passing_gate_exits_zero(tmp_path: Path, capsys):
    path = _write(
        tmp_path / "gate_summary.json",
        {"passed": True, "total": 2, "passed_count": 2, "pass_rate": 1.0},
    )

    rc = _load_check_gate().main([str(path)])

    assert rc == 0
    assert "GATE PASSED" in capsys.readouterr().out


def test_failing_gate_exits_one_with_reason_and_samples(tmp_path: Path, capsys):
    path = _write(
        tmp_path / "gate_summary.json",
        {
            "passed": False,
            "total": 2,
            "passed_count": 1,
            "pass_rate": 0.5,
            "reason": "pass_rate 0.50 not > 0.90",
            "samples": [
                {"dataset": "turnover", "id": "ok", "judge_score": 5, "status": "PASS"},
                {
                    "dataset": "turnover",
                    "id": "bad",
                    "judge_score": 2,
                    "status": "FAIL",
                    "reasoning": "wrong filter",
                },
            ],
        },
    )

    rc = _load_check_gate().main([str(path)])

    err = capsys.readouterr().err
    assert rc == 1
    assert "GATE FAILED" in err
    assert "pass_rate 0.50 not > 0.90" in err
    assert "turnover / bad" in err
    assert "wrong filter" in err
    assert "turnover / ok" not in err


def test_failing_gate_without_reason_or_samples_still_reports(tmp_path: Path, capsys):
    path = _write(
        tmp_path / "gate_summary.json",
        {"passed": False, "total": 1, "passed_count": 0, "pass_rate": 0.0},
    )

    rc = _load_check_gate().main([str(path)])

    assert rc == 1
    assert "GATE FAILED" in capsys.readouterr().err


def test_missing_file_exits_two(tmp_path: Path, capsys):
    rc = _load_check_gate().main([str(tmp_path / "does_not_exist.json")])

    assert rc == 2
    assert "cannot read file" in capsys.readouterr().err


def test_malformed_json_exits_two(tmp_path: Path, capsys):
    path = tmp_path / "gate_summary.json"
    path.write_text("{not json")

    rc = _load_check_gate().main([str(path)])

    assert rc == 2
    assert "invalid JSON" in capsys.readouterr().err


def test_missing_required_field_exits_two(tmp_path: Path, capsys):
    path = _write(tmp_path / "gate_summary.json", {"passed": True, "total": 1})

    rc = _load_check_gate().main([str(path)])

    err = capsys.readouterr().err
    assert rc == 2
    assert "missing required field" in err
    assert "passed_count" in err
    assert "pass_rate" in err


def test_non_boolean_passed_exits_two(tmp_path: Path, capsys):
    path = _write(
        tmp_path / "gate_summary.json",
        {"passed": "true", "total": 1, "passed_count": 1, "pass_rate": 1.0},
    )

    rc = _load_check_gate().main([str(path)])

    assert rc == 2
    assert "must be a boolean" in capsys.readouterr().err


def test_json_array_root_exits_two(tmp_path: Path, capsys):
    path = tmp_path / "gate_summary.json"
    path.write_text("[]")

    rc = _load_check_gate().main([str(path)])

    assert rc == 2
    assert "must be an object" in capsys.readouterr().err


def test_works_against_per_dataset_summary_shape(tmp_path: Path, capsys):
    """Per-dataset summary.json (has 'stem' instead of 'reason') is also valid input."""
    path = _write(
        tmp_path / "summary.json",
        {
            "stem": "turnover",
            "passed": False,
            "total": 1,
            "passed_count": 0,
            "pass_rate": 0.0,
            "samples": [
                {"dataset": "turnover", "id": "a", "status": "FAIL", "judge_score": 1}
            ],
        },
    )

    rc = _load_check_gate().main([str(path)])

    assert rc == 1
    assert "turnover / a" in capsys.readouterr().err
