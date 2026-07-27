import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from parse_processor_logs import (  # noqa: E402
    DagStat,
    _compute_analysis,
    build_by_identity,
    format_text,
    summarize_period,
)


def _stat(path: str, runtime: float, queries: int) -> DagStat:
    return DagStat(
        file_path=path,
        basename=path.rsplit("/", 1)[-1],
        last_runtime_s=runtime,
        last_run="2026-07-21T22:00:00",
        db_queries=queries,
    )


def _analysis(before: dict[str, DagStat], after: dict[str, DagStat]) -> dict:
    return _compute_analysis(
        before,
        after,
        significant_improvement_pct=50,
        significant_improvement_abs_s=3,
        unchanged_pct_threshold=15,
        still_slow_threshold_s=5,
        top_n_next=25,
    )


def test_bundle_basenames_are_keyed_by_domain_path():
    stats = [
        _stat(
            "/usr/local/airflow/dags/_astro_bundles/growth/_bundle_01.py",
            4.0,
            10,
        ),
        _stat(
            "/usr/local/airflow/dags/_astro_bundles/fintech/_bundle_01.py",
            5.0,
            12,
        ),
    ]

    indexed = build_by_identity(stats)

    assert set(indexed) == {
        "_astro_bundles/growth/_bundle_01.py",
        "_astro_bundles/fintech/_bundle_01.py",
    }


def test_identity_normalizes_legacy_duplicated_dags_component():
    stat = _stat(
        "/usr/local/airflow/dags/dags/growth/example/example_dag.py",
        1.0,
        2,
    )

    assert stat.identity == "growth/example/example_dag.py"


def test_summarize_period_is_independent_of_file_topology():
    summary = summarize_period(
        {
            "a": _stat("/dags/a.py", 1.0, 10),
            "b": _stat("/dags/b.py", 3.0, 20),
        }
    )

    assert summary == {
        "files": 2,
        "total_runtime_s": 4.0,
        "mean_runtime_s": 2.0,
        "median_runtime_s": 2.0,
        "p90_runtime_s": 3.0,
        "max_runtime_s": 3.0,
        "mean_db_queries": 15,
        "max_db_queries": 20,
    }


def test_summarize_period_p90_handles_single_file():
    summary = summarize_period({"a": _stat("/dags/a.py", 2.0, 10)})

    assert summary["p90_runtime_s"] == 2.0


def test_empty_periods_are_not_topology_comparable():
    assert _analysis({}, {})["topology_comparable"] is False
    assert (
        _analysis(
            {"a": _stat("/dags/a.py", 1.0, 1)},
            {},
        )["topology_comparable"]
        is False
    )


def test_topology_comparison_uses_union_overlap():
    before = {
        name: _stat(f"/dags/{name}.py", 1.0, 1) for name in ("a", "b", "c", "d", "e")
    }
    after = {
        "a": _stat("/dags/a.py", 1.0, 1),
        "new": _stat("/dags/new.py", 1.0, 1),
    }

    data = _analysis(before, after)

    assert data["topology_overlap"] == pytest.approx(1 / 6)
    assert data["topology_comparable"] is False


def test_half_union_overlap_is_topology_comparable():
    before = {
        name: _stat(f"/dags/{name}.py", 1.0, 1) for name in ("a", "b", "before_only")
    }
    after = {
        name: _stat(f"/dags/{name}.py", 1.0, 1) for name in ("a", "b", "after_only")
    }

    data = _analysis(before, after)

    assert data["topology_overlap"] == 0.5
    assert data["topology_comparable"] is True


def test_report_uses_period_totals_when_file_topology_changes():
    before = {"growth/a/a_dag.py": _stat("/dags/a.py", 3.0, 10)}
    after = {
        "_astro_bundles/growth/_bundle_01.py": _stat("/dags/_bundle_01.py", 1.0, 4)
    }
    data = _analysis(before, after)

    report = format_text([Path("before.log")], [Path("after.log")], data)

    assert data["topology_comparable"] is False
    assert data["cycle_delta_pct"] == pytest.approx(-66.6667, rel=1e-4)
    assert "file topology changed" in report
