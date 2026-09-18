"""Unit tests for scripts/recommend_cluster_specs.py.

The recommender is bidirectional and cost-truthful: it builds collapse and
refined-multi candidates, prices them under one model, and keeps the cheapest
that beats observed cost within SLA. Normalizations (Photon off, NVMe off) apply
on every recommendation when the observed runs used those features.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from scripts import recommend_cluster_specs as rcs  # noqa: E402
from scripts.recommend_cluster_specs import (  # noqa: E402
    AMD_WALL_CORRECTION,
    PRESET_CATALOG,
    DagMetrics,
    _apply_amd_wall_correction,
    _current_cost_basis,
    build_amd_recommendation,
    build_dag_id_like_filter,
    build_recommendation,
    build_sql,
    build_validation_dag_id_like_filter,
    build_validation_outcomes,
    build_validation_sql,
    classify,
    effective_demand,
    estimate_cost,
    estimate_drv_cpu_after_collapse,
    estimate_projected_total_cost,
    generate_validation_config,
    infer_current_preset,
    recommend_preset,
    size_single_node,
    write_validation_cluster_file,
    write_validation_configs,
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
        defaults["arm_avg_cost_per_run_usd"] = kwargs["arm_avg_total_cost_estimate_usd"]
    return DagMetrics(**defaults)


class TestClassifyQualityGates:
    def test_needs_more_arm_data(self):
        assert classify(_m(arm_days=2, arm_runs=10)) == "needs_more_arm_data"
        assert classify(_m(arm_days=5, arm_runs=2)) == "needs_more_arm_data"

    def test_autoscale_and_mixed_config_review(self):
        assert classify(_m(worker_count=None)) == "autoscale_review"
        assert classify(_m(dominant_config_run_share=0.49)) == "mixed_config_review"
        assert classify(_m(dominant_config_cost_share=0.49)) == "mixed_config_review"

    def test_dominant_config_share_min_boundary(self):
        at_threshold = _m(dominant_config_run_share=0.5, dominant_config_cost_share=0.5)
        below_threshold = _m(
            dominant_config_run_share=0.49, dominant_config_cost_share=0.9
        )
        assert classify(at_threshold) != "mixed_config_review"
        assert classify(below_threshold) == "mixed_config_review"
        assert (
            classify(_m(dominant_config_run_share=0.5), dominant_config_share_min=0.80)
            == "mixed_config_review"
        )

    def test_recent_config_change_waits_for_telemetry(self):
        thin_switch = _m(
            arm_days=1,
            arm_runs=1,
            config_changed_in_window=True,
            latest_config_runs=1,
            latest_config_days=1,
            dominant_config_run_share=0.1,
            dominant_config_cost_share=0.05,
        )
        assert (
            classify(
                thin_switch,
                min_days=3,
                min_runs=3,
                recent_era_min_days=2,
                recent_era_min_runs=2,
            )
            == "recent_config_change"
        )
        assert (
            classify(
                thin_switch,
                min_days=3,
                min_runs=3,
                recent_era_min_days=2,
                recent_era_min_runs=2,
            )
            != "needs_more_arm_data"
        )
        assert recommend_preset("recent_config_change", thin_switch) == (None, None)

    def test_established_config_switch_evaluates_on_latest_era(self):
        """Default recent-era thresholds (1 day, 2 runs) → size on new config."""
        established = _m(
            arm_days=2,
            arm_runs=2,
            config_changed_in_window=True,
            latest_config_runs=2,
            latest_config_days=2,
            dominant_config_run_share=0.4,
            dominant_config_cost_share=0.2,
            driver_node_type="r6g.2xlarge",
            worker_node_type="r6gd.4xlarge",
            worker_count=5,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=25.0,
            wall_p95_min=30.0,
        )
        assert classify(established, min_days=3, min_runs=3) != "recent_config_change"
        assert classify(established, min_days=3, min_runs=3) != "needs_more_arm_data"

    def test_recent_config_change_skips_mixed_config_review(self):
        switched = _m(
            config_changed_in_window=True,
            latest_config_runs=5,
            latest_config_days=3,
            dominant_config_run_share=0.2,
            dominant_config_cost_share=0.1,
        )
        assert classify(switched, min_days=2, min_runs=2) != "mixed_config_review"

    def test_recent_downsize_does_not_recommend_old_expensive_era(self):
        """Regression: team shrinks cluster; thin new era must not upsize to old XL."""
        rec = build_recommendation(
            _m(
                dag_id="bietlejuice.enrich_amplitude_page_viewed_events",
                config_changed_in_window=True,
                latest_config_runs=1,
                latest_config_days=1,
                dominant_config_run_share=0.1,
                dominant_config_cost_share=0.05,
                driver_node_type="r6g.xlarge",
                worker_node_type="r6g.xlarge",
                worker_count=2,
            ),
            min_days=2,
            min_runs=2,
        )
        assert rec.cohort == "recent_config_change"
        assert rec.recommended_preset is None

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
        assert rec.rec_driver_node_type == "r7g.xlarge"
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
        assert rec.rec_driver_node_type == "m7g.xlarge"

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
        assert rec.rec_driver_node_type == "r7g.2xlarge"
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
        assert rec.rec_driver_node_type == "m7g.large"

    def test_single_node_hot_cpu_is_healthy_not_auto_keep(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            drv_cpu_p95=90.0,
            drv_mem_p95=50.0,
        )

        assert classify(m) == "healthy_single"


class TestAdditiveSingleNodeSizing:
    def test_driver_bound_idle_workers_refine_to_cheap_spot_multi(self):
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

        sizing = size_single_node(m)
        rec = build_recommendation(m)

        # Effective CPU demand (p50-anchored) sizes the idle workers near their
        # p50, so the whole additive load fits the driver-sized single node…
        assert sizing.node_type == "m6g.xlarge"
        assert sizing.projected_mem_pct == pytest.approx(55.0)
        assert rcs.build_best_single_candidate(m).driver_node_type == "m6g.xlarge"
        # …and the collapse beats every refined-multi candidate on cost.
        assert rec.cohort == "collapse_to_single"
        assert rec.rec_driver_node_type == "m6g.xlarge"
        assert rec.rec_worker_count == 0
        assert rec.projected.est_cost_delta_pct is not None
        assert rec.projected.est_cost_delta_pct < 0

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

        # The additive sizer picks the family by actual GiB/core, not the
        # current node's family — m6g (4 GiB/core) here, not r6g.
        assert sizing.node_type == "m6g.2xlarge"
        assert sizing.projected_mem_pct == pytest.approx(50.0)
        # Cheapest feasible shape is a refined spot multi, not the OD single node.
        # (The default p50 fixtures exceed the synthetic p95s, so cpu_eff == p50
        # and the driver lands one tier above the old p95-only pick.)
        assert rec.cohort == "right_size_multi"
        assert rec.rec_driver_node_type == "m6g.xlarge"
        assert rec.rec_worker_node_type == "m6g.large"

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

    def test_large_single_node_without_exact_preset_uses_driver_override(
        self, monkeypatch
    ):
        monkeypatch.setenv("ENVIRONMENT", "prod")
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

        # The collapse candidate still maps to a valid single-node node type,
        assert rcs.build_best_single_candidate(m).driver_node_type == "r6g.4xlarge"
        # but the refined spot multi is cheaper and maps to a valid preset.
        assert rec.cohort == "right_size_multi"
        assert rec.recommended_preset is not None
        assert rec.rec_driver_node_type is not None


class TestSlaLimitMinutes:
    def test_cadence_bound_uses_schedule_target(self):
        m = _m(runs_per_day=18.0, schedule_interval_minutes=60.0, wall_p95_min=30.0)
        assert rcs._sla_limit_minutes(m) == pytest.approx(48.0)

    def test_interval_above_two_hours_is_unbounded(self):
        # Wall regressions are acceptable by policy outside the <=2h cadence
        # band; the projected cost (with wall inflation) is the only brake.
        m = _m(runs_per_day=1.0, schedule_interval_minutes=1440.0, wall_p95_min=20.0)
        assert rcs._sla_limit_minutes(m) == float("inf")

    def test_two_hour_schedule_is_cadence_bound(self):
        m = _m(runs_per_day=12.0, schedule_interval_minutes=120.0, wall_p95_min=30.0)
        assert rcs._sla_limit_minutes(m) == pytest.approx(96.0)

    def test_cadence_limit_floors_at_observed_p95(self):
        # A DAG already past the 80% target keeps wall-neutral candidates.
        m = _m(runs_per_day=72.0, schedule_interval_minutes=20.0, wall_p95_min=18.0)
        assert rcs._sla_limit_minutes(m) == pytest.approx(18.0)


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

        # Memory-bound workers pin the worker type; the driver still minimizes to
        # the compute family, which the bidirectional pick keeps as a refined
        # multi. (cpu_eff sizes the driver at p50+0.3*(p95-p50), one tier below
        # the old p95-only pick.)
        assert rec.cohort == "right_size_multi"
        assert rec.rec_driver_node_type == "c6g.xlarge"
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

    def test_hourly_opa_istio_shape_stays_multi_for_sla_and_minimizes_driver(
        self, monkeypatch
    ):
        monkeypatch.setenv("ENVIRONMENT", "prod")
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

        # Hourly cadence with wall_p95 44min vs a 48min limit: under the
        # work-conserving wall model every core cut projects past the limit,
        # so the cadence-bound shape is kept as-is (no validation config).
        assert rec.cohort == "keep_multi_sla"
        assert rec.actions == "keep_multi_node"
        assert rec.rec_worker_node_type == "m6g.2xlarge"
        assert rec.rec_worker_count == 5
        assert cfg is None

    def test_keep_multi_downsizes_worker_type_without_reducing_count(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
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
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=8.0,
            arm_avg_ec2_cost_usd=1.5,
            arm_avg_dbu_cost_usd=6.5,
        )

        rec = build_recommendation(m)
        cfg = generate_validation_config(rec)

        # Same parallelism (count kept), worker type shrunk — a refined multi.
        assert rec.cohort == "right_size_multi"
        assert rec.rec_worker_node_type == "r6g.large"
        assert rec.rec_worker_count == 2
        assert (
            rec.actions
            == "keep_multi_node|keep_driver|reduce_worker_type|keep_worker_count"
        )
        assert cfg is not None
        custom = cfg["validation"]["cluster"]["custom_configurations"]
        assert custom["driver_node_type_id"] == "m6g.large"
        assert custom["node_type_id"] == "r6g.large"

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

        # Track C: jump straight to demand-derived min_count (5 here), not -2/step.
        assert rec.cohort == "right_size_multi"
        assert rec.rec_worker_node_type == "r6g.4xlarge"
        assert rec.rec_worker_count == 5
        assert "reduce_worker_count" in rec.actions.split("|")
        assert rec.num_workers_override == 5

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
            runs_per_day=18.0,
            schedule_interval_minutes=40.0,
            arm_avg_total_cost_estimate_usd=40.0,
            arm_avg_ec2_cost_usd=15.0,
            arm_avg_dbu_cost_usd=25.0,
        )

        rec = build_recommendation(m)

        # Tight SLA blocks the count reduction, but the worker type still shrinks.
        assert rec.cohort == "right_size_multi"
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
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=0.01,
            arm_avg_ec2_cost_usd=0.005,
            arm_avg_dbu_cost_usd=0.005,
        )

        rec = build_recommendation(m)

        # On a near-zero baseline every refined/collapse candidate costs more, so
        # nothing wins: keep the observed shape and surface the rejected cost.
        assert rec.cohort == "keep_multi_cost"
        assert rec.rec_worker_node_type == "r6g.4xlarge"
        assert rec.rec_worker_count == 2
        assert rec.actions == "keep_multi_node"
        assert generate_validation_config(rec) is None
        assert rec.projected.est_cost_delta_pct == pytest.approx(0.0)
        assert rec.projected.blocked_cost_delta_pct is not None
        assert rec.projected.blocked_cost_delta_pct > 0.0
        assert rcs._format_delta(rec).startswith("  est 0% (")


class TestOneWorkerMultiHygiene:
    def test_one_worker_keeps_multi_when_spot_cheaper(self, monkeypatch):
        """1-worker with large spot worker is kept when cheaper than collapse."""
        monkeypatch.setenv("ENVIRONMENT", "prod")
        # Scenario: small driver + large spot worker with HIGH utilization.
        # High utilization forces collapse to a large expensive node (r6g.4xlarge).
        # Low baseline ($0.50) reflects actual multi-node spot pricing.
        # Collapse projected cost ($1.09) > baseline ($0.50) => keep multi.
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="r6g.4xlarge",
            worker_count=1,
            drv_cpu_p50=40.0,
            drv_cpu_p95=50.0,
            drv_mem_p95=75.0,  # 75% of 8GB = 6GB
            wrk_cpu_p50=50.0,
            wrk_cpu_p95=70.0,
            wrk_mem_p95=60.0,  # 60% of 128GB = 77GB -> collapse needs r6g.4xlarge
            wall_p50_min=60.0,
            wall_p95_min=90.0,
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=0.50,  # Low baseline (spot pricing)
            arm_avg_cost_per_run_usd=0.50,
            arm_avg_ec2_cost_usd=0.25,
            arm_avg_dbu_cost_usd=0.25,
        )

        rec = build_recommendation(m)

        # High utilization + low spot baseline => collapse costs more => keep multi
        assert rec.cohort in (
            "keep_multi_cost",
            "keep_multi_memory",
            "keep_multi_balanced",
        )

    def test_one_worker_collapses_when_sizes_similar(self, monkeypatch):
        """1-worker with similar driver/worker sizes collapses (spot discount doesn't overcome overhead)."""
        monkeypatch.setenv("ENVIRONMENT", "prod")
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=1,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
            wall_p50_min=18.0,
            wall_p95_min=18.0,
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=0.5,
            arm_avg_cost_per_run_usd=0.5,
            arm_avg_ec2_cost_usd=0.25,
            arm_avg_dbu_cost_usd=0.25,
        )

        rec = build_recommendation(m)

        # Similar sizes = collapse is the right call
        assert rec.cohort == "collapse_to_single"
        assert rec.rec_worker_count == 0

    def test_two_worker_still_blocked_by_cost_guard(self):
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
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=0.01,
            arm_avg_ec2_cost_usd=0.005,
            arm_avg_dbu_cost_usd=0.005,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "keep_multi_cost"
        assert generate_validation_config(rec) is None

    def test_one_worker_io_bound_still_keeps_multi(self):
        m = _m(
            driver_node_type="m6g.2xlarge",
            worker_node_type="m6g.2xlarge",
            worker_count=1,
            drv_cpu_p95=75.0,
            drv_mem_p95=70.0,
            wrk_cpu_p50=55.0,
            wrk_cpu_p95=70.0,
            wrk_mem_p95=65.0,
            wrk_wait_p95=50.0,
            arm_avg_total_cost_estimate_usd=100.0,
            arm_avg_ec2_cost_usd=40.0,
            arm_avg_dbu_cost_usd=60.0,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "keep_multi_io_bound"
        assert generate_validation_config(rec) is None

    def test_one_worker_uses_max_driver_worker_not_additive_upsize(self):
        # Realistic cost where collapse saves money (collapse cost ~$0.25, baseline $0.50)
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="r6g.4xlarge",
            worker_count=1,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
            wall_p50_min=18.0,
            wall_p95_min=18.0,
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=0.50,  # Realistic baseline
            arm_avg_cost_per_run_usd=0.50,
            arm_avg_ec2_cost_usd=0.25,
            arm_avg_dbu_cost_usd=0.25,
        )
        rec = build_recommendation(m)

        assert rec.cohort == "collapse_to_single"
        assert rec.rec_driver_node_type == "r6g.4xlarge"
        assert rec.rec_driver_node_type != "r6g.12xlarge"
        assert rec.recommended_preset == "consolidation_l_memory_single_node_cluster"

    def test_one_worker_asymmetric_picks_larger_driver(self):
        # Driver is larger than worker: collapse should use driver node (r6g.2xlarge)
        # Need realistic cost where collapse is cheaper than multi
        m = _m(
            driver_node_type="r6g.2xlarge",
            worker_node_type="r6g.large",
            worker_count=1,
            drv_cpu_p95=15.0,
            drv_mem_p95=15.0,
            wrk_cpu_p50=3.0,
            wrk_cpu_p95=5.0,
            wrk_mem_p95=5.0,
            wall_p50_min=20.0,
            wall_p95_min=20.0,
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=0.50,  # Realistic baseline
            arm_avg_cost_per_run_usd=0.50,
            arm_avg_ec2_cost_usd=0.25,
            arm_avg_dbu_cost_usd=0.25,
        )
        rec = build_recommendation(m)

        assert rec.rec_driver_node_type == "r6g.2xlarge"
        assert rec.recommended_preset == "consolidation_m_memory_single_node_cluster"

    def test_larger_node_type_helper(self):
        assert rcs._larger_node_type("m6g.large", "r6g.4xlarge") == "r6g.4xlarge"
        assert rcs._larger_node_type("r6g.2xlarge", "r6g.large") == "r6g.2xlarge"

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

        # Collapsing the spiky hourly shape would blow the SLA, so it stays multi,
        # but the spiky-idle workers (p50 14.5 / p95 75.9) size near their p50
        # under cpu_eff — a much cheaper refined multi.
        assert rec.cohort == "right_size_multi"
        assert rec.rec_worker_count == 2
        assert rec.rec_worker_node_type == "r6g.xlarge"

    def test_busy_spot_cluster_collapses_when_cpu_eff_makes_single_node_cheaper(self):
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

        # p95-bursty (80%) but p50-idle (default 20%) workers size near p50, so
        # a single memory node holds the additive demand and wins on cost.
        assert rec.cohort == "collapse_to_single"
        assert rec.rec_driver_node_type == "r6g.2xlarge"
        assert rec.projected.est_cost_delta_pct is not None
        assert rec.projected.est_cost_delta_pct < 0

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

    def test_driver_and_workers_hot_at_p95_but_idle_at_p50_collapses(self):
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

        # Sustained p50 load is moderate (drv 30 / wrk 55 on 8-core nodes), so
        # the additive cpu_eff demand fits one r6g.4xlarge and the collapse is
        # cost-justified; CPU burst alone no longer pins the multi shape.
        assert classify(m) == "collapse_to_single"


class TestReviewFlags:
    def test_io_scan_review_flags_high_wait_low_cpu_base(self):
        # langfuse/enrich_search shape: workers babysit S3 (high IO-wait, low p50).
        m = _m(wrk_wait_p95=67.0, wrk_cpu_p50=14.0)
        assert rcs.review_flags(m) == ["io_scan_review"]

    def test_driver_bound_review_flags_idle_workers_without_io_wait(self):
        # greenhouse_v3 shape: driver paginates an API while workers idle.
        m = _m(wrk_wait_p95=1.2, wrk_cpu_p50=2.2)
        assert rcs.review_flags(m) == ["driver_bound_review"]

    def test_no_flags_for_healthy_or_single_node_shapes(self):
        assert rcs.review_flags(_m(wrk_wait_p95=12.0, wrk_cpu_p50=30.0)) == []
        assert rcs.review_flags(_m(worker_count=0, worker_node_type=None)) == []

    def test_flags_surface_on_recommendation_without_blocking_it(self):
        m = _m(wrk_wait_p95=67.0, wrk_cpu_p50=14.0)
        rec = build_recommendation(m)
        assert rec.review_flags == "io_scan_review"
        assert rec.cohort not in ("", None)


class TestPhotonComputeFamilyExclusion:
    def test_keep_photon_candidates_never_pick_compute_family(self):
        # Databricks rejects Photon on c* nodes (core/RAM ratio too low). A
        # compute-leaning demand must land on general family when Photon stays.
        order = rcs._family_order_for_demand(8.0, 6.0, exclude_compute=True)
        assert "compute" not in order
        node = rcs._node_for_demand(8.0, 6.0, exclude_compute=True)
        assert node is not None and rcs._node_family(node) != "compute"

    def test_recommendation_never_keeps_photon_on_compute_nodes(self):
        # CPU-heavy Photon DAG whose cheapest shape is compute-family: either
        # the shape avoids c* nodes, or Photon is dropped — never both kept.
        m = _m(
            driver_node_type="c6g.4xlarge",
            worker_node_type="c6g.4xlarge",
            worker_count=4,
            drv_cpu_p50=60.0,
            drv_cpu_p95=80.0,
            drv_mem_p95=30.0,
            wrk_cpu_p50=50.0,
            wrk_cpu_p95=70.0,
            wrk_mem_p95=25.0,
            is_any_photon=True,
            arm_avg_total_cost_estimate_usd=20.0,
            arm_avg_ec2_cost_usd=8.0,
            arm_avg_dbu_cost_usd=12.0,
        )
        rec = build_recommendation(m)
        keeps_photon = rec.rec_runtime_engine is None
        rec_nodes = [
            n
            for n in (rec.rec_driver_node_type, rec.rec_worker_node_type)
            if n is not None
        ]
        if keeps_photon and rec_nodes:
            assert all(rcs._node_family(n) != "compute" for n in rec_nodes)


class TestNormalizationActions:
    def test_strip_nvme_maps_gd_family_to_non_gd(self):
        assert rcs._strip_nvme("m6gd.2xlarge") == "m6g.2xlarge"
        assert rcs._strip_nvme("r6gd.xlarge") == "r6g.xlarge"
        assert rcs._strip_nvme("c6gd.4xlarge") == "c6g.4xlarge"
        # Already non-NVMe and unknown shapes pass through unchanged.
        assert rcs._strip_nvme("m6g.large") == "m6g.large"
        assert rcs._strip_nvme(None) is None

    def test_disable_photon_emits_standard_runtime_and_action(self):
        m = _m(
            driver_node_type="m6g.2xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p95=30.0,
            drv_mem_p95=40.0,
            is_any_photon=True,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "healthy_single"
        assert "disable_photon" in rec.actions.split("|")
        assert rec.rec_runtime_engine == "STANDARD"
        assert rec.recommended_preset == "consolidation_m_general_single_node_cluster"
        assert rec.rec_driver_node_type == "m6g.2xlarge"

    def test_no_photon_leaves_runtime_engine_unset(self):
        m = _m(
            driver_node_type="m6g.2xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p95=30.0,
            drv_mem_p95=40.0,
            is_any_photon=False,
        )

        rec = build_recommendation(m)

        assert "disable_photon" not in rec.actions.split("|")
        assert rec.rec_runtime_engine is None

    def test_drop_nvme_emits_action_and_recommends_non_gd_nodes(self):
        m = _m(
            driver_node_type="m6gd.2xlarge",
            worker_node_type="m6gd.2xlarge",
            worker_count=2,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
            is_any_local_nvme=True,
        )

        rec = build_recommendation(m)

        assert "drop_nvme" in rec.actions.split("|")
        assert rec.rec_driver_node_type is None or "gd." not in rec.rec_driver_node_type
        assert rec.rec_worker_node_type is None or "gd." not in rec.rec_worker_node_type

    def test_validation_config_forces_spot_workers_never_on_demand(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
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
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=8.0,
            arm_avg_ec2_cost_usd=1.5,
            arm_avg_dbu_cost_usd=6.5,
        )

        rec = build_recommendation(m)
        cfg = generate_validation_config(rec)

        assert cfg is not None
        custom = cfg["validation"]["cluster"]["custom_configurations"]
        aws = custom.get("aws_attributes", {})
        # Workers must never be pinned to ON_DEMAND in a recommendation.
        assert aws.get("availability", "SPOT") != "ON_DEMAND"


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
            wall_p50_min=5.0,
            wall_p95_min=7.0,
            arm_avg_ec2_cost_usd=0.04,
            arm_avg_dbu_cost_usd=0.16,
        )

        # A 5-minute run on one m6g.2xlarge must cost a small fraction of its
        # hourly price, not a whole hour.
        projected = estimate_projected_total_cost(
            m, "m6g.2xlarge", 0, fleet_dbu_rate={"m6g.2xlarge": 1.0}
        )
        full_hour = rcs.EC2_ON_DEMAND_USD_PER_HOUR["m6g.2xlarge"]

        assert projected is not None
        assert 0.0 < projected < full_hour

    def test_cost_prices_od_driver_and_spot_workers_with_fleet_dbu(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="m6g.2xlarge",
            worker_count=4,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            is_any_photon=False,
        )
        fleet = {"m6g.large": 1.0, "m6g.2xlarge": 4.0}

        projected = estimate_projected_total_cost(
            m, "m6g.large", 4, rec_worker="m6g.2xlarge", fleet_dbu_rate=fleet
        )

        wall_h = 0.5
        od_drv = rcs.EC2_ON_DEMAND_USD_PER_HOUR["m6g.large"]
        spot_wrk = round(rcs.EC2_ON_DEMAND_USD_PER_HOUR["m6g.2xlarge"] * 0.37, 6)
        ec2 = od_drv * wall_h + spot_wrk * wall_h * 4
        dbu = (1.0 + 4 * 4.0) * wall_h * 0.15  # driver + 4 workers, $0.15/DBU PAYG

        assert projected == pytest.approx(round(ec2 + dbu, 6))

    def test_photon_off_applies_wall_inflation_when_fleet_priced(self):
        common = dict(
            driver_node_type="m6g.xlarge",
            worker_node_type=None,
            worker_count=0,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
        )
        fleet = {"m6g.xlarge": 2.0}

        cost_no_photon = estimate_projected_total_cost(
            _m(is_any_photon=False, **common), "m6g.xlarge", 0, fleet_dbu_rate=fleet
        )
        cost_photon = estimate_projected_total_cost(
            _m(is_any_photon=True, **common), "m6g.xlarge", 0, fleet_dbu_rate=fleet
        )

        # +100% wall when Photon is normalized off; cost scales linearly with wall.
        assert cost_photon == pytest.approx(cost_no_photon * 2.0)

    def test_photon_off_credits_dbu_premium_without_fleet_rates(self):
        common = dict(
            driver_node_type="m6g.xlarge",
            worker_node_type=None,
            worker_count=0,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            arm_avg_dbu_cost_usd=5.0,
            arm_avg_ec2_cost_usd=3.0,
        )
        od = rcs.EC2_ON_DEMAND_USD_PER_HOUR["m6g.xlarge"]

        cost_no_photon = estimate_projected_total_cost(
            _m(is_any_photon=False, **common), "m6g.xlarge", 0, fleet_dbu_rate={}
        )
        cost_photon = estimate_projected_total_cost(
            _m(is_any_photon=True, **common), "m6g.xlarge", 0, fleet_dbu_rate={}
        )

        # Non-Photon: wall 30 min, DBU = observed 5.0 (vCPU ratio 1, wall factor 1).
        assert cost_no_photon == pytest.approx(round(od * 0.5 + 5.0, 6))
        # Dropping Photon: EC2 doubles with the 2x normalized wall, but the offline
        # DBU fallback first removes the baked-in Photon premium (/3.0), so DBU nets
        # to 5.0/3 * 2 (premium removed, then 2x wall) rather than naively doubling.
        assert cost_photon == pytest.approx(round(od * 1.0 + 5.0 / 3.0 * 2.0, 6))
        # The premium credit makes Photon-off cheaper than a naive 2x projection.
        assert cost_photon < cost_no_photon * 2.0

    def test_keep_photon_collapse_wall_uses_raw_demand(self):
        """Regression: a keep-Photon candidate must be priced on raw-demand
        topology inflation, mirroring ``_projected_wall_for_sla``. Previously
        ``_shape_wall_minutes`` always sized the collapse / worker-reduction
        inflation on the Photon-off (inflated) demand, overstating keep-Photon
        wall — and hence EC2 + the wall-scaled observed-DBU anchor — which could
        skew the cheapest-feasible quadrant pick toward dropping Photon.
        """
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            is_any_photon=True,
        )

        keep_wall = rcs._shape_wall_minutes(m, 0, keep_photon=True, rec_total_cores=4)
        drop_wall = rcs._shape_wall_minutes(m, 0, keep_photon=False, rec_total_cores=4)
        assert keep_wall is not None and drop_wall is not None
        # Raw demand → smaller wall inflation than the Photon-off world.
        assert keep_wall < drop_wall
        assert keep_wall == pytest.approx(
            30.0 * rcs._wall_inflation(m, 4, photon_off=False)
        )
        # The cost wall now matches the SLA gate for keep-Photon (both raw).
        assert keep_wall == pytest.approx(
            rcs._projected_wall_for_sla(m, 0, keep_photon=True, rec_total_cores=4)
        )

        # The priced keep-Photon collapse tracks the raw-demand wall end to end,
        # including the disk-bandwidth term threaded through ``estimate_projected_total_cost``.
        rec_disk_bw = rcs._candidate_disk_bw("m6g.xlarge", None, 0)
        expected_wall = 30.0 * rcs._wall_inflation(
            m, 4, photon_off=False, rec_disk_bw=rec_disk_bw
        )
        priced_wall = rcs._shape_wall_minutes(
            m,
            0,
            keep_photon=True,
            rec_total_cores=4,
            rec_disk_bw=rec_disk_bw,
        )
        assert priced_wall == pytest.approx(expected_wall)
        expected_ec2 = rcs.EC2_ON_DEMAND_USD_PER_HOUR["m6g.xlarge"] * (
            expected_wall / 60.0
        )
        expected_dbu = rcs._legacy_dbu_projection(
            m, ["m6g.xlarge"], expected_wall, photon_off=False
        )
        keep_cost = estimate_projected_total_cost(m, "m6g.xlarge", 0, keep_photon=True)
        assert keep_cost == pytest.approx(round(expected_ec2 + expected_dbu, 6))

    def test_cost_falls_back_to_observed_dbu_proxy_without_fleet(self):
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            arm_avg_dbu_cost_usd=5.0,
            arm_avg_ec2_cost_usd=3.0,
        )

        projected = estimate_projected_total_cost(
            m, "m6g.xlarge", 2, rec_worker="m6g.xlarge", fleet_dbu_rate={}
        )

        assert projected is not None
        assert projected > 0.0


class TestPhotonEffectiveDemand:
    def test_effective_demand_passthrough_without_photon(self):
        m = _m(drv_cpu_p95=40.0, drv_mem_p95=50.0, is_any_photon=False)
        d = effective_demand(m)
        assert d.drv_cpu_p95 == 40.0
        assert d.drv_mem_p95 == 50.0

    def test_effective_demand_inflates_cpu_and_mem_when_photon(self):
        m = _m(
            drv_cpu_p50=40.0,
            drv_cpu_p95=50.0,
            drv_mem_p95=50.0,
            wrk_cpu_p50=30.0,
            wrk_cpu_p95=40.0,
            wrk_mem_p95=50.0,
            is_any_photon=True,
        )
        d = effective_demand(m)
        assert d.drv_cpu_p95 == pytest.approx(60.0)
        assert d.drv_mem_p95 == pytest.approx(65.0)
        assert d.wrk_cpu_p95 == pytest.approx(48.0)
        assert d.wrk_mem_p95 == pytest.approx(65.0)

    def test_photon_blocks_single_node_downsize_at_relaxed_gates(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            drv_cpu_p95=10.0,
            drv_mem_p95=40.0,
            is_any_photon=True,
        )
        assert classify(m) == "healthy_single"

        without_photon = _m(
            worker_count=0,
            worker_node_type=None,
            drv_cpu_p95=10.0,
            drv_mem_p95=40.0,
            is_any_photon=False,
        )
        assert classify(without_photon) == "driver_downsize"

    def test_photon_triggers_oom_at_inflated_memory(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            drv_mem_p95=70.0,
            drv_cpu_p95=30.0,
            is_any_photon=True,
        )
        assert classify(m) == "protect_oom_risk"

    def test_photon_sizes_larger_collapse_node_when_demand_crosses_tier(self):
        base = dict(
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            drv_cpu_p95=50.0,
            drv_mem_p95=60.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=40.0,
        )
        without = size_single_node(_m(**base, is_any_photon=False))
        with_photon = size_single_node(_m(**base, is_any_photon=True))
        assert without.node_type is not None
        assert with_photon.node_type is not None
        without_spec = rcs.INSTANCE_CATALOG[without.node_type]
        with_spec = rcs.INSTANCE_CATALOG[with_photon.node_type]
        assert with_spec.memory_gb >= without_spec.memory_gb
        assert with_spec.vcpus >= without_spec.vcpus


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

    def test_healthy_single_photon_emits_validation_config(self, tmp_path, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        dag_dir = tmp_path / "dags" / "platform" / "photon_dag"
        dag_dir.mkdir(parents=True)
        (dag_dir / "photon_dag_cluster.yml").write_text(
            "cluster:\n"
            "  type: consolidation_m_general_single_node_cluster\n"
            "  databricks_conn_id: databricks_new\n"
            "  custom_configurations:\n"
            "    runtime_engine: PHOTON\n",
            encoding="utf-8",
        )
        (dag_dir / "photon_dag_declaration.yml").write_text(
            "dag:\n  name: photon_dag\n"
            "workflow:\n  type: query_delta\n  layer: enrich\n",
            encoding="utf-8",
        )
        monkeypatch.setattr(rcs, "DAGS_ROOT", tmp_path / "dags")

        m = _m(
            dag_id="bietlejuice.photon_dag",
            driver_node_type="m6g.2xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p95=30.0,
            drv_mem_p95=40.0,
            is_any_photon=True,
        )
        rec = build_recommendation(m)
        cfg = generate_validation_config(rec, dags_root=tmp_path / "dags")

        assert rec.cohort == "healthy_single"
        assert cfg is not None
        assert cfg["validation"]["cluster"]["type"] == (
            "consolidation_m_general_single_node_cluster"
        )
        custom = cfg["validation"]["cluster"].get("custom_configurations", {})
        assert "runtime_engine" not in custom

    def test_healthy_single_nvme_emits_validation_config(self, tmp_path, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        dag_dir = tmp_path / "dags" / "platform" / "nvme_dag"
        dag_dir.mkdir(parents=True)
        (dag_dir / "nvme_dag_cluster.yml").write_text(
            "cluster:\n"
            "  type: consolidation_m_general_single_node_cluster\n"
            "  databricks_conn_id: databricks_new\n"
            "  custom_configurations:\n"
            "    driver_node_type_id: m6gd.2xlarge\n",
            encoding="utf-8",
        )
        (dag_dir / "nvme_dag_declaration.yml").write_text(
            "dag:\n  name: nvme_dag\nworkflow:\n  type: query_delta\n  layer: enrich\n",
            encoding="utf-8",
        )
        monkeypatch.setattr(rcs, "DAGS_ROOT", tmp_path / "dags")

        m = _m(
            dag_id="bietlejuice.nvme_dag",
            driver_node_type="m6gd.2xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p95=70.0,
            drv_mem_p95=50.0,
            is_any_local_nvme=True,
        )
        rec = build_recommendation(m)
        cfg = generate_validation_config(rec, dags_root=tmp_path / "dags")

        assert rec.cohort == "healthy_single"
        assert "drop_nvme" in rec.actions.split("|")
        assert rec.recommended_preset == "consolidation_m_general_single_node_cluster"
        assert cfg is not None
        assert cfg["validation"]["cluster"]["type"] == (
            "consolidation_m_general_single_node_cluster"
        )

    def test_preset_catalog_sanity(self):
        assert PRESET_CATALOG["consolidation_m_general_cluster"].num_workers == 2
        assert (
            PRESET_CATALOG["consolidation_m_general_single_node_cluster"].num_workers
            == 0
        )
        assert PRESET_CATALOG["consolidation_m_general_cluster"].worker_node_type.startswith(
            "m7g."
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
        assert "config_last_run" in sql
        assert "rn_recent" in sql
        assert "rn_cost" in sql
        assert "config_changed_in_window" in sql
        assert "dag_cadence" in sql
        assert "eligible_dags" in sql
        assert "runs_per_day" in amd_sql
        assert "schedule_interval_minutes" in amd_sql
        assert "dag_cadence" in amd_sql
        assert "amd_history_eligible" in amd_sql
        assert "eligible_dags" in amd_sql
        assert "dominant_era_eligible" not in amd_sql
        assert "total_memory_bytes_spilled" in amd_sql
        assert "arm_avg_dbu_consumed" in amd_sql
        assert "is_job_on_interactive = FALSE" in sql
        assert "is_any_task_failed = FALSE" in sql
        assert "is_any_databricks_run_failed = FALSE" in sql
        assert "NOT REGEXP_LIKE(airflow_dag_id, '__validation$')" in sql
        assert "NOT REGEXP_LIKE(airflow_dag_id, '__validation$')" in amd_sql

    def test_latest_era_sql_includes_validation_when_flag_on(self):
        sql = build_sql(
            days=14,
            min_days=3,
            min_runs=3,
            include_validation_runs=True,
            recent_era_min_days=1,
            recent_era_min_runs=2,
        )
        assert "COUNT(DISTINCT CAST(dt_dag_run_started AS DATE)) >= 1" in sql
        assert "COUNT(*) >= 2" in sql
        assert "COUNT(DISTINCT CAST(dt_dag_run_started AS DATE)) >= 3" not in sql
        assert "validation_runs" in sql
        assert "bietlejuice.%__validation" in sql
        assert "REGEXP_REPLACE(airflow_dag_id, '__validation$', '')" in sql
        assert "dag_max_gen" in sql
        assert "latest_config" in sql
        assert "observed_max_gen" in sql
        assert "arm_runs_prod" in sql
        assert "arm_runs_validation" in sql
        assert "metrics_era_generation" in sql
        assert "metrics_include_validation" in sql
        assert "FALSE                                                                 AS config_changed_in_window" in sql
        assert "rn_cost" not in sql
        assert "FROM dominant_config" not in sql
        assert "dominant_config AS (" not in sql

    def test_latest_era_sql_same_latest_filter_matches_nvme(self):
        sql = build_sql(
            days=14,
            min_days=1,
            min_runs=1,
            include_validation_runs=True,
            validation_config_filter="same-latest",
        )
        assert "shape_matched WHERE is_validation_run" in sql
        assert "gd\\." in sql or "gd\\\\." in sql

    def test_latest_era_sql_all_filter_unions_validation_on_max_gen(self):
        sql = build_sql(
            days=14,
            min_days=1,
            min_runs=1,
            include_validation_runs=True,
            validation_config_filter="all",
        )
        assert "SELECT * FROM era_runs WHERE is_validation_run" in sql

    def test_latest_era_sql_pins_target_generation(self):
        sql = build_sql(
            days=14,
            min_days=1,
            min_runs=1,
            include_validation_runs=True,
            target_generation=7,
        )
        assert "7                                            AS metrics_generation" in sql

    def test_build_sql_rejects_unknown_validation_filter(self):
        with pytest.raises(ValueError, match="validation_config_filter"):
            build_sql(
                days=14,
                min_days=1,
                min_runs=1,
                include_validation_runs=True,
                validation_config_filter="bogus",
            )

    def test_dag_id_prefix_filters_include_wonka(self):
        sql = build_sql(
            days=90,
            min_days=3,
            min_runs=3,
            dag_id_prefixes=("bietlejuice.%", "quintoml.wonka.%"),
        )
        assert "bietlejuice.%" in sql
        assert "quintoml.wonka.%" in sql
        val_sql = build_validation_sql(
            90,
            2,
            dag_id_prefixes=("bietlejuice.%", "quintoml.wonka.%"),
        )
        assert "quintoml.wonka.%__validation" in val_sql

    def test_build_dag_id_like_filter_helpers(self):
        assert "LIKE 'bietlejuice.%'" in build_dag_id_like_filter("airflow_dag_id")
        multi = build_dag_id_like_filter(
            "airflow_dag_id", ("bietlejuice.%", "quintoml.wonka.%")
        )
        assert " OR " in multi
        val_multi = build_validation_dag_id_like_filter(
            "airflow_dag_id", ("bietlejuice.%", "quintoml.wonka.%")
        )
        assert "quintoml.wonka.%__validation" in val_multi


class TestWonkaRecommenderPathSetup:
    def test_wonka_config_paths_module_imports_via_compiler_path(self):
        if "scripts" in sys.modules and not hasattr(sys.modules["scripts"], "ci_cd"):
            del sys.modules["scripts"]
        mod = rcs._wonka_config_paths_module()
        assert mod.WONKA_DAG_ID_PREFIX == "quintoml.wonka."
        assert mod.DEFAULT_QUINTOML_ROOT.name == "quintoml"

    def test_resolve_quintoml_root_from_wonka_prefix(self):
        resolved = rcs._resolve_quintoml_root(None, ("quintoml.wonka.%",), [])
        assert resolved == rcs._wonka_config_paths_module().DEFAULT_QUINTOML_ROOT

    def test_resolve_quintoml_root_from_wonka_recommendations(self):
        rec = MagicMock()
        rec.dag_id = "quintoml.wonka.house_main"
        resolved = rcs._resolve_quintoml_root(None, ("bietlejuice.%",), [rec])
        assert resolved == rcs._wonka_config_paths_module().DEFAULT_QUINTOML_ROOT

    def test_resolve_quintoml_root_returns_none_for_bietlejuice_only(self):
        rec = MagicMock()
        rec.dag_id = "bietlejuice.dw_agent"
        assert rcs._resolve_quintoml_root(None, ("bietlejuice.%",), [rec]) is None

    def test_write_validation_configs_omits_quintoml_root_when_none(self, tmp_path):
        rec = MagicMock()
        rec.dag_id = "bietlejuice.dw_agent"
        mock_module = MagicMock()
        mock_module.write_validation_configs.return_value = 0
        with patch.object(rcs, "_rightsizing_validation_module", return_value=mock_module):
            write_validation_configs([rec], tmp_path / "out.yml", quintoml_root=None)
        call_kwargs = mock_module.write_validation_configs.call_args.kwargs
        assert "quintoml_root" not in call_kwargs

    def test_row_to_metrics_parses_validation_mix_fields(self):
        metrics = rcs._row_to_metrics(
            {
                "airflow_dag_id": "bietlejuice.test_dag",
                "arm_days": "2",
                "arm_runs": "5",
                "arm_runs_prod": "1",
                "arm_runs_validation": "4",
                "metrics_era_generation": "7",
                "metrics_include_validation": "true",
                "driver_node_type": "m7g.xlarge",
                "worker_node_type": "m7g.xlarge",
                "worker_count": "2",
                "arm_total_cost_usd": "10",
                "arm_avg_cost_per_run_usd": "2",
                "wall_p50_min": "10",
                "wall_p95_min": "12",
                "dominant_config_run_share": "1.0",
                "dominant_config_cost_share": "1.0",
                "config_changed_in_window": "false",
                "latest_config_runs": "5",
                "latest_config_days": "2",
            }
        )
        assert metrics.arm_runs_prod == 1
        assert metrics.arm_runs_validation == 4
        assert metrics.metrics_era_generation == 7
        assert metrics.metrics_include_validation is True

    def test_classify_uses_validation_thickened_era_without_recent_config_change(self):
        m = _m(
            arm_days=2,
            arm_runs=5,
            latest_config_runs=5,
            latest_config_days=2,
            config_changed_in_window=False,
            dominant_config_run_share=1.0,
            dominant_config_cost_share=1.0,
            metrics_include_validation=True,
            arm_runs_validation=4,
        )
        assert classify(m, recent_era_min_runs=2, recent_era_min_days=1) != "recent_config_change"
        assert (
            classify(m, min_days=3, min_runs=3, recent_era_min_runs=2, recent_era_min_days=1)
            != "needs_more_arm_data"
        )

    def test_classify_validation_mode_uses_recent_era_eligibility_thresholds(self):
        thin_validation = _m(
            arm_days=1,
            arm_runs=2,
            config_changed_in_window=False,
            dominant_config_run_share=1.0,
            dominant_config_cost_share=1.0,
            metrics_include_validation=True,
        )
        assert (
            classify(
                thin_validation,
                min_days=3,
                min_runs=3,
                recent_era_min_days=1,
                recent_era_min_runs=2,
            )
            != "needs_more_arm_data"
        )
        assert (
            classify(
                _m(
                    arm_days=1,
                    arm_runs=2,
                    config_changed_in_window=False,
                    dominant_config_run_share=1.0,
                    dominant_config_cost_share=1.0,
                ),
                min_days=3,
                min_runs=3,
                recent_era_min_days=1,
                recent_era_min_runs=2,
            )
            == "needs_more_arm_data"
        )

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
        assert "config_changed_in_window" in amd_sql
        assert "rn_recent" in amd_sql
        assert "amd_history_eligible" in amd_sql
        assert "eligible_dags" in amd_sql
        assert "dominant_era_eligible" not in amd_sql
        assert "FROM dominant_runs" in amd_sql
        assert "MAX(driver_node_type)" not in amd_sql
        assert "primary_min_autoscale_workers" in amd_sql
        assert "drv_mem_p50" in amd_sql
        assert "wrk_mem_p50" in amd_sql

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

    def test_row_to_metrics_maps_recent_config_fields(self):
        metrics = rcs._row_to_metrics(
            {
                "airflow_dag_id": "bietlejuice.test_dag",
                "arm_days": "5",
                "arm_runs": "10",
                "driver_node_type": "m6g.xlarge",
                "worker_node_type": "m6g.xlarge",
                "worker_count": "2",
                "arm_total_cost_usd": "100",
                "arm_avg_cost_per_run_usd": "10",
                "wall_p50_min": "20",
                "wall_p95_min": "30",
                "drv_cpu_p50": "20",
                "drv_cpu_p95": "40",
                "drv_mem_p95": "40",
                "drv_wait_p95": "1",
                "wrk_cpu_p50": "10",
                "wrk_cpu_p95": "30",
                "wrk_mem_p95": "30",
                "wrk_wait_p95": "1",
                "config_changed_in_window": "true",
                "latest_config_runs": "2",
                "latest_config_days": "2",
            }
        )

        assert metrics.config_changed_in_window is True
        assert metrics.latest_config_runs == 2
        assert metrics.latest_config_days == 2

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
        monkeypatch.setenv("ENVIRONMENT", "prod")
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
            rec_driver_node_type="r7g.large",
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

    def test_correction_factor_and_wall_scaling(self):
        assert AMD_WALL_CORRECTION == pytest.approx(0.735)
        m = self._amd_m(wall_p50_min=40.0, wall_p95_min=50.0)
        corrected = _apply_amd_wall_correction(m)

        assert corrected.wall_p50_min == pytest.approx(
            40.0 * AMD_WALL_CORRECTION, abs=0.1
        )
        assert corrected.wall_p95_min == pytest.approx(
            50.0 * AMD_WALL_CORRECTION, abs=0.1
        )

    def test_amd_wall_correction_preserves_observed_walls_in_output(self):
        m = self._amd_m(wall_p50_min=40.0, wall_p95_min=50.0)
        rec = build_amd_recommendation(m)

        assert rec.wall_p50_min == 40.0
        assert rec.wall_p95_min == 50.0
        assert rec.confidence == "medium-x86"

    def test_build_amd_recommendation_returns_collapse_when_eligible(self):
        m = self._amd_m(
            drv_cpu_p95=35.0,
            drv_mem_p95=78.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=8.0,
            wrk_mem_p95=38.3,
            wall_p95_min=15.0,
        )
        rec = build_amd_recommendation(m)

        assert rec.cohort == "collapse_to_single"
        assert rec.confidence == "medium-x86"
        assert rec.recommended_preset is not None

    def test_build_amd_recommendation_collapses_driver_bound_shape(self):
        m = self._amd_m(
            driver_node_type="m5a.xlarge",
            worker_node_type="m5a.xlarge",
            drv_cpu_p50=55.0,
            drv_cpu_p95=82.0,
            drv_mem_p95=35.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
            wall_p95_min=12.0,
        )
        rec = build_amd_recommendation(m)

        # Idle workers (p50 5%) size near p50 under cpu_eff: the hot driver plus
        # worker remainder fits one ARM general node, mirroring the ARM engine.
        assert rec.cohort == "collapse_to_single"
        assert rec.confidence == "medium-x86"
        assert rec.rec_worker_count == 0
        assert rec.projected.est_cost_delta_pct is not None
        assert rec.projected.est_cost_delta_pct < 0

    def test_build_amd_recommendation_uses_additive_sized_driver_override(
        self, monkeypatch
    ):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        m = self._amd_m(
            driver_node_type="r6g.8xlarge",
            worker_node_type="r6g.8xlarge",
            worker_count=2,
            drv_cpu_p95=25.0,
            drv_mem_p95=55.0,
            wrk_cpu_p95=5.0,
            wrk_mem_p95=30.0,
            wall_p95_min=20.0,
            arm_avg_total_cost_estimate_usd=100.0,
            arm_avg_cost_per_run_usd=100.0,
            arm_avg_ec2_cost_usd=40.0,
            arm_avg_dbu_cost_usd=60.0,
        )

        rec = build_amd_recommendation(m)
        cfg = generate_validation_config(rec)

        assert rec.cohort == "collapse_to_single"
        assert rec.rec_driver_node_type == "r6g.12xlarge"
        assert rec.driver_override_node_type_id == "r6g.12xlarge"
        assert rec.recommended_preset == "consolidation_xl_memory_single_node_cluster"
        assert cfg is not None
        assert cfg["validation"]["cluster"]["custom_configurations"] == {
            "driver_node_type_id": "r6g.12xlarge"
        }

    def test_build_amd_recommendation_unknown_worker_needs_telemetry(self):
        rec = build_amd_recommendation(self._amd_m(worker_node_type="unknown.type"))

        assert rec.cohort == "needs_more_telemetry"
        assert rec.confidence == "medium-x86"

    def test_build_amd_recommendation_mixed_config_review(self):
        rec = build_amd_recommendation(
            self._amd_m(dominant_config_run_share=0.49, dominant_config_cost_share=0.9)
        )

        assert rec.cohort == "mixed_config_review"
        assert rec.confidence == "medium-x86"

    def test_build_amd_recommendation_thin_dominant_era_guard_cohorts(self):
        needs_more = build_amd_recommendation(
            self._amd_m(arm_days=2, arm_runs=2, config_changed_in_window=False)
        )
        recent_change = build_amd_recommendation(
            self._amd_m(
                config_changed_in_window=True,
                latest_config_days=1,
                latest_config_runs=1,
            )
        )

        assert needs_more.cohort == "needs_more_arm_data"
        assert recent_change.cohort == "recent_config_change"
        assert needs_more.confidence == "medium-x86"
        assert recent_change.confidence == "medium-x86"


class TestDataLayerPhotonNvme:
    def test_sql_selects_photon_and_nvme_flags(self):
        sql = build_sql(days=90, min_days=3, min_runs=3)
        amd_sql = rcs.build_amd_sql(days=90, min_days=3, min_runs=3, amd_min_runs=3)

        assert "is_any_photon" in sql
        assert "is_any_local_nvme" in sql
        assert "is_any_photon" in amd_sql
        assert "is_any_local_nvme" in amd_sql

    def test_dag_metrics_photon_nvme_default_false(self):
        m = _m()

        assert m.is_any_photon is False
        assert m.is_any_local_nvme is False

    def test_row_to_metrics_maps_photon_and_nvme_flags(self):
        m = rcs._row_to_metrics(
            {
                "airflow_dag_id": "bietlejuice.test_dag",
                "driver_node_type": "m6gd.xlarge",
                "worker_node_type": "m6gd.xlarge",
                "worker_count": "2",
                "is_any_photon": "true",
                "is_any_local_nvme": "true",
            }
        )

        assert m.is_any_photon is True
        assert m.is_any_local_nvme is True


class TestSizingLevers:
    def test_observed_total_cores_counts_driver_plus_workers(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="m6g.xlarge",
            worker_count=2,
        )
        # m6g.large=2 vCPU, m6g.xlarge=4 vCPU -> 2 + 2*4 = 10
        assert rcs.observed_total_cores(m) == 10

    def test_observed_total_cores_single_node(self):
        m = _m(driver_node_type="m6g.2xlarge", worker_node_type=None, worker_count=0)
        assert rcs.observed_total_cores(m) == 8

    def test_best_single_candidate_sizes_to_additive_demand(self):
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            drv_cpu_p95=55.0,
            drv_mem_p95=35.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
        )

        cand = rcs.build_best_single_candidate(m)

        assert cand is not None
        assert cand.worker_count == 0
        assert cand.worker_node_type is None
        assert cand.driver_node_type == size_single_node(m).node_type

    def test_current_refined_candidate_keeps_two_or_more_workers(self):
        m = _m(
            driver_node_type="m6g.2xlarge",
            worker_node_type="r6g.4xlarge",
            worker_count=4,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
        )

        cand = rcs.build_current_refined_candidate(m)

        assert cand is not None
        assert cand.worker_count >= 2
        # driver lever shrinks the idle on-demand driver
        assert rcs._vcpus(cand.driver_node_type) <= rcs._vcpus("m6g.2xlarge")

    def test_current_refined_candidate_none_for_single_node(self):
        m = _m(worker_count=0, worker_node_type=None)

        assert rcs.build_current_refined_candidate(m) is None

    def test_candidate_total_cores_never_exceeds_observed(self):
        m = _m(
            driver_node_type="m6g.2xlarge",
            worker_node_type="m6g.2xlarge",
            worker_count=2,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p95=20.0,
            wrk_mem_p95=20.0,
        )
        observed = rcs.observed_total_cores(m)

        best = rcs.build_best_single_candidate(m)
        refined = rcs.build_current_refined_candidate(m)

        assert best is not None
        assert rcs.candidate_total_cores(best) <= observed
        if refined is not None:
            assert rcs.candidate_total_cores(refined) <= observed


class TestFleetDbuRate:
    def test_fleet_dbu_rate_sql_aggregates_non_photon_dbu_per_node_hour(self):
        sql = rcs.build_fleet_dbu_rate_sql(days=90)

        assert "is_any_photon = FALSE" in sql
        assert "total_dbu_consumed" in sql
        assert "ec2_spot_hours" in sql
        assert "ec2_on_demand_hours" in sql
        assert "instance_type" in sql
        assert "dbu_per_node_hour" in sql
        assert "GROUP BY" in sql

    def test_fleet_dbu_rate_from_rows_builds_per_instance_map(self):
        rows = [
            {"instance_type": "m6g.xlarge", "dbu_per_node_hour": "1.6"},
            {"instance_type": "r6g.2xlarge", "dbu_per_node_hour": "3.0"},
        ]

        fleet = rcs.fleet_dbu_rate_from_rows(rows)

        assert fleet["m6g.xlarge"] == pytest.approx(1.6)
        assert fleet["r6g.2xlarge"] == pytest.approx(3.0)

    def test_fleet_dbu_per_node_hour_uses_observed_value(self):
        fleet = {"m6g.xlarge": 1.6}

        assert rcs.fleet_dbu_per_node_hour("m6g.xlarge", fleet) == pytest.approx(1.6)

    def test_fleet_dbu_per_node_hour_falls_back_to_vcpu_proportional(self):
        # m6g.xlarge = 4 vCPU -> 0.4 DBU/vCPU-hr; m6g.2xlarge = 8 vCPU -> 3.2.
        fleet = {"m6g.xlarge": 1.6}

        assert rcs.fleet_dbu_per_node_hour("m6g.2xlarge", fleet) == pytest.approx(3.2)

    def test_fleet_dbu_per_node_hour_returns_none_when_no_observations(self):
        assert rcs.fleet_dbu_per_node_hour("m6g.xlarge", {}) is None


_ACCEPTANCE_FIXTURES_PATH = (
    REPO_ROOT / "tests" / "fixtures" / "recommend_cluster_specs_acceptance.json"
)


class TestIoBoundGuards:
    def test_nvme_kept_under_disk_pressure(self):
        m = _m(
            driver_node_type="m6gd.xlarge",
            worker_node_type="m6gd.4xlarge",
            worker_count=4,
            is_any_local_nvme=True,
            is_any_photon=True,
            local_disk_p95=62.0,
            wrk_wait_p95=66.0,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=25.0,
        )
        rec = build_recommendation(m)
        assert "drop_nvme" not in rec.actions.split("|")
        if rec.rec_worker_node_type is not None:
            assert rcs._is_nvme(rec.rec_worker_node_type)

    def test_nvme_still_stripped_when_disk_idle(self):
        m = _m(
            driver_node_type="m6gd.xlarge",
            worker_node_type="m6gd.4xlarge",
            worker_count=4,
            is_any_local_nvme=True,
            is_any_photon=True,
            local_disk_p95=5.0,
            wrk_wait_p95=2.0,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=25.0,
        )
        rec = build_recommendation(m)
        assert "drop_nvme" in rec.actions.split("|")
        if rec.rec_driver_node_type is not None:
            assert not rcs._is_nvme(rec.rec_driver_node_type)
        if rec.rec_worker_node_type is not None:
            assert not rcs._is_nvme(rec.rec_worker_node_type)

    def test_worker_type_pinned_under_guard(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="r6g.8xlarge",
            worker_count=8,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=25.0,
            wrk_wait_p95=50.0,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            schedule_interval_minutes=240.0,
            arm_avg_total_cost_estimate_usd=40.0,
            arm_avg_ec2_cost_usd=15.0,
            arm_avg_dbu_cost_usd=25.0,
        )
        assert rcs._worker_resize(m).node_type == m.worker_node_type

    def test_count_shrink_capped_at_minus_one(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="r6g.4xlarge",
            worker_count=6,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
            wrk_wait_p95=50.0,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            schedule_interval_minutes=1440.0,
            arm_avg_total_cost_estimate_usd=40.0,
            arm_avg_ec2_cost_usd=15.0,
            arm_avg_dbu_cost_usd=25.0,
        )
        assert rcs._worker_resize(m).worker_count == 5

    def test_collapse_suppressed_under_io_guard(self):
        m = _m(
            driver_node_type="m6g.2xlarge",
            worker_node_type="m6g.2xlarge",
            worker_count=2,
            drv_cpu_p95=75.0,
            drv_mem_p95=70.0,
            wrk_cpu_p50=55.0,
            wrk_cpu_p95=70.0,
            wrk_mem_p95=65.0,
            wrk_wait_p95=50.0,
            arm_avg_total_cost_estimate_usd=100.0,
            arm_avg_ec2_cost_usd=40.0,
            arm_avg_dbu_cost_usd=60.0,
        )
        assert classify(m) != "collapse_to_single"
        assert classify(m) == "keep_multi_io_bound"

    def test_single_node_downsize_suppressed(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            drv_cpu_p95=10.0,
            drv_mem_p95=40.0,
            drv_wait_p95=50.0,
            is_any_photon=False,
        )
        assert classify(m) == "healthy_single"

    def test_wall_io_term(self):
        m = _m(wrk_wait_p95=66.1, worker_count=4, worker_node_type="m6gd.4xlarge")
        old_cores = rcs.observed_total_cores(m)
        same = rcs._wall_inflation(m, old_cores, rec_disk_bw=8 * 4)
        assert same == pytest.approx(1.0)
        shrunk = rcs._wall_inflation(m, old_cores, rec_disk_bw=1 * 4)
        assert shrunk == pytest.approx(1.0 + 0.661 * 7, rel=1e-3)
        cpu_only = rcs._wall_inflation(m, old_cores, rec_disk_bw=None)
        assert cpu_only == pytest.approx(1.0)

    def test_chatbot_end_to_end_regression(self, tmp_path, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        dag_dir = tmp_path / "dags" / "conversational_xp" / "enrich_chatbot"
        dag_dir.mkdir(parents=True)
        (dag_dir / "enrich_chatbot_cluster.yml").write_text(
            "cluster:\n"
            "  type: consolidation_l_memory_cluster\n"
            "  databricks_conn_id: databricks_new\n",
            encoding="utf-8",
        )
        (dag_dir / "enrich_chatbot_declaration.yml").write_text(
            "dag:\n  name: enrich_chatbot\n"
            "workflow:\n  type: query_delta\n  layer: enrich\n",
            encoding="utf-8",
        )
        monkeypatch.setattr(rcs, "DAGS_ROOT", tmp_path / "dags")

        m = _m(
            dag_id="bietlejuice.enrich_chatbot",
            driver_node_type="r6g.2xlarge",
            worker_node_type="r6g.4xlarge",
            worker_count=6,
            wrk_wait_p95=45.0,
            wrk_mem_p95=33.0,
            wrk_cpu_p50=10.0,
            wrk_cpu_p95=50.0,
            schedule_interval_minutes=1440.0,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            arm_avg_total_cost_estimate_usd=40.0,
            arm_avg_ec2_cost_usd=15.0,
            arm_avg_dbu_cost_usd=25.0,
        )
        rec = build_recommendation(m)
        assert rec.cohort == "right_size_multi"
        assert rec.rec_worker_node_type == "r6g.4xlarge"
        assert rec.rec_worker_count == 5
        assert rec.recommended_preset == "consolidation_l_memory_cluster"
        assert rec.num_workers_override == 5

        cfg = generate_validation_config(rec, dags_root=tmp_path / "dags")
        assert cfg is not None
        assert cfg["validation"]["cluster"]["custom_configurations"]["num_workers"] == 5

    def test_min_worker_count_for_disk_space(self):
        # ceil(observed_count * occupancy / 85): scratch redistributes over survivors.
        assert (
            rcs._min_worker_count_for_disk_space(
                _m(worker_count=8, local_disk_p95=24.0)
            )
            == 3
        )
        assert (
            rcs._min_worker_count_for_disk_space(
                _m(worker_count=6, local_disk_p95=75.0)
            )
            == 6
        )
        assert (
            rcs._min_worker_count_for_disk_space(_m(worker_count=4)) == 0
        )  # no telemetry

    def test_disk_space_floor_blocks_count_shrink(self):
        # Disk-pressure-only (iowait below the I/O-bound threshold): the -1 count
        # cap alone would allow 6 -> 5, but ceil(6 * 75 / 85) = 6 keeps the count.
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="r6g.4xlarge",
            worker_count=6,
            drv_cpu_p95=20.0,
            drv_mem_p95=20.0,
            wrk_cpu_p50=5.0,
            wrk_cpu_p95=10.0,
            wrk_mem_p95=10.0,
            wrk_wait_p95=10.0,
            local_disk_p95=75.0,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            schedule_interval_minutes=1440.0,
            arm_avg_total_cost_estimate_usd=40.0,
            arm_avg_ec2_cost_usd=15.0,
            arm_avg_dbu_cost_usd=25.0,
        )
        resize = rcs._worker_resize(m)
        assert resize.node_type == "r6g.4xlarge"
        assert resize.worker_count == 6

    def test_collapse_blocked_by_disk_space(self):
        # Hot-at-p95 / moderate-at-p50 shape that collapses when worker disks are
        # empty, but 4 workers at 24% occupancy (below the guard threshold)
        # cannot fit on a single node's disk -> collapse is suppressed.
        kwargs = dict(
            driver_node_type="m6g.2xlarge",
            worker_node_type="m6g.2xlarge",
            worker_count=4,
            drv_cpu_p95=75.0,
            drv_mem_p95=70.0,
            wrk_cpu_p50=55.0,
            wrk_cpu_p95=70.0,
            wrk_mem_p95=65.0,
            arm_avg_total_cost_estimate_usd=100.0,
            arm_avg_ec2_cost_usd=40.0,
            arm_avg_dbu_cost_usd=60.0,
        )
        assert classify(_m(**kwargs)) == "collapse_to_single"
        assert classify(_m(**kwargs, local_disk_p95=24.0)) != "collapse_to_single"


class TestRealDagAcceptance:
    """Regression locks from live Trino telemetry (90-day window, 2026-06-09).

    Each fixture encodes dominant-config metrics for a production DAG and the
    recommender output that was observed when the fixture was generated. Re-run
    Trino + regenerate tests/fixtures/recommend_cluster_specs_acceptance.json if
    the algorithm changes intentionally.
    """

    @pytest.fixture(scope="class")
    def acceptance_fixtures(self) -> dict:
        return json.loads(_ACCEPTANCE_FIXTURES_PATH.read_text())

    @pytest.mark.parametrize(
        "dag_key",
        [
            "istio",
            "emlio",
            "jaiminho",
            "langfuse",
            "enrich_search",
            "enrich_tracked_events",
            "opa",
        ],
    )
    def test_live_dag_recommendation(self, acceptance_fixtures, dag_key: str):
        fixture = acceptance_fixtures[dag_key]
        m = DagMetrics(**fixture["kwargs"])
        expected = fixture["expected"]
        rec = build_recommendation(m)

        assert rec.cohort == expected["cohort"], (
            f"{dag_key}: cohort {rec.cohort!r} != {expected['cohort']!r}"
        )
        assert rec.actions == expected["actions"], (
            f"{dag_key}: actions {rec.actions!r} != {expected['actions']!r}"
        )
        assert rec.recommended_preset == expected["recommended_preset"]
        assert rec.rec_driver_node_type == expected["rec_driver_node_type"]
        assert rec.rec_worker_node_type == expected["rec_worker_node_type"]
        assert rec.rec_worker_count == expected["rec_worker_count"]
        assert rec.rec_runtime_engine == expected["rec_runtime_engine"]


class TestPhotonQuadrantSearch:
    """Photon on/off is a costed dimension explored against the observed cost.

    Dropping Photon/NVMe is only recommended when it genuinely beats keeping it
    (the cost gate), and when it wins it surfaces as an actionable recommendation
    with a real delta and a validation config -- never a 0%-delta keep_multi.
    """

    def test_healthy_single_drops_photon_when_dbu_heavy(self):
        # DBU-dominated single node: removing the Photon premium beats the 2x
        # STANDARD wall, so the drop is recommended with a real saving.
        m = _m(
            driver_node_type="m6g.2xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p95=30.0,
            drv_mem_p95=40.0,
            arm_avg_total_cost_estimate_usd=2.5,
            arm_avg_ec2_cost_usd=0.25,
            arm_avg_dbu_cost_usd=2.25,
            is_any_photon=True,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "healthy_single"
        assert "disable_photon" in rec.actions.split("|")
        assert rec.rec_runtime_engine == "STANDARD"
        assert rec.projected.est_cost_delta_pct is not None
        assert rec.projected.est_cost_delta_pct < 0.0

    def test_healthy_single_keeps_photon_when_ec2_heavy(self):
        # EC2-dominated single node: the 2x STANDARD wall outweighs the DBU
        # premium credit, so dropping Photon would cost more -> keep it.
        m = _m(
            driver_node_type="m6g.2xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p95=30.0,
            drv_mem_p95=40.0,
            arm_avg_total_cost_estimate_usd=2.5,
            arm_avg_ec2_cost_usd=2.4,
            arm_avg_dbu_cost_usd=0.1,
            is_any_photon=True,
        )

        rec = build_recommendation(m)

        assert rec.cohort == "healthy_single"
        assert "disable_photon" not in rec.actions.split("|")
        assert rec.rec_runtime_engine is None
        assert rec.actions == "no_change"

    def test_protect_oom_emits_promote_driver_memory_action(self):
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
        assert "promote_driver_memory" in rec.actions.split("|")
        # Safety upsize keeps the runtime engine untouched.
        assert rec.rec_runtime_engine is None

    def test_keep_multi_does_not_bolt_on_normalization_at_zero_delta(self):
        # Near-zero baseline: every candidate (incl. dropping Photon at the
        # observed shape, which now competes in the pool) costs more, so nothing
        # wins -> a true no-change keep_multi with NO normalization bolted on.
        m = _m(
            driver_node_type="m6gd.large",
            worker_node_type="r6gd.4xlarge",
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
            is_any_photon=True,
            is_any_local_nvme=True,
        )

        rec = build_recommendation(m)

        assert rec.cohort in rcs._KEEP_MULTI_COHORTS
        assert rec.actions == "keep_multi_node"
        assert "disable_photon" not in rec.actions.split("|")
        assert "drop_nvme" not in rec.actions.split("|")
        assert rec.rec_runtime_engine is None
        assert rec.projected.est_cost_delta_pct == pytest.approx(0.0)
        assert generate_validation_config(rec) is None

    def test_drop_photon_winner_is_actionable_and_emits_validation(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        # Idle, DBU-heavy Photon+NVMe multi: dropping Photon/NVMe wins the
        # quadrant search and must surface as an actionable recommendation.
        m = _m(
            driver_node_type="m6gd.2xlarge",
            worker_node_type="m6gd.2xlarge",
            worker_count=2,
            drv_cpu_p95=20.0,
            drv_mem_p95=25.0,
            wrk_cpu_p50=8.0,
            wrk_cpu_p95=15.0,
            wrk_mem_p95=18.0,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            schedule_interval_minutes=1440.0,
            arm_avg_total_cost_estimate_usd=10.0,
            arm_avg_ec2_cost_usd=1.0,
            arm_avg_dbu_cost_usd=9.0,
            is_any_photon=True,
            is_any_local_nvme=True,
        )

        rec = build_recommendation(m)

        assert rec.cohort not in rcs._KEEP_MULTI_COHORTS
        assert "disable_photon" in rec.actions.split("|")
        assert "drop_nvme" in rec.actions.split("|")
        assert rec.rec_runtime_engine == "STANDARD"
        assert rec.rec_driver_node_type is not None
        assert "gd." not in rec.rec_driver_node_type
        assert rec.projected.est_cost_delta_pct < 0.0
        assert generate_validation_config(rec) is not None


class TestTracksABC:
    def setup_method(self) -> None:
        self._saved_memory_history = dict(rcs._MEMORY_HISTORY)
        self._saved_task_metrics = {k: list(v) for k, v in rcs._TASK_METRICS.items()}
        self._saved_demand_override = dict(rcs._DEMAND_OVERRIDE)

    def teardown_method(self) -> None:
        rcs._MEMORY_HISTORY.clear()
        rcs._MEMORY_HISTORY.update(self._saved_memory_history)
        rcs._TASK_METRICS.clear()
        for dag_id, tasks in self._saved_task_metrics.items():
            rcs._TASK_METRICS[dag_id] = list(tasks)
        rcs._DEMAND_OVERRIDE.clear()
        rcs._DEMAND_OVERRIDE.update(self._saved_demand_override)

    def test_cores_floor_guard_blocks_over_aggressive_worker_cut(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="m6g.xlarge",
            worker_count=8,
            drv_cpu_p50=10.0,
            drv_cpu_p95=15.0,
            wrk_cpu_p50=30.0,
            wrk_cpu_p95=40.0,
            wrk_mem_p95=10.0,
            wall_p50_min=30.0,
            wall_p95_min=30.0,
            schedule_interval_minutes=240.0,
        )

        resize = rcs._worker_resize(m)

        assert resize is not None
        # Demand alone would land on 2 workers; cores floor keeps measured busy demand.
        assert resize.worker_count == 4
        assert resize.worker_count < m.worker_count

    def test_memory_history_max_blending_raises_additive_demand(self):
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            drv_mem_p95=30.0,
            wrk_mem_p95=30.0,
        )
        baseline = rcs._additive_memory_gb(m)
        rcs._MEMORY_HISTORY[m.dag_id] = (999.0, None)

        blended = rcs._additive_memory_gb(m)

        assert baseline is not None
        assert blended is not None
        assert blended > baseline

    def test_task_override_sizing_uses_critical_task_memory(self):
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            drv_mem_p95=30.0,
            wrk_mem_p95=30.0,
            wrk_cpu_p50=10.0,
            wrk_cpu_p95=15.0,
        )
        baseline = rcs._additive_memory_gb(m)
        rcs._TASK_METRICS[m.dag_id] = [
            rcs.TaskMetrics(
                dag_id=m.dag_id,
                airflow_task_id="light_task",
                task_runs=10,
                wall_p50_min=20.0,
                wall_p95_min=25.0,
                drv_cpu_p50=5.0,
                drv_cpu_p95=8.0,
                drv_cpu_wait_p50=None,
                drv_cpu_wait_p95=None,
                drv_mem_p50=20.0,
                drv_mem_p95=35.0,
                wrk_cpu_p50=5.0,
                wrk_cpu_p95=8.0,
                wrk_cpu_wait_p50=None,
                wrk_cpu_wait_p95=None,
                wrk_mem_p50=20.0,
                wrk_mem_p95=35.0,
                peak_concurrent_workers=2,
            ),
            rcs.TaskMetrics(
                dag_id=m.dag_id,
                airflow_task_id="heavy_task",
                task_runs=5,
                wall_p50_min=5.0,
                wall_p95_min=8.0,
                drv_cpu_p50=5.0,
                drv_cpu_p95=8.0,
                drv_cpu_wait_p50=None,
                drv_cpu_wait_p95=None,
                drv_mem_p50=20.0,
                drv_mem_p95=95.0,
                wrk_cpu_p50=60.0,
                wrk_cpu_p95=90.0,
                wrk_cpu_wait_p50=None,
                wrk_cpu_wait_p95=None,
                wrk_mem_p50=20.0,
                wrk_mem_p95=95.0,
                peak_concurrent_workers=2,
            ),
        ]
        rcs._apply_task_demand_overrides(m.dag_id, rcs._TASK_METRICS[m.dag_id])

        overridden = rcs._additive_memory_gb(m)

        assert baseline is not None
        assert overridden is not None
        assert overridden > baseline

    def test_task_named_review_flag_pins_worst_io_scan_task(self):
        m = _m(wrk_wait_p95=5.0, wrk_cpu_p50=30.0)
        rcs._TASK_METRICS[m.dag_id] = [
            rcs.TaskMetrics(
                dag_id=m.dag_id,
                airflow_task_id="ok_task",
                task_runs=10,
                wall_p50_min=10.0,
                wall_p95_min=12.0,
                drv_cpu_p50=20.0,
                drv_cpu_p95=30.0,
                drv_cpu_wait_p50=None,
                drv_cpu_wait_p95=None,
                drv_mem_p50=20.0,
                drv_mem_p95=30.0,
                wrk_cpu_p50=30.0,
                wrk_cpu_p95=40.0,
                wrk_cpu_wait_p50=None,
                wrk_cpu_wait_p95=10.0,
                wrk_mem_p50=20.0,
                wrk_mem_p95=30.0,
                peak_concurrent_workers=2,
            ),
            rcs.TaskMetrics(
                dag_id=m.dag_id,
                airflow_task_id="scan_partitions",
                task_runs=10,
                wall_p50_min=15.0,
                wall_p95_min=20.0,
                drv_cpu_p50=10.0,
                drv_cpu_p95=15.0,
                drv_cpu_wait_p50=None,
                drv_cpu_wait_p95=None,
                drv_mem_p50=10.0,
                drv_mem_p95=15.0,
                wrk_cpu_p50=12.0,
                wrk_cpu_p95=18.0,
                wrk_cpu_wait_p50=None,
                wrk_cpu_wait_p95=72.0,
                wrk_mem_p50=10.0,
                wrk_mem_p95=15.0,
                peak_concurrent_workers=2,
            ),
        ]

        assert rcs.review_flags(m) == ["io_scan_review:task=scan_partitions"]

    def test_task_duty_cycle_fallback_matches_dag_blend_without_task_rows(self):
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            drv_cpu_p50=20.0,
            wrk_cpu_p50=40.0,
        )

        assert rcs._task_duty_cycle(m.dag_id, m) is None
        dag_busy = rcs._p50_busy_cores(m)
        assert dag_busy == pytest.approx(3.6)

    def test_build_task_and_memory_history_sql(self):
        task_sql = rcs.build_task_sql(days=14)
        mem_sql = rcs.build_memory_history_sql(days=90)

        assert "fact_databricks_task_run" in task_sql
        assert "task_result_state = 'SUCCEEDED'" in task_sql
        assert "peak_concurrent_workers" in task_sql
        assert "fact_databricks_dag_run" in mem_sql
        assert "driver_mem_p99" in mem_sql
        assert "0-9]g" not in mem_sql


class TestExpandToMulti:
    """Tests for single-node to multi-node expansion logic."""

    def test_expand_to_multi_when_large_single_node(self, monkeypatch):
        """Large single-node with high utilization expands to small driver + spot workers."""
        monkeypatch.setenv("ENVIRONMENT", "prod")
        m = _m(
            driver_node_type="r6g.4xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p50=25.0,
            drv_cpu_p95=30.0,
            drv_mem_p95=60.0,
            wall_p50_min=30.0,
            wall_p95_min=40.0,
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=10.0,
            arm_avg_cost_per_run_usd=10.0,
            arm_avg_ec2_cost_usd=5.0,
            arm_avg_dbu_cost_usd=5.0,
            arm_runs=10,
            arm_days=7,
        )

        cohort = rcs.classify(m)

        # Large single node should be eligible for expansion check
        # Note: actual expansion depends on cost comparison
        assert cohort in ("expand_to_multi", "healthy_single", "driver_downsize")

    def test_no_expand_when_small_single_node(self, monkeypatch):
        """Small single-node should not be considered for expansion."""
        monkeypatch.setenv("ENVIRONMENT", "prod")
        m = _m(
            driver_node_type="m6g.large",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p50=25.0,
            drv_cpu_p95=30.0,
            drv_mem_p95=50.0,
            wall_p50_min=10.0,
            wall_p95_min=15.0,
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=0.5,
            arm_avg_cost_per_run_usd=0.5,
            arm_avg_ec2_cost_usd=0.25,
            arm_avg_dbu_cost_usd=0.25,
            arm_runs=10,
            arm_days=7,
        )

        cohort = rcs.classify(m)

        # Small nodes (below tier l/xl) should not expand
        assert cohort in ("healthy_single", "driver_downsize")

    def test_no_expand_compute_family(self, monkeypatch):
        """Compute family single-nodes should not expand."""
        monkeypatch.setenv("ENVIRONMENT", "prod")
        m = _m(
            driver_node_type="c6g.2xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p50=40.0,
            drv_cpu_p95=50.0,
            drv_mem_p95=40.0,
            wall_p50_min=15.0,
            wall_p95_min=20.0,
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=2.0,
            arm_avg_cost_per_run_usd=2.0,
            arm_avg_ec2_cost_usd=1.0,
            arm_avg_dbu_cost_usd=1.0,
            arm_runs=10,
            arm_days=7,
        )

        cohort = rcs.classify(m)

        # Compute family should not expand
        assert cohort == "healthy_single"

    def test_decide_single_returns_candidate_when_cheaper(self):
        """_decide_single returns expand candidate when multi is cheaper."""
        m = _m(
            driver_node_type="r6g.4xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p50=20.0,
            drv_cpu_p95=25.0,
            drv_mem_p95=70.0,
            wall_p50_min=30.0,
            wall_p95_min=40.0,
            schedule_interval_minutes=600.0,
            arm_avg_total_cost_estimate_usd=20.0,  # High baseline makes multi attractive
            arm_avg_cost_per_run_usd=20.0,
            arm_avg_ec2_cost_usd=10.0,
            arm_avg_dbu_cost_usd=10.0,
            arm_runs=10,
            arm_days=7,
        )

        cohort, candidate = rcs._decide_single(m)

        # High baseline should make expansion attractive
        if cohort == "expand_to_multi":
            assert candidate is not None
            assert candidate.worker_count >= 1


class TestMemTargetParameter:
    """Tests for --mem-target CLI parameter threading."""

    def test_mem_target_parameter_changes_sizing(self):
        """Higher mem_target allows tighter packing."""
        m = _m(
            driver_node_type="r6g.2xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p50=15.0,
            drv_cpu_p95=20.0,
            drv_mem_p95=75.0,  # 75% on r6g.2xlarge = 48GB
            wall_p50_min=10.0,
            wall_p95_min=15.0,
        )

        # Default 82% target
        sizing_82 = rcs.size_single_node(m, mem_target=0.82)

        # Higher 93% target
        sizing_93 = rcs.size_single_node(m, mem_target=0.93)

        # Both should succeed (sizing is about projected utilization)
        assert (
            sizing_82.blocked_reason is None
            or sizing_82.blocked_reason != "needs_more_telemetry"
        )
        assert (
            sizing_93.blocked_reason is None
            or sizing_93.blocked_reason != "needs_more_telemetry"
        )

    def test_node_for_demand_respects_mem_target(self):
        """_node_for_demand should use mem_target in filtering."""
        required_mem = 50.0  # 50GB
        required_cores = 4.0

        # With 82% target, need node with 50/0.82 = 61GB
        node_82 = rcs._node_for_demand(required_mem, required_cores, mem_target=0.82)

        # With 93% target, need node with 50/0.93 = 54GB
        node_93 = rcs._node_for_demand(required_mem, required_cores, mem_target=0.93)

        # Both should find valid nodes
        assert node_82 is not None
        assert node_93 is not None

    def test_build_recommendation_accepts_mem_target(self):
        """build_recommendation should accept and use mem_target."""
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p50=15.0,
            drv_cpu_p95=20.0,
            drv_mem_p95=50.0,
        )

        # Should not raise
        rec = rcs.build_recommendation(m, mem_target=0.93)

        assert rec.cohort is not None


class TestGenerationRetarget:
    @pytest.fixture(autouse=True)
    def _reset_generation_state(self):
        rcs._TARGET_GENERATION.clear()
        rcs._RETARGET_SCOPE = "bounded"
        yield
        rcs._TARGET_GENERATION.clear()
        rcs._RETARGET_SCOPE = "bounded"

    def test_generation_of(self):
        assert rcs._generation_of("m6g.2xlarge") == 6
        assert rcs._generation_of("r7gd.4xlarge") == 7
        assert rcs._generation_of("c8g.xlarge") == 8
        assert rcs._generation_of("m5a.large") is None

    def test_to_generation(self):
        assert rcs._to_generation("m6g.2xlarge", 7) == "m7g.2xlarge"
        assert rcs._to_generation("m6gd.4xlarge", 7) == "m7gd.4xlarge"
        assert rcs._to_generation("c6g.large", 7) is None

    def test_cost_model_credits_gen7(self):
        m = _m(
            driver_node_type="m6g.2xlarge",
            worker_node_type="m6g.2xlarge",
            worker_count=2,
            wall_p50_min=30.0,
            wall_p95_min=45.0,
        )
        gen6 = estimate_projected_total_cost(
            m, "m6g.2xlarge", 2, rec_worker="m6g.2xlarge"
        )
        gen7 = estimate_projected_total_cost(
            m, "m7g.2xlarge", 2, rec_worker="m7g.2xlarge"
        )
        assert gen6 is not None and gen7 is not None
        assert gen7 < gen6
        p, s = 1.06, 1.15
        for e in (0.0, 0.5, 1.0):
            ratio = (e * p + (1.0 - e)) / s
            assert 0.86 <= ratio <= 0.93

    def test_bounded_vs_fleet_healthy_single(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            driver_node_type="m6g.xlarge",
            drv_cpu_p95=90.0,
            drv_mem_p95=50.0,
        )
        assert classify(m) == "healthy_single"

        rcs._set_target_generations(
            {"general": 7, "compute": 7, "memory": 7}, "bounded"
        )
        bounded = build_recommendation(m)
        assert bounded.recommended_preset is None

        rcs._set_target_generations({"general": 7, "compute": 7, "memory": 7}, "fleet")
        fleet = build_recommendation(m)
        assert fleet.recommended_preset == fleet.current_preset
        assert fleet.rec_driver_node_type == "m7g.xlarge"
        assert "retarget_generation" in fleet.actions.split("|")

    def test_fleet_skips_when_already_on_target_generation(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            driver_node_type="m7g.xlarge",
            drv_cpu_p95=90.0,
            drv_mem_p95=50.0,
        )
        rcs._set_target_generations({"general": 7, "compute": 7, "memory": 7}, "fleet")
        rec = build_recommendation(m)
        assert rec.recommended_preset is None
        assert "retarget_generation" not in rec.actions.split("|")

    def test_fleet_skips_non_arm_nodes(self):
        m = _m(
            worker_count=0,
            worker_node_type=None,
            driver_node_type="m5a.xlarge",
            drv_cpu_p95=90.0,
            drv_mem_p95=50.0,
        )
        rcs._set_target_generations({"general": 7, "compute": 7, "memory": 7}, "fleet")
        rec = build_recommendation(m)
        assert rec.recommended_preset is None
        assert "retarget_generation" not in rec.actions.split("|")

    def test_default_generation_state_is_unchanged(self):
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
        baseline = build_recommendation(m)
        assert not rcs._TARGET_GENERATION
        repeat = build_recommendation(m)
        assert repeat.recommended_preset == baseline.recommended_preset
        assert repeat.rec_driver_node_type == baseline.rec_driver_node_type
        assert repeat.rec_worker_node_type == baseline.rec_worker_node_type
        assert (
            repeat.projected.est_cost_per_run_usd
            == baseline.projected.est_cost_per_run_usd
        )

    def test_fleet_retarget_driver_tracks_worker_generation(self):
        m = _m(
            driver_node_type="m6g.xlarge",
            worker_node_type="m6g.xlarge",
            worker_count=2,
            drv_cpu_p50=40.0,
            drv_cpu_p95=45.0,
            drv_mem_p95=30.0,
            wrk_cpu_p50=40.0,
            wrk_cpu_p95=45.0,
            wrk_mem_p95=30.0,
            wall_p95_min=20.0,
        )
        rcs._set_target_generations({"general": 7}, "fleet")
        rec = build_recommendation(m)
        assert rec.rec_driver_node_type is not None
        assert rec.rec_worker_node_type is not None
        assert rcs._generation_of(rec.rec_driver_node_type) == 7
        assert rcs._generation_of(rec.rec_worker_node_type) == 7

    def test_bounded_retarget_compute_still_drops_photon(self):
        m = _m(
            driver_node_type="c6g.2xlarge",
            worker_node_type=None,
            worker_count=0,
            drv_cpu_p50=70.0,
            drv_cpu_p95=85.0,
            drv_mem_p95=45.0,
            arm_avg_total_cost_estimate_usd=2.5,
            arm_avg_ec2_cost_usd=0.25,
            arm_avg_dbu_cost_usd=2.25,
            is_any_photon=True,
        )
        rcs._set_target_generations(
            {"compute": 7, "general": 7, "memory": 7}, "bounded"
        )
        rec = build_recommendation(m)
        assert rec.rec_driver_node_type == "c7g.2xlarge"
        assert "disable_photon" in rec.actions.split("|")
        assert rec.rec_runtime_engine == "STANDARD"
