"""Unit tests for scripts/recommend_cluster_specs.py.

The recommender is intentionally single-node-first: multi-node clusters are
collapsed when additive CPU/memory demand, schedule SLA, and cost all fit.
Multi-node recommendations are now narrow keep exits plus driver minimization.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from scripts import recommend_cluster_specs as rcs  # noqa: E402
from scripts.recommend_cluster_specs import (  # noqa: E402
    AMD_WALL_CORRECTION,
    PRESET_CATALOG,
    DagMetrics,
    _current_cost_basis,
    build_amd_recommendation,
    build_recommendation,
    build_sql,
    build_validation_outcomes,
    build_validation_sql,
    classify,
    classify_amd_for_collapse,
    estimate_cost,
    estimate_drv_cpu_after_collapse,
    estimate_projected_total_cost,
    generate_validation_config,
    infer_current_preset,
    recommend_preset,
    size_single_node,
    write_validation_cluster_file,
)


def _m(**kwargs) -> DagMetrics:
    defaults = dict(
        dag_id="bietlejuice.test_dag",
        arm_days=5,
        arm_runs=10,
        driver_node_type="m6g.xlarge",
        worker_node_type="m6g.xlarge",
        worker_count=2,
        arm_total_cost_usd=80.0,
        arm_avg_cost_per_run_usd=8.0,
        arm_total_cost_estimate_usd=80.0,
        arm_avg_total_cost_estimate_usd=8.0,
        arm_total_ec2_cost_usd=30.0,
        arm_avg_ec2_cost_usd=3.0,
        arm_total_dbu_cost_usd=50.0,
        arm_avg_dbu_cost_usd=5.0,
        ec2_spot_hours=20.0,
        ec2_on_demand_hours=10.0,
        runs_per_day=1.0,
        schedule_interval_minutes=1440.0,
        wall_p50_min=10.0,
        wall_p95_min=20.0,
        drv_cpu_p50=30.0,
        drv_cpu_p95=50.0,
        drv_mem_p95=40.0,
        drv_wait_p95=2.0,
        wrk_cpu_p50=20.0,
        wrk_cpu_p95=40.0,
        wrk_mem_p95=30.0,
        wrk_wait_p95=2.0,
    )
    defaults.update(kwargs)
    if (
        "driver_node_type" in kwargs
        and "worker_node_type" not in kwargs
        and defaults.get("worker_count") not in (0, None)
    ):
        defaults["worker_node_type"] = defaults["driver_node_type"]
    if (
        "arm_avg_total_cost_estimate_usd" in kwargs
        and "arm_avg_cost_per_run_usd" not in kwargs
    ):
        defaults["arm_avg_cost_per_run_usd"] = kwargs[
            "arm_avg_total_cost_estimate_usd"
        ]
    return DagMetrics(**defaults)


class TestClassifyQualityGates:
    def test_needs_more_arm_data(self):
        assert classify(_m(arm_days=2, arm_runs=10)) == "needs_more_arm_data"
        assert classify(_m(arm_days=5, arm_runs=2)) == "needs_more_arm_data"

    def test_autoscale_and_mixed_config_review(self):
        assert classify(_m(worker_count=None)) == "autoscale_review"
        assert classify(_m(dominant_config_run_share=0.5)) == "mixed_config_review"

    def test_missing_metrics_and_cost_confidence_review(self):
        assert classify(_m(drv_cpu_p95=None)) == "needs_more_telemetry"
        assert classify(_m(ec2_pricing_missing=True)) == "cost_confidence_review"
        assert (
            classify(_m(dbu_negotiated_price_missing=True)) == "cost_confidence_review"
        )

    def test_spill_pressure_review(self):
        assert classify(_m(total_disk_bytes_spilled=1)) == "spill_pressure_review"

    def test_multi_node_unknown_worker_type_returns_needs_more_telemetry(self):
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type="unknown.type",
            worker_count=2,
        )

        assert classify(m) == "needs_more_telemetry"
        assert build_recommendation(m).cohort == "needs_more_telemetry"


class TestSingleNodeBranch:
    def test_single_node_oom_risk_promotes_general_to_memory_family(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            drv_mem_p95=90.0,
            arm_avg_total_cost_estimate_usd=2.0,
            arm_avg_ec2_cost_usd=0.154,
            arm_avg_dbu_cost_usd=1.846,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "protect_oom_risk"
        assert rec.recommended_preset == "consolidation_s_memory_single_node_cluster"
        assert rec.rec_driver_node_type == "r6g.xlarge"
        assert rec.projected.est_drv_mem_p95 == "projected 45.0%"

    def test_single_node_oom_risk_promotes_compute_to_general_family(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            driver_node_type="c6g.xlarge",
            drv_mem_p95=90.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "protect_oom_risk"
        assert rec.recommended_preset == "consolidation_s_general_single_node_cluster"
        assert rec.rec_driver_node_type == "m6g.xlarge"

    def test_single_node_oom_risk_on_memory_family_steps_up_size_tier(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            driver_node_type="r6g.xlarge",
            drv_mem_p95=90.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "protect_oom_risk"
        assert rec.recommended_preset == "consolidation_m_memory_single_node_cluster"
        assert rec.rec_driver_node_type == "r6g.2xlarge"
        assert rec.projected.est_drv_mem_p95 == "projected 45.0%"

    def test_single_node_oom_risk_on_memory_xl_cannot_upsize(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            driver_node_type="r6g.8xlarge",
            drv_mem_p95=90.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "protect_oom_risk"
        assert rec.recommended_preset is None
        assert generate_validation_config(rec) is None

    def test_single_node_low_cpu_and_mem_downsizes(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            drv_cpu_p95=10.0,
            drv_mem_p95=20.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "driver_downsize"
        assert rec.rec_driver_node_type == "m6g.large"

    def test_single_node_hot_cpu_is_healthy_not_auto_keep(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            drv_cpu_p95=90.0,
            drv_mem_p95=50.0,
        )

        assert classify(m) == "healthy_single"


class TestAdditiveSingleNodeSizing:
    def test_driver_bound_idle_workers_collapse_to_sized_single_node(self):
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            drv_cpu_p50=55.0,
            drv_cpu_p95=82.0,
            drv_mem_p95=35.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
            wall_p95_min=12.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "collapse_to_single"
        assert rec.rec_driver_node_type == "m6g.2xlarge"
        assert rec.rec_worker_count == 0
        assert rec.projected.est_drv_mem_p95 == "projected 27.5%"

    def test_sizer_uses_actual_gib_per_core_not_current_family(self):
        m = _m(
            driver_node_type="r6g.2xlarge",
            worker_node_type="r6g.2xlarge",
            worker_count=2,
            drv_cpu_p95=20.0,
            drv_mem_p95=10.0,
            wrk_cpu_p95=15.0,
            wrk_mem_p95=7.5,
        )

        sizing = size_single_node(m)
        rec = build_recommendation(m)

        assert sizing.node_type == "m6g.2xlarge"
        assert sizing.projected_mem_pct == pytest.approx(50.0)
        assert rec.cohort == "collapse_to_single"
        assert rec.rec_driver_node_type == "m6g.2xlarge"

    def test_memory_pressure_collapses_to_memory_single_node_when_additive_load_fits(
        self,
    ):
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            drv_cpu_p95=35.0,
            drv_mem_p95=78.0,
            wrk_cpu_p95=8.0,
            wrk_mem_p95=38.3,
            wall_p95_min=15.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "collapse_to_single"
        assert rec.rec_driver_node_type == "r6g.xlarge"
        assert rec.projected.est_drv_mem_p95 == "projected 77.3%"

    def test_large_single_node_without_exact_preset_uses_driver_override(self):
        import os

        os.environ["ENVIRONMENT"] = "prod"
        m = _m(
            driver_node_type="r6g.8xlarge",
            worker_node_type="r6g.8xlarge",
            worker_count=2,
            drv_cpu_p95=25.0,
            drv_mem_p95=55.0,
            wrk_cpu_p95=5.0,
            wrk_mem_p95=30.0,
            wall_p95_min=20.0,
            arm_avg_total_cost_estimate_usd=100.0,
            arm_avg_ec2_cost_usd=40.0,
            arm_avg_dbu_cost_usd=60.0,
        )

        rec = build_recommendation(m)
        cfg = generate_validation_config(rec)

        assert rec.cohort == "collapse_to_single"
        assert rec.rec_driver_node_type == "r6g.12xlarge"
        assert rec.recommended_preset == "consolidation_xl_memory_single_node_cluster"
        assert cfg is not None
        assert cfg["validation"]["cluster"]["custom_configurations"] == {
            "driver_node_type_id": "r6g.12xlarge"
        }

    def test_r7g_current_cluster_maps_to_valid_single_node_preset(self):
        m = _m(
            driver_node_type="r7g.2xlarge",
            worker_node_type="r7g.2xlarge",
            worker_count=4,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
            wall_p95_min=10.0,
            arm_avg_total_cost_estimate_usd=100.0,
            arm_avg_ec2_cost_usd=40.0,
            arm_avg_dbu_cost_usd=60.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "collapse_to_single"
        assert rec.recommended_preset is not None
        assert rec.rec_driver_node_type is not None


class TestSingleNodeFirstKeepMultiGuards:
    def test_keep_multi_driver_minimize_can_shift_to_compute_family(self):
        m = _m(
            driver_node_type="r6g.2xlarge",
            worker_node_type="r6g.16xlarge",
            worker_count=2,
            drv_cpu_p95=50.0,
            drv_mem_p95=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=95.0,
            arm_avg_total_cost_estimate_usd=80.0,
            arm_avg_ec2_cost_usd=20.0,
            arm_avg_dbu_cost_usd=60.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "keep_multi_memory"
        assert rec.rec_driver_node_type == "c6g.2xlarge"
        assert "reduce_driver" in rec.actions.split("|")

    def test_keep_multi_never_upsizes_hot_driver_as_reduce_driver(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="m6g.large",
            worker_count=2,
            drv_cpu_p95=90.0,
            drv_mem_p95=50.0,
            wrk_cpu_p50=60.0,
            wrk_cpu_p95=70.0,
            wrk_mem_p95=65.0,
            wall_p95_min=20.0,
            arm_avg_total_cost_estimate_usd=10.0,
            arm_avg_ec2_cost_usd=2.0,
            arm_avg_dbu_cost_usd=8.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "keep_multi_balanced"
        assert rec.rec_driver_node_type == "m6g.large"
        assert "reduce_driver" not in rec.actions.split("|")

    def test_hourly_opa_istio_shape_stays_multi_for_sla_and_minimizes_driver(self):
        import os

        os.environ["ENVIRONMENT"] = "prod"
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="m6g.2xlarge",
            worker_count=5,
            drv_cpu_p95=35.0,
            drv_mem_p95=35.0,
            wrk_cpu_p50=18.0,
            wrk_cpu_p95=35.0,
            wrk_mem_p95=20.0,
            wrk_wait_p95=12.0,
            wall_p95_min=44.0,
            schedule_interval_minutes=60.0,
            arm_avg_total_cost_estimate_usd=12.0,
            arm_avg_ec2_cost_usd=5.0,
            arm_avg_dbu_cost_usd=7.0,
        )

        rec = build_recommendation(m)
        cfg = generate_validation_config(rec)

        assert rec.cohort == "keep_multi_sla"
        assert rec.recommended_preset == "consolidation_s_general_cluster"
        assert rec.rec_driver_node_type == "m6g.large"
        assert rec.rec_worker_node_type == "m6g.xlarge"
        assert rec.num_workers_override == 5
        assert cfg is not None
        assert cfg["validation"]["cluster"]["custom_configurations"] == {
            "num_workers": 5,
            "driver_node_type_id": "m6g.large",
        }

    def test_keep_multi_downsizes_worker_type_without_reducing_count(self):
        import os

        os.environ["ENVIRONMENT"] = "prod"
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="r6g.4xlarge",
            worker_count=2,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
            wall_p50_min=18.0,
            wall_p95_min=18.0,
            schedule_interval_minutes=20.0,
            arm_avg_total_cost_estimate_usd=8.0,
            arm_avg_ec2_cost_usd=1.5,
            arm_avg_dbu_cost_usd=6.5,
        )

        rec = build_recommendation(m)
        cfg = generate_validation_config(rec)

        assert rec.cohort == "keep_multi_sla"
        assert rec.rec_worker_node_type == "r6g.large"
        assert rec.rec_worker_count == 2
        assert (
            rec.actions
            == "keep_multi_node|keep_driver|reduce_worker_type|keep_worker_count"
        )
        assert cfg is not None
        custom = cfg["validation"]["cluster"]["custom_configurations"]
        assert custom["driver_node_type_id"] == "m6g.large"
        assert "node_type_id" not in custom

    def test_keep_multi_conservatively_reduces_worker_count_when_sla_allows(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="r6g.8xlarge",
            worker_count=8,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=25.0,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            schedule_interval_minutes=240.0,
            arm_avg_total_cost_estimate_usd=40.0,
            arm_avg_ec2_cost_usd=15.0,
            arm_avg_dbu_cost_usd=25.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "keep_multi_memory"
        assert rec.rec_worker_node_type == "r6g.4xlarge"
        assert rec.rec_worker_count == 6
        assert "reduce_worker_count" in rec.actions.split("|")
        assert rec.num_workers_override == 6

    def test_keep_multi_worker_count_reduction_is_blocked_by_sla(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="r6g.8xlarge",
            worker_count=8,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=25.0,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            schedule_interval_minutes=40.0,
            arm_avg_total_cost_estimate_usd=40.0,
            arm_avg_ec2_cost_usd=15.0,
            arm_avg_dbu_cost_usd=25.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "keep_multi_memory"
        assert rec.rec_worker_node_type == "r6g.4xlarge"
        assert rec.rec_worker_count == 8
        assert "worker_count_blocked_sla" in rec.actions.split("|")

    def test_keep_multi_resize_falls_back_when_cost_guard_blocks(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="r6g.4xlarge",
            worker_count=2,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
            wall_p50_min=18.0,
            wall_p95_min=18.0,
            schedule_interval_minutes=20.0,
            arm_avg_total_cost_estimate_usd=0.01,
            arm_avg_ec2_cost_usd=0.005,
            arm_avg_dbu_cost_usd=0.005,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "keep_multi_sla"
        assert rec.rec_worker_node_type == "r6g.4xlarge"
        assert rec.rec_worker_count == 2
        assert "resize_blocked_cost" in rec.actions.split("|")
        assert generate_validation_config(rec) is None
        assert rec.projected.est_cost_delta_pct == pytest.approx(0.0)
        assert rec.projected.blocked_cost_delta_pct is not None
        assert rec.projected.blocked_cost_delta_pct > 0.0
        assert rcs._format_delta(rec).startswith("  est 0% (")

    def test_opa_like_spiky_hourly_shape_stays_multi_for_sla_before_cost(self):
        m = _m(
            dag_id="bietlejuice.opa",
            driver_node_type="r6g.2xlarge",
            worker_node_type="r6g.2xlarge",
            worker_count=2,
            arm_days=7,
            arm_runs=132,
            runs_per_day=18.857,
            schedule_interval_minutes=76.4,
            wall_p95_min=27.9,
            drv_cpu_p95=46.2,
            drv_mem_p95=39.7,
            wrk_cpu_p50=14.5,
            wrk_cpu_p95=75.9,
            wrk_mem_p95=34.9,
            arm_avg_total_cost_estimate_usd=0.4052,
            arm_avg_ec2_cost_usd=0.2189,
            arm_avg_dbu_cost_usd=0.2451,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "keep_multi_sla"

    def test_busy_spot_cluster_stays_multi_when_on_demand_collapse_costs_more(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="m6g.2xlarge",
            worker_count=2,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p95=80.0,
            wrk_mem_p95=50.0,
            wall_p95_min=20.0,
            arm_avg_total_cost_estimate_usd=1.0,
            arm_avg_ec2_cost_usd=0.305,
            arm_avg_dbu_cost_usd=0.695,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "keep_multi_cost"
        assert rec.recommended_preset == "consolidation_m_general_cluster"
        assert rec.projected.est_cost_delta_pct == pytest.approx(0.0)
        assert rec.projected.blocked_cost_delta_pct > 0

    def test_demand_over_largest_single_node_stays_multi_memory(self):
        m = _m(
            driver_node_type="r6g.16xlarge",
            worker_node_type="r6g.16xlarge",
            worker_count=2,
            drv_cpu_p95=20.0,
            drv_mem_p95=95.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=95.0,
            wall_p95_min=20.0,
            arm_avg_total_cost_estimate_usd=200.0,
            arm_avg_ec2_cost_usd=100.0,
            arm_avg_dbu_cost_usd=100.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "keep_multi_memory"
        assert rec.recommended_preset == "consolidation_xl_memory_cluster"

    def test_driver_and_workers_both_hot_stays_multi_balanced(self):
        m = _m(
            driver_node_type="m6g.2xlarge",
            worker_node_type="m6g.2xlarge",
            worker_count=2,
            drv_cpu_p95=75.0,
            drv_mem_p95=70.0,
            wrk_cpu_p50=55.0,
            wrk_cpu_p95=70.0,
            wrk_mem_p95=65.0,
            arm_avg_total_cost_estimate_usd=100.0,
            arm_avg_ec2_cost_usd=40.0,
            arm_avg_dbu_cost_usd=60.0,
        )

        assert classify(m) == "keep_multi_balanced"


class TestCostProjection:
    def test_legacy_estimate_cost_still_scales_by_vcpu_for_fallbacks(self):
        result = estimate_cost(
            3.0,
            "m6g.xlarge",
            "m6g.xlarge",
            2,
            "m6g.xlarge",
            None,
            0,
        )

        assert result == pytest.approx(1.0, rel=1e-4)

    def test_unknown_node_type_returns_none(self):
        assert (
            estimate_cost(1.0, "unknown.type", None, 0, "m6g.xlarge", None, 0) is None
        )

    def test_estimate_driver_cpu_after_collapse_caps_at_90(self):
        est, uncertain = estimate_drv_cpu_after_collapse(
            50.0, 60.0, "m6g.xlarge", "m6g.xlarge", 2
        )

        assert est == pytest.approx(90.0)
        assert uncertain is True

    def test_projected_ec2_cost_uses_runtime_not_full_hour_price(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="m6g.large",
            worker_count=8,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=20.0,
            wall_p50_min=5.0,
            wall_p95_min=7.0,
            arm_avg_total_cost_estimate_usd=0.20,
            arm_avg_ec2_cost_usd=0.04,
            arm_avg_dbu_cost_usd=0.16,
        )

        projected = estimate_projected_total_cost(m, "m6g.2xlarge", 0)
        rec = build_recommendation(m)

        assert projected is not None
        assert projected < 0.20
        assert rec.cohort == "collapse_to_single"

    def test_projected_multi_node_cost_accounts_for_worker_type_and_count_resize(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="r6g.8xlarge",
            worker_count=8,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=25.0,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            schedule_interval_minutes=240.0,
            arm_avg_total_cost_estimate_usd=40.0,
            arm_avg_ec2_cost_usd=15.0,
            arm_avg_dbu_cost_usd=25.0,
        )

        projected = estimate_projected_total_cost(
            m,
            "m6g.large",
            6,
            rec_worker="r6g.4xlarge",
        )
        worker_activity = max(5.0 / 85.0, 10.0 / 85.0, 25.0 / 82.0)
        wall_inflation = 1.0 + (8 / 6 - 1.0) * worker_activity
        current_driver_ec2 = 0.077 * 30.0 / 60.0
        measured_worker_ec2 = 15.0 - current_driver_ec2
        expected = (
            25.0 * (2 + 6 * 16) / (2 + 8 * 32) * wall_inflation
            + measured_worker_ec2 * ((6 * 0.8064) / (8 * 1.6128)) * wall_inflation
            + 0.077 * (30.0 * wall_inflation) / 60.0
        )

        assert projected == pytest.approx(expected)


class TestPresetAndValidation:
    def test_infer_current_preset(self):
        assert (
            infer_current_preset("m6g.xlarge", "m6g.xlarge", 2)
            == "consolidation_s_general_cluster"
        )
        assert (
            infer_current_preset("m6g.2xlarge", None, 0)
            == "consolidation_m_general_single_node_cluster"
        )

    def test_recommend_preset_uses_additive_sized_single_node(self):
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            drv_cpu_p95=82.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
        )

        name, override = recommend_preset("collapse_to_single", m)

        assert name == "consolidation_m_general_single_node_cluster"
        assert override is None

    def test_validation_config_omits_non_actionable_recommendations(self):
        rec = build_recommendation(
            _m(
                worker_count=0,
                worker_node_type=None,
                drv_cpu_p95=70.0,
                drv_mem_p95=50.0,
            )
        )

        assert rec.cohort == "healthy_single"
        assert generate_validation_config(rec) is None

    def test_preset_catalog_sanity(self):
        assert PRESET_CATALOG["consolidation_m_general_cluster"].num_workers == 2
        assert (
            PRESET_CATALOG["consolidation_m_general_single_node_cluster"].num_workers
            == 0
        )


class TestSqlAndRowMapping:
    def test_report_schema_includes_actions_column(self):
        rec = build_recommendation(_m(worker_count=0, worker_node_type=None))
        row = rcs._rec_to_row(rec)

        assert "actions" in rcs._CSV_FIELDS
        assert row["actions"]

    def test_report_schema_includes_blocked_cost_delta_columns(self):
        row = rcs._rec_to_row(
            build_recommendation(_m(worker_count=0, worker_node_type=None))
        )

        assert "blocked_cost_per_run_usd" in rcs._CSV_FIELDS
        assert "blocked_cost_delta_pct" in rcs._CSV_FIELDS
        assert "blocked_cost_delta_pct" in row

    def test_sql_projects_cadence_and_cost_authority_inputs(self):
        sql = build_sql(days=90, min_days=3, min_runs=3)
        amd_sql = rcs.build_amd_sql(days=90, min_days=3, min_runs=3, amd_min_runs=3)

        assert "runs_per_day" in sql
        assert "schedule_interval_minutes" in sql
        assert "total_ec2_cost_calculated_usd" in sql
        assert "ec2_spot_hours" in sql
        assert "ec2_on_demand_hours" in sql
        assert "total_dbu_cost_usd" in sql
        assert "total_dbu_consumed" in sql
        assert "arm_avg_dbu_consumed" in sql
        assert "COALESCE(total_cost_usd, 0) > 0" in sql
        assert "COALESCE(total_cost_usd, 0) > 0" in amd_sql
        assert "total_dbu_list_cost_usd" not in sql
        assert "total_dbu_list_cost_usd" not in amd_sql
        assert "config_total_cost_usd" in sql
        assert "is_job_on_interactive = FALSE" in sql
        assert "is_any_task_failed = FALSE" in sql
        assert "is_any_databricks_run_failed = FALSE" in sql
        assert "NOT REGEXP_LIKE(airflow_dag_id, '__validation$')" in sql
        assert "NOT REGEXP_LIKE(airflow_dag_id, '__validation$')" in amd_sql

    def test_amd_sql_matches_arm_filters_and_percentiles(self):
        amd_sql = rcs.build_amd_sql(days=90, min_days=3, min_runs=3, amd_min_runs=3)

        assert "is_job_on_interactive = FALSE" in amd_sql
        assert "is_any_task_failed = FALSE" in amd_sql
        assert "is_any_databricks_run_failed = FALSE" in amd_sql
        assert "COUNT(DISTINCT CAST(dt_dag_run_started AS DATE)) >= 3" in amd_sql
        assert "APPROX_PERCENTILE(drv_cpu_p95, 0.95)" in amd_sql
        assert "APPROX_PERCENTILE(wrk_cpu_p95, 0.95)" in amd_sql
        assert "APPROX_PERCENTILE(wrk_mem_p95, 0.95)" in amd_sql
        assert "dominant_config" in amd_sql
        assert "dominant_runs" in amd_sql
        assert "dominant_config_run_share" in amd_sql
        assert "dominant_config_cost_share" in amd_sql
        assert "FROM dominant_runs" in amd_sql
        assert "MAX(driver_node_type)" not in amd_sql

    def test_row_to_metrics_maps_cadence_and_cost_authority_inputs(self):
        metrics = rcs._row_to_metrics(
            {
                "airflow_dag_id": "bietlejuice.test_dag",
                "arm_days": "5",
                "arm_runs": "10",
                "runs_per_day": "2",
                "schedule_interval_minutes": "720",
                "driver_node_type": "m6g.xlarge",
                "worker_node_type": "m6g.xlarge",
                "worker_count": "2",
                "arm_total_cost_usd": "100",
                "arm_avg_cost_per_run_usd": "10",
                "arm_total_cost_estimate_usd": "130",
                "arm_avg_total_cost_estimate_usd": "13",
                "arm_total_ec2_cost_usd": "30",
                "arm_avg_ec2_cost_usd": "3",
                "arm_total_dbu_cost_usd": "100",
                "arm_avg_dbu_cost_usd": "10",
                "arm_avg_dbu_consumed": "2.5",
                "ec2_spot_hours": "20",
                "ec2_on_demand_hours": "10",
                "wall_p50_min": "20",
                "wall_p95_min": "30",
                "drv_cpu_p50": "20",
                "drv_cpu_p95": "40",
                "drv_mem_p50": "25",
                "drv_mem_p95": "40",
                "drv_wait_p95": "1",
                "wrk_cpu_p50": "10",
                "wrk_cpu_p95": "30",
                "wrk_mem_p50": "20",
                "wrk_mem_p95": "30",
                "wrk_wait_p95": "1",
            }
        )

        assert metrics.runs_per_day == pytest.approx(2.0)
        assert metrics.schedule_interval_minutes == pytest.approx(720.0)
        assert metrics.arm_avg_ec2_cost_usd == pytest.approx(3.0)
        assert metrics.ec2_spot_hours == pytest.approx(20.0)
        assert metrics.arm_avg_dbu_consumed == pytest.approx(2.5)

    def test_current_cost_basis_uses_negotiated_total_only(self):
        m = _m(
            arm_avg_cost_per_run_usd=8.0,
            arm_avg_total_cost_estimate_usd=99.0,
        )
        assert _current_cost_basis(m) == pytest.approx(8.0)

    def test_load_from_csv_ignores_validation_dags(self, tmp_path):
        csv_path = tmp_path / "metrics.csv"
        csv_path.write_text(
            "\n".join(
                [
                    "airflow_dag_id,arm_days,arm_runs,driver_node_type,worker_node_type,worker_count,arm_total_cost_usd,arm_avg_cost_per_run_usd,wall_p50_min,wall_p95_min,drv_cpu_p50,drv_cpu_p95,drv_mem_p95,drv_wait_p95,wrk_cpu_p50,wrk_cpu_p95,wrk_mem_p95,wrk_wait_p95",
                    "bietlejuice.test_dag,5,10,m6g.xlarge,m6g.xlarge,2,100,10,20,30,20,40,40,1,10,30,30,1",
                    "bietlejuice.test_dag__validation,5,10,m6g.xlarge,m6g.xlarge,2,100,10,20,30,20,40,40,1,10,30,30,1",
                ]
            ),
            encoding="utf-8",
        )

        metrics = rcs.load_from_csv(csv_path)

        assert [m.dag_id for m in metrics] == ["bietlejuice.test_dag"]

    def test_load_from_csv_excludes_zero_cost_runs_at_sql_layer(self):
        sql = build_sql(days=90, min_days=3, min_runs=3)
        assert "COALESCE(total_cost_usd, 0) > 0" in sql

    def test_validation_sql_targets_validation_suffix(self):
        sql = build_validation_sql(days=90, validation_min_runs=1)
        assert "bietlejuice.%__validation" in sql
        assert "prod_dag_id" in sql
        assert "COALESCE(total_cost_usd, 0) > 0" in sql
        assert "HAVING COUNT(*) >= 1" in sql

    def test_build_validation_outcomes_pass_warn_fail(self):
        rec = build_recommendation(
            _m(
                dag_id="bietlejuice.test_dag",
                worker_count=0,
                worker_node_type=None,
                wall_p95_min=10.0,
                drv_cpu_p50=20.0,
                drv_mem_p95=40.0,
                arm_avg_cost_per_run_usd=1.0,
            )
        )
        rec.cohort = "collapse_to_single"
        rec.projected.est_cost_per_run_usd = 0.8
        rec.projected.est_drv_cpu_p50 = 30.0
        rec.projected.est_drv_mem_p95 = "projected 45.0%"

        pass_rows = [
            {
                "prod_dag_id": "bietlejuice.test_dag",
                "validation_runs": "3",
                "actual_avg_cost_per_run_usd": "0.82",
                "actual_drv_cpu_p50": "32.0",
                "actual_drv_mem_p95": "44.0",
                "actual_wall_p95_min": "11.0",
            }
        ]
        outcomes = build_validation_outcomes([rec], pass_rows)
        assert len(outcomes) == 1
        assert outcomes[0].outcome == "pass"

        warn_rows = [
            {
                **pass_rows[0],
                "actual_avg_cost_per_run_usd": "0.95",
            }
        ]
        warn_outcomes = build_validation_outcomes([rec], warn_rows)
        assert warn_outcomes[0].outcome == "warn"

        fail_rows = [
            {
                **pass_rows[0],
                "actual_avg_cost_per_run_usd": "1.5",
            }
        ]
        fail_outcomes = build_validation_outcomes([rec], fail_rows)
        assert fail_outcomes[0].outcome == "fail"


class TestInstanceCatalogGenerator:
    def test_generated_prices_match_dim_ec2_price_seed(self):
        import importlib.util

        from scripts.instance_catalog_data import EC2_ON_DEMAND_USD_PER_HOUR

        spec = importlib.util.spec_from_file_location(
            "generate_instance_catalog",
            REPO_ROOT / "scripts/generate_instance_catalog.py",
        )
        gen_mod = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(gen_mod)
        seed_prices = gen_mod.parse_dim_ec2_price_seed(
            REPO_ROOT
            / "dags/platform/enrich_databricks_pricing/queries/enrich/dim_ec2_price.sql"
        )
        for name, price in EC2_ON_DEMAND_USD_PER_HOUR.items():
            assert seed_prices[name] == pytest.approx(price)

    def test_spot_ratio_matches_seed_derivation(self):
        from scripts.instance_catalog_data import EC2_ON_DEMAND_USD_PER_HOUR

        assert rcs._SPOT_TO_ON_DEMAND_RATIO == pytest.approx(0.37)
        spot_price = rcs._instance_price("m6g.xlarge", spot=True)
        od_price = EC2_ON_DEMAND_USD_PER_HOUR["m6g.xlarge"]
        assert spot_price == pytest.approx(od_price * 0.37)

    def test_catalog_has_expanded_graviton_variants(self):
        assert "m7gd.xlarge" in rcs.INSTANCE_CATALOG
        assert "c7g.xlarge" in rcs.INSTANCE_CATALOG


class TestGenerateValidationConfigContract:
    """Smoke test that recommend_cluster_specs delegates to ci_cd validation module."""

    def test_delegates_to_ci_cd_module(self, tmp_path, monkeypatch):
        import os

        os.environ["ENVIRONMENT"] = "prod"
        dag_dir = tmp_path / "dags" / "growth" / "enrich_semrush_classified"
        dag_dir.mkdir(parents=True)
        (dag_dir / "enrich_semrush_classified_cluster.yml").write_text(
            "cluster:\n"
            "  type: consolidation_xs_general_single_node_cluster\n"
            "  databricks_conn_id: databricks_new_env\n",
            encoding="utf-8",
        )
        (dag_dir / "enrich_semrush_classified_declaration.yml").write_text(
            "dag:\n  name: enrich_semrush_classified\n"
            "workflow:\n  type: query_delta\n  layer: enrich\n",
            encoding="utf-8",
        )
        monkeypatch.setattr(rcs, "DAGS_ROOT", tmp_path / "dags")

        rec = rcs.Recommendation(
            dag_id="bietlejuice.enrich_semrush_classified",
            cohort="collapse_to_single",
            confidence="high",
            actions="collapse_to_single",
            current_preset="consolidation_xs_general_single_node_cluster",
            current_driver_node_type="m6g.large",
            current_worker_node_type=None,
            current_worker_count=0,
            arm_days=5,
            arm_runs=10,
            arm_total_cost_usd=10.0,
            arm_avg_cost_per_run_usd=1.0,
            arm_total_cost_estimate_usd=None,
            arm_avg_total_cost_estimate_usd=None,
            wall_p50_min=10.0,
            wall_p95_min=15.0,
            drv_cpu_p50=10.0,
            drv_cpu_p95=20.0,
            drv_mem_p95=30.0,
            drv_wait_p95=1.0,
            wrk_cpu_p50=10.0,
            wrk_cpu_p95=20.0,
            wrk_mem_p95=30.0,
            wrk_wait_p95=1.0,
            recommended_preset="consolidation_xs_memory_single_node_cluster",
            rec_driver_node_type="r6g.large",
            rec_worker_count=0,
            projected=rcs.ProjectedMetrics(est_cost_delta_pct=-20.0),
        )

        cfg = generate_validation_config(rec, dags_root=tmp_path / "dags")

        assert cfg is not None
        assert (
            cfg["validation"]["cluster"]["databricks_conn_id"] == "databricks_new_env"
        )
        assert "custom_configurations" not in cfg["validation"]["cluster"]


class TestWriteValidationClusterFile:
    def _make_cfg(self, cluster_type: str, custom: dict | None = None) -> dict:
        cluster: dict = {"type": cluster_type, "databricks_conn_id": "databricks_new"}
        if custom:
            cluster["custom_configurations"] = custom
        return {
            "dag_id": "bietlejuice.test_dag",
            "cohort": "collapse_to_single",
            "confidence": "high",
            "est_cost_delta_pct": -30.0,
            "validation": {"cluster": cluster},
        }

    def test_creates_new_file_with_validation_section(self, tmp_path):
        path = tmp_path / "test_cluster.yml"

        write_validation_cluster_file(
            path,
            self._make_cfg("consolidation_m_general_single_node_cluster"),
            current_cluster_type="consolidation_m_general_cluster",
        )

        doc = yaml.safe_load(path.read_text())
        assert doc["cluster"]["type"] == "consolidation_m_general_cluster"
        assert (
            doc["validation"]["cluster"]["type"]
            == "consolidation_m_general_single_node_cluster"
        )

    def test_preserves_existing_cluster_section_and_writes_overrides(self, tmp_path):
        path = tmp_path / "test_cluster.yml"
        path.write_text(
            "cluster:\n  type: old_cluster_type\n  databricks_conn_id: databricks_new\n",
            encoding="utf-8",
        )

        write_validation_cluster_file(
            path,
            self._make_cfg(
                "consolidation_xl_memory_single_node_cluster",
                {"driver_node_type_id": "r6g.12xlarge"},
            ),
            current_cluster_type=None,
        )

        doc = yaml.safe_load(path.read_text())
        assert doc["cluster"]["type"] == "old_cluster_type"
        assert doc["validation"]["cluster"]["custom_configurations"] == {
            "driver_node_type_id": "r6g.12xlarge"
        }

    def test_preserves_cluster_formatting_comments_and_jinja(self, tmp_path):
        original = (
            "cluster:\n"
            "  type: consolidation_m_general_cluster\n"
            "  custom_configurations:\n"
            "    # Cost-saving spot/OD mix.\n"
            "    spark_conf:\n"
            '      spark.driver.cores: "4"\n'
            "      spark.databricks.sql.initial.catalog.namespace: "
            "quintoandar_{{ var.value.environment }}\n"
        )
        path = tmp_path / "test_cluster.yml"
        path.write_text(original, encoding="utf-8")

        write_validation_cluster_file(
            path,
            self._make_cfg("consolidation_s_general_cluster"),
            current_cluster_type=None,
        )

        text = path.read_text(encoding="utf-8")
        assert "# Cost-saving spot/OD mix." in text
        assert 'spark.driver.cores: "4"' in text
        assert (
            "spark.databricks.sql.initial.catalog.namespace: "
            "quintoandar_{{ var.value.environment }}"
        ) in text
        assert "environment\n        }}" not in text
        assert "validation:\n  cluster:" in text

    def test_replaces_existing_validation_section(self, tmp_path):
        path = tmp_path / "test_cluster.yml"
        path.write_text(
            "cluster:\n  type: old_cluster_type\n"
            "validation:\n  cluster:\n    type: old_validation_type\n",
            encoding="utf-8",
        )

        write_validation_cluster_file(
            path,
            self._make_cfg("consolidation_s_general_cluster"),
            current_cluster_type=None,
        )

        text = path.read_text(encoding="utf-8")
        assert text.count("validation:") == 1
        assert "old_validation_type" not in text
        assert "consolidation_s_general_cluster" in text

    def test_preserves_corrupt_cluster_text_verbatim(self, tmp_path):
        path = tmp_path / "test_cluster.yml"
        path.write_text("cluster: [invalid yaml\n", encoding="utf-8")

        write_validation_cluster_file(
            path,
            self._make_cfg("consolidation_m_general_single_node_cluster"),
            current_cluster_type=None,
        )

        text = path.read_text(encoding="utf-8")
        assert text.startswith("cluster: [invalid yaml\n")
        assert "validation:\n  cluster:" in text


class TestAmdCorrection:
    def _amd_m(self, **kwargs) -> DagMetrics:
        defaults = dict(
            dag_id="bietlejuice.test_amd_dag",
            arm_days=1,
            arm_runs=2,
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            arm_total_cost_usd=20.0,
            arm_avg_cost_per_run_usd=0.4,
            wall_p50_min=25.0,
            wall_p95_min=35.0,
            drv_cpu_p50=10.0,
            drv_cpu_p95=30.0,
            drv_mem_p95=40.0,
            drv_wait_p95=1.0,
            wrk_cpu_p50=10.0,
            wrk_cpu_p95=30.0,
            wrk_mem_p95=30.0,
            wrk_wait_p95=2.0,
        )
        defaults.update(kwargs)
        return DagMetrics(**defaults)

    def test_correction_factor_and_classifier(self):
        assert AMD_WALL_CORRECTION == pytest.approx(0.735)
        assert classify_amd_for_collapse(self._amd_m()) is True
        assert classify_amd_for_collapse(self._amd_m(wall_p95_min=50.0)) is False

    def test_build_amd_recommendation_returns_collapse_when_eligible(self):
        rec = build_amd_recommendation(self._amd_m())

        assert rec is not None
        assert rec.cohort == "collapse_to_single"
        assert rec.confidence == "medium-x86"
        assert rec.recommended_preset is not None

    def test_build_amd_recommendation_uses_additive_sized_driver_override(self):
        m = self._amd_m(
            driver_node_type="r6g.8xlarge",
            worker_node_type="r6g.8xlarge",
            worker_count=2,
            drv_cpu_p95=25.0,
            drv_mem_p95=55.0,
            wrk_cpu_p95=5.0,
            wrk_mem_p95=30.0,
            wall_p95_min=20.0,
        )

        rec = build_amd_recommendation(m)
        cfg = generate_validation_config(rec)

        assert rec is not None
        assert rec.rec_driver_node_type == "r6g.12xlarge"
        assert rec.driver_override_node_type_id == "r6g.12xlarge"
        assert rec.recommended_preset == "consolidation_xl_memory_single_node_cluster"
        assert cfg is not None
        assert cfg["validation"]["cluster"]["custom_configurations"] == {
            "driver_node_type_id": "r6g.12xlarge"
        }

    def test_build_amd_recommendation_returns_none_for_unknown_worker_type(self):
        assert (
            build_amd_recommendation(self._amd_m(worker_node_type="unknown.type"))
            is None
        )

    def test_build_amd_recommendation_returns_none_for_mixed_config(self):
        assert (
            build_amd_recommendation(
                self._amd_m(
                    dominant_config_run_share=0.5, dominant_config_cost_share=0.9
                )
            )
            is None
        )
        assert (
            build_amd_recommendation(
                self._amd_m(
                    dominant_config_run_share=0.9, dominant_config_cost_share=0.5
                )
            )
            is None
        )
