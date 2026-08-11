import importlib.util
import json
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "build_rollup.py"


def _load_build_rollup():
    spec = importlib.util.spec_from_file_location("test_build_rollup_script", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _write_config(root: Path) -> None:
    (root / "config.yaml").write_text(
        "tars_model: subject\n"
        "judge_model: judge\n"
        "judge_threshold: 4\n"
        "gate_pass_rate: 0.5\n"
    )


def _write_dataset(root: Path, stem: str) -> None:
    datasets_dir = root / "datasets"
    datasets_dir.mkdir(exist_ok=True)
    (datasets_dir / f"{stem}.yaml").write_text("items: []\n")


def _write_summary(
    per_dataset_dir: Path,
    directory_stem: str,
    *,
    summary_stem: str | None = None,
    status: str = "PASS",
) -> None:
    summary_dir = per_dataset_dir / directory_stem
    summary_dir.mkdir(parents=True)
    passed = status == "PASS"
    payload = {
        "stem": summary_stem or directory_stem,
        "passed": passed,
        "total": 1,
        "passed_count": int(passed),
        "pass_rate": float(passed),
        "samples": [
            {
                "dataset": directory_stem,
                "id": f"{directory_stem}-sample",
                "judge_score": 5 if passed else 2,
                "status": status,
                "reasoning": "",
            }
        ],
    }
    (summary_dir / "summary.json").write_text(json.dumps(payload))


def test_rollup_only_counts_explicitly_selected_stems(tmp_path: Path):
    root = tmp_path / "package"
    per_dataset_dir = root / "logs" / "per_dataset"
    root.mkdir()
    _write_config(root)
    _write_dataset(root, "fresh")
    _write_dataset(root, "stale")
    _write_summary(per_dataset_dir, "fresh")
    _write_summary(per_dataset_dir, "stale", status="FAIL")

    rc = _load_build_rollup().main(
        ["fresh"], root=root, per_dataset_dir=per_dataset_dir
    )

    assert rc == 0
    rollup = json.loads((per_dataset_dir / "rollup.json").read_text())
    assert rollup["datasets_completed"] == 1
    assert list(rollup["per_dataset"]) == ["fresh"]
    assert rollup["suite"]["passed"] is True


def test_rollup_fails_closed_when_suite_pass_rate_too_low(tmp_path: Path):
    """A valid, successfully-parsed rollup must still fail CI when the
    aggregate pass rate does not clear gate_pass_rate — this is the suite's
    one authoritative gate decision."""
    root = tmp_path / "package"
    per_dataset_dir = root / "logs" / "per_dataset"
    root.mkdir()
    (root / "config.yaml").write_text(
        "tars_model: subject\n"
        "judge_model: judge\n"
        "judge_threshold: 4\n"
        "gate_pass_rate: 0.9\n"
    )
    _write_dataset(root, "fresh")
    _write_dataset(root, "stale")
    _write_summary(per_dataset_dir, "fresh")
    _write_summary(per_dataset_dir, "stale", status="FAIL")

    rc = _load_build_rollup().main(
        ["fresh", "stale"], root=root, per_dataset_dir=per_dataset_dir
    )

    assert rc == 1
    rollup = json.loads((per_dataset_dir / "rollup.json").read_text())
    assert rollup["suite"]["passed"] is False
    gate_summary = json.loads((root / "gate_summary.json").read_text())
    assert gate_summary["passed"] is False


def test_rollup_rejects_missing_selected_summary(tmp_path: Path, capsys):
    root = tmp_path / "package"
    per_dataset_dir = root / "logs" / "per_dataset"
    root.mkdir()
    per_dataset_dir.mkdir(parents=True)
    _write_config(root)
    _write_dataset(root, "missing")

    rc = _load_build_rollup().main(
        ["missing"], root=root, per_dataset_dir=per_dataset_dir
    )

    assert rc == 2
    assert "Missing summary" in capsys.readouterr().err
    assert not (per_dataset_dir / "rollup.json").exists()


def test_rollup_rejects_duplicate_selected_stems(tmp_path: Path, capsys):
    root = tmp_path / "package"
    per_dataset_dir = root / "logs" / "per_dataset"
    root.mkdir()
    _write_config(root)
    _write_dataset(root, "alpha")
    _write_summary(per_dataset_dir, "alpha")

    rc = _load_build_rollup().main(
        ["alpha", "alpha"], root=root, per_dataset_dir=per_dataset_dir
    )

    assert rc == 2
    assert "Duplicate dataset stem" in capsys.readouterr().err


def test_rollup_rejects_duplicate_summary_stems(tmp_path: Path, capsys):
    """Directory stem must match payload stem; a hijacked stem is rejected as invalid."""
    root = tmp_path / "package"
    per_dataset_dir = root / "logs" / "per_dataset"
    root.mkdir()
    _write_config(root)
    _write_dataset(root, "alpha")
    _write_dataset(root, "beta")
    _write_summary(per_dataset_dir, "alpha")
    _write_summary(per_dataset_dir, "beta", summary_stem="alpha")

    rc = _load_build_rollup().main(
        ["alpha", "beta"], root=root, per_dataset_dir=per_dataset_dir
    )

    assert rc == 2
    err = capsys.readouterr().err
    assert err.count("ERROR:") == 1
    assert "Invalid summary for beta:" in err
    assert "stem mismatch" in err
    assert "expected beta" in err
    assert "got alpha" in err
    assert "Traceback" not in err


def test_rollup_rejects_empty_dataset_discovery(tmp_path: Path, capsys):
    root = tmp_path / "package"
    per_dataset_dir = root / "logs" / "per_dataset"
    root.mkdir()
    (root / "datasets").mkdir()
    _write_config(root)

    rc = _load_build_rollup().main([], root=root, per_dataset_dir=per_dataset_dir)

    assert rc == 2
    assert "no dataset stems found" in capsys.readouterr().err


def test_rollup_rejects_malformed_summary_json(tmp_path: Path, capsys):
    root = tmp_path / "package"
    per_dataset_dir = root / "logs" / "per_dataset"
    root.mkdir()
    _write_config(root)
    _write_dataset(root, "alpha")
    summary_path = per_dataset_dir / "alpha" / "summary.json"
    summary_path.parent.mkdir(parents=True)
    summary_path.write_text('{"stem": "alpha",')

    rc = _load_build_rollup().main(
        ["alpha"], root=root, per_dataset_dir=per_dataset_dir
    )

    assert rc == 2
    err = capsys.readouterr().err
    assert err.count("ERROR:") == 1
    assert "Invalid summary for alpha:" in err
    assert str(summary_path) in err
    assert "invalid JSON" in err
    assert "Traceback" not in err
    assert not (per_dataset_dir / "rollup.json").exists()


def test_rollup_rejects_summary_stem_mismatch(tmp_path: Path, capsys):
    root = tmp_path / "package"
    per_dataset_dir = root / "logs" / "per_dataset"
    root.mkdir()
    _write_config(root)
    _write_dataset(root, "alpha")
    summary_path = per_dataset_dir / "alpha" / "summary.json"
    _write_summary(per_dataset_dir, "alpha", summary_stem="beta")

    rc = _load_build_rollup().main(
        ["alpha"], root=root, per_dataset_dir=per_dataset_dir
    )

    assert rc == 2
    err = capsys.readouterr().err
    assert err.count("ERROR:") == 1
    assert "Invalid summary for alpha:" in err
    assert str(summary_path) in err
    assert "stem mismatch" in err
    assert "expected alpha" in err
    assert "got beta" in err
    assert "Traceback" not in err


def test_rollup_rejects_missing_samples_key(tmp_path: Path, capsys):
    root = tmp_path / "package"
    per_dataset_dir = root / "logs" / "per_dataset"
    root.mkdir()
    _write_config(root)
    _write_dataset(root, "alpha")
    summary_dir = per_dataset_dir / "alpha"
    summary_dir.mkdir(parents=True)
    (summary_dir / "summary.json").write_text(
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

    rc = _load_build_rollup().main(
        ["alpha"], root=root, per_dataset_dir=per_dataset_dir
    )

    assert rc == 2
    err = capsys.readouterr().err
    assert "Invalid summary for alpha" in err
    assert "Traceback" not in err
