import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from tars_evals.dataset import DatasetValidationError, select_import_log_samples
from tars_evals.retry import DEFAULT_MAX_RETRIES, DEFAULT_RETRY_ON_ERROR

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = PACKAGE_ROOT / "scripts" / "run_single_dataset_eval.py"


def _run(stem: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), stem],
        cwd=PACKAGE_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def _load_script_module():
    spec = importlib.util.spec_from_file_location("run_single_dataset_eval", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _sample(sample_id: str, dataset: str, *, score: int = 5):
    return SimpleNamespace(
        id=sample_id,
        metadata={"dataset": dataset},
        scores={
            "judge_query_match": SimpleNamespace(
                value="C",
                explanation="",
                metadata={"judge_score": score, "judge_reasoning": "ok"},
            )
        },
        error=None,
    )


@pytest.mark.parametrize(
    "stem", ["", "../turnover", r"nested\turnover", "/tmp/turnover"]
)
def test_rejects_non_plain_dataset_stem(stem: str):
    result = _run(stem)

    assert result.returncode == 2
    assert "plain filename stem" in result.stderr


def test_rejects_unknown_dataset_stem():
    result = _run("not-a-real-dataset")

    assert result.returncode == 2
    assert "Unknown dataset stem" in result.stderr


def test_select_import_log_samples_exact_one_to_one_passes():
    samples = [
        _sample("a", "alpha"),
        _sample("other", "beta"),
        _sample("b", "alpha"),
    ]

    matched = select_import_log_samples(samples, stem="alpha", expected_ids={"a", "b"})

    assert [str(s.id) for s in matched] == ["a", "b"]


def test_select_import_log_samples_rejects_missing_ids():
    samples = [_sample("a", "alpha")]

    with pytest.raises(DatasetValidationError, match=r"missing") as exc:
        select_import_log_samples(samples, stem="alpha", expected_ids={"a", "b"})
    assert "b" in str(exc.value)


def test_select_import_log_samples_rejects_unexpected_ids():
    samples = [
        _sample("a", "alpha"),
        _sample("extra", "alpha"),
    ]

    with pytest.raises(DatasetValidationError, match=r"unexpected") as exc:
        select_import_log_samples(samples, stem="alpha", expected_ids={"a"})
    assert "extra" in str(exc.value)


def test_select_import_log_samples_rejects_duplicate_ids():
    samples = [
        _sample("a", "alpha"),
        _sample("a", "alpha"),
    ]

    with pytest.raises(DatasetValidationError, match=r"duplicate") as exc:
        select_import_log_samples(samples, stem="alpha", expected_ids={"a"})
    assert "a" in str(exc.value)


def test_import_log_path_rejects_unexpected_ids(tmp_path: Path, monkeypatch):
    datasets_dir = tmp_path / "datasets"
    datasets_dir.mkdir()
    (datasets_dir / "alpha.yaml").write_text(
        "items:\n- id: a\n  question: Q\n  expected_query: SELECT 1\n",
        encoding="utf-8",
    )
    log_path = tmp_path / "run.eval"
    log_path.write_text("placeholder", encoding="utf-8")

    module = _load_script_module()
    monkeypatch.setattr(module, "_PACKAGE_ROOT", tmp_path)
    monkeypatch.setattr(module, "_CONFIG_PATH", PACKAGE_ROOT / "config.yaml")

    fake_log = SimpleNamespace(
        samples=[
            _sample("a", "alpha"),
            _sample("extra", "alpha"),
        ]
    )

    import inspect_ai.log as inspect_log

    monkeypatch.setattr(inspect_log, "read_eval_log", lambda _path: fake_log)
    monkeypatch.setattr(
        sys,
        "argv",
        [str(SCRIPT), "alpha", "--import-log", str(log_path)],
    )

    rc = module.main()

    assert rc == 3


def test_empty_dataset_still_writes_summary_and_exits_zero(
    tmp_path: Path, monkeypatch
):
    """build_rollup.py requires a summary.json for every explicitly selected
    stem (hard-fails otherwise) — a legitimately empty dataset (0 golden
    queries) must still produce one instead of being silently skipped."""
    datasets_dir = tmp_path / "datasets"
    datasets_dir.mkdir()
    (datasets_dir / "alpha.yaml").write_text("items: []\n", encoding="utf-8")

    module = _load_script_module()
    monkeypatch.setattr(module, "_PACKAGE_ROOT", tmp_path)
    monkeypatch.setattr(module, "_CONFIG_PATH", PACKAGE_ROOT / "config.yaml")
    monkeypatch.setattr(sys, "argv", [str(SCRIPT), "alpha"])

    rc = module.main()

    assert rc == 0
    summary_path = tmp_path / "logs" / "per_dataset" / "alpha" / "summary.json"
    assert summary_path.is_file()
    summary = json.loads(summary_path.read_text())
    assert summary["passed"] is True
    assert summary["total"] == 0
    assert summary["samples"] == []


def _write_alpha_dataset(tmp_path: Path, *, item_count: int = 1) -> None:
    datasets_dir = tmp_path / "datasets"
    datasets_dir.mkdir()
    items = "\n".join(
        f"- id: a{i}\n  question: Q{i}\n  expected_query: SELECT {i}\n"
        for i in range(item_count)
    )
    (datasets_dir / "alpha.yaml").write_text(
        f"items:\n{items}",
        encoding="utf-8",
    )


def _prepare_live_eval(tmp_path: Path, monkeypatch, *, item_count: int = 1):
    _write_alpha_dataset(tmp_path, item_count=item_count)
    module = _load_script_module()
    monkeypatch.setattr(module, "_PACKAGE_ROOT", tmp_path)
    monkeypatch.setattr(module, "_CONFIG_PATH", PACKAGE_ROOT / "config.yaml")
    monkeypatch.setenv("TARS_SKILL_DIR", str(tmp_path / "skill"))
    (tmp_path / "skill").mkdir()
    (tmp_path / "skill" / "SKILL.md").write_text("# tars\n", encoding="utf-8")
    (tmp_path / "skill" / "scripts").mkdir()

    captured: dict = {}

    def fake_inspect_eval(task, **kwargs):
        captured.update(kwargs)
        return [
            SimpleNamespace(
                samples=[_sample(f"a{i}", "alpha") for i in range(item_count)],
            )
        ]

    monkeypatch.setattr(module, "inspect_eval", fake_inspect_eval)
    monkeypatch.setattr(
        module,
        "make_tars_eval_task",
        lambda samples, config=None: SimpleNamespace(samples=samples),
    )
    monkeypatch.setattr(sys, "argv", [str(SCRIPT), "alpha"])
    return module, captured


def test_resolve_max_connections_defaults_to_sample_count():
    module = _load_script_module()
    assert module.resolve_max_connections(5, env_value=None) == 5
    assert module.resolve_max_connections(0, env_value=None) == 1


def test_resolve_max_connections_explicit_cap_limits_dynamic_default():
    module = _load_script_module()
    assert module.resolve_max_connections(10, env_value="2") == 2
    assert module.resolve_max_connections(1, env_value="4") == 1


@pytest.mark.parametrize("bad", ["0", "-1", "abc", ""])
def test_resolve_max_connections_rejects_invalid_override(bad: str):
    module = _load_script_module()
    with pytest.raises(ValueError, match=r"TARS_EVAL_MAX_CONNECTIONS"):
        module.resolve_max_connections(3, env_value=bad)


def test_live_eval_defaults_max_connections_to_sample_count(
    tmp_path: Path, monkeypatch
):
    monkeypatch.delenv("TARS_EVAL_MAX_CONNECTIONS", raising=False)
    module, captured = _prepare_live_eval(tmp_path, monkeypatch, item_count=3)

    rc = module.main()

    assert rc == 0
    assert captured["max_retries"] == DEFAULT_MAX_RETRIES
    assert captured["retry_on_error"] == DEFAULT_RETRY_ON_ERROR
    assert captured["max_connections"] == 3
    assert captured["epochs"] == 1
    assert (tmp_path / "logs" / "per_dataset" / "alpha" / "summary.json").is_file()

def test_live_eval_respects_explicit_max_connections_cap(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("TARS_EVAL_MAX_CONNECTIONS", "2")
    module, captured = _prepare_live_eval(tmp_path, monkeypatch, item_count=5)

    rc = module.main()

    assert rc == 0
    assert captured["max_connections"] == 2


def test_live_eval_rejects_nonpositive_max_connections(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("TARS_EVAL_MAX_CONNECTIONS", "0")
    module, _captured = _prepare_live_eval(tmp_path, monkeypatch)

    rc = module.main()

    assert rc == 2


def test_completed_run_exits_zero_even_when_its_own_gate_fails(
    tmp_path: Path, monkeypatch
):
    """Exit code communicates execution status, not the quality verdict — the
    suite-level rollup (build_rollup.py) is the one authoritative gate. A
    completed run must still exit 0 so the queue keeps evaluating the rest of
    the stems and reaches the rollup; the FAIL verdict lives in summary.json.
    """
    datasets_dir = tmp_path / "datasets"
    datasets_dir.mkdir()
    (datasets_dir / "alpha.yaml").write_text(
        "items:\n"
        "- id: a\n"
        "  question: Q\n"
        "  expected_query: SELECT 1\n",
        encoding="utf-8",
    )

    module = _load_script_module()
    monkeypatch.setattr(module, "_PACKAGE_ROOT", tmp_path)
    monkeypatch.setattr(module, "_CONFIG_PATH", PACKAGE_ROOT / "config.yaml")

    def fake_inspect_eval(task, **kwargs):
        return [SimpleNamespace(samples=[_sample("a", "alpha", score=2)])]

    monkeypatch.setattr(module, "inspect_eval", fake_inspect_eval)
    monkeypatch.setattr(
        module,
        "make_tars_eval_task",
        lambda samples, config=None: SimpleNamespace(samples=samples),
    )
    monkeypatch.setattr(sys, "argv", [str(SCRIPT), "alpha"])

    rc = module.main()

    assert rc == 0
    summary_path = tmp_path / "logs" / "per_dataset" / "alpha" / "summary.json"
    summary = json.loads(summary_path.read_text())
    assert summary["passed"] is False
