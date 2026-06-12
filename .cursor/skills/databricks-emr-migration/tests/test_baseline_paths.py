"""Tests for baseline storage paths and repo-root discovery."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

from baseline import (
    baseline_file_path,
    discover_tables,
    is_baseline_valid,
    load_baseline_for_table,
    load_baselines,
)
from models import TableBaseline
from paths import REPO_ROOT


class BaselinePathTests(unittest.TestCase):
    def test_baseline_file_path_includes_layer(self) -> None:
        path = baseline_file_path("fintech", "dw_credit_analysis", "dw", "dim_drop_reason")
        self.assertEqual(
            path.as_posix().endswith("baseline/fintech/dw_credit_analysis/dw/dim_drop_reason.json"),
            True,
        )

    def test_discover_tables_uses_repo_root_not_cwd(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            dag_queries = repo_root / "dags" / "fintech" / "dw_x" / "queries" / "dw"
            dag_queries.mkdir(parents=True)
            (dag_queries / "dim_sample.sql").write_text("SELECT 1", encoding="utf-8")

            with patch("baseline.Path.cwd", return_value=Path("/tmp/nowhere")):
                tables = discover_tables("fintech", "dw_x", repo_root=repo_root)

            self.assertEqual(tables, [("dim_sample", "dw")])

    def test_load_baseline_for_table_reads_layer_scoped_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import baseline as baseline_module

            original_root = baseline_module.BASELINE_ROOT
            baseline_module.BASELINE_ROOT = Path(tmp) / "baseline"
            try:
                baseline_path = baseline_file_path("fintech", "dw_x", "dw", "dim_sample")
                baseline_path.parent.mkdir(parents=True)
                payload = TableBaseline(
                    dag="dw_x",
                    table="dim_sample",
                    layer="dw",
                    load_start_date="2026-06-04",
                    load_end_date="2026-06-05",
                    schema=[("id", "bigint")],
                    count=1,
                    sample_rows=0,
                    sample=[],
                    order_by_cols=["id"],
                    time_pinned_functions=[],
                    non_comparable_cols=[],
                    sql_hash="abc",
                )
                baseline_path.write_text(
                    json.dumps(
                        {
                            **payload.__dict__,
                            "schema": payload.schema,
                        }
                    ),
                    encoding="utf-8",
                )
                loaded = load_baseline_for_table("fintech", "dw_x", "dim_sample", "dw")
                self.assertIsNotNone(loaded)
                assert loaded is not None
                self.assertEqual(loaded.layer, "dw")
                self.assertIsNone(
                    load_baseline_for_table("fintech", "dw_x", "dim_sample", "enrich")
                )
            finally:
                baseline_module.BASELINE_ROOT = original_root

    def test_load_baselines_prefers_layer_scoped_over_legacy(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import baseline as baseline_module

            original_root = baseline_module.BASELINE_ROOT
            baseline_module.BASELINE_ROOT = Path(tmp) / "baseline"
            try:
                layer_path = baseline_file_path("fintech", "dw_x", "dw", "dim_sample")
                legacy_path = (
                    baseline_module.BASELINE_ROOT / "fintech" / "dw_x" / "dim_sample.json"
                )
                layer_path.parent.mkdir(parents=True, exist_ok=True)
                legacy_path.parent.mkdir(parents=True, exist_ok=True)

                fresh = TableBaseline(
                    dag="dw_x",
                    table="dim_sample",
                    layer="dw",
                    load_start_date="2026-06-04",
                    load_end_date="2026-06-05",
                    schema=[("id", "bigint")],
                    count=99,
                    sample_rows=0,
                    sample=[],
                    order_by_cols=["id"],
                    time_pinned_functions=[],
                    non_comparable_cols=[],
                    sql_hash="fresh",
                )
                stale = TableBaseline(
                    dag="dw_x",
                    table="dim_sample",
                    layer="dw",
                    load_start_date="2026-01-01",
                    load_end_date="2026-01-02",
                    schema=[("id", "bigint")],
                    count=1,
                    sample_rows=0,
                    sample=[],
                    order_by_cols=["id"],
                    time_pinned_functions=[],
                    non_comparable_cols=[],
                    sql_hash="stale",
                )
                for path, payload in ((layer_path, fresh), (legacy_path, stale)):
                    path.write_text(
                        json.dumps({**payload.__dict__, "schema": payload.schema}),
                        encoding="utf-8",
                    )

                loaded = load_baselines("fintech", "dw_x")
                self.assertEqual(len(loaded), 1)
                self.assertEqual(loaded[0].sql_hash, "fresh")
            finally:
                baseline_module.BASELINE_ROOT = original_root

    def test_is_baseline_valid_accepts_empty_table(self) -> None:
        baseline = TableBaseline(
            dag="dw_credit_analysis",
            table="fact_fintechops_tasks",
            layer="dw",
            load_start_date="2026-06-07",
            schema=[],
            count=0,
            sample_rows=0,
            sample=[],
            order_by_cols=[],
            time_pinned_functions=[],
            non_comparable_cols=[],
        )
        self.assertTrue(is_baseline_valid(baseline))

    def test_repo_root_points_at_bi_etl_ejuice(self) -> None:
        self.assertTrue((REPO_ROOT / "dags").is_dir())


if __name__ == "__main__":
    unittest.main()
