"""Unit tests for scripts/promote_rightsizing_validations.py."""

from __future__ import annotations

import json
import sys
from datetime import date
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from scripts import promote_rightsizing_validations as prv  # noqa: E402


def _row(**kwargs) -> dict:
    defaults = {
        "prod_airflow_dag_id": "bietlejuice.test_dag",
        "dt": "2026-06-10",
        "schedule_interval_minutes": "1440",
        "prod_avg_cost_usd": "1.00",
        "val_avg_cost_usd": "0.80",
        "prod_wall_p50_min": "10.0",
        "prod_wall_p95_min": "15.0",
        "val_wall_p50_min": "10.4",
        "val_wall_p95_min": "14.0",
        "val_clean_run_count": "2",
        "val_failure_count": "0",
        "val_drv_mem_p95": "70.0",
        "val_wrk_mem_p95": "65.0",
    }
    defaults.update(kwargs)
    return defaults


class TestDecidePromotionAction:
    def test_promote_on_clean_lower_cost_and_acceptable_wall(self):
        decision = prv.decide_promotion_action(_row())
        assert decision.action == "promote"
        assert decision.outcome == "pass"

    def test_reject_on_validation_failure(self):
        decision = prv.decide_promotion_action(_row(val_failure_count="1"))
        assert decision.action == "reject"
        assert decision.outcome == "fail"

    def test_reject_when_validation_cost_exceeds_tolerance(self):
        decision = prv.decide_promotion_action(_row(val_avg_cost_usd="1.10"))
        assert decision.action == "reject"

    def test_promote_when_cost_within_five_percent_tolerance(self):
        decision = prv.decide_promotion_action(_row(val_avg_cost_usd="1.03"))
        assert decision.action == "promote"

    def test_reject_when_cost_above_five_percent_tolerance(self):
        decision = prv.decide_promotion_action(_row(val_avg_cost_usd="1.06"))
        assert decision.action == "reject"

    def test_extend_when_no_clean_validation_runs(self):
        decision = prv.decide_promotion_action(_row(val_clean_run_count="0"))
        assert decision.action == "extend"
        assert decision.outcome == "extend"

    def test_extend_on_memory_guard(self):
        decision = prv.decide_promotion_action(_row(val_drv_mem_p95="88.0"))
        assert decision.action == "extend"
        assert decision.outcome == "warn"
        assert "memory" in decision.reason.lower()

    def test_reject_on_wall_breach_for_hourly_schedule(self):
        decision = prv.decide_promotion_action(
            _row(
                schedule_interval_minutes="60",
                prod_wall_p95_min="40.0",
                val_wall_p95_min="55.0",
            )
        )
        assert decision.action == "reject"

    def test_promote_for_hourly_when_wall_within_sla(self):
        decision = prv.decide_promotion_action(
            _row(
                schedule_interval_minutes="60",
                prod_wall_p95_min="40.0",
                val_wall_p95_min="48.0",
            )
        )
        assert decision.action == "promote"

    def test_promote_for_hourly_when_wall_within_five_percent_of_prod(self):
        decision = prv.decide_promotion_action(
            _row(
                schedule_interval_minutes="60",
                prod_wall_p95_min="40.0",
                val_wall_p95_min="42.0",
            )
        )
        assert decision.action == "promote"

    def test_reject_when_unconstrained_wall_exceeds_five_percent_of_prod(self):
        decision = prv.decide_promotion_action(
            _row(
                schedule_interval_minutes="240",
                prod_wall_p50_min="10.0",
                val_wall_p50_min="16.0",
            )
        )
        assert decision.action == "reject"

    def test_reject_after_validation_age_cap_without_clean_run(self):
        decision = prv.decide_promotion_action(
            _row(val_clean_run_count="0"),
            validation_age_days=15,
        )
        assert decision.action == "reject"
        assert "freeing validation slot" in decision.reason


class TestPromoteValidationClusterFile:
    def test_moves_validation_cluster_into_prod_block(self, tmp_path):
        cluster_path = tmp_path / "test_cluster.yml"
        cluster_path.write_text(
            "cluster:\n"
            "  type: consolidation_s_general_cluster\n"
            "  databricks_conn_id: databricks_new\n"
            "  custom_configurations:\n"
            "    num_workers: 3\n"
            "validation:\n"
            "  cluster:\n"
            "    type: consolidation_s_memory_single_node_cluster\n"
            "    databricks_conn_id: databricks_new\n",
            encoding="utf-8",
        )

        previous = prv.promote_validation_cluster_file(cluster_path)

        assert previous == {
            "type": "consolidation_s_general_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {"num_workers": 3},
        }
        doc = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
        assert doc["cluster"]["type"] == "consolidation_s_memory_single_node_cluster"
        assert "validation" not in doc

    def test_preserves_spark_session_configs_tail(self, tmp_path):
        cluster_path = tmp_path / "test_cluster.yml"
        cluster_path.write_text(
            "cluster:\n"
            "  type: old_cluster_type\n"
            "spark_session_configs:\n"
            "  spark.sql.shuffle.partitions: 200\n"
            "validation:\n"
            "  cluster:\n"
            "    type: consolidation_xs_memory_cluster\n"
            "    databricks_conn_id: databricks_new_env\n",
            encoding="utf-8",
        )

        prv.promote_validation_cluster_file(cluster_path)

        text = cluster_path.read_text(encoding="utf-8")
        assert "spark_session_configs:" in text
        assert "spark.sql.shuffle.partitions: 200" in text
        assert "validation:" not in text
        doc = yaml.safe_load(text)
        assert doc["cluster"]["type"] == "consolidation_xs_memory_cluster"

    def test_returns_none_when_validation_block_missing(self, tmp_path):
        cluster_path = tmp_path / "test_cluster.yml"
        cluster_path.write_text(
            "cluster:\n  type: only_prod\n  databricks_conn_id: databricks_new\n",
            encoding="utf-8",
        )
        assert prv.promote_validation_cluster_file(cluster_path) is None


class TestWatchPromotions:
    def test_flags_cost_regression_with_revert_spec(self, tmp_path):
        ledger_path = tmp_path / "ledger.json"
        previous_spec = {
            "type": "consolidation_s_general_cluster",
            "databricks_conn_id": "databricks_new",
        }
        ledger_path.write_text(
            json.dumps(
                {
                    "entries": [
                        {
                            "dag_id": "bietlejuice.test_dag",
                            "promoted_at": "2026-06-09",
                            "previous_cluster_spec": previous_spec,
                            "baseline": {"avg_cost_usd": 1.0, "wall_p95_min": 15.0},
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        rows = [
            _row(
                dt="2026-06-10",
                prod_avg_cost_usd="1.20",
                schedule_interval_minutes="1440",
            )
        ]

        alerts = prv.watch_promotions(
            rows,
            ledger_path,
            as_of=date(2026, 6, 10),
        )

        assert len(alerts) == 1
        assert "cost" in alerts[0]
        assert "consolidation_s_general_cluster" in alerts[0]


class TestDecidePromotionForDagWindow:
    """Per-day rows must aggregate: the newest day alone is not the evidence."""

    def test_quiet_latest_day_does_not_hide_earlier_clean_pass(self):
        rows = [
            _row(dt="2026-06-08"),  # clean, cheaper → promote-worthy
            _row(
                dt="2026-06-10",  # no validation run that day
                val_clean_run_count="0",
                val_run_count="0",
                val_avg_cost_usd="",
                val_wall_p50_min="",
                val_wall_p95_min="",
            ),
        ]
        decision, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "promote"
        assert row["dt"] == "2026-06-08"  # ledger baseline anchored on pass day

    def test_failure_newer_than_pass_rejects(self):
        rows = [
            _row(dt="2026-06-08"),
            _row(dt="2026-06-10", val_failure_count="1", val_run_count="1"),
        ]
        decision, _ = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "reject"

    def test_pass_newer_than_failure_promotes(self):
        rows = [
            _row(dt="2026-06-08", val_failure_count="1", val_run_count="1"),
            _row(dt="2026-06-10"),
        ]
        decision, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "promote"
        assert row["dt"] == "2026-06-10"

    def test_mem_warn_newer_than_pass_holds_promotion(self):
        # The OOM guard must never be bypassed by an older passing day.
        rows = [
            _row(dt="2026-06-08"),  # clean pass
            _row(dt="2026-06-10", val_drv_mem_p95="90.0", val_run_count="1"),
        ]
        decision, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "extend"
        assert decision.outcome == "warn"
        assert row["dt"] == "2026-06-10"

    def test_pass_newer_than_mem_warn_promotes(self):
        rows = [
            _row(dt="2026-06-08", val_drv_mem_p95="90.0", val_run_count="1"),
            _row(dt="2026-06-10"),
        ]
        decision, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "promote"
        assert row["dt"] == "2026-06-10"

    def test_no_validation_activity_extends(self):
        rows = [
            _row(
                dt="2026-06-10",
                val_clean_run_count="0",
                val_run_count="0",
                val_avg_cost_usd="",
            )
        ]
        decision, _ = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "extend"


class TestValidationRunGrain:
    def test_two_clean_passes_picks_latest_decisive_run(self):
        rows = [
            _row(
                validation_airflow_run_id="manual__2026-06-08",
                val_dt="2026-06-08",
            ),
            _row(
                validation_airflow_run_id="manual__2026-06-10",
                val_dt="2026-06-10",
            ),
        ]
        decision, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "promote"
        assert row["validation_airflow_run_id"] == "manual__2026-06-10"

    def test_failure_newer_than_pass_rejects(self):
        rows = [
            _row(
                validation_airflow_run_id="manual__pass",
                val_dt="2026-06-08",
                val_ts_started="2026-06-08 10:00:00",
            ),
            _row(
                validation_airflow_run_id="manual__fail",
                val_dt="2026-06-10",
                val_ts_started="2026-06-10 10:00:00",
                val_failure_count="1",
                val_run_count="1",
            ),
        ]
        decision, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "reject"
        assert row["validation_airflow_run_id"] == "manual__fail"

    def test_pass_newer_than_failure_promotes(self):
        rows = [
            _row(
                validation_airflow_run_id="manual__fail",
                val_dt="2026-06-08",
                val_ts_started="2026-06-08 10:00:00",
                val_failure_count="1",
                val_run_count="1",
            ),
            _row(
                validation_airflow_run_id="manual__pass",
                val_dt="2026-06-10",
                val_ts_started="2026-06-10 10:00:00",
            ),
        ]
        decision, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "promote"
        assert row["validation_airflow_run_id"] == "manual__pass"

    def test_mem_warn_newer_than_pass_holds_promotion(self):
        rows = [
            _row(
                validation_airflow_run_id="manual__pass",
                val_dt="2026-06-08",
                val_ts_started="2026-06-08 10:00:00",
            ),
            _row(
                validation_airflow_run_id="manual__warn",
                val_dt="2026-06-10",
                val_ts_started="2026-06-10 10:00:00",
                val_drv_mem_p95="90.0",
                val_run_count="1",
            ),
        ]
        decision, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "extend"
        assert decision.outcome == "warn"
        assert row["validation_airflow_run_id"] == "manual__warn"

    def test_pass_newer_than_mem_warn_promotes(self):
        rows = [
            _row(
                validation_airflow_run_id="manual__warn",
                val_dt="2026-06-08",
                val_ts_started="2026-06-08 10:00:00",
                val_drv_mem_p95="90.0",
                val_run_count="1",
            ),
            _row(
                validation_airflow_run_id="manual__pass",
                val_dt="2026-06-10",
                val_ts_started="2026-06-10 10:00:00",
            ),
        ]
        decision, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "promote"
        assert row["validation_airflow_run_id"] == "manual__pass"

    def test_latest_extend_does_not_hide_older_pass(self):
        rows = [
            _row(
                validation_airflow_run_id="manual__pass",
                val_dt="2026-06-08",
                val_ts_started="2026-06-08 10:00:00",
            ),
            _row(
                validation_airflow_run_id="manual__extend",
                val_dt="2026-06-10",
                val_ts_started="2026-06-10 10:00:00",
                val_clean_run_count="0",
                val_avg_cost_usd="",
                val_wall_p50_min="",
                val_wall_p95_min="",
            ),
        ]
        decision, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert decision.action == "promote"
        assert row["validation_airflow_run_id"] == "manual__pass"

    def test_same_day_picks_latest_val_ts_started(self):
        rows = [
            _row(
                validation_airflow_run_id="manual__2026-06-11T10:00:00",
                val_dt="2026-06-11",
                val_ts_started="2026-06-11 10:00:00",
            ),
            _row(
                validation_airflow_run_id="manual__2026-06-11T20:00:00",
                val_dt="2026-06-11",
                val_ts_started="2026-06-11 20:00:00",
            ),
        ]
        _, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert row["validation_airflow_run_id"] == "manual__2026-06-11T20:00:00"

    def test_duplicate_is_latest_flag_uses_val_ts_started(self):
        rows = [
            _row(
                validation_airflow_run_id="manual__older",
                val_dt="2026-06-11",
                val_ts_started="2026-06-11 10:00:00",
            ),
            _row(
                validation_airflow_run_id="manual__newer",
                val_dt="2026-06-20",
                val_ts_started="2026-06-20 15:00:00",
            ),
        ]
        _, row = prv.decide_promotion_for_dag(rows, "bietlejuice.test_dag")
        assert row["validation_airflow_run_id"] == "manual__newer"

    def test_latest_row_per_dag_uses_val_ts_started(self):
        rows = [
            _row(
                prod_airflow_dag_id="bietlejuice.test_dag",
                validation_airflow_run_id="manual__older",
                val_dt="2026-06-11",
                val_ts_started="2026-06-11 10:00:00",
            ),
            _row(
                prod_airflow_dag_id="bietlejuice.test_dag",
                validation_airflow_run_id="manual__newer",
                val_dt="2026-06-11",
                val_ts_started="2026-06-11 22:00:00",
            ),
        ]
        latest = prv.latest_row_per_dag(rows)
        assert (
            latest["bietlejuice.test_dag"]["validation_airflow_run_id"]
            == "manual__newer"
        )

    def test_decisive_row_per_dag_uses_newest_decisive_signal(self):
        rows = [
            _row(
                prod_airflow_dag_id="bietlejuice.test_dag",
                validation_airflow_run_id="manual__pass",
                val_dt="2026-06-08",
                val_ts_started="2026-06-08 10:00:00",
            ),
            _row(
                prod_airflow_dag_id="bietlejuice.test_dag",
                validation_airflow_run_id="manual__extend",
                val_dt="2026-06-10",
                val_ts_started="2026-06-10 10:00:00",
                val_clean_run_count="0",
                val_avg_cost_usd="",
            ),
        ]
        decisive = prv.decisive_row_per_dag(rows)
        assert (
            decisive["bietlejuice.test_dag"]["validation_airflow_run_id"]
            == "manual__pass"
        )

    def test_has_strong_positive_signal_on_large_savings(self):
        row = _row(
            val_clean_run_count="0",
            val_avg_cost_usd="0.50",
            prod_avg_cost_usd="1.00",
        )
        assert prv._has_strong_positive_signal(row) is True
