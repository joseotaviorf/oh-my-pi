#!/usr/bin/env python3
"""Right-sizing recommender for ARM/Graviton DAG clusters (round 2).

Reads post-ARM utilization from dw_databricks_health.fact_databricks_dag_run and
makes a *bidirectional, cost-truthful* shape decision per eligible DAG: it
builds the feasible candidates (collapse to a single node; refine the
multi-node shape with independent driver/worker levers), prices each under one
model (on-demand driver + spot workers + fleet-derived non-Photon DBU, with
Photon and local NVMe normalized off; when Photon ran, wall x2 plus CPU/mem
effective-demand inflation for sizing), and keeps the cheapest candidate that
beats the observed cost basis without regressing the SLA.  The chosen cohort is
the reason for the pick (collapse_to_single / right_size_multi / keep_multi_*).
Produces:

  recommendations.csv / recommendations.json
      Current spec + observed metrics  →  recommended spec + projected metrics.

  validation_configs.yml  (with --validation-config PATH)
      Per-DAG cluster type ready to drop into each DAG's *_cluster.yml
      validation: block, which the existing trigger_cluster_validation_dags.py
      picks up for shadow validation.

  validation_outcomes.csv  (with --validation-outcomes PATH, requires --trino)
      Projected vs observed metrics for DAGs that already have __validation runs.

Cost authority: negotiated total_cost_usd (DBU USD + EC2 USD) from
fact_databricks_dag_run; EC2 rates from dim_ec2_price seed via
scripts/instance_catalog_data.py (regenerate with generate_instance_catalog.py).

Eligibility: ≥ --min-days ARM days AND ≥ --min-runs ARM runs.
Scope: bietlejuice.* DAGs only; PHASE1/PHASE2 workflow types (same as the
       existing cluster-validation tooling).

Usage
-----
  # Pull live metrics from Trino and emit all outputs:
  uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \\
      python scripts/recommend_cluster_specs.py \\
      --trino --validation-config validation_configs.yml

  # Compare recommendations vs existing shadow validation runs:
  uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \\
      python scripts/recommend_cluster_specs.py \\
      --trino --validation-outcomes validation_outcomes.csv \\
      --out-dir /tmp/recs

  # From a pre-exported CSV (no Trino needed):
  uv run --no-project --with pandas \\
      python scripts/recommend_cluster_specs.py \\
      --metrics-csv arm_metrics.csv --validation-config validation_configs.yml

  # Dry-run: list DAGs and their cohorts, no files written:
  uv run --no-project --with "trino==0.337.0,pandas,...,orjson" \\
      python scripts/recommend_cluster_specs.py --trino --list

Docs: docs/platform/cluster_spec_recommender_runbook.md
      docs/platform/cluster_spec_recommender_algorithm.md
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import math
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Repository layout
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[1]
DAGS_ROOT = REPO_ROOT / "dags"
EXECUTE_TRINO = (
    REPO_ROOT / "plugins" / "tars" / "skills" / "tars" / "scripts" / "execute_trino.py"
)
_DEFAULT_TRINO_HOST = "trino.apps.data-prd.habitat.zone"
logger = logging.getLogger(__name__)
AMD_WALL_CORRECTION = (
    0.735  # ARM p95 wall is 26.5% shorter than AMD (fleet median, 594 DAGs)
)

# ---------------------------------------------------------------------------
# ARM detection
# ---------------------------------------------------------------------------

ARM_REGEX = re.compile(r"^([a-z][a-z0-9]*[0-9]g(d|n|b)?|a1)\.", re.IGNORECASE)

# ---------------------------------------------------------------------------
# Instance catalog  (ARM Graviton + x86 AMD fallback for reverse-mapping)
#
# vcpus    — logical vCPUs (used as DBU-rate proxy for cost projection)
# memory_gb — GiB RAM
# family   — 'compute' | 'general' | 'memory'
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class InstanceSpec:
    vcpus: int
    memory_gb: int
    family: str  # compute | general | memory


try:
    from scripts.instance_catalog_data import (  # noqa: PLC0415
        EC2_ON_DEMAND_USD_PER_HOUR,
        INSTANCE_SPECS_RAW,
    )
except ImportError:
    from instance_catalog_data import (  # type: ignore[no-redef]  # noqa: PLC0415
        EC2_ON_DEMAND_USD_PER_HOUR,
        INSTANCE_SPECS_RAW,
    )

INSTANCE_CATALOG: dict[str, InstanceSpec] = {
    name: InstanceSpec(
        vcpus=int(spec["vcpus"]),
        memory_gb=int(spec["memory_gb"]),
        family=str(spec["family"]),
    )
    for name, spec in INSTANCE_SPECS_RAW.items()
}

_SPOT_TO_ON_DEMAND_RATIO = 0.37
_SINGLE_NODE_MEM_TARGET = 0.82
_SINGLE_NODE_CPU_TARGET = 0.85
_SLA_INTERVAL_TARGET = 0.80

# Negotiated JOBS $/DBU from dim_dbu_price (cost-attribution seed).
# TODO: source dynamically from fact_databricks_dag_run.dbu_rate_usd.
_USD_PER_DBU = 0.114
# +100% wall when Photon is normalized off: middle of the observed 2-3x Photon
# ETL speedup and the 2x TPC-DS baseline — conservative for both SLA and cost.
_PHOTON_OFF_WALL_INFLATION = 2.0
# CPU/memory demand inflation when sizing for STANDARD after Photon removal
# (web-research midpoints: CPU 1.15-1.25, mem 1.25-1.35).
_PHOTON_OFF_CPU_INFLATION = 1.20
_PHOTON_OFF_MEM_INFLATION = 1.30
# Fleet-derived DBU consumed per node-hour, per instance type (non-Photon runs).
# Populated once at runtime (main); empty in offline/unit contexts, where the
# cost engine degrades to a vCPU-scaled observed-DBU proxy.
_FLEET_DBU_RATE: dict[str, float] = {}
_COLLAPSE_WALL_INFLATION_MAX = 0.67
_COLLAPSE_WALL_BURST_INFLATION_MAX = 0.15
_KEEP_MULTI_COHORTS = {
    "keep_multi_sla",
    "keep_multi_memory",
    "keep_multi_compute",
    "keep_multi_balanced",
    "keep_multi_cost",
}

# ---------------------------------------------------------------------------
# Preset catalog  (from prod_conf.yml consolidation_* entries)
#
# All multi-node presets default to num_workers=2 (from prod_conf.yml).
# All single-node presets have num_workers=0.
# ---------------------------------------------------------------------------

_TIER_ORDER = ("xs", "s", "m", "l", "xl")
_OOM_FAMILY_LADDER = ("compute", "general", "memory")
_SIZE_TO_TIER: dict[str, str] = {
    "large": "xs",
    "xlarge": "s",
    "2xlarge": "m",
    "4xlarge": "l",
    "8xlarge": "xl",
}
_TIER_TO_SIZE: dict[str, str] = {v: k for k, v in _SIZE_TO_TIER.items()}


@dataclass(frozen=True)
class PresetSpec:
    driver_node_type: str
    worker_node_type: str
    num_workers: int  # 0 = single-node
    single_node: bool
    family: str  # compute | general | memory
    tier: str  # xs | s | m | l | xl


def _build_preset_catalog() -> dict[str, PresetSpec]:
    catalog: dict[str, PresetSpec] = {}
    families = [
        ("compute", "c6g"),
        ("general", "m6g"),
        ("memory", "r6g"),
    ]
    for family, prefix in families:
        for tier, size in _TIER_TO_SIZE.items():
            node = f"{prefix}.{size}"
            # Multi-node
            name = f"consolidation_{tier}_{family}_cluster"
            catalog[name] = PresetSpec(node, node, 2, False, family, tier)
            # Single-node (no compute single-node in prod_conf.yml)
            if family != "compute":
                sn_name = f"consolidation_{tier}_{family}_single_node_cluster"
                catalog[sn_name] = PresetSpec(node, node, 0, True, family, tier)
    return catalog


PRESET_CATALOG: dict[str, PresetSpec] = _build_preset_catalog()


def _node_family(node_type: str) -> str:
    """Map a node type string to 'compute' | 'general' | 'memory'."""
    prefix = node_type.split(".")[0]
    if prefix.startswith("c"):
        return "compute"
    if prefix.startswith("r"):
        return "memory"
    return "general"  # m6g, m6gd, m7g → general


def _strip_nvme(node_type: str | None) -> str | None:
    """Map a local-NVMe instance to its non-NVMe equivalent (``*gd`` → ``*g``).

    e.g. ``m6gd.2xlarge`` → ``m6g.2xlarge``, ``r6gd.xlarge`` → ``r6g.xlarge``.
    Non-NVMe types (and ``None``) pass through unchanged. Recommendations never
    keep NVMe instances: the cost engine assumes the ~20% NVMe EC2 premium is
    removed, so the emitted node type must match.
    """
    if not node_type or "." not in node_type:
        return node_type
    prefix, _, size = node_type.partition(".")
    if prefix.endswith("gd"):
        prefix = prefix[:-1]  # drop the trailing 'd' (m6gd → m6g)
    return f"{prefix}.{size}"


def _node_tier(node_type: str) -> str | None:
    """Map 'm6g.xlarge' → 's', 'm6g.2xlarge' → 'm', etc."""
    try:
        size = node_type.split(".")[-1]
        return _SIZE_TO_TIER.get(size)
    except (IndexError, AttributeError):
        return None


def infer_current_preset(
    driver_node_type: str,
    worker_node_type: str | None,
    worker_count: int,
) -> str | None:
    """Reverse-map observed node types to a consolidation preset name, or None."""
    tier = _node_tier(driver_node_type)
    family = _node_family(driver_node_type)
    if not tier:
        return None
    single = worker_count == 0
    if single:
        if family == "compute":
            family = "general"  # no compute single-node preset
        name = f"consolidation_{tier}_{family}_single_node_cluster"
    else:
        name = f"consolidation_{tier}_{family}_cluster"
    return name if name in PRESET_CATALOG else None


# ---------------------------------------------------------------------------
# Input data model
# ---------------------------------------------------------------------------


@dataclass
class DagMetrics:
    dag_id: str
    arm_days: int
    arm_runs: int
    driver_node_type: str
    worker_node_type: str | None
    worker_count: int | None  # 0 = single-node; None = autoscale
    arm_total_cost_usd: float
    arm_avg_cost_per_run_usd: float
    wall_p50_min: float
    wall_p95_min: float
    drv_cpu_p50: float | None
    drv_cpu_p95: float | None
    drv_mem_p95: float | None
    drv_wait_p95: float | None
    wrk_cpu_p50: float | None
    wrk_cpu_p95: float | None
    wrk_mem_p95: float | None
    wrk_wait_p95: float | None
    drv_mem_p50: float | None = None
    wrk_mem_p50: float | None = None
    local_disk_p95: float | None = None
    arm_total_cost_estimate_usd: float | None = None
    arm_avg_total_cost_estimate_usd: float | None = None
    dominant_config_run_share: float = 1.0
    dominant_config_cost_share: float = 1.0
    runs_per_day: float | None = None
    schedule_interval_minutes: float | None = None
    arm_total_ec2_cost_usd: float | None = None
    arm_avg_ec2_cost_usd: float | None = None
    arm_total_dbu_cost_usd: float | None = None
    arm_avg_dbu_cost_usd: float | None = None
    arm_avg_dbu_consumed: float | None = None
    ec2_spot_hours: float | None = None
    ec2_on_demand_hours: float | None = None
    total_memory_bytes_spilled: float = 0.0
    total_disk_bytes_spilled: float = 0.0
    max_peak_execution_memory_bytes: float | None = None
    max_jvm_heap_bytes: float | None = None
    total_gc_time_ms: float = 0.0
    total_executor_run_time_ms: float = 0.0
    max_task_skew_ratio: float | None = None
    primary_min_autoscale_workers: int | None = None
    primary_max_autoscale_workers: int | None = None
    is_ec2_estimated: bool = False
    ec2_pricing_missing: bool = False
    dbu_negotiated_price_missing: bool = False
    is_any_photon: bool = False
    is_any_local_nvme: bool = False

    @property
    def topology(self) -> str:
        if (
            self.worker_count is None
            or self.primary_min_autoscale_workers is not None
            or self.primary_max_autoscale_workers is not None
        ):
            return "autoscale"
        if self.worker_count == 0:
            return "single"
        return "multi"


@dataclass(frozen=True)
class EffectiveDemand:
    """CPU/memory utilization for sizing when Photon is normalized off."""

    drv_cpu_p50: float | None
    drv_cpu_p95: float | None
    drv_mem_p50: float | None
    drv_mem_p95: float | None
    wrk_cpu_p50: float | None
    wrk_cpu_p95: float | None
    wrk_mem_p50: float | None
    wrk_mem_p95: float | None


def _photon_adjust_pct(value: float | None, factor: float) -> float | None:
    if value is None:
        return None
    return round(value * factor, 1)


def effective_demand(m: DagMetrics) -> EffectiveDemand:
    """Observed utilization inflated for STANDARD-runtime sizing when Photon ran."""
    if not m.is_any_photon:
        return EffectiveDemand(
            drv_cpu_p50=m.drv_cpu_p50,
            drv_cpu_p95=m.drv_cpu_p95,
            drv_mem_p50=m.drv_mem_p50,
            drv_mem_p95=m.drv_mem_p95,
            wrk_cpu_p50=m.wrk_cpu_p50,
            wrk_cpu_p95=m.wrk_cpu_p95,
            wrk_mem_p50=m.wrk_mem_p50,
            wrk_mem_p95=m.wrk_mem_p95,
        )
    return EffectiveDemand(
        drv_cpu_p50=_photon_adjust_pct(m.drv_cpu_p50, _PHOTON_OFF_CPU_INFLATION),
        drv_cpu_p95=_photon_adjust_pct(m.drv_cpu_p95, _PHOTON_OFF_CPU_INFLATION),
        drv_mem_p50=_photon_adjust_pct(m.drv_mem_p50, _PHOTON_OFF_MEM_INFLATION),
        drv_mem_p95=_photon_adjust_pct(m.drv_mem_p95, _PHOTON_OFF_MEM_INFLATION),
        wrk_cpu_p50=_photon_adjust_pct(m.wrk_cpu_p50, _PHOTON_OFF_CPU_INFLATION),
        wrk_cpu_p95=_photon_adjust_pct(m.wrk_cpu_p95, _PHOTON_OFF_CPU_INFLATION),
        wrk_mem_p50=_photon_adjust_pct(m.wrk_mem_p50, _PHOTON_OFF_MEM_INFLATION),
        wrk_mem_p95=_photon_adjust_pct(m.wrk_mem_p95, _PHOTON_OFF_MEM_INFLATION),
    )


# ---------------------------------------------------------------------------
# Classifier
# ---------------------------------------------------------------------------

_DOMINANT_CONFIG_SHARE_MIN = 0.80
_DRIVER_CPU_BOUND_P95 = 70.0
_DRIVER_WAIT_P95 = 10.0
_DRIVER_MEM_PRESSURE_P95 = 75.0
_DRIVER_OOM_P95 = 88.0
_WORKER_WAIT_P95 = 10.0
_WORKER_MEM_BOUND_P95 = 75.0
_COLLAPSE_WALL_P95_MIN = 30.0
_COLLAPSE_WORKER_CPU_P50_MAX = 20.0
_COLLAPSE_WORKER_CPU_P95_MAX = 55.0
_COLLAPSE_WORKER_MEM_P95_MAX = 60.0
_COLLAPSE_DRIVER_MEM_P95_MAX = 75.0
_DOWNSIZE_WORKER_CPU_P50_MAX = 20.0
_DOWNSIZE_WORKER_CPU_P95_MAX = 55.0
_DOWNSIZE_WORKER_MEM_P95_MAX = 45.0
_SPILL_PRESSURE_BYTES = 0.0
_COLLAPSE_DRIVER_MEM_PROJECTED_MAX = 125.0


def _is_validation_dag(dag_id: str) -> bool:
    return dag_id.endswith("__validation")


def _has_values(*values: float | int | None) -> bool:
    return all(v is not None for v in values)


def _required_metrics_present(m: DagMetrics) -> bool:
    driver_required = (m.drv_cpu_p50, m.drv_cpu_p95, m.drv_mem_p95, m.drv_wait_p95)
    if not _has_values(*driver_required):
        return False
    if m.topology == "single":
        return True
    worker_required = (m.wrk_cpu_p50, m.wrk_cpu_p95, m.wrk_mem_p95, m.wrk_wait_p95)
    return _has_values(*worker_required)


def _worker_node_type(m: DagMetrics) -> str:
    return m.worker_node_type or m.driver_node_type


def _tier_index(tier: str | None) -> int | None:
    return _TIER_ORDER.index(tier) if tier in _TIER_ORDER else None


def _node_for_family_tier(family: str, tier: str) -> str:
    prefix_by_family = {"compute": "c6g", "general": "m6g", "memory": "r6g"}
    return f"{prefix_by_family[family]}.{_TIER_TO_SIZE[tier]}"


@dataclass(frozen=True)
class SingleNodeSizing:
    node_type: str | None
    required_mem_gb: float | None
    required_cores: float | None
    projected_mem_pct: float | None
    projected_cpu_pct: float | None
    blocked_reason: str | None = None


@dataclass(frozen=True)
class WorkerResize:
    node_type: str
    worker_count: int
    count_blocked_sla: bool = False


def _instance_price(node_type: str | None, *, spot: bool = False) -> float | None:
    if not node_type:
        return None
    od_price = EC2_ON_DEMAND_USD_PER_HOUR.get(node_type)
    if od_price is None:
        return None
    return round(od_price * _SPOT_TO_ON_DEMAND_RATIO, 6) if spot else od_price


def _single_node_candidates() -> list[tuple[str, InstanceSpec, float]]:
    candidates: list[tuple[str, InstanceSpec, float]] = []
    for node_type, spec in INSTANCE_CATALOG.items():
        if not ARM_REGEX.match(node_type):
            continue
        price = _instance_price(node_type)
        if price is None:
            continue
        candidates.append((node_type, spec, price))
    return sorted(
        candidates, key=lambda item: (item[2], item[1].memory_gb, item[1].vcpus)
    )


def _additive_memory_gb(m: DagMetrics) -> float | None:
    d = effective_demand(m)
    driver_spec = INSTANCE_CATALOG.get(m.driver_node_type)
    if not driver_spec or d.drv_mem_p95 is None:
        return None
    used = driver_spec.memory_gb * d.drv_mem_p95 / 100.0
    if m.topology == "multi":
        worker_spec = INSTANCE_CATALOG.get(_worker_node_type(m))
        if not worker_spec or d.wrk_mem_p95 is None or not m.worker_count:
            return None
        used += worker_spec.memory_gb * d.wrk_mem_p95 / 100.0 * m.worker_count
    return round(used, 4)


def _additive_cores(m: DagMetrics) -> float | None:
    d = effective_demand(m)
    driver_spec = INSTANCE_CATALOG.get(m.driver_node_type)
    if not driver_spec or d.drv_cpu_p95 is None:
        return None
    cores = driver_spec.vcpus * d.drv_cpu_p95 / 100.0
    if m.topology == "multi":
        worker_spec = INSTANCE_CATALOG.get(_worker_node_type(m))
        if not worker_spec or d.wrk_cpu_p95 is None or not m.worker_count:
            return None
        cores += worker_spec.vcpus * d.wrk_cpu_p95 / 100.0 * m.worker_count
    return round(cores, 4)


def _family_order_for_demand(
    required_mem_gb: float, required_cores: float
) -> tuple[str, ...]:
    if required_cores <= 0:
        return ("general", "memory")
    gib_per_core = required_mem_gb / required_cores
    if gib_per_core <= 2:
        return ("compute", "general", "memory")
    if gib_per_core <= 4:
        return ("general", "memory")
    return ("memory",)


def _node_for_demand(required_mem_gb: float, required_cores: float) -> str | None:
    """Pick the cheapest ARM node that fits demand at target utilization."""
    for family in _family_order_for_demand(required_mem_gb, required_cores):
        family_candidates = [
            (node_type, spec, price)
            for node_type, spec, price in _single_node_candidates()
            if spec.family == family
            and required_mem_gb / spec.memory_gb <= _SINGLE_NODE_MEM_TARGET
            and required_cores / spec.vcpus <= _SINGLE_NODE_CPU_TARGET
        ]
        if family_candidates:
            return min(
                family_candidates,
                key=lambda item: (item[2], item[1].memory_gb, item[1].vcpus),
            )[0]
    return None


def size_single_node(m: DagMetrics) -> SingleNodeSizing:
    required_mem_gb = _additive_memory_gb(m)
    required_cores = _additive_cores(m)
    if required_mem_gb is None or required_cores is None:
        return SingleNodeSizing(
            None, required_mem_gb, required_cores, None, None, "needs_more_telemetry"
        )

    family_order = _family_order_for_demand(required_mem_gb, required_cores)
    feasible: list[tuple[str, InstanceSpec, float]] = []
    for family in family_order:
        family_candidates = [
            (node_type, spec, price)
            for node_type, spec, price in _single_node_candidates()
            if spec.family == family
            and required_mem_gb / spec.memory_gb <= _SINGLE_NODE_MEM_TARGET
            and required_cores / spec.vcpus <= _SINGLE_NODE_CPU_TARGET
        ]
        if family_candidates:
            feasible = family_candidates
            break

    if not feasible:
        largest_mem = max(spec.memory_gb for _, spec, _ in _single_node_candidates())
        largest_vcpus = max(spec.vcpus for _, spec, _ in _single_node_candidates())
        blocked_reason = (
            "keep_multi_memory"
            if required_mem_gb / largest_mem > _SINGLE_NODE_MEM_TARGET
            else "keep_multi_compute"
            if required_cores / largest_vcpus > _SINGLE_NODE_CPU_TARGET
            else "keep_multi_balanced"
        )
        return SingleNodeSizing(
            None, required_mem_gb, required_cores, None, None, blocked_reason
        )

    node_type, spec, _price = min(
        feasible, key=lambda item: (item[2], item[1].memory_gb, item[1].vcpus)
    )
    return SingleNodeSizing(
        node_type=node_type,
        required_mem_gb=required_mem_gb,
        required_cores=required_cores,
        projected_mem_pct=round(required_mem_gb / spec.memory_gb * 100.0, 1),
        projected_cpu_pct=round(required_cores / spec.vcpus * 100.0, 1),
    )


def _schedule_interval_minutes(m: DagMetrics) -> float:
    if m.schedule_interval_minutes and m.schedule_interval_minutes > 0:
        if m.runs_per_day and m.runs_per_day >= 18.0:
            return min(m.schedule_interval_minutes, 60.0)
        return m.schedule_interval_minutes
    if m.runs_per_day and m.runs_per_day > 0:
        if m.runs_per_day >= 18.0:
            return 60.0
        return 1440.0 / m.runs_per_day
    if m.arm_days > 0 and m.arm_runs > 0:
        return 1440.0 / max(m.arm_runs / m.arm_days, 0.001)
    return 1440.0


def _collapse_wall_inflation(m: DagMetrics) -> float:
    d = effective_demand(m)
    worker_activity = max(
        (d.wrk_cpu_p50 or 0.0) / 85.0,
        (d.wrk_cpu_p95 or 0.0) / 85.0,
        (d.wrk_mem_p95 or 0.0) / 82.0,
    )
    worker_activity = min(max(worker_activity, 0.0), 1.0)
    worker_burst = min(max((d.wrk_cpu_p95 or 0.0) / 85.0, 0.0), 1.0)
    worker_multiplier = min((m.worker_count or 0) / 2.0, 1.0)
    inflation = (
        1.0
        + (
            _COLLAPSE_WALL_INFLATION_MAX * worker_activity
            + _COLLAPSE_WALL_BURST_INFLATION_MAX * worker_burst
        )
        * worker_multiplier
    )
    return inflation


def _current_cost_basis(m: DagMetrics) -> float:
    """Per-run total USD (negotiated DBU + EC2). Never mix USD with DBU scalars."""
    return m.arm_avg_cost_per_run_usd


def _wall_minutes_for_cost(m: DagMetrics) -> float | None:
    if m.wall_p50_min and m.wall_p50_min > 0:
        return m.wall_p50_min
    if m.wall_p95_min and m.wall_p95_min > 0:
        return m.wall_p95_min
    return None


def _shape_wall_minutes(m: DagMetrics, rec_workers: int) -> float | None:
    """Observed wall with topology-shape inflation only (no Photon term).

    Conservative inflation when collapsing a multi-node cluster onto a single
    node, or when reducing the worker count below the observed count.
    """
    base = _wall_minutes_for_cost(m)
    if base is None:
        return None
    current_workers = m.worker_count or 0
    if rec_workers == 0 and m.topology == "multi":
        return base * _collapse_wall_inflation(m)
    if rec_workers and current_workers and rec_workers < current_workers:
        return base * _worker_reduction_wall_inflation(m, current_workers, rec_workers)
    return base


def _legacy_dbu_projection(
    m: DagMetrics, nodes: list[str], wall_minutes: float
) -> float | None:
    """Offline fallback: scale observed DBU USD by vCPU ratio and wall factor.

    Used only when the fleet DBU-rate map cannot price the candidate (no fleet
    data, e.g. offline/CSV/unit runs). Does not credit Photon-off DBU savings —
    that truthful reprojection requires the non-Photon fleet rate.
    """
    current_dbu_usd = (
        m.arm_avg_dbu_cost_usd
        if m.arm_avg_dbu_cost_usd is not None
        else max(_current_cost_basis(m) - (m.arm_avg_ec2_cost_usd or 0.0), 0.0)
    )
    current_vcpus = _vcpus(m.driver_node_type) + (m.worker_count or 0) * _vcpus(
        _worker_node_type(m)
    )
    rec_vcpus = sum(_vcpus(node) for node in nodes)
    current_wall = _wall_minutes_for_cost(m)
    if current_vcpus <= 0 or rec_vcpus <= 0 or not current_wall:
        return None
    wall_factor = wall_minutes / current_wall
    return current_dbu_usd * rec_vcpus / current_vcpus * wall_factor


def estimate_projected_total_cost(
    m: DagMetrics,
    rec_driver: str,
    rec_workers: int,
    *,
    rec_worker: str | None = None,
    fleet_dbu_rate: dict[str, float] | None = None,
) -> float | None:
    """Explicit per-run cost of a candidate shape (USD).

    EC2 = on-demand driver + spot workers, priced over the projected wall-clock.
    DBU = fleet non-Photon DBU/node-hour x node-hours x negotiated $/DBU.
    Workers are *always* priced spot (the preset default), regardless of the
    DAG's current availability override. When the observed config ran Photon and
    the fleet can reprice DBU, the projected wall is inflated by
    ``_PHOTON_OFF_WALL_INFLATION`` (cost reflects the normalized Photon-off run).
    """
    fleet = _FLEET_DBU_RATE if fleet_dbu_rate is None else fleet_dbu_rate
    rec_worker_type = (rec_worker or _worker_node_type(m)) if rec_workers > 0 else None

    if _instance_price(rec_driver) is None:
        return None
    if rec_workers > 0 and _instance_price(rec_worker_type) is None:
        return None

    base_wall = _shape_wall_minutes(m, rec_workers)
    if base_wall is None:
        return None

    nodes = [rec_driver]
    if rec_workers > 0 and rec_worker_type:
        nodes.extend([rec_worker_type] * rec_workers)

    fleet_rates = [fleet_dbu_per_node_hour(node, fleet) for node in nodes]
    fleet_priced = bool(fleet_rates) and all(rate is not None for rate in fleet_rates)

    photon_off = bool(m.is_any_photon)
    wall_minutes = base_wall * (_PHOTON_OFF_WALL_INFLATION if photon_off else 1.0)
    wall_h = wall_minutes / 60.0

    driver_price = _instance_price(rec_driver, spot=False)
    if driver_price is None:
        return None
    ec2 = driver_price * wall_h
    if rec_workers > 0:
        worker_price = _instance_price(rec_worker_type, spot=True)
        if worker_price is None:
            return None
        ec2 += worker_price * wall_h * rec_workers

    if fleet_priced:
        dbu = sum(fleet_rates) * wall_h * _USD_PER_DBU
    else:
        dbu = _legacy_dbu_projection(m, nodes, wall_minutes)
        if dbu is None:
            return None

    return round(ec2 + dbu, 6)


def _single_node_preset_for_node(
    node_type: str | None,
) -> tuple[str | None, str | None]:
    if not node_type:
        return None, None
    family = _node_family(node_type)
    tier = _node_tier(node_type)
    preset_family = "general" if family == "compute" else family
    if tier is None:
        tier = "xl"
    name = f"consolidation_{tier}_{preset_family}_single_node_cluster"
    return (name, node_type) if name in PRESET_CATALOG else (None, None)


def _multi_preset_for_worker(worker_node_type: str | None) -> str | None:
    if not worker_node_type:
        return None
    family = _node_family(worker_node_type)
    tier = _node_tier(worker_node_type) or "xl"
    name = f"consolidation_{tier}_{family}_cluster"
    return name if name in PRESET_CATALOG else None


def _driver_minimize_node(m: DagMetrics) -> str | None:
    d = effective_demand(m)
    if d.drv_mem_p95 is None:
        return None
    current_spec = INSTANCE_CATALOG.get(m.driver_node_type)
    if not current_spec:
        return None
    used_mem_gb = current_spec.memory_gb * d.drv_mem_p95 / 100.0
    used_cores = current_spec.vcpus * (d.drv_cpu_p95 or 0.0) / 100.0
    candidate = _node_for_demand(used_mem_gb, used_cores)
    current_price = _instance_price(m.driver_node_type)
    candidate_price = _instance_price(candidate)
    if (
        not candidate
        or current_price is None
        or candidate_price is None
        or candidate_price >= current_price
    ):
        return m.driver_node_type
    return candidate


def _worker_reduction_wall_inflation(
    m: DagMetrics,
    old_count: int,
    new_count: int,
) -> float:
    if new_count >= old_count or old_count <= 0 or new_count <= 0:
        return 1.0
    d = effective_demand(m)
    worker_activity = max(
        (d.wrk_cpu_p50 or 0.0) / (_SINGLE_NODE_CPU_TARGET * 100.0),
        (d.wrk_cpu_p95 or 0.0) / (_SINGLE_NODE_CPU_TARGET * 100.0),
        (d.wrk_mem_p95 or 0.0) / (_SINGLE_NODE_MEM_TARGET * 100.0),
    )
    worker_activity = min(max(worker_activity, 0.0), 1.0)
    parallelism_loss = old_count / new_count - 1.0
    return 1.0 + parallelism_loss * worker_activity


def _worker_resize(m: DagMetrics) -> WorkerResize | None:
    d = effective_demand(m)
    if (
        m.topology != "multi"
        or not m.worker_count
        or d.wrk_mem_p95 is None
        or d.wrk_cpu_p95 is None
    ):
        return None

    current_worker = _worker_node_type(m)
    current_spec = INSTANCE_CATALOG.get(current_worker)
    current_price = _instance_price(current_worker)
    if not current_spec or current_price is None:
        return None

    per_node_mem_gb = current_spec.memory_gb * d.wrk_mem_p95 / 100.0
    per_node_cores = current_spec.vcpus * d.wrk_cpu_p95 / 100.0
    candidate_worker = (
        _node_for_demand(per_node_mem_gb, per_node_cores) or current_worker
    )
    candidate_price = _instance_price(candidate_worker)
    if candidate_price is None or candidate_price >= current_price:
        candidate_worker = current_worker

    candidate_spec = INSTANCE_CATALOG[candidate_worker]
    aggregate_mem_gb = per_node_mem_gb * m.worker_count
    aggregate_cores = per_node_cores * m.worker_count
    min_count = max(
        2,
        math.ceil(
            max(
                aggregate_mem_gb / (candidate_spec.memory_gb * _SINGLE_NODE_MEM_TARGET),
                aggregate_cores / (candidate_spec.vcpus * _SINGLE_NODE_CPU_TARGET),
            )
        ),
    )
    rec_count = m.worker_count
    count_blocked_sla = False
    if min_count < m.worker_count and m.worker_count > 2:
        candidate_count = max(min_count, m.worker_count - 2, 2)
        projected_wall = _projected_wall_for_sla(m, candidate_count)
        if projected_wall is None or projected_wall > _sla_limit_minutes(m):
            count_blocked_sla = True
        else:
            rec_count = candidate_count

    return WorkerResize(candidate_worker, rec_count, count_blocked_sla)


@dataclass(frozen=True)
class ShapeCandidate:
    """A candidate cluster shape; topology is implied by ``worker_count``."""

    driver_node_type: str
    worker_node_type: str | None
    worker_count: int  # 0 = single node
    label: str


def observed_total_cores(m: DagMetrics) -> int:
    """Provisioned vCPUs of the observed dominant config (telemetry_only cap)."""
    cores = _vcpus(m.driver_node_type)
    if m.topology == "multi" and m.worker_count:
        cores += m.worker_count * _vcpus(_worker_node_type(m))
    return cores


def candidate_total_cores(candidate: ShapeCandidate) -> int:
    cores = _vcpus(candidate.driver_node_type)
    if candidate.worker_count > 0 and candidate.worker_node_type:
        cores += candidate.worker_count * _vcpus(candidate.worker_node_type)
    return cores


def build_best_single_candidate(m: DagMetrics) -> ShapeCandidate | None:
    """Smallest single on-demand node that holds the additive demand."""
    sizing = size_single_node(m)
    if not sizing.node_type:
        return None
    return ShapeCandidate(sizing.node_type, None, 0, "best_single")


def build_current_refined_candidate(m: DagMetrics) -> ShapeCandidate | None:
    """Refined multi-node: demand-sized OD driver + >=2 right-sized spot workers.

    The driver and worker levers are evaluated independently from their own p95
    demand and assembled here. Returns None for non-multi topologies or when the
    worker lever falls below the 2-worker floor (1 driver + 1 worker is strictly
    dominated by single-node) — the caller then compares the single candidate.
    """
    if m.topology != "multi":
        return None
    worker_resize = _worker_resize(m)
    if worker_resize is None or worker_resize.worker_count < 2:
        return None
    driver = _driver_minimize_node(m) or m.driver_node_type
    return ShapeCandidate(
        driver,
        worker_resize.node_type,
        worker_resize.worker_count,
        "right_size_multi",
    )


def _project_utilization_pct(
    current_pct: float | None,
    current_node: str | None,
    rec_node: str | None,
    *,
    metric: str,
    count_ratio: float = 1.0,
) -> float | None:
    if current_pct is None or not current_node or not rec_node:
        return None
    current_spec = INSTANCE_CATALOG.get(current_node)
    rec_spec = INSTANCE_CATALOG.get(rec_node)
    if not current_spec or not rec_spec:
        return None
    current_capacity = (
        current_spec.memory_gb if metric == "memory" else current_spec.vcpus
    )
    rec_capacity = rec_spec.memory_gb if metric == "memory" else rec_spec.vcpus
    if rec_capacity <= 0:
        return None
    return round(current_pct * current_capacity / rec_capacity * count_ratio, 1)


def _lower_tier(tier: str | None) -> str | None:
    idx = _tier_index(tier)
    if idx is None or idx == 0:
        return None
    return _TIER_ORDER[idx - 1]


def _higher_tier(tier: str | None) -> str | None:
    idx = _tier_index(tier)
    if idx is None or idx >= len(_TIER_ORDER) - 1:
        return None
    return _TIER_ORDER[idx + 1]


def _spill_pressure(m: DagMetrics) -> bool:
    return (m.total_memory_bytes_spilled or 0.0) > _SPILL_PRESSURE_BYTES or (
        m.total_disk_bytes_spilled or 0.0
    ) > _SPILL_PRESSURE_BYTES


def _projected_driver_mem_after_collapse(
    m: DagMetrics, rec_driver: str | None
) -> float | None:
    d = effective_demand(m)
    if (
        rec_driver is None
        or d.drv_mem_p95 is None
        or d.wrk_mem_p95 is None
        or not m.worker_node_type
        or not m.worker_count
    ):
        return None
    rec_mem = INSTANCE_CATALOG.get(rec_driver)
    worker_mem = INSTANCE_CATALOG.get(m.worker_node_type)
    current_driver_mem = INSTANCE_CATALOG.get(m.driver_node_type)
    if not rec_mem or not worker_mem or not current_driver_mem:
        return None

    driver_used_gb = current_driver_mem.memory_gb * d.drv_mem_p95 / 100.0
    worker_used_gb = worker_mem.memory_gb * d.wrk_mem_p95 / 100.0 * m.worker_count
    return round((driver_used_gb + worker_used_gb) / rec_mem.memory_gb * 100.0, 1)


def _collapse_memory_feasible(m: DagMetrics, rec_driver: str | None) -> bool:
    projected = _projected_driver_mem_after_collapse(m, rec_driver)
    return projected is None or projected < _COLLAPSE_DRIVER_MEM_PROJECTED_MAX


def _driver_downsize_node(m: DagMetrics) -> str | None:
    family = _node_family(m.driver_node_type)
    tier = _lower_tier(_node_tier(m.driver_node_type))
    if tier is None:
        return None
    if m.topology == "single" and family == "compute":
        family = "general"
    return _node_for_family_tier(family, tier)


_RELAXED_DOWNSIZE_CPU_P95_MAX = 40.0
_RELAXED_DOWNSIZE_MEM_P95_MAX = 70.0


def _single_node_downsize_node(m: DagMetrics) -> str | None:
    """Relaxed single-node downsize candidate.

    A same-family one-tier-down node, accepted only when CPU/mem headroom allows
    it (projected memory must stay under the single-node memory target). Returns
    None when no safe downsize exists.
    """
    d = effective_demand(m)
    if d.drv_cpu_p95 is None or d.drv_mem_p95 is None:
        return None
    if (
        d.drv_cpu_p95 > _RELAXED_DOWNSIZE_CPU_P95_MAX
        or d.drv_mem_p95 > _RELAXED_DOWNSIZE_MEM_P95_MAX
    ):
        return None
    downsize = _driver_downsize_node(m)
    if not downsize or downsize == m.driver_node_type:
        return None
    current_spec = INSTANCE_CATALOG.get(m.driver_node_type)
    downsize_spec = INSTANCE_CATALOG.get(downsize)
    if not current_spec or not downsize_spec or downsize_spec.memory_gb <= 0:
        return None
    used_mem_gb = current_spec.memory_gb * d.drv_mem_p95 / 100.0
    projected_mem_pct = used_mem_gb / downsize_spec.memory_gb
    used_cores = current_spec.vcpus * (d.drv_cpu_p95 or 0.0) / 100.0
    projected_cpu_pct = used_cores / downsize_spec.vcpus if downsize_spec.vcpus else 1.0
    if (
        projected_mem_pct > _SINGLE_NODE_MEM_TARGET
        or projected_cpu_pct > _SINGLE_NODE_CPU_TARGET
    ):
        return None
    return downsize


def _projected_wall_for_sla(m: DagMetrics, rec_workers: int) -> float | None:
    """Projected p95 wall used for the SLA guard.

    Built on the SLA-relevant p95 wall (not the p50-preferred cost wall), with
    topology-shape inflation (collapse / worker-count reduction) plus the
    Photon-off normalization the recommender always applies. A same-parallelism
    change (worker-type swap at equal count) leaves wall unchanged.
    """
    base = m.wall_p95_min if (m.wall_p95_min and m.wall_p95_min > 0) else m.wall_p50_min
    if not base or base <= 0:
        return None
    wall = base
    current_workers = m.worker_count or 0
    if rec_workers == 0 and m.topology == "multi":
        wall *= _collapse_wall_inflation(m)
    elif rec_workers and current_workers and rec_workers < current_workers:
        wall *= _worker_reduction_wall_inflation(m, current_workers, rec_workers)
    if m.is_any_photon:
        wall *= _PHOTON_OFF_WALL_INFLATION
    return wall


def _sla_limit_minutes(m: DagMetrics) -> float:
    """SLA ceiling: the larger of the schedule-based target and the observed p95.

    Never regress a DAG's wall beyond what it already runs at, but also never use
    a candidate that would push wall past the schedule SLA target.
    """
    sla_cap = _SLA_INTERVAL_TARGET * _schedule_interval_minutes(m)
    return max(sla_cap, m.wall_p95_min or 0.0)


@dataclass(frozen=True)
class MultiDecision:
    cohort: str
    candidate: ShapeCandidate | None  # None = keep observed shape
    blocked_cost: float | None = None


def _candidate_is_reduction(m: DagMetrics, candidate: ShapeCandidate) -> bool:
    """True when the refined multi candidate genuinely shrinks the shape.

    A refined candidate identical to the observed shape is not a recommendation
    on its own (any apparent "savings" would just be the spot-vs-observed pricing
    gap, which the dedicated restore_spot action surfaces separately).
    """
    return (
        candidate.driver_node_type != m.driver_node_type
        or candidate.worker_node_type != _worker_node_type(m)
        or candidate.worker_count != (m.worker_count or 0)
    )


def _keep_multi_reason(m: DagMetrics, sizing: SingleNodeSizing) -> str:
    """Most informative reason a multi-node DAG is kept as-is."""
    if sizing.blocked_reason in {
        "keep_multi_memory",
        "keep_multi_compute",
        "keep_multi_balanced",
    }:
        return sizing.blocked_reason
    d = effective_demand(m)
    if (
        (d.drv_cpu_p95 or 0.0) >= _DRIVER_CPU_BOUND_P95
        and (d.wrk_cpu_p50 or 0.0) >= 50.0
        and (d.wrk_mem_p95 or 0.0) >= 60.0
    ):
        return "keep_multi_balanced"
    wall = _projected_wall_for_sla(m, 0)
    if wall is None or wall > _sla_limit_minutes(m):
        return "keep_multi_sla"
    return "keep_multi_cost"


def _decide_multi(m: DagMetrics) -> MultiDecision:
    """Bidirectional multi-node decision: cost-truthful pick among candidates.

    Generates the feasible candidates (collapse to a single node; refine the
    multi-node shape when it genuinely shrinks), filters by core-cap / SLA /
    memory headroom, and keeps the cheapest that beats the observed cost. The
    cohort *is* the reason; when nothing wins, the DAG is kept with the most
    informative keep-multi reason.
    """
    sizing = size_single_node(m)
    if sizing.blocked_reason == "needs_more_telemetry":
        return MultiDecision("needs_more_telemetry", None)

    observed_cores = observed_total_cores(m)
    sla_limit = _sla_limit_minutes(m)
    baseline = _current_cost_basis(m)

    options: list[tuple[float, str, ShapeCandidate]] = []

    best_single = build_best_single_candidate(m)
    if (
        best_single is not None
        and candidate_total_cores(best_single) <= observed_cores
        and _collapse_memory_feasible(m, best_single.driver_node_type)
    ):
        wall = _projected_wall_for_sla(m, 0)
        cost = estimate_projected_total_cost(m, best_single.driver_node_type, 0)
        if wall is not None and wall <= sla_limit and cost is not None:
            options.append((cost, "collapse_to_single", best_single))

    refined = build_current_refined_candidate(m)
    if (
        refined is not None
        and candidate_total_cores(refined) <= observed_cores
        and _candidate_is_reduction(m, refined)
    ):
        wall = _projected_wall_for_sla(m, refined.worker_count)
        cost = estimate_projected_total_cost(
            m,
            refined.driver_node_type,
            refined.worker_count,
            rec_worker=refined.worker_node_type,
        )
        if wall is not None and wall <= sla_limit and cost is not None:
            options.append((cost, "right_size_multi", refined))

    viable = [option for option in options if baseline <= 0 or option[0] < baseline]
    if viable:
        cost, cohort, candidate = min(viable, key=lambda option: option[0])
        return MultiDecision(cohort, candidate)

    # Nothing beats the observed cost — keep multi, but surface the cheapest
    # feasible candidate cost (if any) as the rejected/blocked alternative.
    blocked_cost = min((option[0] for option in options), default=None)
    return MultiDecision(_keep_multi_reason(m, sizing), None, blocked_cost=blocked_cost)


def classify(m: DagMetrics, min_days: int = 3, min_runs: int = 3) -> str:
    if m.arm_days < min_days or m.arm_runs < min_runs:
        return "needs_more_arm_data"

    topo = m.topology

    if topo == "autoscale":
        return "autoscale_review"
    if (
        m.dominant_config_run_share < _DOMINANT_CONFIG_SHARE_MIN
        or m.dominant_config_cost_share < _DOMINANT_CONFIG_SHARE_MIN
    ):
        return "mixed_config_review"
    if not _required_metrics_present(m):
        return "needs_more_telemetry"
    if _spill_pressure(m):
        return "spill_pressure_review"
    if m.ec2_pricing_missing or m.dbu_negotiated_price_missing:
        return "cost_confidence_review"

    # Single-node branch: only refine downward (single -> multi is parked).
    if topo == "single":
        d = effective_demand(m)
        if (d.drv_mem_p95 or 0.0) >= _DRIVER_OOM_P95:
            return "protect_oom_risk"
        if _single_node_downsize_node(m):
            return "driver_downsize"
        return "healthy_single"

    # Multi-node branch: bidirectional, cost-truthful candidate selection.
    # A 1-worker cluster is strictly dominated by single-node, so it folds into
    # the single-node candidate comparison (build_current_refined returns None).
    if topo == "multi":
        return _decide_multi(m).cohort

    return "autoscale_review"


# ---------------------------------------------------------------------------
# Metric estimator
# ---------------------------------------------------------------------------


def _vcpus(node_type: str | None) -> int:
    if not node_type:
        return 0
    return INSTANCE_CATALOG.get(node_type, InstanceSpec(0, 0, "general")).vcpus


def estimate_cost(
    current_cost_per_run: float,
    driver: str,
    worker: str | None,
    current_workers: int,
    rec_driver: str,
    rec_worker: str | None,
    rec_workers: int,
) -> float | None:
    """Project cost per run via vCPU scaling (proxy for DBU consumption)."""
    drv_v = _vcpus(driver)
    wrk_v = _vcpus(worker) if current_workers > 0 else 0
    cur_total = drv_v + current_workers * wrk_v
    if cur_total == 0:
        return None

    rec_drv_v = _vcpus(rec_driver)
    rec_wrk_v = _vcpus(rec_worker) if rec_workers > 0 else 0
    rec_total = rec_drv_v + rec_workers * rec_wrk_v
    return round(current_cost_per_run * rec_total / cur_total, 6)


def estimate_drv_cpu_after_collapse(
    drv_cpu_p50: float | None,
    wrk_cpu_p50: float | None,
    driver: str,
    worker: str | None,
    worker_count: int,
) -> tuple[float | None, bool]:
    """Estimate driver CPU utilisation after collapsing workers onto it.

    Returns (estimate, is_uncertain).
    is_uncertain=True when estimate >= 75 % (flag for human review).
    Cap at 90 % to leave headroom for scheduler overhead.
    """
    base = drv_cpu_p50 or 0.0
    if not wrk_cpu_p50 or worker_count == 0 or not worker:
        return base, False
    driver_vcpus = _vcpus(driver)
    if driver_vcpus == 0:
        return None, True
    worker_vcpus = _vcpus(worker)
    absorbed = wrk_cpu_p50 * worker_count * worker_vcpus / driver_vcpus
    estimate = min(base + absorbed, 90.0)
    uncertain = estimate >= 75.0
    return round(estimate, 1), uncertain


# ---------------------------------------------------------------------------
# Preset recommender
# ---------------------------------------------------------------------------


def recommend_preset(
    cohort: str,
    m: DagMetrics,
) -> tuple[str | None, int | None]:
    """Return (recommended_preset_name, num_workers_override).

    num_workers_override is set only for downsize_workers (= 1); None otherwise.
    Returns (None, None) for cohorts with no actionable recommendation.
    """
    if cohort in (
        "needs_more_arm_data",
        "needs_more_telemetry",
        "mixed_config_review",
        "cost_confidence_review",
        "spill_pressure_review",
        "spiky_manual",
        "driver_oom_risk",
        "driver_memory_pressure",
        "driver_cpu_bound_keep",
        "driver_io_bound_keep",
        "io_bound_keep",
        "memory_bound_keep",
        "healthy_single",
        "healthy_multi",
        "autoscale_review",
    ):
        return None, None

    sizing_node = m.driver_node_type if m.topology == "single" else _worker_node_type(m)
    tier = _node_tier(sizing_node)
    family = _node_family(sizing_node)
    keep_multi_cohorts = {
        "keep_multi_sla",
        "keep_multi_memory",
        "keep_multi_compute",
        "keep_multi_balanced",
        "keep_multi_cost",
        "right_size_multi",
    }
    if not tier and cohort not in {"collapse_to_single", *keep_multi_cohorts}:
        return None, None

    if cohort == "collapse_to_single":
        name, _node_type = _single_node_preset_for_node(size_single_node(m).node_type)
        return (name, None) if name else (None, None)

    if cohort in keep_multi_cohorts:
        name = _multi_preset_for_worker(_worker_node_type(m))
        return (name, None) if name else (None, None)

    if cohort == "downsize_workers":
        worker_count = m.worker_count or 0
        d = effective_demand(m)
        if worker_count == 2 and (d.drv_mem_p95 or 100) < _DRIVER_MEM_PRESSURE_P95:
            # Collapse to single-node: driver + 1 worker is wasteful overhead.
            sn_family = "general" if family == "compute" else family
            sn_name = f"consolidation_{tier}_{sn_family}_single_node_cluster"
            return (sn_name, None) if sn_name in PRESET_CATALOG else (None, None)
        elif worker_count > 2:
            # Step down to 2 (the consolidation preset default; no override needed).
            name = f"consolidation_{tier}_{family}_cluster"
            return (name, None) if name in PRESET_CATALOG else (None, None)
        # worker_count == 2 but driver full: cannot safely collapse → no recommendation.
        return None, None

    if cohort == "right_size_to_memory_family":
        # general → memory, one tier down: same RAM, half vCPUs.
        # Mapping: s→xs, m→s, l→m, xl→l (xs not eligible — enters memory_bound_keep instead).
        idx = _TIER_ORDER.index(tier)
        if idx == 0:
            return None, None  # xs: no tier below in memory family with same RAM
        lower_tier = _TIER_ORDER[idx - 1]
        name = f"consolidation_{lower_tier}_memory_cluster"
        return (name, None) if name in PRESET_CATALOG else (None, None)

    if cohort == "protect_oom_risk":
        # Memory-targeted upsize: promote family at same tier (compute→general→memory),
        # then step up one size tier only when already on the memory family.
        if tier is None:
            return None, None
        if family in ("compute", "general"):
            family_idx = _OOM_FAMILY_LADDER.index(family)
            new_family = _OOM_FAMILY_LADDER[family_idx + 1]
            name = f"consolidation_{tier}_{new_family}_single_node_cluster"
            return (name, None) if name in PRESET_CATALOG else (None, None)
        tier_idx = _TIER_ORDER.index(tier)
        if tier_idx >= len(_TIER_ORDER) - 1:
            return None, None  # already xl — cannot upsize
        new_tier = _TIER_ORDER[tier_idx + 1]
        name = f"consolidation_{new_tier}_memory_single_node_cluster"
        return (name, None) if name in PRESET_CATALOG else (None, None)

    if cohort == "driver_downsize":
        if m.topology == "single":
            lower_tier = _node_tier(_driver_downsize_node(m) or "")
            driver_family = _node_family(_driver_downsize_node(m) or m.driver_node_type)
            if lower_tier is None:
                return None, None
            name = f"consolidation_{lower_tier}_{driver_family}_single_node_cluster"
            return (name, None) if name in PRESET_CATALOG else (None, None)
        name = f"consolidation_{tier}_{family}_cluster"
        return (name, None) if name in PRESET_CATALOG else (None, None)

    return None, None


# ---------------------------------------------------------------------------
# Recommendation output model
# ---------------------------------------------------------------------------


@dataclass
class ProjectedMetrics:
    """Post-change metric estimates (None = unchanged or not applicable)."""

    est_drv_cpu_p50: float | None = None
    est_drv_cpu_p95: float | None = None
    est_drv_cpu_p50_uncertain: bool = False  # True → ⚠ human review recommended
    est_drv_mem_p95: str | None = None  # "unchanged" | "⚠ may rise" | None
    est_wrk_cpu_p50: float | None = None
    est_wrk_cpu_p95: float | None = None
    est_wrk_mem_p95: str | None = None  # "unchanged" | "N/A" | None
    est_cost_per_run_usd: float | None = None
    est_cost_delta_pct: float | None = None
    blocked_cost_per_run_usd: float | None = None
    blocked_cost_delta_pct: float | None = None
    blocked_reason: str | None = None


@dataclass
class Recommendation:
    # Identity
    dag_id: str
    cohort: str
    confidence: str  # high | medium
    actions: str

    # Current (observed)
    current_preset: str | None
    current_driver_node_type: str
    current_worker_node_type: str | None
    current_worker_count: int | None
    arm_days: int
    arm_runs: int
    arm_total_cost_usd: float
    arm_avg_cost_per_run_usd: float
    arm_total_cost_estimate_usd: float | None
    arm_avg_total_cost_estimate_usd: float | None
    wall_p50_min: float
    wall_p95_min: float
    drv_cpu_p50: float | None
    drv_cpu_p95: float | None
    drv_mem_p95: float | None
    drv_wait_p95: float | None
    wrk_cpu_p50: float | None
    wrk_cpu_p95: float | None
    wrk_mem_p95: float | None
    wrk_wait_p95: float | None
    runs_per_day: float | None = None
    schedule_interval_minutes: float | None = None
    arm_total_ec2_cost_usd: float | None = None
    arm_avg_ec2_cost_usd: float | None = None
    arm_total_dbu_cost_usd: float | None = None
    arm_avg_dbu_cost_usd: float | None = None
    ec2_spot_hours: float | None = None
    ec2_on_demand_hours: float | None = None
    dominant_config_run_share: float = 1.0
    dominant_config_cost_share: float = 1.0
    driver_action: str | None = None
    worker_action: str | None = None
    blocking_reason: str | None = None

    # Recommended (projected)
    recommended_preset: str | None = None
    rec_driver_node_type: str | None = None
    rec_worker_node_type: str | None = None
    rec_worker_count: int | None = None
    num_workers_override: int | None = None  # set when different from preset default
    driver_override_node_type_id: str | None = None
    rec_runtime_engine: str | None = None  # "STANDARD" when normalizing Photon off
    projected: ProjectedMetrics = field(default_factory=ProjectedMetrics)


def _confidence(m: DagMetrics) -> str:
    if m.arm_days >= 7 and m.arm_runs >= 10:
        return "high"
    return "medium"


def _cost_delta_pct(
    projected_cost: float | None, current_cost: float | None
) -> float | None:
    if projected_cost is None or not current_cost:
        return None
    return round((projected_cost - current_cost) / current_cost * 100, 1)


def _has_accepted_resize(actions: list[str] | str) -> bool:
    if isinstance(actions, str):
        action_set = set(actions.split("|"))
    else:
        action_set = set(actions)
    return bool(
        {
            "collapse_to_single",
            "reduce_driver",
            "reduce_worker_type",
            "reduce_worker_count",
        }
        & action_set
    )


def build_recommendation(
    m: DagMetrics, min_days: int = 3, min_runs: int = 3
) -> Recommendation:
    cohort = classify(m, min_days, min_runs)
    current_preset = infer_current_preset(
        m.driver_node_type, m.worker_node_type, m.worker_count
    )
    rec_preset_name, num_workers_override = recommend_preset(cohort, m)

    # Resolve recommended node types from the preset catalog
    rec_spec = PRESET_CATALOG.get(rec_preset_name) if rec_preset_name else None
    rec_driver = rec_spec.driver_node_type if rec_spec else None
    rec_worker = rec_spec.worker_node_type if rec_spec else None
    rec_workers = (
        num_workers_override
        if num_workers_override is not None
        else (rec_spec.num_workers if rec_spec else None)
    )
    actions: list[str] = []
    blocked_cost_per_run: float | None = None
    driver_override_node_type_id = None
    sizing = size_single_node(m) if cohort == "collapse_to_single" else None

    decision = _decide_multi(m) if m.topology == "multi" else None
    candidate = decision.candidate if decision else None

    if cohort == "collapse_to_single" and candidate is not None:
        actions = ["collapse_to_single"]
        rec_driver = candidate.driver_node_type
        rec_worker = None
        rec_workers = 0
    elif cohort == "right_size_multi" and candidate is not None:
        current_worker = _worker_node_type(m)
        current_workers = m.worker_count or 0
        worker_resize = _worker_resize(m)
        actions = ["keep_multi_node"]
        actions.append(
            "reduce_driver"
            if candidate.driver_node_type != m.driver_node_type
            else "keep_driver"
        )
        actions.append(
            "reduce_worker_type"
            if candidate.worker_node_type != current_worker
            else "keep_worker_type"
        )
        if candidate.worker_count != current_workers:
            actions.append("reduce_worker_count")
        elif worker_resize is not None and worker_resize.count_blocked_sla:
            actions.append("worker_count_blocked_sla")
        else:
            actions.append("keep_worker_count")
        rec_driver = candidate.driver_node_type
        rec_worker = candidate.worker_node_type
        rec_workers = candidate.worker_count
        rec_preset_name = _multi_preset_for_worker(rec_worker) or rec_preset_name
        rec_spec = PRESET_CATALOG.get(rec_preset_name) if rec_preset_name else None
        if rec_spec and rec_workers is not None and rec_workers != rec_spec.num_workers:
            num_workers_override = rec_workers
        else:
            num_workers_override = None
    elif cohort in _KEEP_MULTI_COHORTS:
        # No candidate beat the observed cost-or-SLA — keep the observed shape and
        # surface the rejected single-node collapse cost for transparency.
        actions = ["keep_multi_node"]
        rec_driver = m.driver_node_type
        rec_worker = _worker_node_type(m)
        rec_workers = m.worker_count
        if decision is not None and decision.blocked_cost is not None:
            blocked_cost_per_run = decision.blocked_cost
        rejected = build_best_single_candidate(m)
        if rejected is not None and rejected.driver_node_type:
            rejected_cost = estimate_projected_total_cost(
                m, rejected.driver_node_type, 0
            )
            if rejected_cost is not None:
                blocked_cost_per_run = (
                    rejected_cost
                    if blocked_cost_per_run is None
                    else max(blocked_cost_per_run, rejected_cost)
                )
    if cohort == "driver_downsize" and rec_preset_name:
        actions = ["reduce_driver"]
        rec_driver = _single_node_downsize_node(m) or _driver_downsize_node(m)

    # Cost-neutral normalizations the cost engine already assumes: drop Photon
    # (DBU ~3x) and local NVMe (EC2 ~+20%). They make an otherwise-healthy DAG
    # actionable and never pin workers to on-demand.
    rec_runtime_engine: str | None = None
    if m.is_any_photon:
        rec_runtime_engine = "STANDARD"
        actions.append("disable_photon")
    if m.is_any_local_nvme:
        rec_driver = _strip_nvme(rec_driver)
        rec_worker = _strip_nvme(rec_worker)
        actions.append("drop_nvme")

    # For healthy cohorts where only normalizations apply (disable_photon /
    # drop_nvme), fill the current shape so projected metrics and validation
    # YAML can be generated.
    if rec_preset_name is None and any(
        a in actions for a in ("disable_photon", "drop_nvme")
    ):
        rec_preset_name = current_preset
        if rec_driver is None:
            rec_driver = _strip_nvme(m.driver_node_type)
        if rec_worker is None and m.topology == "multi":
            rec_worker = _strip_nvme(_worker_node_type(m))
        if rec_workers is None:
            rec_workers = m.worker_count if m.topology == "multi" else 0
        rec_spec = PRESET_CATALOG.get(rec_preset_name) if rec_preset_name else None

    if rec_spec and rec_driver and rec_driver != rec_spec.driver_node_type:
        driver_override_node_type_id = rec_driver
    if not actions:
        actions = ["no_change"]

    # Build projected metrics (sizing bases use effective demand when Photon ran)
    projected = ProjectedMetrics()
    demand = effective_demand(m)
    if rec_preset_name and rec_driver is not None and rec_workers is not None:
        cost_basis = (
            m.arm_avg_total_cost_estimate_usd
            if m.arm_avg_total_cost_estimate_usd is not None
            else m.arm_avg_cost_per_run_usd
        )
        projected.est_cost_per_run_usd = estimate_projected_total_cost(
            m,
            rec_driver,
            rec_workers,
            rec_worker=rec_worker,
        )
        if projected.est_cost_per_run_usd is None:
            projected.est_cost_per_run_usd = estimate_cost(
                cost_basis,
                m.driver_node_type,
                m.worker_node_type,
                m.worker_count or 0,
                rec_driver,
                rec_worker,
                rec_workers,
            )
        if projected.est_cost_per_run_usd is not None and cost_basis:
            projected.est_cost_delta_pct = _cost_delta_pct(
                projected.est_cost_per_run_usd,
                cost_basis,
            )
        if cohort in _KEEP_MULTI_COHORTS and not _has_accepted_resize(actions):
            projected.est_cost_per_run_usd = cost_basis
            projected.est_cost_delta_pct = 0.0
        if blocked_cost_per_run is not None and cost_basis:
            projected.blocked_cost_per_run_usd = blocked_cost_per_run
            projected.blocked_cost_delta_pct = _cost_delta_pct(
                blocked_cost_per_run,
                cost_basis,
            )

        if cohort in ("collapse_to_single", "downsize_workers") and rec_workers == 0:
            est_cpu, uncertain = estimate_drv_cpu_after_collapse(
                demand.drv_cpu_p50,
                demand.wrk_cpu_p50,
                m.driver_node_type,
                m.worker_node_type,
                m.worker_count or 0,
            )
            est_cpu_p95, _uncertain_p95 = estimate_drv_cpu_after_collapse(
                demand.drv_cpu_p95,
                demand.wrk_cpu_p95,
                m.driver_node_type,
                m.worker_node_type,
                m.worker_count or 0,
            )
            est_mem_p95 = _projected_driver_mem_after_collapse(m, rec_driver)
            if cohort == "collapse_to_single" and sizing:
                est_cpu_p95 = sizing.projected_cpu_pct
                est_mem_p95 = sizing.projected_mem_pct
            projected.est_drv_cpu_p50 = est_cpu
            projected.est_drv_cpu_p95 = est_cpu_p95
            projected.est_drv_cpu_p50_uncertain = uncertain
            projected.est_drv_mem_p95 = (
                f"projected {est_mem_p95:.1f}%"
                if est_mem_p95 is not None
                else "⚠ may rise"
            )
            projected.est_wrk_cpu_p50 = None  # no workers
            projected.est_wrk_cpu_p95 = None
            projected.est_wrk_mem_p95 = "N/A"
            if cohort != "collapse_to_single" and projected.est_drv_cpu_p50_uncertain:
                projected.blocked_reason = "projected_driver_cpu_uncertain"
                rec_preset_name = None
                rec_driver = None
                rec_worker = None
                rec_workers = None
            elif (
                cohort != "collapse_to_single"
                and est_mem_p95 is not None
                and est_mem_p95 >= _COLLAPSE_DRIVER_MEM_PROJECTED_MAX
            ):
                projected.blocked_reason = "projected_driver_memory_too_high"
                rec_preset_name = None
                rec_driver = None
                rec_worker = None
                rec_workers = None

        elif cohort in ("downsize_workers", "right_size_to_memory_family"):
            cur_w = m.worker_count or 1
            new_w = rec_spec.num_workers if rec_spec else cur_w

            if cohort == "downsize_workers" and cur_w > 2:
                # Stepped to 2 workers: CPU scales by old/new ratio
                ratio = cur_w / max(new_w, 1)
                projected.est_wrk_cpu_p50 = (
                    min(round((demand.wrk_cpu_p50 or 0) * ratio, 1), 95.0)
                    if demand.wrk_cpu_p50 is not None
                    else None
                )
                projected.est_wrk_cpu_p95 = (
                    min(round((demand.wrk_cpu_p95 or 0) * ratio, 1), 95.0)
                    if demand.wrk_cpu_p95 is not None
                    else None
                )
                projected.est_wrk_mem_p95 = "unchanged"
                projected.est_drv_cpu_p50 = demand.drv_cpu_p50
                projected.est_drv_mem_p95 = "unchanged"
            elif cohort == "right_size_to_memory_family":
                cur_worker_vcpus = _vcpus(m.worker_node_type)
                rec_worker_vcpus = _vcpus(rec_worker)
                ratio = (
                    cur_w / max(new_w, 1) * cur_worker_vcpus / max(rec_worker_vcpus, 1)
                )
                projected.est_wrk_cpu_p50 = (
                    min(round((demand.wrk_cpu_p50 or 0) * ratio, 1), 95.0)
                    if demand.wrk_cpu_p50 is not None
                    else None
                )
                projected.est_wrk_cpu_p95 = (
                    min(round((demand.wrk_cpu_p95 or 0) * ratio, 1), 95.0)
                    if demand.wrk_cpu_p95 is not None
                    else None
                )
                projected.est_wrk_mem_p95 = "unchanged"  # same GiB per node
                projected.est_drv_cpu_p50 = demand.drv_cpu_p50
                projected.est_drv_mem_p95 = "unchanged"
                if (
                    projected.est_wrk_cpu_p95 is not None
                    and projected.est_wrk_cpu_p95 >= 85
                ):
                    projected.blocked_reason = "projected_worker_cpu_too_high"
                    rec_preset_name = None
                    rec_driver = None
                    rec_worker = None
                    rec_workers = None

        elif cohort == "protect_oom_risk":
            projected.est_drv_cpu_p50 = _project_utilization_pct(
                demand.drv_cpu_p50,
                m.driver_node_type,
                rec_driver,
                metric="cpu",
            )
            projected.est_drv_cpu_p95 = _project_utilization_pct(
                demand.drv_cpu_p95,
                m.driver_node_type,
                rec_driver,
                metric="cpu",
            )
            projected_drv_mem = _project_utilization_pct(
                demand.drv_mem_p95,
                m.driver_node_type,
                rec_driver,
                metric="memory",
            )
            projected.est_drv_mem_p95 = (
                f"projected {projected_drv_mem:.1f}%"
                if projected_drv_mem is not None
                else "↓ headroom added"
            )
        elif cohort == "driver_downsize":
            projected.est_drv_cpu_p50 = demand.drv_cpu_p50
            projected.est_drv_cpu_p95 = demand.drv_cpu_p95
            projected.est_drv_mem_p95 = "unchanged"
            projected.est_wrk_cpu_p50 = demand.wrk_cpu_p50
            projected.est_wrk_cpu_p95 = demand.wrk_cpu_p95
            projected.est_wrk_mem_p95 = "unchanged"
        elif cohort in _KEEP_MULTI_COHORTS or cohort == "right_size_multi":
            projected.est_drv_cpu_p50 = _project_utilization_pct(
                demand.drv_cpu_p50,
                m.driver_node_type,
                rec_driver,
                metric="cpu",
            )
            projected.est_drv_cpu_p95 = _project_utilization_pct(
                demand.drv_cpu_p95,
                m.driver_node_type,
                rec_driver,
                metric="cpu",
            )
            projected_drv_mem = _project_utilization_pct(
                demand.drv_mem_p95,
                m.driver_node_type,
                rec_driver,
                metric="memory",
            )
            projected.est_drv_mem_p95 = (
                f"projected {projected_drv_mem:.1f}%"
                if projected_drv_mem is not None
                else "unchanged"
            )
            worker_count_ratio = (m.worker_count or 1) / max(rec_workers or 1, 1)
            projected.est_wrk_cpu_p50 = _project_utilization_pct(
                demand.wrk_cpu_p50,
                _worker_node_type(m),
                rec_worker,
                metric="cpu",
                count_ratio=worker_count_ratio,
            )
            projected.est_wrk_cpu_p95 = _project_utilization_pct(
                demand.wrk_cpu_p95,
                _worker_node_type(m),
                rec_worker,
                metric="cpu",
                count_ratio=worker_count_ratio,
            )
            projected_wrk_mem = _project_utilization_pct(
                demand.wrk_mem_p95,
                _worker_node_type(m),
                rec_worker,
                metric="memory",
                count_ratio=worker_count_ratio,
            )
            projected.est_wrk_mem_p95 = (
                f"projected {projected_wrk_mem:.1f}%"
                if projected_wrk_mem is not None
                else "unchanged"
            )

    return Recommendation(
        dag_id=m.dag_id,
        cohort=cohort,
        confidence=_confidence(m),
        actions="|".join(actions),
        current_preset=current_preset,
        current_driver_node_type=m.driver_node_type,
        current_worker_node_type=m.worker_node_type,
        current_worker_count=m.worker_count,
        arm_days=m.arm_days,
        arm_runs=m.arm_runs,
        arm_total_cost_usd=m.arm_total_cost_usd,
        arm_avg_cost_per_run_usd=m.arm_avg_cost_per_run_usd,
        arm_total_cost_estimate_usd=m.arm_total_cost_estimate_usd,
        arm_avg_total_cost_estimate_usd=m.arm_avg_total_cost_estimate_usd,
        runs_per_day=m.runs_per_day,
        schedule_interval_minutes=m.schedule_interval_minutes,
        arm_total_ec2_cost_usd=m.arm_total_ec2_cost_usd,
        arm_avg_ec2_cost_usd=m.arm_avg_ec2_cost_usd,
        arm_total_dbu_cost_usd=m.arm_total_dbu_cost_usd,
        arm_avg_dbu_cost_usd=m.arm_avg_dbu_cost_usd,
        ec2_spot_hours=m.ec2_spot_hours,
        ec2_on_demand_hours=m.ec2_on_demand_hours,
        wall_p50_min=m.wall_p50_min,
        wall_p95_min=m.wall_p95_min,
        drv_cpu_p50=m.drv_cpu_p50,
        drv_cpu_p95=m.drv_cpu_p95,
        drv_mem_p95=m.drv_mem_p95,
        drv_wait_p95=m.drv_wait_p95,
        wrk_cpu_p50=m.wrk_cpu_p50,
        wrk_cpu_p95=m.wrk_cpu_p95,
        wrk_mem_p95=m.wrk_mem_p95,
        wrk_wait_p95=m.wrk_wait_p95,
        dominant_config_run_share=m.dominant_config_run_share,
        dominant_config_cost_share=m.dominant_config_cost_share,
        driver_action=cohort if cohort.startswith("driver_") else None,
        worker_action=cohort if not cohort.startswith("driver_") else None,
        blocking_reason=projected.blocked_reason,
        recommended_preset=rec_preset_name,
        rec_driver_node_type=rec_driver,
        rec_worker_node_type=rec_worker,
        rec_worker_count=rec_workers,
        num_workers_override=num_workers_override,
        driver_override_node_type_id=driver_override_node_type_id
        if rec_preset_name
        else None,
        rec_runtime_engine=rec_runtime_engine,
        projected=projected,
    )


# ---------------------------------------------------------------------------
# Trino SQL
# ---------------------------------------------------------------------------

_TRINO_SQL_TEMPLATE = """\
-- ARM cohort metrics per DAG for cluster right-sizing recommendations
-- Generated by recommend_cluster_specs.py; do not hand-edit.
WITH runs AS (
    SELECT
        airflow_dag_id,
        dt_dag_run_started,
        driver_node_type,
        worker_node_type,
        worker_count,
        primary_min_autoscale_workers,
        primary_max_autoscale_workers,
        total_dbu_cost_usd                               AS dbu_cost_usd,
        total_dbu_consumed,
        total_ec2_cost_calculated_usd                    AS ec2_cost_usd,
        ec2_spot_hours,
        ec2_on_demand_hours,
        total_cost_usd,
        total_wall_clock_seconds,
        weighted_avg_p50_driver_cpu_busy_percent         AS drv_cpu_p50,
        weighted_avg_p95_driver_cpu_busy_percent         AS drv_cpu_p95,
        weighted_avg_p50_driver_mem_used_percent         AS drv_mem_p50,
        weighted_avg_p95_driver_mem_used_percent         AS drv_mem_p95,
        weighted_avg_p95_driver_cpu_wait_percent         AS drv_wait_p95,
        weighted_avg_p50_worker_cpu_busy_percent         AS wrk_cpu_p50,
        weighted_avg_p95_worker_cpu_busy_percent         AS wrk_cpu_p95,
        weighted_avg_p50_worker_mem_used_percent         AS wrk_mem_p50,
        weighted_avg_p95_worker_mem_used_percent         AS wrk_mem_p95,
        weighted_avg_p95_worker_cpu_wait_percent         AS wrk_wait_p95,
        weighted_avg_local_disk_utilization_pct_p95      AS local_disk_p95,
        total_memory_bytes_spilled,
        total_disk_bytes_spilled,
        max_peak_execution_memory_bytes,
        max_jvm_heap_bytes,
        total_gc_time_ms,
        total_executor_run_time_ms,
        max_task_skew_ratio,
        is_ec2_estimated,
        ec2_pricing_missing,
        dbu_negotiated_price_missing,
        is_any_photon,
        is_any_local_nvme,
        CASE
            WHEN REGEXP_LIKE(
                LOWER(COALESCE(worker_node_type, driver_node_type)),
                '^([a-z][a-z0-9]*[0-9]g(d|n|b)?|a1)[.]'
            ) THEN 'arm'
            ELSE 'x86'
        END AS arch
    FROM dw_databricks_health.fact_databricks_dag_run
    WHERE dt_dag_run_started >= CURRENT_DATE - INTERVAL '{days}' DAY
      AND airflow_dag_id LIKE 'bietlejuice.%'
      AND airflow_dag_id IS NOT NULL
      AND NOT REGEXP_LIKE(airflow_dag_id, '__validation$')
      AND is_job_on_interactive = FALSE
      AND is_any_task_failed = FALSE
      AND is_any_databricks_run_failed = FALSE
      AND COALESCE(total_cost_usd, 0) > 0
),
arm_runs AS (
    SELECT *
    FROM runs
    WHERE arch = 'arm'
),
config_runs AS (
    SELECT
        airflow_dag_id,
        driver_node_type,
        worker_node_type,
        worker_count,
        primary_min_autoscale_workers,
        primary_max_autoscale_workers,
        COUNT(*)                                                                  AS config_run_count,
        COUNT(DISTINCT CAST(dt_dag_run_started AS DATE))                          AS config_day_count,
        SUM(total_cost_usd)                                                       AS config_total_cost_usd
    FROM arm_runs
    GROUP BY
        airflow_dag_id,
        driver_node_type,
        worker_node_type,
        worker_count,
        primary_min_autoscale_workers,
        primary_max_autoscale_workers
),
dag_totals AS (
    SELECT
        airflow_dag_id,
        COUNT(*)                                                                  AS total_run_count,
        SUM(total_cost_usd)                                                       AS total_cost_usd
    FROM arm_runs
    GROUP BY airflow_dag_id
),
dominant_config AS (
    SELECT
        config_runs.*,
        ROUND(config_runs.config_run_count / CAST(dag_totals.total_run_count AS DOUBLE), 4)
                                                                                  AS dominant_config_run_share,
        ROUND(config_runs.config_total_cost_usd / NULLIF(dag_totals.total_cost_usd, 0), 4)
                                                                                  AS dominant_config_cost_share,
        ROW_NUMBER() OVER (
            PARTITION BY config_runs.airflow_dag_id
            ORDER BY config_runs.config_total_cost_usd DESC, config_runs.config_run_count DESC
        )                                                                         AS rn
    FROM config_runs
    JOIN dag_totals
        ON config_runs.airflow_dag_id = dag_totals.airflow_dag_id
),
dominant_runs AS (
    SELECT
        arm_runs.*,
        dominant_config.dominant_config_run_share,
        dominant_config.dominant_config_cost_share
    FROM arm_runs
    JOIN dominant_config
        ON arm_runs.airflow_dag_id = dominant_config.airflow_dag_id
        AND arm_runs.driver_node_type = dominant_config.driver_node_type
        AND COALESCE(arm_runs.worker_node_type, '__single__')
            = COALESCE(dominant_config.worker_node_type, '__single__')
        AND COALESCE(CAST(arm_runs.worker_count AS VARCHAR), '__autoscale__')
            = COALESCE(CAST(dominant_config.worker_count AS VARCHAR), '__autoscale__')
        AND COALESCE(CAST(arm_runs.primary_min_autoscale_workers AS VARCHAR), '__fixed__')
            = COALESCE(CAST(dominant_config.primary_min_autoscale_workers AS VARCHAR), '__fixed__')
        AND COALESCE(CAST(arm_runs.primary_max_autoscale_workers AS VARCHAR), '__fixed__')
            = COALESCE(CAST(dominant_config.primary_max_autoscale_workers AS VARCHAR), '__fixed__')
        AND dominant_config.rn = 1
),
per_dag AS (
    SELECT
        airflow_dag_id,
        COUNT(DISTINCT CAST(dt_dag_run_started AS DATE))                          AS arm_days,
        COUNT(*)                                                                   AS arm_runs,
        ROUND(
            COUNT(*) / CAST(NULLIF(COUNT(DISTINCT CAST(dt_dag_run_started AS DATE)), 0) AS DOUBLE),
            3
        )                                                                          AS runs_per_day,
        ROUND(
            1440.0 / NULLIF(
                COUNT(*) / CAST(NULLIF(COUNT(DISTINCT CAST(dt_dag_run_started AS DATE)), 0) AS DOUBLE),
                0
            ),
            1
        )                                                                          AS schedule_interval_minutes,
        ARBITRARY(driver_node_type)                                                 AS driver_node_type,
        ARBITRARY(worker_node_type)                                                 AS worker_node_type,
        ARBITRARY(worker_count)                                                     AS worker_count,
        ARBITRARY(primary_min_autoscale_workers)                                    AS primary_min_autoscale_workers,
        ARBITRARY(primary_max_autoscale_workers)                                    AS primary_max_autoscale_workers,
        ROUND(SUM(total_cost_usd), 4)                                              AS arm_total_cost_usd,
        ROUND(AVG(total_cost_usd), 6)                                              AS arm_avg_cost_per_run_usd,
        ROUND(SUM(total_cost_usd), 4)                                              AS arm_total_cost_estimate_usd,
        ROUND(AVG(total_cost_usd), 6)                                              AS arm_avg_total_cost_estimate_usd,
        ROUND(SUM(ec2_cost_usd), 4)                                                AS arm_total_ec2_cost_usd,
        ROUND(AVG(ec2_cost_usd), 6)                                                AS arm_avg_ec2_cost_usd,
        ROUND(SUM(dbu_cost_usd), 4)                                                AS arm_total_dbu_cost_usd,
        ROUND(AVG(dbu_cost_usd), 6)                                                AS arm_avg_dbu_cost_usd,
        ROUND(AVG(total_dbu_consumed), 6)                                          AS arm_avg_dbu_consumed,
        ROUND(SUM(ec2_spot_hours), 4)                                              AS ec2_spot_hours,
        ROUND(SUM(ec2_on_demand_hours), 4)                                         AS ec2_on_demand_hours,
        ARBITRARY(dominant_config_run_share)                                       AS dominant_config_run_share,
        ARBITRARY(dominant_config_cost_share)                                      AS dominant_config_cost_share,
        ROUND(APPROX_PERCENTILE(total_wall_clock_seconds, 0.5)  / 60.0, 1)        AS wall_p50_min,
        ROUND(APPROX_PERCENTILE(total_wall_clock_seconds, 0.95) / 60.0, 1)        AS wall_p95_min,
        ROUND(APPROX_PERCENTILE(drv_cpu_p50, 0.5), 1)                             AS drv_cpu_p50,
        ROUND(APPROX_PERCENTILE(drv_cpu_p95, 0.95), 1)                            AS drv_cpu_p95,
        ROUND(APPROX_PERCENTILE(drv_mem_p50, 0.5), 1)                             AS drv_mem_p50,
        ROUND(APPROX_PERCENTILE(drv_mem_p95, 0.95), 1)                            AS drv_mem_p95,
        ROUND(APPROX_PERCENTILE(drv_wait_p95, 0.95), 1)                           AS drv_wait_p95,
        ROUND(APPROX_PERCENTILE(wrk_cpu_p50, 0.5), 1)                             AS wrk_cpu_p50,
        ROUND(APPROX_PERCENTILE(wrk_cpu_p95, 0.95), 1)                            AS wrk_cpu_p95,
        ROUND(APPROX_PERCENTILE(wrk_mem_p50, 0.5), 1)                             AS wrk_mem_p50,
        ROUND(APPROX_PERCENTILE(wrk_mem_p95, 0.95), 1)                            AS wrk_mem_p95,
        ROUND(APPROX_PERCENTILE(wrk_wait_p95, 0.95), 1)                           AS wrk_wait_p95,
        ROUND(APPROX_PERCENTILE(local_disk_p95, 0.95), 1)                         AS local_disk_p95,
        SUM(total_memory_bytes_spilled)                                           AS total_memory_bytes_spilled,
        SUM(total_disk_bytes_spilled)                                             AS total_disk_bytes_spilled,
        MAX(max_peak_execution_memory_bytes)                                      AS max_peak_execution_memory_bytes,
        MAX(max_jvm_heap_bytes)                                                   AS max_jvm_heap_bytes,
        SUM(total_gc_time_ms)                                                     AS total_gc_time_ms,
        SUM(total_executor_run_time_ms)                                           AS total_executor_run_time_ms,
        MAX(max_task_skew_ratio)                                                  AS max_task_skew_ratio,
        BOOL_OR(is_ec2_estimated)                                                 AS is_ec2_estimated,
        BOOL_OR(ec2_pricing_missing)                                              AS ec2_pricing_missing,
        BOOL_OR(dbu_negotiated_price_missing)                                     AS dbu_negotiated_price_missing,
        BOOL_OR(is_any_photon)                                                    AS is_any_photon,
        BOOL_OR(is_any_local_nvme)                                                AS is_any_local_nvme
    FROM dominant_runs
    GROUP BY airflow_dag_id
    HAVING COUNT(DISTINCT CAST(dt_dag_run_started AS DATE)) >= {min_days}
       AND COUNT(*) >= {min_runs}
)
SELECT * FROM per_dag
ORDER BY arm_total_cost_usd DESC
"""


def build_sql(days: int, min_days: int, min_runs: int) -> str:
    return _TRINO_SQL_TEMPLATE.format(days=days, min_days=min_days, min_runs=min_runs)


# ---------------------------------------------------------------------------
# AMD correction — collapse-only classification from x86 history
# ---------------------------------------------------------------------------


def classify_amd_for_collapse(m: DagMetrics) -> bool:
    """Return True if AMD metrics + wall-clock correction suggest collapse_to_single.

    Applies AMD_WALL_CORRECTION to wall_p95_min before testing the collapse gate.
    All other conditions use AMD metric values directly (conservative: ARM CPU is
    typically equal or lower, memory is flat).  Only the collapse cohort is inferred
    from AMD history; all other cohorts require ARM data.
    """
    corrected_wall = m.wall_p95_min * AMD_WALL_CORRECTION
    return (
        m.topology == "multi"
        and corrected_wall <= 30
        and (m.wrk_cpu_p50 or 100) < 20
        and (m.wrk_cpu_p95 or 100) < 55
        and (m.wrk_mem_p95 or 100) < 60
        and (m.drv_mem_p95 or 100) < 75
        and (m.wrk_wait_p95 or 100) < 10  # ensure not io-bound on AMD either
    )


_AMD_SQL_TEMPLATE = """\
-- AMD (x86) metrics for DAGs that have not yet met the ARM eligibility threshold.
-- Used with AMD_WALL_CORRECTION to identify additional collapse_to_single candidates.
WITH runs AS (
    SELECT
        airflow_dag_id,
        dt_dag_run_started,
        driver_node_type,
        worker_node_type,
        worker_count,
        primary_min_autoscale_workers,
        primary_max_autoscale_workers,
        total_cost_usd,
        total_wall_clock_seconds,
        weighted_avg_p50_driver_cpu_busy_percent         AS drv_cpu_p50,
        weighted_avg_p95_driver_cpu_busy_percent         AS drv_cpu_p95,
        weighted_avg_p95_driver_mem_used_percent         AS drv_mem_p95,
        weighted_avg_p95_driver_cpu_wait_percent         AS drv_wait_p95,
        weighted_avg_p50_worker_cpu_busy_percent         AS wrk_cpu_p50,
        weighted_avg_p95_worker_cpu_busy_percent         AS wrk_cpu_p95,
        weighted_avg_p95_worker_mem_used_percent         AS wrk_mem_p95,
        weighted_avg_p95_worker_cpu_wait_percent         AS wrk_wait_p95,
        is_any_photon,
        is_any_local_nvme,
        CASE
            WHEN REGEXP_LIKE(
                LOWER(COALESCE(worker_node_type, driver_node_type)),
                '^([a-z][a-z0-9]*[0-9]g(d|n|b)?|a1)[.]'
            ) THEN 'arm'
            ELSE 'x86'
        END AS arch
    FROM dw_databricks_health.fact_databricks_dag_run
    WHERE dt_dag_run_started >= CURRENT_DATE - INTERVAL '{days}' DAY
      AND airflow_dag_id LIKE 'bietlejuice.%'
      AND airflow_dag_id IS NOT NULL
      AND NOT REGEXP_LIKE(airflow_dag_id, '__validation$')
      AND is_job_on_interactive = FALSE
      AND is_any_task_failed = FALSE
      AND is_any_databricks_run_failed = FALSE
      AND COALESCE(total_cost_usd, 0) > 0
),
arm_eligible AS (
    -- DAGs that already have enough ARM data — exclude from AMD correction pool.
    SELECT airflow_dag_id
    FROM runs WHERE arch = 'arm'
    GROUP BY airflow_dag_id
    HAVING COUNT(DISTINCT CAST(dt_dag_run_started AS DATE)) >= {min_days}
       AND COUNT(*) >= {min_runs}
),
amd_pool AS (
    SELECT r.*
    FROM runs r
    WHERE r.arch = 'x86'
      AND r.airflow_dag_id NOT IN (SELECT airflow_dag_id FROM arm_eligible)
),
config_runs AS (
    SELECT
        airflow_dag_id,
        driver_node_type,
        worker_node_type,
        worker_count,
        primary_min_autoscale_workers,
        primary_max_autoscale_workers,
        COUNT(*)                                                                  AS config_run_count,
        SUM(total_cost_usd)                                                       AS config_total_cost_usd
    FROM amd_pool
    GROUP BY
        airflow_dag_id,
        driver_node_type,
        worker_node_type,
        worker_count,
        primary_min_autoscale_workers,
        primary_max_autoscale_workers
),
dag_totals AS (
    SELECT
        airflow_dag_id,
        COUNT(*)                                                                  AS total_run_count,
        SUM(total_cost_usd)                                                       AS total_cost_usd
    FROM amd_pool
    GROUP BY airflow_dag_id
),
dominant_config AS (
    SELECT
        config_runs.*,
        ROUND(config_runs.config_run_count / CAST(dag_totals.total_run_count AS DOUBLE), 4)
                                                                                  AS dominant_config_run_share,
        ROUND(config_runs.config_total_cost_usd / NULLIF(dag_totals.total_cost_usd, 0), 4)
                                                                                  AS dominant_config_cost_share,
        ROW_NUMBER() OVER (
            PARTITION BY config_runs.airflow_dag_id
            ORDER BY config_runs.config_total_cost_usd DESC, config_runs.config_run_count DESC
        )                                                                         AS rn
    FROM config_runs
    JOIN dag_totals
        ON config_runs.airflow_dag_id = dag_totals.airflow_dag_id
),
dominant_runs AS (
    SELECT
        amd_pool.*,
        dominant_config.dominant_config_run_share,
        dominant_config.dominant_config_cost_share
    FROM amd_pool
    JOIN dominant_config
        ON amd_pool.airflow_dag_id = dominant_config.airflow_dag_id
        AND amd_pool.driver_node_type = dominant_config.driver_node_type
        AND COALESCE(amd_pool.worker_node_type, '__single__')
            = COALESCE(dominant_config.worker_node_type, '__single__')
        AND COALESCE(CAST(amd_pool.worker_count AS VARCHAR), '__autoscale__')
            = COALESCE(CAST(dominant_config.worker_count AS VARCHAR), '__autoscale__')
        AND COALESCE(CAST(amd_pool.primary_min_autoscale_workers AS VARCHAR), '__fixed__')
            = COALESCE(CAST(dominant_config.primary_min_autoscale_workers AS VARCHAR), '__fixed__')
        AND COALESCE(CAST(amd_pool.primary_max_autoscale_workers AS VARCHAR), '__fixed__')
            = COALESCE(CAST(dominant_config.primary_max_autoscale_workers AS VARCHAR), '__fixed__')
        AND dominant_config.rn = 1
),
per_dag AS (
    SELECT
        airflow_dag_id,
        COUNT(*)                                                                   AS arm_runs,
        COUNT(DISTINCT CAST(dt_dag_run_started AS DATE))                          AS arm_days,
        ARBITRARY(driver_node_type)                                                 AS driver_node_type,
        ARBITRARY(worker_node_type)                                                 AS worker_node_type,
        ARBITRARY(worker_count)                                                     AS worker_count,
        ROUND(SUM(total_cost_usd), 4)                                              AS arm_total_cost_usd,
        ROUND(AVG(total_cost_usd), 6)                                              AS arm_avg_cost_per_run_usd,
        ARBITRARY(dominant_config_run_share)                                       AS dominant_config_run_share,
        ARBITRARY(dominant_config_cost_share)                                      AS dominant_config_cost_share,
        ROUND(APPROX_PERCENTILE(total_wall_clock_seconds, 0.5)  / 60.0, 1)        AS wall_p50_min,
        ROUND(APPROX_PERCENTILE(total_wall_clock_seconds, 0.95) / 60.0, 1)        AS wall_p95_min,
        ROUND(APPROX_PERCENTILE(drv_cpu_p50, 0.5), 1)                             AS drv_cpu_p50,
        ROUND(APPROX_PERCENTILE(drv_cpu_p95, 0.95), 1)                            AS drv_cpu_p95,
        ROUND(APPROX_PERCENTILE(drv_mem_p95, 0.95), 1)                            AS drv_mem_p95,
        ROUND(APPROX_PERCENTILE(drv_wait_p95, 0.95), 1)                           AS drv_wait_p95,
        ROUND(APPROX_PERCENTILE(wrk_cpu_p50, 0.5), 1)                             AS wrk_cpu_p50,
        ROUND(APPROX_PERCENTILE(wrk_cpu_p95, 0.95), 1)                            AS wrk_cpu_p95,
        ROUND(APPROX_PERCENTILE(wrk_mem_p95, 0.95), 1)                            AS wrk_mem_p95,
        ROUND(APPROX_PERCENTILE(wrk_wait_p95, 0.95), 1)                           AS wrk_wait_p95,
        BOOL_OR(is_any_photon)                                                    AS is_any_photon,
        BOOL_OR(is_any_local_nvme)                                                AS is_any_local_nvme
    FROM dominant_runs
    GROUP BY airflow_dag_id
    HAVING COUNT(*) >= {amd_min_runs}
)
SELECT * FROM per_dag
ORDER BY arm_total_cost_usd DESC
"""


def build_amd_sql(days: int, min_days: int, min_runs: int, amd_min_runs: int) -> str:
    return _AMD_SQL_TEMPLATE.format(
        days=days, min_days=min_days, min_runs=min_runs, amd_min_runs=amd_min_runs
    )


# ---------------------------------------------------------------------------
# Fleet DBU rate — DBU consumed per node-hour, per instance type (non-Photon)
#
# The cost engine prices DBU at the negotiated JOBS rate (dim_dbu_price), but
# needs the DBU *quantity* a node-hour consumes. That quantity is not in the
# preset catalog, so we derive it fleet-wide from telemetry: across all
# bietlejuice runs with Photon OFF on homogeneous clusters (single-node, or
# driver == worker type), SUM(total_dbu_consumed) / SUM(node-hours) per instance
# type. Photon runs are excluded because Photon inflates DBU ~3x and would bias
# the non-Photon projection the recommender normalizes toward.
# ---------------------------------------------------------------------------

_FLEET_DBU_RATE_SQL_TEMPLATE = """\
-- Fleet DBU consumed per node-hour, per instance type, non-Photon homogeneous runs.
-- Generated by recommend_cluster_specs.py; do not hand-edit.
WITH runs AS (
    SELECT
        COALESCE(worker_node_type, driver_node_type)                   AS instance_type,
        total_dbu_consumed                                             AS total_dbu_consumed,
        COALESCE(ec2_spot_hours, 0) + COALESCE(ec2_on_demand_hours, 0) AS node_hours
    FROM dw_databricks_health.fact_databricks_dag_run
    WHERE dt_dag_run_started >= CURRENT_DATE - INTERVAL '{days}' DAY
      AND airflow_dag_id LIKE 'bietlejuice.%'
      AND airflow_dag_id IS NOT NULL
      AND NOT REGEXP_LIKE(airflow_dag_id, '__validation$')
      AND is_job_on_interactive = FALSE
      AND is_any_task_failed = FALSE
      AND is_any_databricks_run_failed = FALSE
      AND is_any_photon = FALSE
      AND COALESCE(total_cost_usd, 0) > 0
      AND COALESCE(total_dbu_consumed, 0) > 0
      AND (worker_node_type IS NULL OR worker_node_type = driver_node_type)
      AND COALESCE(ec2_spot_hours, 0) + COALESCE(ec2_on_demand_hours, 0) > 0
)
SELECT
    instance_type,
    ROUND(SUM(total_dbu_consumed) / SUM(node_hours), 6)                AS dbu_per_node_hour
FROM runs
GROUP BY instance_type
HAVING SUM(node_hours) > 0
ORDER BY instance_type
"""


def build_fleet_dbu_rate_sql(days: int) -> str:
    return _FLEET_DBU_RATE_SQL_TEMPLATE.format(days=days)


def fleet_dbu_rate_from_rows(rows: list[dict[str, Any]]) -> dict[str, float]:
    """Map instance_type -> observed DBU consumed per node-hour (non-Photon)."""
    fleet: dict[str, float] = {}
    for row in rows:
        instance_type = str(row.get("instance_type") or "").strip()
        rate = _f_row(row.get("dbu_per_node_hour"))
        if instance_type and rate is not None and rate > 0:
            fleet[instance_type] = rate
    return fleet


def fleet_dbu_per_node_hour(
    node_type: str | None, fleet: dict[str, float]
) -> float | None:
    """Observed non-Photon DBU/node-hour for ``node_type``.

    Falls back to a vCPU-proportional estimate (average DBU per vCPU-hour across
    the fleet's observed instance types) when ``node_type`` has no observations.
    Returns None only when the fleet map is empty / unusable.
    """
    if not node_type:
        return None
    observed = fleet.get(node_type)
    if observed is not None:
        return observed
    per_vcpu_rates: list[float] = []
    for observed_type, rate in fleet.items():
        vcpus = _vcpus(observed_type)
        if vcpus > 0:
            per_vcpu_rates.append(rate / vcpus)
    node_vcpus = _vcpus(node_type)
    if not per_vcpu_rates or node_vcpus <= 0:
        return None
    avg_per_vcpu = sum(per_vcpu_rates) / len(per_vcpu_rates)
    return round(avg_per_vcpu * node_vcpus, 6)


_VALIDATION_OUTCOMES_SQL = """\
-- Observed metrics from __validation shadow DAG runs (compare vs recommendations).
WITH runs AS (
    SELECT
        REGEXP_REPLACE(airflow_dag_id, '__validation$', '')                    AS prod_dag_id,
        dt_dag_run_started,
        driver_node_type,
        worker_node_type,
        worker_count,
        total_cost_usd,
        total_dbu_cost_usd                               AS dbu_cost_usd,
        total_ec2_cost_calculated_usd                    AS ec2_cost_usd,
        total_wall_clock_seconds,
        weighted_avg_p50_driver_cpu_busy_percent         AS drv_cpu_p50,
        weighted_avg_p95_driver_cpu_busy_percent         AS drv_cpu_p95,
        weighted_avg_p95_driver_mem_used_percent         AS drv_mem_p95,
        weighted_avg_p50_worker_cpu_busy_percent         AS wrk_cpu_p50,
        weighted_avg_p95_worker_cpu_busy_percent         AS wrk_cpu_p95,
        weighted_avg_p95_worker_mem_used_percent         AS wrk_mem_p95
    FROM dw_databricks_health.fact_databricks_dag_run
    WHERE dt_dag_run_started >= CURRENT_DATE - INTERVAL '{days}' DAY
      AND airflow_dag_id LIKE 'bietlejuice.%__validation'
      AND is_job_on_interactive = FALSE
      AND is_any_task_failed = FALSE
      AND is_any_databricks_run_failed = FALSE
      AND COALESCE(total_cost_usd, 0) > 0
),
per_dag AS (
    SELECT
        prod_dag_id,
        COUNT(*)                                                                   AS validation_runs,
        ROUND(AVG(total_cost_usd), 6)                                              AS actual_avg_cost_per_run_usd,
        ROUND(AVG(dbu_cost_usd), 6)                                                AS actual_avg_dbu_cost_usd,
        ROUND(AVG(ec2_cost_usd), 6)                                                AS actual_avg_ec2_cost_usd,
        ROUND(APPROX_PERCENTILE(total_wall_clock_seconds, 0.5)  / 60.0, 1)        AS actual_wall_p50_min,
        ROUND(APPROX_PERCENTILE(total_wall_clock_seconds, 0.95) / 60.0, 1)        AS actual_wall_p95_min,
        ROUND(APPROX_PERCENTILE(drv_cpu_p50, 0.5), 1)                             AS actual_drv_cpu_p50,
        ROUND(APPROX_PERCENTILE(drv_cpu_p95, 0.95), 1)                            AS actual_drv_cpu_p95,
        ROUND(APPROX_PERCENTILE(drv_mem_p95, 0.95), 1)                            AS actual_drv_mem_p95,
        ROUND(APPROX_PERCENTILE(wrk_cpu_p50, 0.5), 1)                             AS actual_wrk_cpu_p50,
        ROUND(APPROX_PERCENTILE(wrk_cpu_p95, 0.95), 1)                            AS actual_wrk_cpu_p95,
        ROUND(APPROX_PERCENTILE(wrk_mem_p95, 0.95), 1)                            AS actual_wrk_mem_p95,
        ARBITRARY(driver_node_type)                                                 AS actual_driver_node_type,
        ARBITRARY(worker_node_type)                                                 AS actual_worker_node_type,
        ARBITRARY(worker_count)                                                     AS actual_worker_count
    FROM runs
    GROUP BY prod_dag_id
    HAVING COUNT(*) >= {validation_min_runs}
)
SELECT * FROM per_dag
ORDER BY validation_runs DESC
"""

_VALIDATION_COST_PASS_PCT = 15.0
_VALIDATION_COST_WARN_PCT = 30.0
_VALIDATION_CPU_PASS_PP = 15.0
_VALIDATION_WALL_INFLATION_MAX = 1.2


def build_validation_sql(days: int, validation_min_runs: int) -> str:
    return _VALIDATION_OUTCOMES_SQL.format(
        days=days, validation_min_runs=validation_min_runs
    )


@dataclass
class ValidationOutcome:
    dag_id: str
    cohort: str
    recommended_preset: str | None
    rec_driver_node_type: str | None
    rec_worker_node_type: str | None
    rec_worker_count: int | None
    projected_est_cost_per_run_usd: float | None
    projected_est_drv_cpu_p50: float | None
    projected_est_drv_mem_p95: str | None
    projected_est_wall_p95_min: float | None
    validation_runs: int
    actual_avg_cost_per_run_usd: float | None
    actual_drv_cpu_p50: float | None
    actual_drv_mem_p95: float | None
    actual_wall_p95_min: float | None
    actual_driver_node_type: str | None
    actual_worker_node_type: str | None
    actual_worker_count: int | None
    delta_cost_pct: float | None
    delta_drv_cpu_p50: float | None
    delta_drv_mem_p95: float | None
    delta_wall_p95_min: float | None
    outcome: str


def _parse_projected_mem_pct(value: str | None) -> float | None:
    if not value:
        return None
    match = re.search(r"([\d.]+)\s*%", value)
    if not match:
        return None
    return float(match.group(1))


def _validation_outcome_label(
    rec: Recommendation,
    actual_cost: float | None,
    actual_drv_cpu_p50: float | None,
    actual_drv_mem_p95: float | None,
    actual_wall_p95: float | None,
    delta_cost_pct: float | None,
    delta_drv_cpu_p50: float | None,
    delta_drv_mem_p95: float | None,
    delta_wall_p95_min: float | None,
) -> str:
    if actual_cost is None:
        return "insufficient_validation_data"

    fails = 0
    warns = 0

    if delta_cost_pct is not None:
        if abs(delta_cost_pct) > _VALIDATION_COST_WARN_PCT:
            fails += 1
        elif abs(delta_cost_pct) > _VALIDATION_COST_PASS_PCT:
            warns += 1

    if delta_drv_cpu_p50 is not None:
        if abs(delta_drv_cpu_p50) > _VALIDATION_CPU_PASS_PP:
            warns += 1

    if delta_drv_mem_p95 is not None:
        if abs(delta_drv_mem_p95) > 20.0:
            warns += 1

    if (
        rec.cohort == "collapse_to_single"
        and actual_wall_p95 is not None
        and rec.wall_p95_min
        and rec.wall_p95_min > 0
        and actual_wall_p95 > rec.wall_p95_min * _VALIDATION_WALL_INFLATION_MAX
    ):
        warns += 1

    if fails:
        return "fail"
    if warns:
        return "warn"
    return "pass"


def build_validation_outcomes(
    recs: list[Recommendation],
    validation_rows: list[dict[str, Any]],
) -> list[ValidationOutcome]:
    actionable = _rightsizing_validation_module()._ACTIONABLE_COHORTS
    rec_by_id = {r.dag_id: r for r in recs if r.cohort in actionable}
    outcomes: list[ValidationOutcome] = []

    for row in validation_rows:
        dag_id = str(row.get("prod_dag_id") or "")
        rec = rec_by_id.get(dag_id)
        if rec is None:
            continue

        actual_cost = _f_row(row.get("actual_avg_cost_per_run_usd"))
        projected_cost = rec.projected.est_cost_per_run_usd
        delta_cost_pct = None
        if (
            actual_cost is not None
            and projected_cost is not None
            and projected_cost > 0
        ):
            delta_cost_pct = round(
                (actual_cost - projected_cost) / projected_cost * 100, 1
            )

        actual_drv_cpu = _f_row(row.get("actual_drv_cpu_p50"))
        projected_drv_cpu = rec.projected.est_drv_cpu_p50
        delta_drv_cpu = None
        if actual_drv_cpu is not None and projected_drv_cpu is not None:
            delta_drv_cpu = round(actual_drv_cpu - projected_drv_cpu, 1)

        actual_drv_mem = _f_row(row.get("actual_drv_mem_p95"))
        projected_drv_mem = _parse_projected_mem_pct(rec.projected.est_drv_mem_p95)
        delta_drv_mem = None
        if actual_drv_mem is not None and projected_drv_mem is not None:
            delta_drv_mem = round(actual_drv_mem - projected_drv_mem, 1)

        actual_wall = _f_row(row.get("actual_wall_p95_min"))
        projected_wall = rec.wall_p95_min
        delta_wall = None
        if actual_wall is not None and projected_wall is not None:
            delta_wall = round(actual_wall - projected_wall, 1)

        outcome = _validation_outcome_label(
            rec,
            actual_cost,
            actual_drv_cpu,
            actual_drv_mem,
            actual_wall,
            delta_cost_pct,
            delta_drv_cpu,
            delta_drv_mem,
            delta_wall,
        )

        outcomes.append(
            ValidationOutcome(
                dag_id=dag_id,
                cohort=rec.cohort,
                recommended_preset=rec.recommended_preset,
                rec_driver_node_type=rec.rec_driver_node_type,
                rec_worker_node_type=rec.rec_worker_node_type,
                rec_worker_count=rec.rec_worker_count,
                projected_est_cost_per_run_usd=projected_cost,
                projected_est_drv_cpu_p50=projected_drv_cpu,
                projected_est_drv_mem_p95=rec.projected.est_drv_mem_p95,
                projected_est_wall_p95_min=projected_wall,
                validation_runs=int(float(str(row.get("validation_runs") or 0))),
                actual_avg_cost_per_run_usd=actual_cost,
                actual_drv_cpu_p50=actual_drv_cpu,
                actual_drv_mem_p95=actual_drv_mem,
                actual_wall_p95_min=actual_wall,
                actual_driver_node_type=str(row.get("actual_driver_node_type") or "")
                or None,
                actual_worker_node_type=str(row.get("actual_worker_node_type") or "")
                or None,
                actual_worker_count=(
                    int(_f_row(row.get("actual_worker_count")) or 0)
                    if _f_row(row.get("actual_worker_count")) is not None
                    else None
                ),
                delta_cost_pct=delta_cost_pct,
                delta_drv_cpu_p50=delta_drv_cpu,
                delta_drv_mem_p95=delta_drv_mem,
                delta_wall_p95_min=delta_wall,
                outcome=outcome,
            )
        )

    return outcomes


def _f_row(v: Any) -> float | None:
    s = str(v).strip() if v is not None else ""
    if s in ("", "None", "nan", "NaN"):
        return None
    return float(s)


def _i_row(v: Any, default: int = 0) -> int:
    s = str(v).strip() if v is not None else ""
    if s in ("", "None", "nan", "NaN"):
        return default
    return int(float(s))


_VALIDATION_OUTCOME_FIELDS = [
    "dag_id",
    "cohort",
    "recommended_preset",
    "rec_driver_node_type",
    "rec_worker_node_type",
    "rec_worker_count",
    "projected_est_cost_per_run_usd",
    "projected_est_drv_cpu_p50",
    "projected_est_drv_mem_p95",
    "projected_est_wall_p95_min",
    "validation_runs",
    "actual_avg_cost_per_run_usd",
    "actual_drv_cpu_p50",
    "actual_drv_mem_p95",
    "actual_wall_p95_min",
    "actual_driver_node_type",
    "actual_worker_node_type",
    "actual_worker_count",
    "delta_cost_pct",
    "delta_drv_cpu_p50",
    "delta_drv_mem_p95",
    "delta_wall_p95_min",
    "outcome",
]


def write_validation_outcomes(
    outcomes: list[ValidationOutcome],
    out_csv: Path,
) -> None:
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=_VALIDATION_OUTCOME_FIELDS)
        writer.writeheader()
        for outcome in outcomes:
            writer.writerow(asdict(outcome))


def fetch_validation_rows(
    sql: str,
    trino_host: str | None = None,
) -> list[dict[str, Any]]:
    """Run validation SQL and return raw row dicts."""
    host = resolve_trino_host(trino_host)
    with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
        csv_path = tmp.name

    cmd = [
        sys.executable,
        str(EXECUTE_TRINO),
        "--host",
        host,
        "--catalog",
        "delta",
        "--external-auth",
        "--query",
        sql,
        "--csv-output",
        csv_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"execute_trino.py failed (exit {result.returncode}):\n"
            f"stdout: {result.stdout[:500]}\nstderr: {result.stderr[:500]}"
        )

    out = json.loads(result.stdout)
    if out.get("status") != "success":
        raise RuntimeError(f"Trino query failed: {out.get('message', out)}")

    rows: list[dict[str, Any]] = []
    with open(csv_path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        rows.extend(reader)
    return rows


def resolve_trino_host(cli_host: str | None = None) -> str:
    """Resolve Trino host from TRINO_HOST env var, CLI flag, or prod default."""
    return os.environ.get("TRINO_HOST") or cli_host or _DEFAULT_TRINO_HOST


def fetch_amd_candidates(
    metrics: list[DagMetrics],
    sql: str,
    trino_host: str | None = None,
) -> list[DagMetrics]:
    """Query AMD-era metrics and return collapse candidates not in the ARM pool."""
    arm_dag_ids = {m.dag_id for m in metrics}
    amd_rows = fetch_from_trino(sql, resolve_trino_host(trino_host))
    return [m for m in amd_rows if m.dag_id not in arm_dag_ids]


def build_amd_recommendation(m: DagMetrics) -> Recommendation | None:
    """Build a collapse_to_single recommendation from AMD data, or None if not eligible.

    The DAG's wall_p95 is corrected by AMD_WALL_CORRECTION before testing the
    collapse gate.  Returned Recommendation has confidence='medium-x86' to signal
    it relies on AMD history.
    """
    if not classify_amd_for_collapse(m):
        return None
    if (
        m.dominant_config_run_share < _DOMINANT_CONFIG_SHARE_MIN
        or m.dominant_config_cost_share < _DOMINANT_CONFIG_SHARE_MIN
    ):
        return None

    # Force worker_count=2 for projection purposes if unknown from AMD data
    worker_count = m.worker_count if m.worker_count and m.worker_count > 0 else 2
    sizing = size_single_node(m)
    if sizing.blocked_reason == "needs_more_telemetry" or not sizing.node_type:
        return None

    rec_preset, _ = _single_node_preset_for_node(sizing.node_type)
    if not rec_preset:
        return None
    rec_spec = PRESET_CATALOG.get(rec_preset)
    rec_driver = sizing.node_type
    rec_workers = 0  # single-node
    driver_override_node_type_id = None
    if rec_spec and rec_driver != rec_spec.driver_node_type:
        driver_override_node_type_id = rec_driver

    projected = ProjectedMetrics()
    if rec_driver:
        projected.est_cost_per_run_usd = estimate_cost(
            m.arm_avg_cost_per_run_usd,
            m.driver_node_type,
            m.worker_node_type,
            worker_count,
            rec_driver,
            None,
            rec_workers,
        )
        if projected.est_cost_per_run_usd is not None and m.arm_avg_cost_per_run_usd:
            projected.est_cost_delta_pct = round(
                (projected.est_cost_per_run_usd - m.arm_avg_cost_per_run_usd)
                / m.arm_avg_cost_per_run_usd
                * 100,
                1,
            )
        amd_demand = effective_demand(m)
        est_cpu, uncertain = estimate_drv_cpu_after_collapse(
            amd_demand.drv_cpu_p50,
            amd_demand.wrk_cpu_p50,
            m.driver_node_type,
            m.worker_node_type,
            worker_count,
        )
        projected.est_drv_cpu_p50 = est_cpu
        projected.est_drv_cpu_p50_uncertain = uncertain
        projected.est_drv_cpu_p95 = sizing.projected_cpu_pct
        projected.est_drv_mem_p95 = (
            f"projected {sizing.projected_mem_pct:.1f}%"
            if sizing.projected_mem_pct is not None
            else "⚠ may rise"
        )
        projected.est_wrk_cpu_p50 = None
        projected.est_wrk_cpu_p95 = None
        projected.est_wrk_mem_p95 = "N/A"

    return Recommendation(
        dag_id=m.dag_id,
        cohort="collapse_to_single",
        confidence="medium-x86",
        actions="collapse_to_single",
        current_preset=infer_current_preset(
            m.driver_node_type, m.worker_node_type, worker_count
        ),
        current_driver_node_type=m.driver_node_type,
        current_worker_node_type=m.worker_node_type,
        current_worker_count=m.worker_count,
        arm_days=m.arm_days,
        arm_runs=m.arm_runs,
        arm_total_cost_usd=m.arm_total_cost_usd,
        arm_avg_cost_per_run_usd=m.arm_avg_cost_per_run_usd,
        arm_total_cost_estimate_usd=m.arm_total_cost_estimate_usd,
        arm_avg_total_cost_estimate_usd=m.arm_avg_total_cost_estimate_usd,
        wall_p50_min=m.wall_p50_min,
        wall_p95_min=m.wall_p95_min,
        drv_cpu_p50=m.drv_cpu_p50,
        drv_cpu_p95=m.drv_cpu_p95,
        drv_mem_p95=m.drv_mem_p95,
        drv_wait_p95=m.drv_wait_p95,
        wrk_cpu_p50=m.wrk_cpu_p50,
        wrk_cpu_p95=m.wrk_cpu_p95,
        wrk_mem_p95=m.wrk_mem_p95,
        wrk_wait_p95=m.wrk_wait_p95,
        recommended_preset=rec_preset,
        rec_driver_node_type=rec_driver,
        rec_worker_node_type=None,
        rec_worker_count=rec_workers,
        num_workers_override=None,
        driver_override_node_type_id=driver_override_node_type_id,
        projected=projected,
    )


# ---------------------------------------------------------------------------
# Data I/O
# ---------------------------------------------------------------------------


def _row_to_metrics(row: dict[str, Any]) -> DagMetrics:
    def _f(v: Any) -> float | None:
        s = str(v).strip() if v is not None else ""
        if s in ("", "None", "nan", "NaN"):
            return None
        return float(s)

    def _i(v: Any, default: int = 0) -> int:
        s = str(v).strip() if v is not None else ""
        if s in ("", "None", "nan", "NaN"):
            return default
        # Handle float strings like "2.0"
        return int(float(s))

    def _maybe_worker_count(v: Any) -> int | None:
        """Return None for autoscale (nan/null), int otherwise."""
        s = str(v).strip() if v is not None else ""
        if s in ("", "None", "nan", "NaN"):
            return None
        return int(float(s))

    def _b(v: Any) -> bool:
        if isinstance(v, bool):
            return v
        s = str(v).strip().lower() if v is not None else ""
        return s in ("true", "1", "t", "yes", "y")

    return DagMetrics(
        dag_id=str(row["airflow_dag_id"]),
        arm_days=_i(row.get("arm_days")),
        arm_runs=_i(row.get("arm_runs")),
        driver_node_type=str(row.get("driver_node_type") or ""),
        worker_node_type=str(row["worker_node_type"])
        if row.get("worker_node_type")
        else None,
        worker_count=_maybe_worker_count(row.get("worker_count")),
        arm_total_cost_usd=_f(row.get("arm_total_cost_usd")) or 0.0,
        arm_avg_cost_per_run_usd=_f(row.get("arm_avg_cost_per_run_usd")) or 0.0,
        wall_p50_min=_f(row.get("wall_p50_min")) or 0.0,
        wall_p95_min=_f(row.get("wall_p95_min")) or 0.0,
        drv_cpu_p50=_f(row.get("drv_cpu_p50")),
        drv_cpu_p95=_f(row.get("drv_cpu_p95")),
        drv_mem_p95=_f(row.get("drv_mem_p95")),
        drv_wait_p95=_f(row.get("drv_wait_p95")),
        wrk_cpu_p50=_f(row.get("wrk_cpu_p50")),
        wrk_cpu_p95=_f(row.get("wrk_cpu_p95")),
        wrk_mem_p95=_f(row.get("wrk_mem_p95")),
        wrk_wait_p95=_f(row.get("wrk_wait_p95")),
        drv_mem_p50=_f(row.get("drv_mem_p50")),
        wrk_mem_p50=_f(row.get("wrk_mem_p50")),
        local_disk_p95=_f(row.get("local_disk_p95")),
        arm_total_cost_estimate_usd=_f(row.get("arm_total_cost_estimate_usd")),
        arm_avg_total_cost_estimate_usd=_f(row.get("arm_avg_total_cost_estimate_usd")),
        dominant_config_run_share=_f(row.get("dominant_config_run_share")) or 1.0,
        dominant_config_cost_share=_f(row.get("dominant_config_cost_share")) or 1.0,
        runs_per_day=_f(row.get("runs_per_day")),
        schedule_interval_minutes=_f(row.get("schedule_interval_minutes")),
        arm_total_ec2_cost_usd=_f(row.get("arm_total_ec2_cost_usd")),
        arm_avg_ec2_cost_usd=_f(row.get("arm_avg_ec2_cost_usd")),
        arm_total_dbu_cost_usd=_f(row.get("arm_total_dbu_cost_usd")),
        arm_avg_dbu_cost_usd=_f(row.get("arm_avg_dbu_cost_usd")),
        arm_avg_dbu_consumed=_f(row.get("arm_avg_dbu_consumed")),
        ec2_spot_hours=_f(row.get("ec2_spot_hours")),
        ec2_on_demand_hours=_f(row.get("ec2_on_demand_hours")),
        total_memory_bytes_spilled=_f(row.get("total_memory_bytes_spilled")) or 0.0,
        total_disk_bytes_spilled=_f(row.get("total_disk_bytes_spilled")) or 0.0,
        max_peak_execution_memory_bytes=_f(row.get("max_peak_execution_memory_bytes")),
        max_jvm_heap_bytes=_f(row.get("max_jvm_heap_bytes")),
        total_gc_time_ms=_f(row.get("total_gc_time_ms")) or 0.0,
        total_executor_run_time_ms=_f(row.get("total_executor_run_time_ms")) or 0.0,
        max_task_skew_ratio=_f(row.get("max_task_skew_ratio")),
        primary_min_autoscale_workers=_maybe_worker_count(
            row.get("primary_min_autoscale_workers")
        ),
        primary_max_autoscale_workers=_maybe_worker_count(
            row.get("primary_max_autoscale_workers")
        ),
        is_ec2_estimated=_b(row.get("is_ec2_estimated")),
        ec2_pricing_missing=_b(row.get("ec2_pricing_missing")),
        dbu_negotiated_price_missing=_b(row.get("dbu_negotiated_price_missing")),
        is_any_photon=_b(row.get("is_any_photon")),
        is_any_local_nvme=_b(row.get("is_any_local_nvme")),
    )


def fetch_from_trino(
    sql: str,
    trino_host: str | None = None,
    execute_trino_path: Path = EXECUTE_TRINO,
) -> list[DagMetrics]:
    """Run SQL via execute_trino.py and return parsed DagMetrics rows."""
    host = resolve_trino_host(trino_host)
    with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
        csv_path = tmp.name

    cmd = [
        sys.executable,
        str(execute_trino_path),
        "--host",
        host,
        "--catalog",
        "delta",
        "--external-auth",
        "--query",
        sql,
        "--csv-output",
        csv_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"execute_trino.py failed (exit {result.returncode}):\n"
            f"stdout: {result.stdout[:500]}\nstderr: {result.stderr[:500]}"
        )

    out = json.loads(result.stdout)
    if out.get("status") != "success":
        raise RuntimeError(f"Trino query failed: {out.get('message', out)}")

    return load_from_csv(csv_path)


def load_from_csv(path: str | Path) -> list[DagMetrics]:
    """Load DagMetrics from a CSV file (header row required)."""
    rows: list[DagMetrics] = []
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            try:
                metrics = _row_to_metrics(row)
                if _is_validation_dag(metrics.dag_id):
                    continue
                rows.append(metrics)
            except (KeyError, ValueError) as exc:
                print(f"WARNING: skipping malformed row {row}: {exc}", file=sys.stderr)
    return rows


# ---------------------------------------------------------------------------
# Report writer
# ---------------------------------------------------------------------------

_CSV_FIELDS = [
    # Identity
    "dag_id",
    "cohort",
    "confidence",
    "actions",
    # Current spec
    "current_preset",
    "current_driver_node_type",
    "current_worker_node_type",
    "current_worker_count",
    # Evidence
    "arm_days",
    "arm_runs",
    "arm_total_cost_usd",
    "arm_avg_cost_per_run_usd",
    "arm_total_cost_estimate_usd",
    "arm_avg_total_cost_estimate_usd",
    "runs_per_day",
    "schedule_interval_minutes",
    "arm_total_ec2_cost_usd",
    "arm_avg_ec2_cost_usd",
    "arm_total_dbu_cost_usd",
    "arm_avg_dbu_cost_usd",
    "ec2_spot_hours",
    "ec2_on_demand_hours",
    "dominant_config_run_share",
    "dominant_config_cost_share",
    "wall_p50_min",
    "wall_p95_min",
    # Current metrics
    "drv_cpu_p50",
    "drv_cpu_p95",
    "drv_mem_p50",
    "drv_mem_p95",
    "drv_wait_p95",
    "wrk_cpu_p50",
    "wrk_cpu_p95",
    "wrk_mem_p50",
    "wrk_mem_p95",
    "wrk_wait_p95",
    "total_memory_bytes_spilled",
    "total_disk_bytes_spilled",
    # Recommended spec
    "driver_action",
    "worker_action",
    "blocking_reason",
    "recommended_preset",
    "rec_driver_node_type",
    "rec_worker_node_type",
    "rec_worker_count",
    "num_workers_override",
    "driver_override_node_type_id",
    # Projected metrics
    "est_drv_cpu_p50",
    "est_drv_cpu_p95",
    "est_drv_cpu_p50_uncertain",
    "est_drv_mem_p95",
    "est_wrk_cpu_p50",
    "est_wrk_cpu_p95",
    "est_wrk_mem_p95",
    "est_cost_per_run_usd",
    "est_cost_delta_pct",
    "blocked_cost_per_run_usd",
    "blocked_cost_delta_pct",
    "blocked_reason",
]


def _rec_to_row(r: Recommendation) -> dict[str, Any]:
    row = asdict(r)
    # Flatten projected
    p = row.pop("projected")
    row.update(p)
    return row


def _format_pct(value: float) -> str:
    rounded = round(value)
    if rounded == 0:
        return "0%"
    return f"{value:+.0f}%"


def _format_delta(r: Recommendation) -> str:
    accepted = r.projected.est_cost_delta_pct
    blocked = r.projected.blocked_cost_delta_pct
    if accepted is None and blocked is None:
        return ""
    if accepted is None:
        return f"  est ({_format_pct(blocked)})"
    result = f"  est {_format_pct(accepted)}"
    if blocked is not None:
        result += f" ({_format_pct(blocked)})"
    return result


def write_report(
    recs: list[Recommendation],
    out_csv: Path,
    out_json: Path,
) -> None:
    rows = [_rec_to_row(r) for r in recs]

    # CSV
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=_CSV_FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    # JSON
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(rows, indent=2, default=str), encoding="utf-8")


# ---------------------------------------------------------------------------
# Validation config generator (implementation in bietlejuice-compiler ci_cd)
# ---------------------------------------------------------------------------


def _ensure_bietlejuice_import_path() -> None:
    """Make bietlejuice-compiler scripts importable ahead of repo-root scripts/."""
    compiler_root = REPO_ROOT / "packages" / "bietlejuice-compiler"
    core_src = REPO_ROOT / "packages" / "bietlejuice-core" / "src"
    for subpath in (compiler_root, compiler_root / "src", core_src):
        path_str = str(subpath)
        while path_str in sys.path:
            sys.path.remove(path_str)
        sys.path.insert(0, path_str)


_RIGHTSIZING_VALIDATION_MODULE = None


def _rightsizing_validation_module():
    """Load ci_cd validation module without conflicting with repo-root scripts/."""
    global _RIGHTSIZING_VALIDATION_MODULE
    if _RIGHTSIZING_VALIDATION_MODULE is not None:
        return _RIGHTSIZING_VALIDATION_MODULE

    _ensure_bietlejuice_import_path()
    scripts_mod = sys.modules.get("scripts")
    if scripts_mod is not None and not hasattr(scripts_mod, "ci_cd"):
        del sys.modules["scripts"]

    from scripts.ci_cd.airflow_dag_builder import (  # noqa: PLC0415
        rightsizing_validation_config,
    )

    _RIGHTSIZING_VALIDATION_MODULE = rightsizing_validation_config
    return rightsizing_validation_config


def generate_validation_config(
    rec: Recommendation,
    databricks_conn_id: str = "databricks_new",
    *,
    dags_root: Path = DAGS_ROOT,
) -> dict | None:
    """Return a minimal validation block dict, or None when not actionable."""
    return _rightsizing_validation_module().generate_validation_config(
        rec, databricks_conn_id, dags_root=dags_root
    )


def find_dag_cluster_path(dag_name: str, dags_root: Path = DAGS_ROOT) -> Path | None:
    """Find *_cluster.yml for a dag_name by searching dags/ tree."""
    return _rightsizing_validation_module().find_dag_cluster_path(dag_name, dags_root)


def find_dag_folder(dag_name: str, dags_root: Path = DAGS_ROOT) -> Path | None:
    """Find the DAG folder containing {dag_name}_declaration.yml."""
    return _rightsizing_validation_module().find_dag_folder(dag_name, dags_root)


def write_validation_cluster_file(
    cluster_path: Path,
    val_config: dict,
    current_cluster_type: str | None,
    databricks_conn_id: str = "databricks_new",
) -> None:
    """Upsert the validation: section in a *_cluster.yml file."""
    _rightsizing_validation_module().write_validation_cluster_file(
        cluster_path,
        val_config,
        current_cluster_type,
        databricks_conn_id,
    )


def write_validation_configs(
    recs: list[Recommendation],
    out_yaml: Path,
    *,
    dags_root: Path = DAGS_ROOT,
    write_cluster_files: bool = False,
    databricks_conn_id: str = "databricks_new",
) -> int:
    """Write validation_configs.yml and optionally update *_cluster.yml files."""
    return _rightsizing_validation_module().write_validation_configs(
        recs,
        out_yaml,
        dags_root=dags_root,
        write_cluster_files=write_cluster_files,
        databricks_conn_id=databricks_conn_id,
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    src = parser.add_mutually_exclusive_group()
    src.add_argument(
        "--trino", action="store_true", help="Fetch metrics live from Trino"
    )
    src.add_argument(
        "--metrics-csv", metavar="PATH", help="Load metrics from a pre-exported CSV"
    )

    parser.add_argument(
        "--min-days",
        type=int,
        default=3,
        metavar="N",
        help="Minimum ARM run days for eligibility (default 3)",
    )
    parser.add_argument(
        "--min-runs",
        type=int,
        default=3,
        metavar="N",
        help="Minimum ARM run count for eligibility (default 3)",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=90,
        metavar="N",
        help="Lookback window in days for Trino query (default 90)",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("."),
        help="Directory for recommendations.csv and recommendations.json (default .)",
    )
    parser.add_argument(
        "--validation-config",
        metavar="PATH",
        help="Write validation_configs.yml to PATH (omit to skip)",
    )
    parser.add_argument(
        "--write-cluster-files",
        action="store_true",
        help="Also upsert validation: sections into each DAG's *_cluster.yml",
    )
    parser.add_argument(
        "--databricks-conn-id",
        default="databricks_new",
        help=(
            "Fallback databricks_conn_id when prod *_cluster.yml has none "
            "(default databricks_new)"
        ),
    )
    parser.add_argument(
        "--trino-host",
        default=_DEFAULT_TRINO_HOST,
        help=(
            f"Trino host (default {_DEFAULT_TRINO_HOST}; "
            "overridden by TRINO_HOST env var when set)"
        ),
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="Print DAG IDs and their cohorts, then exit (no files written)",
    )
    parser.add_argument(
        "--use-amd-history",
        action="store_true",
        help=(
            "Also query AMD (x86) history for DAGs below the ARM threshold. "
            "Only collapse_to_single is inferred from AMD data, using a "
            f"{AMD_WALL_CORRECTION:.0%} wall-clock correction. "
            "Recommendations are labelled confidence=medium-x86."
        ),
    )
    parser.add_argument(
        "--amd-min-runs",
        type=int,
        default=10,
        metavar="N",
        help="Minimum AMD run count for AMD correction pool (default 10)",
    )
    parser.add_argument(
        "--validation-outcomes",
        metavar="PATH",
        help="Write validation_outcomes.csv comparing recommendations vs __validation runs",
    )
    parser.add_argument(
        "--validation-min-runs",
        type=int,
        default=1,
        metavar="N",
        help="Minimum validation runs per DAG for outcome comparison (default 1)",
    )
    return parser.parse_args(argv)


def _print_cohort_summary(recs: list[Recommendation]) -> None:
    from collections import Counter

    counts: Counter[str] = Counter(r.cohort for r in recs)
    costs: dict[str, float] = {}
    for r in recs:
        costs[r.cohort] = costs.get(r.cohort, 0.0) + r.arm_total_cost_usd

    print(f"\n{'Cohort':<35} {'DAGs':>5}  {'Cost/period':>12}")
    print("-" * 56)
    for cohort in sorted(counts, key=lambda c: -costs.get(c, 0)):
        print(f"{cohort:<35} {counts[cohort]:>5}  ${costs[cohort]:>10.2f}")
    print(f"\nTotal eligible: {len(recs)} DAGs")
    actionable_cohorts = _rightsizing_validation_module()._ACTIONABLE_COHORTS
    actionable = sum(1 for r in recs if r.cohort in actionable_cohorts)
    print(f"Actionable (collapse + downsize + upsize): {actionable} DAGs")


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s: %(message)s")
    args = _parse_args(argv)
    trino_host = resolve_trino_host(args.trino_host)

    if not args.trino and not args.metrics_csv:
        print("ERROR: specify --trino or --metrics-csv PATH", file=sys.stderr)
        return 1

    # Fetch metrics
    if args.trino:
        sql = build_sql(args.days, args.min_days, args.min_runs)
        print(f"Querying Trino ({trino_host}) …", file=sys.stderr)
        metrics = fetch_from_trino(sql, trino_host)
    else:
        metrics = load_from_csv(args.metrics_csv)

    if not metrics:
        print("No metrics rows loaded. Check data source.", file=sys.stderr)
        return 1

    print(f"Loaded {len(metrics)} DAG rows.", file=sys.stderr)

    # Populate fleet DBU rate map for cost-truthful repricing (Trino runs only).
    if args.trino:
        try:
            fleet_sql = build_fleet_dbu_rate_sql(args.days)
            print("Querying fleet DBU rates …", file=sys.stderr)
            fleet_rows = fetch_validation_rows(fleet_sql, trino_host)
            _FLEET_DBU_RATE.update(fleet_dbu_rate_from_rows(fleet_rows))
            print(
                f"Loaded {len(_FLEET_DBU_RATE)} fleet DBU rates.",
                file=sys.stderr,
            )
        except Exception as exc:
            print(
                f"WARNING: fleet DBU rate query failed ({exc}); "
                "cost engine will use legacy DBU proxy.",
                file=sys.stderr,
            )

    # Build recommendations from ARM data
    recs = [build_recommendation(m, args.min_days, args.min_runs) for m in metrics]

    # Optionally extend with collapse candidates from AMD history
    if getattr(args, "use_amd_history", False) and args.trino:
        print(
            "Querying AMD history for additional collapse candidates …", file=sys.stderr
        )
        amd_sql = build_amd_sql(
            args.days, args.min_days, args.min_runs, args.amd_min_runs
        )
        amd_pool = fetch_amd_candidates(metrics, amd_sql, trino_host)
        amd_recs = [
            r for m in amd_pool if (r := build_amd_recommendation(m)) is not None
        ]
        print(
            f"AMD correction: {len(amd_pool)} candidates, {len(amd_recs)} collapse-eligible.",
            file=sys.stderr,
        )
        recs.extend(amd_recs)

    if args.list:
        _print_cohort_summary(recs)
        for r in sorted(recs, key=lambda x: x.cohort):
            rec_info = f"→ {r.recommended_preset}" if r.recommended_preset else ""
            delta = _format_delta(r)
            print(f"  [{r.cohort}] {r.dag_id}  actions={r.actions}  {rec_info}{delta}")
        return 0

    # Write report
    out_csv = args.out_dir / "recommendations.csv"
    out_json = args.out_dir / "recommendations.json"
    write_report(recs, out_csv, out_json)
    print(f"Wrote {out_csv}", file=sys.stderr)
    print(f"Wrote {out_json}", file=sys.stderr)

    # Write validation configs
    if args.validation_config:
        out_yaml = Path(args.validation_config)
        n = write_validation_configs(
            recs,
            out_yaml,
            dags_root=DAGS_ROOT,
            write_cluster_files=args.write_cluster_files,
            databricks_conn_id=args.databricks_conn_id,
        )
        print(f"Wrote {out_yaml} ({n} actionable DAGs)", file=sys.stderr)

    if args.validation_outcomes and args.trino:
        val_sql = build_validation_sql(args.days, args.validation_min_runs)
        print("Querying validation run outcomes …", file=sys.stderr)
        val_rows = fetch_validation_rows(val_sql, trino_host)
        outcomes = build_validation_outcomes(recs, val_rows)
        val_csv = Path(args.validation_outcomes)
        write_validation_outcomes(outcomes, val_csv)
        print(f"Wrote {val_csv} ({len(outcomes)} matched DAGs)", file=sys.stderr)

    _print_cohort_summary(recs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
