#!/usr/bin/env python3
"""Right-sizing recommender for ARM/Graviton DAG clusters (round 2).

Reads post-ARM utilization from dw_databricks_health.fact_databricks_dag_run,
classifies each eligible DAG into one of 8 cohorts, and recommends a smaller
cluster where safe.  Produces:

  recommendations.csv / recommendations.json
      Current spec + observed metrics  →  recommended spec + projected metrics.

  validation_configs.yml  (with --validation-config PATH)
      Per-DAG cluster type ready to drop into each DAG's *_cluster.yml
      validation: block, which the existing trigger_cluster_validation_dags.py
      picks up for shadow validation.

Eligibility: ≥ --min-days ARM days AND ≥ --min-runs ARM runs.
Scope: bietlejuice.* DAGs only; PHASE1/PHASE2 workflow types (same as the
       existing cluster-validation tooling).

Usage
-----
  # Pull live metrics from Trino and emit all outputs:
  uv run --no-project --with "trino==0.337.0,pandas,requests,tzlocal,lz4,zstandard,orjson" \\
      python scripts/recommend_cluster_specs.py \\
      --trino --validation-config validation_configs.yml

  # From a pre-exported CSV (no Trino needed):
  uv run --no-project --with pandas \\
      python scripts/recommend_cluster_specs.py \\
      --metrics-csv arm_metrics.csv --validation-config validation_configs.yml

  # Dry-run: list DAGs and their cohorts, no files written:
  uv run --no-project --with "trino==0.337.0,pandas,...,orjson" \\
      python scripts/recommend_cluster_specs.py --trino --list
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

ARM_REGEX = re.compile(r"^[a-z][a-z0-9]*[0-9]g[a-z]?\.")

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


INSTANCE_CATALOG: dict[str, InstanceSpec] = {
    # Compute-optimised  c6g  (1 vCPU : 2 GiB)
    "c6g.large": InstanceSpec(2, 4, "compute"),
    "c6g.xlarge": InstanceSpec(4, 8, "compute"),
    "c6g.2xlarge": InstanceSpec(8, 16, "compute"),
    "c6g.4xlarge": InstanceSpec(16, 32, "compute"),
    "c6g.8xlarge": InstanceSpec(32, 64, "compute"),
    "c6g.12xlarge": InstanceSpec(48, 96, "compute"),
    "c6g.16xlarge": InstanceSpec(64, 128, "compute"),
    # General-purpose  m6g  (1 vCPU : 4 GiB)
    "m6g.large": InstanceSpec(2, 8, "general"),
    "m6g.xlarge": InstanceSpec(4, 16, "general"),
    "m6g.2xlarge": InstanceSpec(8, 32, "general"),
    "m6g.4xlarge": InstanceSpec(16, 64, "general"),
    "m6g.8xlarge": InstanceSpec(32, 128, "general"),
    "m6g.12xlarge": InstanceSpec(48, 192, "general"),
    "m6g.16xlarge": InstanceSpec(64, 256, "general"),
    # General  m6gd  (NVMe local-disk variant, same vCPU/RAM)
    "m6gd.large": InstanceSpec(2, 8, "general"),
    "m6gd.xlarge": InstanceSpec(4, 16, "general"),
    "m6gd.2xlarge": InstanceSpec(8, 32, "general"),
    "m6gd.4xlarge": InstanceSpec(16, 64, "general"),
    "m6gd.8xlarge": InstanceSpec(32, 128, "general"),
    # General  m7g  (Graviton Gen 7)
    "m7g.large": InstanceSpec(2, 8, "general"),
    "m7g.xlarge": InstanceSpec(4, 16, "general"),
    "m7g.2xlarge": InstanceSpec(8, 32, "general"),
    "m7g.4xlarge": InstanceSpec(16, 64, "general"),
    "m7g.8xlarge": InstanceSpec(32, 128, "general"),
    "m7g.12xlarge": InstanceSpec(48, 192, "general"),
    "m7g.16xlarge": InstanceSpec(64, 256, "general"),
    # Memory-optimised  r6g  (1 vCPU : 8 GiB)
    "r6g.large": InstanceSpec(2, 16, "memory"),
    "r6g.xlarge": InstanceSpec(4, 32, "memory"),
    "r6g.2xlarge": InstanceSpec(8, 64, "memory"),
    "r6g.4xlarge": InstanceSpec(16, 128, "memory"),
    "r6g.8xlarge": InstanceSpec(32, 256, "memory"),
    "r6g.12xlarge": InstanceSpec(48, 384, "memory"),
    "r6g.16xlarge": InstanceSpec(64, 512, "memory"),
    # Memory  r6gd  (NVMe local-disk variant)
    "r6gd.large": InstanceSpec(2, 16, "memory"),
    "r6gd.xlarge": InstanceSpec(4, 32, "memory"),
    "r6gd.2xlarge": InstanceSpec(8, 64, "memory"),
    "r6gd.4xlarge": InstanceSpec(16, 128, "memory"),
    "r6gd.8xlarge": InstanceSpec(32, 256, "memory"),
    # Memory  r7g  (Graviton Gen 7)
    "r7g.large": InstanceSpec(2, 16, "memory"),
    "r7g.xlarge": InstanceSpec(4, 32, "memory"),
    "r7g.2xlarge": InstanceSpec(8, 64, "memory"),
    "r7g.4xlarge": InstanceSpec(16, 128, "memory"),
    "r7g.8xlarge": InstanceSpec(32, 256, "memory"),
    "r7g.12xlarge": InstanceSpec(48, 384, "memory"),
    "r7g.16xlarge": InstanceSpec(64, 512, "memory"),
    # x86 AMD  (reference only — not recommended targets)
    "m5a.large": InstanceSpec(2, 8, "general"),
    "m5a.xlarge": InstanceSpec(4, 16, "general"),
    "m5a.2xlarge": InstanceSpec(8, 32, "general"),
    "m5a.4xlarge": InstanceSpec(16, 64, "general"),
    "m5a.8xlarge": InstanceSpec(32, 128, "general"),
    "c5a.large": InstanceSpec(2, 4, "compute"),
    "c5a.xlarge": InstanceSpec(4, 8, "compute"),
    "c5a.2xlarge": InstanceSpec(8, 16, "compute"),
    "c5a.4xlarge": InstanceSpec(16, 32, "compute"),
    "c5a.8xlarge": InstanceSpec(32, 64, "compute"),
    "r5a.large": InstanceSpec(2, 16, "memory"),
    "r5a.xlarge": InstanceSpec(4, 32, "memory"),
    "r5a.2xlarge": InstanceSpec(8, 64, "memory"),
    "r5a.4xlarge": InstanceSpec(16, 128, "memory"),
    "r5a.8xlarge": InstanceSpec(32, 256, "memory"),
}

EC2_ON_DEMAND_USD_PER_HOUR: dict[str, float] = {
    "c6g.large": 0.068,
    "c6g.xlarge": 0.136,
    "c6g.2xlarge": 0.272,
    "c6g.4xlarge": 0.544,
    "c6g.8xlarge": 1.088,
    "c6g.12xlarge": 1.632,
    "c6g.16xlarge": 2.176,
    "m6g.large": 0.077,
    "m6g.xlarge": 0.154,
    "m6g.2xlarge": 0.308,
    "m6g.4xlarge": 0.616,
    "m6g.8xlarge": 1.232,
    "m6g.12xlarge": 1.848,
    "m6g.16xlarge": 2.464,
    "m7g.large": 0.0816,
    "m7g.xlarge": 0.1632,
    "m7g.2xlarge": 0.3264,
    "m7g.4xlarge": 0.6528,
    "m7g.8xlarge": 1.3056,
    "m7g.12xlarge": 1.9584,
    "m7g.16xlarge": 2.6112,
    "r6g.large": 0.1,
    "r6g.xlarge": 0.2016,
    "r6g.2xlarge": 0.4032,
    "r6g.4xlarge": 0.8064,
    "r6g.8xlarge": 1.6128,
    "r6g.12xlarge": 2.42,
    "r6g.16xlarge": 3.2256,
    "r7g.large": 0.1071,
    "r7g.xlarge": 0.2142,
    "r7g.2xlarge": 0.4284,
    "r7g.4xlarge": 0.8568,
    "r7g.8xlarge": 1.7136,
    "r7g.12xlarge": 2.5704,
    "r7g.16xlarge": 3.4272,
}

_SPOT_TO_ON_DEMAND_RATIO = 0.37
_SINGLE_NODE_MEM_TARGET = 0.82
_SINGLE_NODE_CPU_TARGET = 0.85
_SLA_INTERVAL_TARGET = 0.80
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


# ---------------------------------------------------------------------------
# Classifier
# ---------------------------------------------------------------------------

_DOMINANT_CONFIG_SHARE_MIN = 0.80
_DRIVER_DOWNSIZE_CPU_P95_MAX = 20.0
_DRIVER_DOWNSIZE_MEM_P95_MAX = 35.0
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
    driver_spec = INSTANCE_CATALOG.get(m.driver_node_type)
    if not driver_spec or m.drv_mem_p95 is None:
        return None
    used = driver_spec.memory_gb * m.drv_mem_p95 / 100.0
    if m.topology == "multi":
        worker_spec = INSTANCE_CATALOG.get(_worker_node_type(m))
        if not worker_spec or m.wrk_mem_p95 is None or not m.worker_count:
            return None
        used += worker_spec.memory_gb * m.wrk_mem_p95 / 100.0 * m.worker_count
    return round(used, 4)


def _additive_cores(m: DagMetrics) -> float | None:
    driver_spec = INSTANCE_CATALOG.get(m.driver_node_type)
    if not driver_spec or m.drv_cpu_p95 is None:
        return None
    cores = driver_spec.vcpus * m.drv_cpu_p95 / 100.0
    if m.topology == "multi":
        worker_spec = INSTANCE_CATALOG.get(_worker_node_type(m))
        if not worker_spec or m.wrk_cpu_p95 is None or not m.worker_count:
            return None
        cores += worker_spec.vcpus * m.wrk_cpu_p95 / 100.0 * m.worker_count
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


def _projected_wall_p95_after_collapse(
    m: DagMetrics, sizing: SingleNodeSizing
) -> float | None:
    if not sizing.node_type or m.topology != "multi":
        return m.wall_p95_min
    return round(m.wall_p95_min * _collapse_wall_inflation(m), 1)


def _collapse_wall_inflation(m: DagMetrics) -> float:
    worker_activity = max(
        (m.wrk_cpu_p50 or 0.0) / 85.0,
        (m.wrk_cpu_p95 or 0.0) / 85.0,
        (m.wrk_mem_p95 or 0.0) / 82.0,
    )
    worker_activity = min(max(worker_activity, 0.0), 1.0)
    worker_burst = min(max((m.wrk_cpu_p95 or 0.0) / 85.0, 0.0), 1.0)
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
    if m.arm_avg_total_cost_estimate_usd is not None:
        return m.arm_avg_total_cost_estimate_usd
    return m.arm_avg_cost_per_run_usd


def _wall_minutes_for_cost(m: DagMetrics) -> float | None:
    if m.wall_p50_min and m.wall_p50_min > 0:
        return m.wall_p50_min
    if m.wall_p95_min and m.wall_p95_min > 0:
        return m.wall_p95_min
    return None


def _ec2_cost_for_runtime(
    node_type: str | None,
    wall_minutes: float | None,
    *,
    spot: bool = False,
    count: int = 1,
) -> float | None:
    price = _instance_price(node_type, spot=spot)
    if price is None or wall_minutes is None:
        return None
    return price * wall_minutes / 60.0 * count


def estimate_projected_total_cost(
    m: DagMetrics,
    rec_driver: str,
    rec_workers: int,
    *,
    rec_worker: str | None = None,
) -> float | None:
    current_basis = _current_cost_basis(m)
    current_vcpus = _vcpus(m.driver_node_type) + (m.worker_count or 0) * _vcpus(
        m.worker_node_type
    )
    rec_worker = (rec_worker or _worker_node_type(m)) if rec_workers > 0 else None
    rec_vcpus = _vcpus(rec_driver) + rec_workers * _vcpus(rec_worker)
    if current_vcpus <= 0 or rec_vcpus <= 0:
        return None
    current_wall_minutes = _wall_minutes_for_cost(m)
    if current_wall_minutes is None:
        return None

    current_dbu = (
        m.arm_avg_dbu_cost_usd
        if m.arm_avg_dbu_cost_usd is not None
        else max(current_basis - (m.arm_avg_ec2_cost_usd or 0.0), 0.0)
    )
    if rec_workers > 0:
        current_workers = m.worker_count or 0
        current_worker = _worker_node_type(m)
        if current_workers <= 0 or not rec_worker:
            return None
        wall_inflation = _worker_reduction_wall_inflation(
            m,
            current_workers,
            rec_workers,
        )
        projected_wall_minutes = current_wall_minutes * wall_inflation
        rec_dbu = current_dbu * rec_vcpus / current_vcpus * wall_inflation
        current_driver_ec2 = _ec2_cost_for_runtime(
            m.driver_node_type, current_wall_minutes, spot=False
        )
        rec_driver_ec2 = _ec2_cost_for_runtime(
            rec_driver, projected_wall_minutes, spot=False
        )
        if current_driver_ec2 is None or rec_driver_ec2 is None:
            return None
        current_worker_ec2 = max(
            (m.arm_avg_ec2_cost_usd or 0.0) - current_driver_ec2, 0.0
        )
        current_worker_price = _instance_price(current_worker)
        rec_worker_price = _instance_price(rec_worker)
        if current_worker_price is None or rec_worker_price is None:
            return None
        worker_price_ratio = (rec_workers * rec_worker_price) / (
            current_workers * current_worker_price
        )
        rec_worker_ec2 = current_worker_ec2 * worker_price_ratio * wall_inflation
        return round(rec_dbu + rec_worker_ec2 + rec_driver_ec2, 6)

    projected_wall_minutes = current_wall_minutes
    if m.topology == "multi":
        projected_wall_minutes *= _collapse_wall_inflation(m)
    wall_factor = projected_wall_minutes / current_wall_minutes
    rec_dbu = current_dbu * rec_vcpus / current_vcpus * wall_factor
    rec_ec2 = _ec2_cost_for_runtime(rec_driver, projected_wall_minutes, spot=False)
    if rec_ec2 is None:
        return None
    return round(rec_dbu + rec_ec2, 6)


def _collapse_cost_increases(m: DagMetrics, sizing: SingleNodeSizing) -> bool:
    if not sizing.node_type:
        return False
    projected = estimate_projected_total_cost(m, sizing.node_type, 0)
    current = _current_cost_basis(m)
    return projected is not None and current > 0 and projected >= current


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
    if m.drv_mem_p95 is None:
        return None
    current_spec = INSTANCE_CATALOG.get(m.driver_node_type)
    if not current_spec:
        return None
    used_mem_gb = current_spec.memory_gb * m.drv_mem_p95 / 100.0
    used_cores = current_spec.vcpus * (m.drv_cpu_p95 or 0.0) / 100.0
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
    worker_activity = max(
        (m.wrk_cpu_p50 or 0.0) / (_SINGLE_NODE_CPU_TARGET * 100.0),
        (m.wrk_cpu_p95 or 0.0) / (_SINGLE_NODE_CPU_TARGET * 100.0),
        (m.wrk_mem_p95 or 0.0) / (_SINGLE_NODE_MEM_TARGET * 100.0),
    )
    worker_activity = min(max(worker_activity, 0.0), 1.0)
    parallelism_loss = old_count / new_count - 1.0
    return 1.0 + parallelism_loss * worker_activity


def _worker_resize(m: DagMetrics) -> WorkerResize | None:
    if (
        m.topology != "multi"
        or not m.worker_count
        or m.wrk_mem_p95 is None
        or m.wrk_cpu_p95 is None
    ):
        return None

    current_worker = _worker_node_type(m)
    current_spec = INSTANCE_CATALOG.get(current_worker)
    current_price = _instance_price(current_worker)
    if not current_spec or current_price is None:
        return None

    per_node_mem_gb = current_spec.memory_gb * m.wrk_mem_p95 / 100.0
    per_node_cores = current_spec.vcpus * m.wrk_cpu_p95 / 100.0
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
        projected_wall = m.wall_p95_min * _worker_reduction_wall_inflation(
            m,
            m.worker_count,
            candidate_count,
        )
        if projected_wall > _SLA_INTERVAL_TARGET * _schedule_interval_minutes(m):
            count_blocked_sla = True
        else:
            rec_count = candidate_count

    return WorkerResize(candidate_worker, rec_count, count_blocked_sla)


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
    if (
        rec_driver is None
        or m.drv_mem_p95 is None
        or m.wrk_mem_p95 is None
        or not m.worker_node_type
        or not m.worker_count
    ):
        return None
    rec_mem = INSTANCE_CATALOG.get(rec_driver)
    worker_mem = INSTANCE_CATALOG.get(m.worker_node_type)
    current_driver_mem = INSTANCE_CATALOG.get(m.driver_node_type)
    if not rec_mem or not worker_mem or not current_driver_mem:
        return None

    driver_used_gb = current_driver_mem.memory_gb * m.drv_mem_p95 / 100.0
    worker_used_gb = worker_mem.memory_gb * m.wrk_mem_p95 / 100.0 * m.worker_count
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

    # Single-node branch
    if topo == "single":
        if m.drv_mem_p95 >= _DRIVER_OOM_P95:
            return "protect_oom_risk"
        if (
            m.drv_cpu_p95 < _DRIVER_DOWNSIZE_CPU_P95_MAX
            and m.drv_mem_p95 < _DRIVER_DOWNSIZE_MEM_P95_MAX
            and _driver_downsize_node(m)
        ):
            return "driver_downsize"
        return "healthy_single"

    # Multi-node branch: single-node-first, with narrow keep-multi exits.
    if topo == "multi":
        sizing = size_single_node(m)
        if sizing.blocked_reason == "needs_more_telemetry":
            return "needs_more_telemetry"
        if sizing.blocked_reason in {
            "keep_multi_memory",
            "keep_multi_compute",
            "keep_multi_balanced",
        }:
            return sizing.blocked_reason

        projected_wall = _projected_wall_p95_after_collapse(m, sizing)
        if (
            projected_wall is None
            or projected_wall > _SLA_INTERVAL_TARGET * _schedule_interval_minutes(m)
        ):
            return "keep_multi_sla"

        if (
            (m.drv_cpu_p95 or 0.0) >= _DRIVER_CPU_BOUND_P95
            and (m.wrk_cpu_p50 or 0.0) >= 50.0
            and (m.wrk_mem_p95 or 0.0) >= 60.0
        ):
            return "keep_multi_balanced"

        if _collapse_cost_increases(m, sizing):
            return "keep_multi_cost"

        return "collapse_to_single"

    # Autoscale
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
        if worker_count == 2 and (m.drv_mem_p95 or 100) < _DRIVER_MEM_PRESSURE_P95:
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
    if cohort == "collapse_to_single" and sizing and sizing.node_type:
        actions = ["collapse_to_single"]
        rec_driver = sizing.node_type
        rec_worker = None
        rec_workers = 0
    if cohort in _KEEP_MULTI_COHORTS and rec_spec:
        actions = ["keep_multi_node"]
        current_worker = _worker_node_type(m)
        current_workers = m.worker_count or 0
        proposed_driver = _driver_minimize_node(m) or rec_spec.driver_node_type
        worker_resize = _worker_resize(m)
        proposed_worker = worker_resize.node_type if worker_resize else current_worker
        proposed_workers = (
            worker_resize.worker_count if worker_resize else current_workers
        )
        proposed_actions = [
            "reduce_driver" if proposed_driver != m.driver_node_type else "keep_driver",
            "reduce_worker_type"
            if proposed_worker != current_worker
            else "keep_worker_type",
        ]
        if worker_resize and worker_resize.count_blocked_sla:
            proposed_actions.append("worker_count_blocked_sla")
        else:
            proposed_actions.append(
                "reduce_worker_count"
                if proposed_workers != current_workers
                else "keep_worker_count"
            )

        current_cost = _current_cost_basis(m)
        projected_cost = estimate_projected_total_cost(
            m,
            proposed_driver,
            proposed_workers,
            rec_worker=proposed_worker,
        )
        if (
            projected_cost is not None
            and current_cost > 0
            and projected_cost < current_cost
        ):
            rec_driver = proposed_driver
            rec_worker = proposed_worker
            rec_workers = proposed_workers
            actions.extend(proposed_actions)
        else:
            blocked_cost_per_run = projected_cost
            driver_only_cost = estimate_projected_total_cost(
                m,
                proposed_driver,
                current_workers,
                rec_worker=current_worker,
            )
            keep_driver_change = (
                proposed_driver != m.driver_node_type
                and driver_only_cost is not None
                and current_cost > 0
                and driver_only_cost < current_cost
            )
            rec_driver = proposed_driver if keep_driver_change else m.driver_node_type
            rec_worker = current_worker
            rec_workers = current_workers
            actions.append("reduce_driver" if keep_driver_change else "keep_driver")
            actions.append("resize_blocked_cost")

        if cohort == "keep_multi_cost":
            rejected_sizing = size_single_node(m)
            if rejected_sizing.node_type:
                rejected_cost = estimate_projected_total_cost(
                    m, rejected_sizing.node_type, 0
                )
                if rejected_cost is not None:
                    blocked_cost_per_run = (
                        rejected_cost
                        if blocked_cost_per_run is None
                        else max(blocked_cost_per_run, rejected_cost)
                    )

        rec_preset_name = _multi_preset_for_worker(rec_worker) or rec_preset_name
        rec_spec = PRESET_CATALOG.get(rec_preset_name) if rec_preset_name else None
        if rec_spec and rec_workers is not None and rec_workers != rec_spec.num_workers:
            num_workers_override = rec_workers
        else:
            num_workers_override = None
    if cohort == "driver_downsize" and rec_preset_name:
        actions = ["reduce_driver"]
        rec_driver = _driver_downsize_node(m)
    if rec_spec and rec_driver and rec_driver != rec_spec.driver_node_type:
        driver_override_node_type_id = rec_driver
    if not actions:
        actions = ["no_change"]

    # Build projected metrics
    projected = ProjectedMetrics()
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
                m.drv_cpu_p50,
                m.wrk_cpu_p50,
                m.driver_node_type,
                m.worker_node_type,
                m.worker_count or 0,
            )
            est_cpu_p95, _uncertain_p95 = estimate_drv_cpu_after_collapse(
                m.drv_cpu_p95,
                m.wrk_cpu_p95,
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
                    min(round((m.wrk_cpu_p50 or 0) * ratio, 1), 95.0)
                    if m.wrk_cpu_p50 is not None
                    else None
                )
                projected.est_wrk_cpu_p95 = (
                    min(round((m.wrk_cpu_p95 or 0) * ratio, 1), 95.0)
                    if m.wrk_cpu_p95 is not None
                    else None
                )
                projected.est_wrk_mem_p95 = "unchanged"
                projected.est_drv_cpu_p50 = m.drv_cpu_p50
                projected.est_drv_mem_p95 = "unchanged"
            elif cohort == "right_size_to_memory_family":
                cur_worker_vcpus = _vcpus(m.worker_node_type)
                rec_worker_vcpus = _vcpus(rec_worker)
                ratio = (
                    cur_w / max(new_w, 1) * cur_worker_vcpus / max(rec_worker_vcpus, 1)
                )
                projected.est_wrk_cpu_p50 = (
                    min(round((m.wrk_cpu_p50 or 0) * ratio, 1), 95.0)
                    if m.wrk_cpu_p50 is not None
                    else None
                )
                projected.est_wrk_cpu_p95 = (
                    min(round((m.wrk_cpu_p95 or 0) * ratio, 1), 95.0)
                    if m.wrk_cpu_p95 is not None
                    else None
                )
                projected.est_wrk_mem_p95 = "unchanged"  # same GiB per node
                projected.est_drv_cpu_p50 = m.drv_cpu_p50
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
                m.drv_cpu_p50,
                m.driver_node_type,
                rec_driver,
                metric="cpu",
            )
            projected.est_drv_cpu_p95 = _project_utilization_pct(
                m.drv_cpu_p95,
                m.driver_node_type,
                rec_driver,
                metric="cpu",
            )
            projected_drv_mem = _project_utilization_pct(
                m.drv_mem_p95,
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
            projected.est_drv_cpu_p50 = m.drv_cpu_p50
            projected.est_drv_cpu_p95 = m.drv_cpu_p95
            projected.est_drv_mem_p95 = "unchanged"
            projected.est_wrk_cpu_p50 = m.wrk_cpu_p50
            projected.est_wrk_cpu_p95 = m.wrk_cpu_p95
            projected.est_wrk_mem_p95 = "unchanged"
        elif cohort in _KEEP_MULTI_COHORTS:
            projected.est_drv_cpu_p50 = _project_utilization_pct(
                m.drv_cpu_p50,
                m.driver_node_type,
                rec_driver,
                metric="cpu",
            )
            projected.est_drv_cpu_p95 = _project_utilization_pct(
                m.drv_cpu_p95,
                m.driver_node_type,
                rec_driver,
                metric="cpu",
            )
            projected_drv_mem = _project_utilization_pct(
                m.drv_mem_p95,
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
                m.wrk_cpu_p50,
                _worker_node_type(m),
                rec_worker,
                metric="cpu",
                count_ratio=worker_count_ratio,
            )
            projected.est_wrk_cpu_p95 = _project_utilization_pct(
                m.wrk_cpu_p95,
                _worker_node_type(m),
                rec_worker,
                metric="cpu",
                count_ratio=worker_count_ratio,
            )
            projected_wrk_mem = _project_utilization_pct(
                m.wrk_mem_p95,
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
        total_dbu_list_cost_usd                          AS cost_usd,
        total_dbu_list_cost_usd                          AS dbu_cost_usd,
        total_ec2_cost_calculated_usd                    AS ec2_cost_usd,
        ec2_spot_hours,
        ec2_on_demand_hours,
        total_cost_usd                                   AS total_cost_usd,
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
        CASE
            WHEN REGEXP_LIKE(
                COALESCE(worker_node_type, driver_node_type),
                '^[a-z][a-z0-9]*[0-9]g[a-z]?\\.')
            THEN 'arm' ELSE 'x86'
        END AS arch
    FROM dw_databricks_health.fact_databricks_dag_run
    WHERE dt_dag_run_started >= CURRENT_DATE - INTERVAL '{days}' DAY
      AND airflow_dag_id LIKE 'bietlejuice.%'
      AND airflow_dag_id IS NOT NULL
      AND NOT REGEXP_LIKE(airflow_dag_id, '__validation$')
      AND is_job_on_interactive = FALSE
      AND is_any_task_failed = FALSE
      AND is_any_databricks_run_failed = FALSE
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
        SUM(cost_usd)                                                             AS config_cost_usd,
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
        SUM(cost_usd)                                                             AS total_cost_usd
    FROM arm_runs
    GROUP BY airflow_dag_id
),
dominant_config AS (
    SELECT
        config_runs.*,
        ROUND(config_runs.config_run_count / CAST(dag_totals.total_run_count AS DOUBLE), 4)
                                                                                  AS dominant_config_run_share,
        ROUND(config_runs.config_cost_usd / NULLIF(dag_totals.total_cost_usd, 0), 4)
                                                                                  AS dominant_config_cost_share,
        ROW_NUMBER() OVER (
            PARTITION BY config_runs.airflow_dag_id
            ORDER BY config_runs.config_cost_usd DESC, config_runs.config_run_count DESC
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
        ROUND(SUM(cost_usd), 4)                                                    AS arm_total_cost_usd,
        ROUND(AVG(cost_usd), 6)                                                    AS arm_avg_cost_per_run_usd,
        ROUND(SUM(total_cost_usd), 4)                                              AS arm_total_cost_estimate_usd,
        ROUND(AVG(total_cost_usd), 6)                                              AS arm_avg_total_cost_estimate_usd,
        ROUND(SUM(ec2_cost_usd), 4)                                                AS arm_total_ec2_cost_usd,
        ROUND(AVG(ec2_cost_usd), 6)                                                AS arm_avg_ec2_cost_usd,
        ROUND(SUM(dbu_cost_usd), 4)                                                AS arm_total_dbu_cost_usd,
        ROUND(AVG(dbu_cost_usd), 6)                                                AS arm_avg_dbu_cost_usd,
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
        BOOL_OR(dbu_negotiated_price_missing)                                     AS dbu_negotiated_price_missing
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
        total_dbu_list_cost_usd                          AS cost_usd,
        total_wall_clock_seconds,
        weighted_avg_p50_driver_cpu_busy_percent         AS drv_cpu_p50,
        weighted_avg_p95_driver_cpu_busy_percent         AS drv_cpu_p95,
        weighted_avg_p95_driver_mem_used_percent         AS drv_mem_p95,
        weighted_avg_p95_driver_cpu_wait_percent         AS drv_wait_p95,
        weighted_avg_p50_worker_cpu_busy_percent         AS wrk_cpu_p50,
        weighted_avg_p95_worker_cpu_busy_percent         AS wrk_cpu_p95,
        weighted_avg_p95_worker_mem_used_percent         AS wrk_mem_p95,
        weighted_avg_p95_worker_cpu_wait_percent         AS wrk_wait_p95,
        CASE
            WHEN REGEXP_LIKE(
                COALESCE(worker_node_type, driver_node_type),
                '^[a-z][a-z0-9]*[0-9]g[a-z]?\\.')
            THEN 'arm' ELSE 'x86'
        END AS arch
    FROM dw_databricks_health.fact_databricks_dag_run
    WHERE dt_dag_run_started >= CURRENT_DATE - INTERVAL '{days}' DAY
      AND airflow_dag_id LIKE 'bietlejuice.%'
      AND airflow_dag_id IS NOT NULL
      AND NOT REGEXP_LIKE(airflow_dag_id, '__validation$')
      AND is_job_on_interactive = FALSE
      AND is_any_task_failed = FALSE
      AND is_any_databricks_run_failed = FALSE
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
        SUM(cost_usd)                                                             AS config_cost_usd
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
        SUM(cost_usd)                                                             AS total_cost_usd
    FROM amd_pool
    GROUP BY airflow_dag_id
),
dominant_config AS (
    SELECT
        config_runs.*,
        ROUND(config_runs.config_run_count / CAST(dag_totals.total_run_count AS DOUBLE), 4)
                                                                                  AS dominant_config_run_share,
        ROUND(config_runs.config_cost_usd / NULLIF(dag_totals.total_cost_usd, 0), 4)
                                                                                  AS dominant_config_cost_share,
        ROW_NUMBER() OVER (
            PARTITION BY config_runs.airflow_dag_id
            ORDER BY config_runs.config_cost_usd DESC, config_runs.config_run_count DESC
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
        ROUND(SUM(cost_usd), 4)                                                    AS arm_total_cost_usd,
        ROUND(AVG(cost_usd), 6)                                                    AS arm_avg_cost_per_run_usd,
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
        ROUND(APPROX_PERCENTILE(wrk_wait_p95, 0.95), 1)                           AS wrk_wait_p95
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
        est_cpu, uncertain = estimate_drv_cpu_after_collapse(
            m.drv_cpu_p50,
            m.wrk_cpu_p50,
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

    _print_cohort_summary(recs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
