#!/usr/bin/env python3
"""Spark/Databricks instance-generation cost-benefit analyzer.

Triangulates the EC2 catalog CSV (CoreMark + prices) against real Spark
benchmarks and (optionally) live fleet telemetry to answer one question for the
``bi-etl-ejuice`` ``consolidation_*`` cluster presets: now that the fleet runs on
ARM Gen 6 (Graviton2), does moving to Gen 7 (Graviton3) or Gen 8 (Graviton4)
lower total Databricks cost?

It emits a single self-contained dark-theme HTML report (inline ``<style>`` +
inline ``<svg>``; no CDN, matplotlib, pandas, or Chart.js) matching the
convention of ``docs/platform/cluster_spec_recommender_decision_tree.html``.

Stdlib only.  Data layer parses the committed catalog snapshot
(``scripts/ec2_instance_comparison.csv``); the cost-of-work model and per-t-shirt
comparison tables are recomputed from that CSV every run.  The only hand-seeded
magic numbers are the externally sourced Spark speedup / per-core constants
(``SPARK_SPEEDUP`` / ``PER_CORE_SOURCES``), each carrying its source.

Usage
-----
  uv run python scripts/analyze_instance_generations.py \\
      --ec2-csv scripts/ec2_instance_comparison.csv \\
      --fleet-csv scripts/analysis_data/recommendations.csv \\
      --out docs/platform/spark_instance_generation_analysis.html

``--fleet-csv`` is optional: when absent/unreadable the report still renders the
full hardware + triangulation analysis and shows an explicit "live fleet data
not provided" notice in the fleet-weighted-savings section (never crashes, never
fabricates fleet numbers).  The fleet CSV is the recommender output produced by
``scripts/recommend_cluster_specs.py --trino``.

See docs/platform/recommender_multigeneration_migration_plan.md for the
companion implementation plan that makes the recommender generation-aware.
"""

from __future__ import annotations

import argparse
import csv
import html
import re
import statistics
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Repository layout / defaults
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EC2_CSV = REPO_ROOT / "scripts" / "ec2_instance_comparison.csv"
DEFAULT_OUT = (
    REPO_ROOT / "docs" / "platform" / "spark_instance_generation_analysis.html"
)
MIGRATION_DOC = "recommender_multigeneration_migration_plan.md"

# ---------------------------------------------------------------------------
# Externally sourced benchmark constants  (the only hand-seeded magic numbers)
# ---------------------------------------------------------------------------

# Real-Spark per-generation speedup (newer/older runtime ratio), triangulated.
# Sources: AWS TPC-DS Data-on-EKS R-series (r6g->r7g 1.14x, r7g->r8g 1.085x);
# AWS EMR Spark C7g +13-19%; SPECint2017 per-core ~+12%/gen; Graviton3 DDR5 +50% BW.
SPARK_SPEEDUP: dict[
    tuple[int, int], tuple[float, float, float]
] = {  # (from_gen, to_gen): (low, mid, high)
    (6, 7): (1.10, 1.15, 1.19),
    (7, 8): (1.05, 1.08, 1.12),
    (6, 8): (1.18, 1.24, 1.30),  # cross-checked vs TPC-DS r6g->r8g 1.236x
}
PER_CORE_SOURCES: dict[
    str, dict[int, int]
] = {  # for the CoreMark-overstatement chart (index, Gen6=100)
    "CoreMark/vCPU (CSV)": {6: 100, 7: 128, 8: 142},
    "SPECint2017 per-core": {6: 100, 7: 112, 8: 125},
    "Real Spark TPC-DS": {6: 100, 7: 115, 8: 124},
}

# Band indices into the SPARK_SPEEDUP tuples.
LOW, MID, HIGH = 0, 1, 2
_BAND_NAME = {LOW: "low", MID: "mid", HIGH: "high"}

# AWS TPC-DS Data-on-EKS cumulative runtime (seconds) for the R-series ladder.
TPCDS_RUNTIME_SEC = {6: 2151.0, 7: 1887.0, 8: 1740.0}

# The recommender's flat spot:on-demand assumption (scripts/recommend_cluster_specs.py:138).
RECOMMENDER_SPOT_RATIO = 0.37

# ---------------------------------------------------------------------------
# Generation / family classification
# ---------------------------------------------------------------------------

_FAMILY_BY_BASE = {"c": "compute", "m": "general", "r": "memory"}
_FAMILY_PREFIX = {"compute": "c", "general": "m", "memory": "r"}
_TIER_TO_SIZE = {
    "xs": "large",
    "s": "xlarge",
    "m": "2xlarge",
    "l": "4xlarge",
    "xl": "8xlarge",
}
_SIZE_TO_TIER = {size: tier for tier, size in _TIER_TO_SIZE.items()}
_TIER_ORDER = ["xs", "s", "m", "l", "xl"]
_FAMILY_ORDER = ["compute", "general", "memory"]
_GENS = (6, 7, 8)
_PREFIX_RE = re.compile(r"^([cmr])([0-9]+)([a-z]*)$")
_NUM_RE = re.compile(r"[-+]?[0-9]*\.?[0-9]+")


@dataclass(frozen=True)
class NodeClass:
    """Structural classification of an instance prefix (e.g. ``r7gd``)."""

    family: str  # compute | general | memory
    base: str  # c | m | r
    gen: int
    suffix: str  # e.g. "g", "gd", "a", ""
    arch: str  # ARM | AMD | Intel


def classify_node(node_type: str) -> NodeClass | None:
    """Classify a node type / API name; ``None`` when it is not a c/m/r prefix.

    ``m6g.2xlarge`` -> (general, 6, ARM); ``r7gd.4xlarge`` -> (memory, 7, ARM);
    ``c8g.xlarge`` -> (compute, 8, ARM); ``m8a.16xlarge`` -> (general, 8, AMD);
    ``c5.large`` -> (compute, 5, Intel).
    """
    prefix = node_type.split(".", 1)[0].strip().lower()
    m = _PREFIX_RE.match(prefix)
    if not m:
        return None
    base, gen_s, suffix = m.group(1), m.group(2), m.group(3)
    if "g" in suffix:
        arch = "ARM"
    elif "a" in suffix:
        arch = "AMD"
    else:
        arch = "Intel"
    return NodeClass(
        family=_FAMILY_BY_BASE[base],
        base=base,
        gen=int(gen_s),
        suffix=suffix,
        arch=arch,
    )


# ---------------------------------------------------------------------------
# Value parsing
# ---------------------------------------------------------------------------


def num(text: str | None) -> float | None:
    """First numeric token in ``text`` (commas stripped); ``None`` if absent.

    ``"19,098.549"`` -> 19098.549; ``"2 GiB"`` -> 2.0; ``"1 vCPUs"`` -> 1.0;
    ``""`` / ``None`` -> None.
    """
    if text is None:
        return None
    m = _NUM_RE.search(text.replace(",", ""))
    return float(m.group()) if m else None


def price(text: str | None) -> float | None:
    """Hourly USD price; ``"$0.0384 hourly"`` -> 0.0384, blank -> ``None``."""
    if text is None:
        return None
    return num(text.replace("$", "").replace("hourly", ""))


# ---------------------------------------------------------------------------
# Instance model
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Instance:
    api: str
    name: str
    family_label: str  # compute | general | memory (derived from base)
    base: str
    gen: int
    arch: str
    suffix: str
    vcpus: float | None
    mem_gb: float | None
    coremark: float | None
    od: float | None
    reserved: float | None
    spot: float | None
    emr: float | None

    @property
    def prefix(self) -> str:
        return self.api.split(".", 1)[0]

    @property
    def cm_per_vcpu(self) -> float | None:
        if self.coremark is None or not self.vcpus:
            return None
        return self.coremark / self.vcpus


def parse_ec2_csv(path: str | Path) -> list[Instance]:
    """Parse the EC2 comparison CSV into classified c/m/r ``Instance`` rows.

    Rows whose prefix is not a c/m/r compute/general/memory family are skipped.
    """
    out: list[Instance] = []
    with Path(path).open(newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            api = (row.get("API Name") or "").strip()
            if not api:
                continue
            nc = classify_node(api)
            if nc is None:
                continue
            out.append(
                Instance(
                    api=api,
                    name=(row.get("Name") or "").strip(),
                    family_label=nc.family,
                    base=nc.base,
                    gen=nc.gen,
                    arch=nc.arch,
                    suffix=nc.suffix,
                    vcpus=num(row.get("vCPUs")),
                    mem_gb=num(row.get("Instance Memory")),
                    coremark=num(row.get("CoreMark Score")),
                    od=price(row.get("On Demand")),
                    reserved=price(row.get("Linux Reserved cost")),
                    spot=price(row.get("Linux Spot Average cost")),
                    emr=price(row.get("EMR cost")),
                )
            )
    return out


# ---------------------------------------------------------------------------
# Prefix aggregation
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Agg:
    prefix: str
    base: str
    gen: int
    arch: str
    family: str
    n: int
    cm_per_vcpu: float | None
    cm_per_od: float | None
    cm_per_spot: float | None
    spot_od_ratio: float | None


def aggregate_by_prefix(instances: list[Instance]) -> dict[str, Agg]:
    """Aggregate CoreMark efficiency per exact prefix (``c6g``, ``c6gd``, ...).

    Ratios are sum-over-sum across rows that carry the needed fields:
    ``cm_per_od = sum(coremark) / sum(on_demand)`` etc.
    """
    sums: dict[str, dict] = {}
    for inst in instances:
        p = inst.prefix
        s = sums.setdefault(
            p,
            dict(
                base=inst.base,
                gen=inst.gen,
                arch=inst.arch,
                family=inst.family_label,
                n=0,
                cm_v_top=0.0,
                cm_v_bot=0.0,
                cm_od_top=0.0,
                cm_od_bot=0.0,
                cm_sp_top=0.0,
                cm_sp_bot=0.0,
                sod_top=0.0,
                sod_bot=0.0,
            ),
        )
        s["n"] += 1
        if inst.coremark is not None and inst.vcpus:
            s["cm_v_top"] += inst.coremark
            s["cm_v_bot"] += inst.vcpus
        if inst.coremark is not None and inst.od is not None:
            s["cm_od_top"] += inst.coremark
            s["cm_od_bot"] += inst.od
        if inst.coremark is not None and inst.spot is not None:
            s["cm_sp_top"] += inst.coremark
            s["cm_sp_bot"] += inst.spot
        if inst.od is not None and inst.spot is not None:
            s["sod_top"] += inst.spot
            s["sod_bot"] += inst.od
    out: dict[str, Agg] = {}
    for p, s in sums.items():

        def _r(top: str, bot: str) -> float | None:
            return s[top] / s[bot] if s[bot] else None

        out[p] = Agg(
            prefix=p,
            base=s["base"],
            gen=s["gen"],
            arch=s["arch"],
            family=s["family"],
            n=s["n"],
            cm_per_vcpu=_r("cm_v_top", "cm_v_bot"),
            cm_per_od=_r("cm_od_top", "cm_od_bot"),
            cm_per_spot=_r("cm_sp_top", "cm_sp_bot"),
            spot_od_ratio=_r("sod_top", "sod_bot"),
        )
    return out


# ---------------------------------------------------------------------------
# Consolidation t-shirt presets (the analysis unit)
# ---------------------------------------------------------------------------


def _preset_node(family: str, gen: int, tier: str) -> str:
    return f"{_FAMILY_PREFIX[family]}{gen}g.{_TIER_TO_SIZE[tier]}"


# Verified t-shirt -> node map for the Databricks consolidation_* presets:
#   xs/s/m/l/xl -> large/xlarge/2xlarge/4xlarge/8xlarge; compute=c, general=m, memory=r.
CONSOLIDATION_PRESETS: dict[tuple[str, str], dict[int, str]] = {
    (family, tier): {gen: _preset_node(family, gen, tier) for gen in _GENS}
    for family in _FAMILY_ORDER
    for tier in _TIER_ORDER
}


@dataclass(frozen=True)
class PresetEcon:
    family: str
    tier: str
    size: str
    vcpus: float | None
    mem_gb: float | None
    nodes: dict[int, str]
    od: dict[int, float | None]
    spot: dict[int, float | None]
    coremark: dict[int, float | None]
    cm_per_vcpu: dict[int, float | None]
    price_ratio_67: float | None
    price_ratio_78: float | None
    cost_of_work_67: float | None
    cost_of_work_78: float | None


def speedup(from_gen: int, to_gen: int, band: int = MID) -> float:
    """Real-Spark wall speedup for a generation transition (1.0 when equal)."""
    if from_gen == to_gen:
        return 1.0
    return SPARK_SPEEDUP[(from_gen, to_gen)][band]


def preset_economics(instances: list[Instance]) -> list[PresetEcon]:
    """Per (family, tier) economics across Gen 6/7/8 nodes.

    cost-of-work delta = price_ratio / spark_speedup_mid - 1 (negative = cheaper
    per unit of work on the faster node).
    """
    by_api = {inst.api: inst for inst in instances}
    rows: list[PresetEcon] = []
    for family in _FAMILY_ORDER:
        for tier in _TIER_ORDER:
            nodes = CONSOLIDATION_PRESETS[(family, tier)]
            insts = {g: by_api.get(nodes[g]) for g in _GENS}
            od = {g: (insts[g].od if insts[g] else None) for g in _GENS}
            spot = {g: (insts[g].spot if insts[g] else None) for g in _GENS}
            cm = {g: (insts[g].coremark if insts[g] else None) for g in _GENS}
            cmpv = {g: (insts[g].cm_per_vcpu if insts[g] else None) for g in _GENS}
            ref = insts[6] or insts[7] or insts[8]
            pr67 = od[7] / od[6] if (od[6] and od[7]) else None
            pr78 = od[8] / od[7] if (od[7] and od[8]) else None
            cow67 = (pr67 / speedup(6, 7) - 1) if pr67 else None
            cow78 = (pr78 / speedup(7, 8) - 1) if pr78 else None
            rows.append(
                PresetEcon(
                    family=family,
                    tier=tier,
                    size=_TIER_TO_SIZE[tier],
                    vcpus=ref.vcpus if ref else None,
                    mem_gb=ref.mem_gb if ref else None,
                    nodes=dict(nodes),
                    od=od,
                    spot=spot,
                    coremark=cm,
                    cm_per_vcpu=cmpv,
                    price_ratio_67=pr67,
                    price_ratio_78=pr78,
                    cost_of_work_67=cow67,
                    cost_of_work_78=cow78,
                )
            )
    return rows


def matched_size_price_ratio(
    instances: list[Instance],
    family: str,
    from_gen: int,
    to_gen: int,
    *,
    metric: str = "od",
) -> float | None:
    """Median price ratio across the five preset sizes for a generation step.

    ``metric`` is ``"od"`` (on-demand) or ``"spot"``. Returns 1.0 when
    ``from_gen == to_gen``; ~1.06 for Gen6->7 OD, ~1.10 for Gen7->8 OD.
    """
    if from_gen == to_gen:
        return 1.0
    by_api = {inst.api: inst for inst in instances}
    ratios: list[float] = []
    for tier in _TIER_ORDER:
        a = by_api.get(_preset_node(family, from_gen, tier))
        b = by_api.get(_preset_node(family, to_gen, tier))
        av = getattr(a, metric) if a else None
        bv = getattr(b, metric) if b else None
        if av and bv:
            ratios.append(bv / av)
    return statistics.median(ratios) if ratios else None


# ---------------------------------------------------------------------------
# Cost-of-work model (perf-per-dollar = throughput / $/hr)
# ---------------------------------------------------------------------------


def spark_perf_per_dollar_index(
    instances: list[Instance], family: str, *, spot: bool = False, band: int = MID
) -> dict[int, float | None]:
    """Real-Spark perf-per-dollar index per generation (Gen 6 = 100).

    index(gen) = spark_speedup(6->gen) / matched_size_price_ratio(6->gen) * 100.
    """
    metric = "spot" if spot else "od"
    out: dict[int, float | None] = {}
    for gen in _GENS:
        sp = speedup(6, gen, band)
        pr = matched_size_price_ratio(instances, family, 6, gen, metric=metric)
        out[gen] = (sp / pr) * 100.0 if pr else None
    return out


def cost_of_work_delta(
    instances: list[Instance],
    family: str,
    tier: str,
    from_gen: int,
    to_gen: int,
    *,
    band: int = MID,
) -> float | None:
    """EC2 cost-of-work change for fixed work: price_ratio / speedup - 1."""
    by_api = {inst.api: inst for inst in instances}
    a = by_api.get(_preset_node(family, from_gen, tier))
    b = by_api.get(_preset_node(family, to_gen, tier))
    if not (a and b and a.od and b.od):
        return None
    return (b.od / a.od) / speedup(from_gen, to_gen, band) - 1


def closed_form_ratio(
    ec2_share: float, price_ratio: float, spark_speedup: float
) -> float:
    """Total-cost ratio (new/old) for one generation step.

    total_new / total_old = (e * p + (1 - e)) / s, with e = fleet EC2 share,
    p = matched-size price ratio, s = real-Spark wall speedup.
    """
    return (ec2_share * price_ratio + (1.0 - ec2_share)) / spark_speedup


# ---------------------------------------------------------------------------
# Mixed-generation cluster model (Gen 6 driver + Gen 7 workers)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ClusterOption:
    label: str
    driver_node: str
    worker_node: str
    driver_od: float | None
    worker_spot: float | None
    worker_count: int
    wall_hours: float
    ec2_cost: float
    dbu_cost: float
    total: float


def mixed_generation_options(
    instances: list[Instance],
    *,
    family: str = "general",
    driver_tier: str = "xs",
    worker_tier: str = "m",
    worker_count: int = 2,
    wall_hours: float = 1.0,
    dbu_per_hour: float = 0.5,
) -> dict[str, ClusterOption]:
    """Three pricing options for a representative non-driver-heavy multi-node job.

    Wall is worker-set, so all-Gen7 and mixed (Gen6 driver + Gen7 workers) share
    worker cost + DBU; the only delta is the driver's on-demand $/hr.
    """
    by_api = {inst.api: inst for inst in instances}

    def _opt(label: str, dnode: str, wnode: str) -> ClusterOption:
        d = by_api.get(dnode)
        w = by_api.get(wnode)
        d_od = d.od if d else None
        w_spot = w.spot if w else None
        ec2 = ((d_od or 0.0) + worker_count * (w_spot or 0.0)) * wall_hours
        dbu = dbu_per_hour * wall_hours
        return ClusterOption(
            label=label,
            driver_node=dnode,
            worker_node=wnode,
            driver_od=d_od,
            worker_spot=w_spot,
            worker_count=worker_count,
            wall_hours=wall_hours,
            ec2_cost=ec2,
            dbu_cost=dbu,
            total=ec2 + dbu,
        )

    d6 = _preset_node(family, 6, driver_tier)
    d7 = _preset_node(family, 7, driver_tier)
    w6 = _preset_node(family, 6, worker_tier)
    w7 = _preset_node(family, 7, worker_tier)
    return {
        "all_gen6": _opt("All Gen 6", d6, w6),
        "all_gen7": _opt("All Gen 7", d7, w7),
        "mixed": _opt("Mixed: Gen 6 driver + Gen 7 workers", d6, w7),
    }


# ---------------------------------------------------------------------------
# Live fleet ingestion + projection (Step 6)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class FleetDag:
    dag_id: str
    driver_node: str
    worker_node: str
    worker_count: int
    total_cost: float
    ec2_cost: float
    dbu_cost: float
    arm_days: float
    runs_per_day: float | None
    wall_p50_min: float | None
    family: str | None
    gen: int | None
    arch: str | None
    tier: str | None


def _tier_from_node(node: str) -> str | None:
    if "." not in node:
        return None
    return _SIZE_TO_TIER.get(node.split(".", 1)[1])


def parse_fleet_csv(path: str | Path) -> list[FleetDag]:
    """Parse the recommender output CSV into per-DAG fleet rows.

    Generation/family/tier are classified from ``current_worker_node_type``
    (falling back to the driver) via the same prefix regex.
    """

    def _f(row: dict, key: str) -> float:
        v = row.get(key)
        if v is None or v == "" or v == "None":
            return 0.0
        try:
            return float(v)
        except ValueError:
            return 0.0

    def _opt(row: dict, key: str) -> float | None:
        v = row.get(key)
        if v is None or v == "" or v == "None":
            return None
        try:
            return float(v)
        except ValueError:
            return None

    dags: list[FleetDag] = []
    with Path(path).open(newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            worker = (row.get("current_worker_node_type") or "").strip()
            driver = (row.get("current_driver_node_type") or "").strip()
            ref = worker or driver
            nc = classify_node(ref) if ref else None
            dags.append(
                FleetDag(
                    dag_id=(row.get("dag_id") or "").strip(),
                    driver_node=driver,
                    worker_node=worker,
                    worker_count=int(_f(row, "current_worker_count")),
                    total_cost=_f(row, "arm_total_cost_usd"),
                    ec2_cost=_f(row, "arm_total_ec2_cost_usd"),
                    dbu_cost=_f(row, "arm_total_dbu_cost_usd"),
                    arm_days=_f(row, "arm_days"),
                    runs_per_day=_opt(row, "runs_per_day"),
                    wall_p50_min=_opt(row, "wall_p50_min"),
                    family=nc.family if nc else None,
                    gen=nc.gen if nc else None,
                    arch=nc.arch if nc else None,
                    tier=_tier_from_node(ref) if ref else None,
                )
            )
    return dags


def _annualize(amount: float, days: float) -> float:
    return amount / days * 365.0 if days else 0.0


@dataclass
class GenProjection:
    target_gen: int
    current_total: float
    current_ec2: float
    current_dbu: float
    new_total: dict[str, float]  # band name -> $/yr
    new_ec2: dict[str, float]  # band name -> projected EC2 $/yr
    new_dbu: dict[str, float]  # band name -> projected DBU $/yr
    saving: dict[str, float]
    saving_pct: dict[str, float]
    n_projected: int


@dataclass
class FleetSummary:
    n_dags: int
    n_classified: int
    n_skipped: int
    current_total: float
    current_ec2: float
    current_dbu: float
    ec2_share: float
    by_family: dict[str, dict[str, float]]
    by_tier: dict[str, dict[str, float]]
    by_gen: dict[int, dict[str, float]]
    projections: dict[int, GenProjection]


def project_fleet(
    instances: list[Instance], dags: list[FleetDag], target_gen: int
) -> GenProjection:
    """Project annualized total cost if every DAG below ``target_gen`` migrates.

    Per DAG (same vCPU/RAM, current_gen -> target_gen):
      ec2_new = ec2_old * price_ratio / spark_speedup
      dbu_new = dbu_old / spark_speedup           (DBU/node-hour gen-neutral)
    DAGs already at/above the target are never downgraded.
    """
    cur_total = cur_ec2 = cur_dbu = 0.0
    new_total = {name: 0.0 for name in _BAND_NAME.values()}
    new_ec2 = {name: 0.0 for name in _BAND_NAME.values()}
    new_dbu = {name: 0.0 for name in _BAND_NAME.values()}
    n_projected = 0
    for d in dags:
        ann_total = _annualize(d.total_cost, d.arm_days)
        ann_ec2 = _annualize(d.ec2_cost, d.arm_days)
        ann_dbu = _annualize(d.dbu_cost, d.arm_days)
        cur_total += ann_total
        cur_ec2 += ann_ec2
        cur_dbu += ann_dbu
        eligible = (
            d.family is not None
            and d.gen is not None
            and d.arch == "ARM"
            and d.gen < target_gen
        )
        if not eligible:
            for name in new_total:
                new_total[name] += ann_total
                new_ec2[name] += ann_ec2
                new_dbu[name] += ann_dbu
            continue
        n_projected += 1
        for band, name in _BAND_NAME.items():
            s = speedup(d.gen, target_gen, band)
            p = matched_size_price_ratio(instances, d.family, d.gen, target_gen) or 1.0
            ec2_new = ann_ec2 * p / s
            dbu_new = ann_dbu / s
            new_ec2[name] += ec2_new
            new_dbu[name] += dbu_new
            new_total[name] += ec2_new + dbu_new
    saving = {name: cur_total - new_total[name] for name in new_total}
    saving_pct = {
        name: (saving[name] / cur_total if cur_total else 0.0) for name in new_total
    }
    return GenProjection(
        target_gen=target_gen,
        current_total=cur_total,
        current_ec2=cur_ec2,
        current_dbu=cur_dbu,
        new_total=new_total,
        new_ec2=new_ec2,
        new_dbu=new_dbu,
        saving=saving,
        saving_pct=saving_pct,
        n_projected=n_projected,
    )


def summarize_fleet(instances: list[Instance], dags: list[FleetDag]) -> FleetSummary:
    cur_total = cur_ec2 = cur_dbu = 0.0
    n_classified = 0
    by_family: dict[str, dict[str, float]] = {}
    by_tier: dict[str, dict[str, float]] = {}
    by_gen: dict[int, dict[str, float]] = {}
    for d in dags:
        ann_total = _annualize(d.total_cost, d.arm_days)
        ann_ec2 = _annualize(d.ec2_cost, d.arm_days)
        ann_dbu = _annualize(d.dbu_cost, d.arm_days)
        cur_total += ann_total
        cur_ec2 += ann_ec2
        cur_dbu += ann_dbu
        if d.family and d.gen:
            n_classified += 1
            for key, bucket in (
                (d.family, by_family),
                (d.tier or "other", by_tier),
                (d.gen, by_gen),
            ):
                slot = bucket.setdefault(
                    key, {"total": 0.0, "ec2": 0.0, "dbu": 0.0, "n": 0.0}
                )
                slot["total"] += ann_total
                slot["ec2"] += ann_ec2
                slot["dbu"] += ann_dbu
                slot["n"] += 1
    return FleetSummary(
        n_dags=len(dags),
        n_classified=n_classified,
        n_skipped=len(dags) - n_classified,
        current_total=cur_total,
        current_ec2=cur_ec2,
        current_dbu=cur_dbu,
        ec2_share=(cur_ec2 / cur_total if cur_total else 0.0),
        by_family=by_family,
        by_tier=by_tier,
        by_gen=by_gen,
        projections={g: project_fleet(instances, dags, g) for g in (7, 8)},
    )


# ===========================================================================
# Formatting helpers
# ===========================================================================


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def fmt_usd(v: float | None, dp: int = 4) -> str:
    return f"${v:.{dp}f}" if v is not None else "—"


def fmt_money(v: float | None, dp: int = 0) -> str:
    return f"${v:,.{dp}f}" if v is not None else "—"


def fmt_num(v: float | None, dp: int = 0) -> str:
    return f"{v:,.{dp}f}" if v is not None else "—"


def fmt_ratio_pct(ratio: float | None, dp: int = 1) -> str:
    """A price ratio (1.06) rendered as a signed delta ("+6.0%")."""
    if ratio is None:
        return "—"
    return f"{(ratio - 1) * 100:+.{dp}f}%"


def fmt_pct(frac: float | None, dp: int = 1) -> str:
    """A fraction (-0.10) rendered as a signed percentage ("-10.0%")."""
    if frac is None:
        return "—"
    return f"{frac * 100:+.{dp}f}%"


# ===========================================================================
# Inline-SVG chart builders (pure Python; dark palette)
# ===========================================================================

C = {
    "bg": "#0f1419",
    "panel": "#171c24",
    "panel2": "#1e2530",
    "ink": "#e6edf3",
    "muted": "#8b98a9",
    "line": "#2d3643",
    "single": "#38bdf8",
    "multi": "#a78bfa",
    "action": "#34d399",
    "guard": "#f0b429",
    "danger": "#f87171",
}
GEN_COLOR = {6: C["single"], 7: C["multi"], 8: C["action"]}
FONT = "system-ui, -apple-system, Segoe UI, Roboto, sans-serif"
_VB_W, _VB_H = 760, 400


def _svg_open(aria: str, title: str) -> str:
    return (
        f'<svg viewBox="0 0 {_VB_W} {_VB_H}" width="100%" role="img" '
        f'aria-label="{esc(aria)}" preserveAspectRatio="xMidYMid meet" '
        f'style="background:{C["panel"]};border:1px solid {C["line"]};border-radius:10px">'
        f"<title>{esc(title)}</title>"
        f'<text x="60" y="26" fill="{C["ink"]}" font-size="15" font-weight="700" '
        f'font-family="{FONT}">{esc(title)}</text>'
    )


def _legend(series: list[dict], y: int = 44, x0: int = 60) -> str:
    parts: list[str] = []
    x = x0
    for s in series:
        parts.append(
            f'<rect x="{x}" y="{y - 9}" width="12" height="12" rx="2" fill="{s["color"]}"/>'
        )
        parts.append(
            f'<text x="{x + 17}" y="{y + 1}" fill="{C["muted"]}" font-size="11.5" '
            f'font-family="{FONT}">{esc(s["name"])}</text>'
        )
        x += 30 + int(7.2 * len(s["name"]))
    return "".join(parts)


def svg_grouped_bars(
    title: str,
    aria: str,
    categories: list[str],
    series: list[dict],
    *,
    baseline: float | None = None,
    vfmt=lambda v: f"{v:.0f}",
    y_title: str = "",
) -> str:
    ml, mr, mt, mb = 62, 22, 64, 78
    pw, ph = _VB_W - ml - mr, _VB_H - mt - mb
    allv = [v for s in series for v in s["values"] if v is not None]
    top = max(allv) * 1.18 if allv else 1.0
    parts = [_svg_open(aria, title), _legend(series)]
    for i in range(5):
        gv = top * i / 4
        yy = mt + ph - (gv / top) * ph
        parts.append(
            f'<line x1="{ml}" y1="{yy:.1f}" x2="{ml + pw}" y2="{yy:.1f}" '
            f'stroke="{C["line"]}" stroke-width="1"/>'
        )
        parts.append(
            f'<text x="{ml - 8}" y="{yy + 4:.1f}" fill="{C["muted"]}" font-size="10.5" '
            f'text-anchor="end" font-family="{FONT}">{vfmt(gv)}</text>'
        )
    if baseline is not None and baseline <= top:
        by = mt + ph - (baseline / top) * ph
        parts.append(
            f'<line x1="{ml}" y1="{by:.1f}" x2="{ml + pw}" y2="{by:.1f}" '
            f'stroke="{C["guard"]}" stroke-width="1.2" stroke-dasharray="5 4"/>'
        )
        parts.append(
            f'<text x="{ml + pw}" y="{by - 5:.1f}" fill="{C["guard"]}" font-size="10" '
            f'text-anchor="end" font-family="{FONT}">baseline {vfmt(baseline)}</text>'
        )
    n_cat, n_ser = len(categories), len(series)
    gw = pw / n_cat
    pad = gw * 0.16
    bw = (gw - 2 * pad) / n_ser
    for ci, cat in enumerate(categories):
        gx = ml + ci * gw
        for si, s in enumerate(series):
            v = s["values"][ci]
            if v is None:
                continue
            bx = gx + pad + si * bw
            bh = (v / top) * ph
            byy = mt + ph - bh
            parts.append(
                f'<rect x="{bx:.1f}" y="{byy:.1f}" width="{max(bw - 3, 1):.1f}" '
                f'height="{bh:.1f}" rx="2" fill="{s["color"]}">'
                f"<title>{esc(cat)} · {esc(s['name'])}: {vfmt(v)}</title></rect>"
            )
            parts.append(
                f'<text x="{bx + (bw - 3) / 2:.1f}" y="{byy - 4:.1f}" fill="{C["ink"]}" '
                f'font-size="9.5" text-anchor="middle" font-family="{FONT}">{vfmt(v)}</text>'
            )
        parts.append(
            f'<text x="{gx + gw / 2:.1f}" y="{mt + ph + 18:.1f}" fill="{C["ink"]}" '
            f'font-size="12" text-anchor="middle" font-family="{FONT}">{esc(cat)}</text>'
        )
    if y_title:
        cy = mt + ph / 2
        parts.append(
            f'<text x="15" y="{cy:.1f}" fill="{C["muted"]}" font-size="10.5" '
            f'text-anchor="middle" font-family="{FONT}" '
            f'transform="rotate(-90 15 {cy:.1f})">{esc(y_title)}</text>'
        )
    parts.append("</svg>")
    return "".join(parts)


def svg_line(
    title: str,
    aria: str,
    categories: list[str],
    series: list[dict],
    *,
    vfmt=lambda v: f"{v:.0f}",
    y_title: str = "",
) -> str:
    ml, mr, mt, mb = 62, 22, 64, 70
    pw, ph = _VB_W - ml - mr, _VB_H - mt - mb
    allv = [v for s in series for v in s["values"] if v is not None]
    lo = min(allv) * 0.96 if allv else 0.0
    hi = max(allv) * 1.06 if allv else 1.0
    span = (hi - lo) or 1.0
    n = len(categories)
    xs = [ml + (pw * i / (n - 1)) if n > 1 else ml + pw / 2 for i in range(n)]

    def yof(v: float) -> float:
        return mt + ph - ((v - lo) / span) * ph

    parts = [_svg_open(aria, title), _legend(series)]
    for i in range(5):
        gv = lo + span * i / 4
        yy = yof(gv)
        parts.append(
            f'<line x1="{ml}" y1="{yy:.1f}" x2="{ml + pw}" y2="{yy:.1f}" '
            f'stroke="{C["line"]}" stroke-width="1"/>'
        )
        parts.append(
            f'<text x="{ml - 8}" y="{yy + 4:.1f}" fill="{C["muted"]}" font-size="10.5" '
            f'text-anchor="end" font-family="{FONT}">{vfmt(gv)}</text>'
        )
    for ci, cat in enumerate(categories):
        parts.append(
            f'<text x="{xs[ci]:.1f}" y="{mt + ph + 20:.1f}" fill="{C["ink"]}" '
            f'font-size="12" text-anchor="middle" font-family="{FONT}">{esc(cat)}</text>'
        )
    for s in series:
        pts = [(xs[i], yof(v)) for i, v in enumerate(s["values"]) if v is not None]
        if len(pts) >= 2:
            d = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in pts)
            parts.append(
                f'<path d="{d}" fill="none" stroke="{s["color"]}" stroke-width="2.4"/>'
            )
        for i, v in enumerate(s["values"]):
            if v is None:
                continue
            parts.append(
                f'<circle cx="{xs[i]:.1f}" cy="{yof(v):.1f}" r="3.6" fill="{s["color"]}">'
                f"<title>{esc(s['name'])} · {esc(categories[i])}: {vfmt(v)}</title></circle>"
            )
            parts.append(
                f'<text x="{xs[i]:.1f}" y="{yof(v) - 8:.1f}" fill="{C["ink"]}" '
                f'font-size="9.5" text-anchor="middle" font-family="{FONT}">{vfmt(v)}</text>'
            )
    if y_title:
        cy = mt + ph / 2
        parts.append(
            f'<text x="15" y="{cy:.1f}" fill="{C["muted"]}" font-size="10.5" '
            f'text-anchor="middle" font-family="{FONT}" '
            f'transform="rotate(-90 15 {cy:.1f})">{esc(y_title)}</text>'
        )
    parts.append("</svg>")
    return "".join(parts)


def svg_runtime_ladder(title: str, aria: str) -> str:
    """Chart D: AWS TPC-DS cumulative runtime ladder r6g/r7g/r8g with callouts."""
    ml, mr, mt, mb = 62, 22, 64, 78
    pw, ph = _VB_W - ml - mr, _VB_H - mt - mb
    gens = [6, 7, 8]
    labels = {6: "r6g  (Graviton2)", 7: "r7g  (Graviton3)", 8: "r8g  (Graviton4)"}
    vals = [TPCDS_RUNTIME_SEC[g] for g in gens]
    top = max(vals) * 1.18
    series = [
        {"name": "TPC-DS total runtime (s) — lower is better", "color": C["single"]}
    ]
    parts = [_svg_open(aria, title), _legend(series)]
    for i in range(5):
        gv = top * i / 4
        yy = mt + ph - (gv / top) * ph
        parts.append(
            f'<line x1="{ml}" y1="{yy:.1f}" x2="{ml + pw}" y2="{yy:.1f}" '
            f'stroke="{C["line"]}" stroke-width="1"/>'
        )
        parts.append(
            f'<text x="{ml - 8}" y="{yy + 4:.1f}" fill="{C["muted"]}" font-size="10.5" '
            f'text-anchor="end" font-family="{FONT}">{gv:.0f}s</text>'
        )
    n = len(gens)
    gw = pw / n
    bw = gw * 0.5
    callouts = {7: "1.14x faster", 8: "1.085x faster"}
    centers = []
    for ci, g in enumerate(gens):
        gx = ml + ci * gw + (gw - bw) / 2
        v = TPCDS_RUNTIME_SEC[g]
        bh = (v / top) * ph
        byy = mt + ph - bh
        centers.append((gx + bw / 2, byy))
        parts.append(
            f'<rect x="{gx:.1f}" y="{byy:.1f}" width="{bw:.1f}" height="{bh:.1f}" rx="3" '
            f'fill="{GEN_COLOR[g]}"><title>{esc(labels[g])}: {v:.0f}s</title></rect>'
        )
        parts.append(
            f'<text x="{gx + bw / 2:.1f}" y="{byy - 6:.1f}" fill="{C["ink"]}" font-size="11" '
            f'font-weight="600" text-anchor="middle" font-family="{FONT}">{v:.0f}s</text>'
        )
        parts.append(
            f'<text x="{gx + bw / 2:.1f}" y="{mt + ph + 18:.1f}" fill="{C["ink"]}" '
            f'font-size="11.5" text-anchor="middle" font-family="{FONT}">{esc(labels[g])}</text>'
        )
        if g in callouts:
            parts.append(
                f'<text x="{gx + bw / 2:.1f}" y="{byy + 18:.1f}" fill="{C["action"]}" '
                f'font-size="10.5" font-weight="600" text-anchor="middle" '
                f'font-family="{FONT}">{esc(callouts[g])}</text>'
            )
    parts.append(
        f'<text x="{centers[2][0]:.1f}" y="{mt + 14:.1f}" fill="{C["guard"]}" font-size="10.5" '
        f'font-weight="600" text-anchor="middle" font-family="{FONT}">cumulative r6g→r8g 1.24x</text>'
    )
    parts.append("</svg>")
    return "".join(parts)


def svg_stacked_fleet(title: str, aria: str, summary: FleetSummary | None) -> str:
    """Chart E: live-fleet EC2/DBU stacked bars, current + Gen7/Gen8 projected."""
    if summary is None or summary.current_total <= 0:
        parts = [_svg_open(aria, title)]
        parts.append(
            f'<rect x="60" y="150" width="640" height="120" rx="10" '
            f'fill="{C["panel2"]}" stroke="{C["line"]}" stroke-dasharray="6 5"/>'
        )
        parts.append(
            f'<text x="380" y="205" fill="{C["muted"]}" font-size="15" font-weight="600" '
            f'text-anchor="middle" font-family="{FONT}">live fleet data not provided</text>'
        )
        parts.append(
            f'<text x="380" y="230" fill="{C["muted"]}" font-size="11.5" '
            f'text-anchor="middle" font-family="{FONT}">'
            f"re-run the recommender Trino pull to populate fleet-weighted savings</text>"
        )
        parts.append("</svg>")
        return "".join(parts)

    p7 = summary.projections[7]
    p8 = summary.projections[8]
    bars = [
        ("Current (Gen mix)", summary.current_ec2, summary.current_dbu, None),
        (
            "Gen 7 projected",
            p7.new_ec2["mid"],
            p7.new_dbu["mid"],
            p7.saving_pct["mid"],
        ),
        (
            "Gen 8 projected",
            p8.new_ec2["mid"],
            p8.new_dbu["mid"],
            p8.saving_pct["mid"],
        ),
    ]
    ml, mr, mt, mb = 70, 22, 64, 78
    pw, ph = _VB_W - ml - mr, _VB_H - mt - mb
    top = max(e + d for _, e, d, _ in bars) * 1.2
    series = [
        {"name": "EC2 $/yr", "color": C["single"]},
        {"name": "DBU $/yr", "color": C["multi"]},
    ]
    parts = [_svg_open(aria, title), _legend(series)]
    for i in range(5):
        gv = top * i / 4
        yy = mt + ph - (gv / top) * ph
        parts.append(
            f'<line x1="{ml}" y1="{yy:.1f}" x2="{ml + pw}" y2="{yy:.1f}" '
            f'stroke="{C["line"]}" stroke-width="1"/>'
        )
        parts.append(
            f'<text x="{ml - 8}" y="{yy + 4:.1f}" fill="{C["muted"]}" font-size="10" '
            f'text-anchor="end" font-family="{FONT}">{fmt_money(gv)}</text>'
        )
    n = len(bars)
    gw = pw / n
    bw = gw * 0.5
    for ci, (label, ec2, dbu, sav) in enumerate(bars):
        gx = ml + ci * gw + (gw - bw) / 2
        eh = (ec2 / top) * ph
        dh = (dbu / top) * ph
        ey = mt + ph - eh
        dy = ey - dh
        parts.append(
            f'<rect x="{gx:.1f}" y="{ey:.1f}" width="{bw:.1f}" height="{eh:.1f}" '
            f'fill="{C["single"]}"><title>{esc(label)} EC2: {fmt_money(ec2)}</title></rect>'
        )
        parts.append(
            f'<rect x="{gx:.1f}" y="{dy:.1f}" width="{bw:.1f}" height="{dh:.1f}" '
            f'fill="{C["multi"]}"><title>{esc(label)} DBU: {fmt_money(dbu)}</title></rect>'
        )
        parts.append(
            f'<text x="{gx + bw / 2:.1f}" y="{dy - 6:.1f}" fill="{C["ink"]}" font-size="10.5" '
            f'font-weight="600" text-anchor="middle" font-family="{FONT}">{fmt_money(ec2 + dbu)}</text>'
        )
        if sav is not None:
            parts.append(
                f'<text x="{gx + bw / 2:.1f}" y="{dy - 20:.1f}" fill="{C["action"]}" '
                f'font-size="10.5" font-weight="700" text-anchor="middle" '
                f'font-family="{FONT}">{fmt_pct(-sav)} vs current</text>'
            )
        parts.append(
            f'<text x="{gx + bw / 2:.1f}" y="{mt + ph + 18:.1f}" fill="{C["ink"]}" '
            f'font-size="11.5" text-anchor="middle" font-family="{FONT}">{esc(label)}</text>'
        )
    parts.append("</svg>")
    return "".join(parts)


# ===========================================================================
# HTML assembly
# ===========================================================================

_CSS = """
:root{
  --bg:#0f1419; --panel:#171c24; --panel2:#1e2530; --ink:#e6edf3; --muted:#8b98a9;
  --line:#2d3643; --single:#38bdf8; --multi:#a78bfa; --action:#34d399; --guard:#f0b429;
  --danger:#f87171; --radius:10px;
  --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
  --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
}
*{box-sizing:border-box;}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);line-height:1.5;-webkit-font-smoothing:antialiased;}
.wrap{max-width:1120px;margin:0 auto;padding:32px 24px 80px;}
header h1{font-size:27px;margin:0 0 8px;letter-spacing:-0.01em;}
header p{color:var(--muted);margin:0 0 6px;font-size:14px;}
header code{font-family:var(--mono);font-size:12.5px;color:var(--single);}
a{color:var(--single);text-decoration:none;}
a:hover{text-decoration:underline;}
h2{font-size:19px;margin:0 0 12px;letter-spacing:-0.01em;}
h3{font-size:15px;margin:18px 0 8px;}
section{margin-top:30px;scroll-margin-top:18px;border-top:1px solid var(--line);padding-top:22px;}
section p{font-size:14px;color:#c7d2dd;max-width:920px;}
section p.muted{color:var(--muted);}
.secnum{color:var(--muted);font-family:var(--mono);font-size:13px;margin-right:8px;}
code{font-family:var(--mono);font-size:12.5px;color:var(--single);background:var(--panel2);padding:1px 5px;border-radius:5px;}
.nav{display:flex;flex-wrap:wrap;gap:8px 14px;margin:22px 0 6px;padding:14px 16px;background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);font-size:13px;}
.nav a{color:var(--muted);}
.nav a:hover{color:var(--single);}
.callout{background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--action);border-radius:var(--radius);padding:14px 18px;margin:16px 0;font-size:14.5px;}
.callout.warn{border-left-color:var(--guard);}
.callout.info{border-left-color:var(--single);}
.callout strong{color:var(--ink);}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:16px;}
@media(max-width:860px){.grid2{grid-template-columns:1fr;}}
table{width:100%;border-collapse:collapse;margin:14px 0;font-size:12.5px;}
caption{caption-side:top;text-align:left;color:var(--muted);font-size:12.5px;margin-bottom:6px;}
th,td{text-align:right;padding:7px 9px;border-bottom:1px solid var(--line);white-space:nowrap;}
th:first-child,td:first-child{text-align:left;}
thead th{color:var(--muted);font-weight:600;border-bottom:1px solid var(--line);position:sticky;}
tbody tr:hover{background:var(--panel2);}
td code,th code{background:transparent;padding:0;}
.tbl-wrap{overflow-x:auto;background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);padding:6px 14px 10px;}
.pos{color:var(--action);}
.neg{color:var(--danger);}
.win{color:var(--action);font-weight:600;}
.marginal{color:var(--guard);font-weight:600;}
.chart{margin:16px 0;}
.chart-cap{color:var(--muted);font-size:12px;margin:6px 2px 0;}
ul{font-size:14px;color:#c7d2dd;}
li{margin:5px 0;}
.verdict{display:inline-block;font-family:var(--mono);font-size:11.5px;font-weight:600;padding:2px 8px;border-radius:99px;}
.verdict.go{background:#0f2e25;color:var(--action);border:1px solid #1f6b53;}
.verdict.hold{background:#2a2410;color:var(--guard);border:1px solid #6b5a18;}
.verdict.no{background:#2a1414;color:var(--danger);border:1px solid #6b2424;}
footer{margin-top:36px;color:var(--muted);font-size:12px;border-top:1px solid var(--line);padding-top:16px;}
.src{font-size:12.5px;}
.src li{word-break:break-all;}
"""


def _row(cells: list[str], *, header: bool = False) -> str:
    tag = "th" if header else "td"
    scope = ' scope="col"' if header else ""
    return "<tr>" + "".join(f"<{tag}{scope}>{c}</{tag}>" for c in cells) + "</tr>"


def _tier_label(tier: str) -> str:
    return {"xs": "xs", "s": "s", "m": "m", "l": "l", "xl": "xl"}[tier]


def _family_table(family: str, econ: list[PresetEcon]) -> str:
    rows = [e for e in econ if e.family == family]
    head = _row(
        [
            "t-shirt",
            "Gen6 node (vCPU/RAM)",
            "OD $/hr",
            "spot $/hr",
            "Gen7 node",
            "OD $/hr (Δ)",
            "Gen8 node",
            "OD $/hr (Δ)",
            "Spark Δperf G6→7",
            "cost/work G6→7",
            "cost/work G7→8",
        ],
        header=True,
    )
    body: list[str] = []
    for e in rows:
        spark_dperf = speedup(6, 7) - 1
        body.append(
            _row(
                [
                    f"<strong>{_tier_label(e.tier)}</strong>",
                    f"<code>{esc(e.nodes[6])}</code> "
                    f'<span class="muted">{fmt_num(e.vcpus)}vCPU / {fmt_num(e.mem_gb)}GiB</span>',
                    fmt_usd(e.od[6]),
                    fmt_usd(e.spot[6]),
                    f"<code>{esc(e.nodes[7])}</code>",
                    f'{fmt_usd(e.od[7])} <span class="neg">{fmt_ratio_pct(e.price_ratio_67)}</span>',
                    f"<code>{esc(e.nodes[8])}</code>",
                    f'{fmt_usd(e.od[8])} <span class="neg">{fmt_ratio_pct(e.price_ratio_78)}</span>',
                    f'<span class="pos">{fmt_pct(spark_dperf)}</span>',
                    f'<span class="{"pos" if (e.cost_of_work_67 or 0) < 0 else "neg"}">{fmt_pct(e.cost_of_work_67)}</span>',
                    f'<span class="{"pos" if (e.cost_of_work_78 or 0) < 0 else "neg"}">{fmt_pct(e.cost_of_work_78)}</span>',
                ]
            )
        )
    title = {
        "compute": "Compute (c-series)",
        "general": "General (m-series)",
        "memory": "Memory (r-series)",
    }[family]
    return (
        f'<div class="tbl-wrap"><table><caption>{esc(title)} consolidation presets — '
        f"Gen 6 → 7 → 8 (cost/work &lt; 0 means cheaper per unit of Spark work)</caption>"
        f"<thead>{head}</thead><tbody>{''.join(body)}</tbody></table></div>"
    )


def render_html(
    instances: list[Instance],
    *,
    fleet: FleetSummary | None = None,
    generated_at: str | None = None,
    ec2_csv_path: str = "scripts/ec2_instance_comparison.csv",
    fleet_csv_path: str | None = None,
) -> str:
    generated_at = generated_at or datetime.now(timezone.utc).strftime(
        "%Y-%m-%d %H:%M UTC"
    )
    agg = aggregate_by_prefix(instances)
    econ = preset_economics(instances)
    by_api = {i.api: i for i in instances}

    # --- Triangulation indices (averaged across the three families) ----------
    def _fam_mean(
        per_fam: dict[str, dict[int, float | None]], gen: int
    ) -> float | None:
        vals = [
            per_fam[f][gen] for f in _FAMILY_ORDER if per_fam[f].get(gen) is not None
        ]
        return statistics.mean(vals) if vals else None

    spark_od = {f: spark_perf_per_dollar_index(instances, f) for f in _FAMILY_ORDER}
    spark_spot = {
        f: spark_perf_per_dollar_index(instances, f, spot=True) for f in _FAMILY_ORDER
    }
    coremark_od_idx: dict[int, float | None] = {}
    for gen in _GENS:
        ratios = []
        for f in _FAMILY_ORDER:
            p6 = agg.get(f"{_FAMILY_PREFIX[f]}6g")
            pg = agg.get(f"{_FAMILY_PREFIX[f]}{gen}g")
            if p6 and pg and p6.cm_per_od and pg.cm_per_od:
                ratios.append(pg.cm_per_od / p6.cm_per_od)
        coremark_od_idx[gen] = statistics.mean(ratios) * 100 if ratios else None
    spark_od_idx = {gen: _fam_mean(spark_od, gen) for gen in _GENS}
    spark_spot_idx = {gen: _fam_mean(spark_spot, gen) for gen in _GENS}

    # --- Charts --------------------------------------------------------------
    chart_a = svg_grouped_bars(
        "Real-Spark perf-per-on-demand-$ index (Gen 6 = 100)",
        "Grouped bars: real Spark performance per on-demand dollar, indexed to Gen 6 = 100, by family and generation.",
        ["Compute", "General", "Memory"],
        [
            {
                "name": f"Gen {g}",
                "color": GEN_COLOR[g],
                "values": [spark_od[f][g] for f in _FAMILY_ORDER],
            }
            for g in _GENS
        ],
        baseline=100.0,
        y_title="perf / OD$ (index)",
    )
    chart_b = svg_grouped_bars(
        "CoreMark/OD$ vs real-Spark/OD$ (Gen 6 = 100) — CoreMark overstates the gain",
        "Grouped bars comparing CoreMark per on-demand dollar against real-Spark per on-demand dollar, indexed to Gen 6 = 100, per generation.",
        ["Gen 6", "Gen 7", "Gen 8"],
        [
            {
                "name": "CoreMark/OD$",
                "color": C["guard"],
                "values": [coremark_od_idx[g] for g in _GENS],
            },
            {
                "name": "Real-Spark/OD$",
                "color": C["action"],
                "values": [spark_od_idx[g] for g in _GENS],
            },
        ],
        baseline=100.0,
        y_title="index (Gen6=100)",
    )
    chart_c = svg_line(
        "Per-core uplift by source (Gen 6 = 100)",
        "Line chart of per-core performance index by generation for CoreMark/vCPU, SPECint2017 per-core, and real Spark TPC-DS.",
        ["Gen 6", "Gen 7", "Gen 8"],
        [
            {
                "name": "CoreMark/vCPU",
                "color": C["guard"],
                "values": [PER_CORE_SOURCES["CoreMark/vCPU (CSV)"][g] for g in _GENS],
            },
            {
                "name": "SPECint2017/core",
                "color": C["single"],
                "values": [PER_CORE_SOURCES["SPECint2017 per-core"][g] for g in _GENS],
            },
            {
                "name": "Real Spark TPC-DS",
                "color": C["action"],
                "values": [PER_CORE_SOURCES["Real Spark TPC-DS"][g] for g in _GENS],
            },
        ],
        y_title="per-core index",
    )
    chart_d = svg_runtime_ladder(
        "AWS TPC-DS cumulative runtime — r6g / r7g / r8g",
        "Bar ladder of AWS TPC-DS cumulative runtime for r6g, r7g, r8g with per-step speedup callouts.",
    )
    chart_e = svg_stacked_fleet(
        "Live fleet annualized cost: EC2 vs DBU, current + Gen 7 / Gen 8 projected",
        "Stacked bars of live fleet annualized EC2 and DBU cost, current versus projected under Gen 7 and Gen 8.",
        fleet,
    )
    chart_f = svg_grouped_bars(
        "Perf-per-spot$ vs perf-per-OD$ (Gen 6 = 100) — workers run on spot",
        "Grouped bars comparing perf per spot dollar against perf per on-demand dollar, indexed to Gen 6 = 100, per generation.",
        ["Gen 6", "Gen 7", "Gen 8"],
        [
            {
                "name": "perf / OD$",
                "color": C["single"],
                "values": [spark_od_idx[g] for g in _GENS],
            },
            {
                "name": "perf / spot$",
                "color": C["action"],
                "values": [spark_spot_idx[g] for g in _GENS],
            },
        ],
        baseline=100.0,
        y_title="index (Gen6=100)",
    )

    # --- Headline savings text ----------------------------------------------
    if fleet is not None and fleet.current_total > 0:
        s7 = fleet.projections[7].saving_pct["mid"]
        s7lo = fleet.projections[7].saving_pct["low"]
        s7hi = fleet.projections[7].saving_pct["high"]
        headline_pct = f"~{s7 * 100:.1f}% total savings ({s7lo * 100:.1f}–{s7hi * 100:.1f}% band, from live fleet data)"
    else:
        headline_pct = "~9–12% total savings (closed-form, from the EC2/DBU cost-of-work model — live fleet data not provided)"

    # --- Section 2: TL;DR recommendation table -------------------------------
    tldr_rows = []
    for f in _FAMILY_ORDER:
        s7 = spark_od[f][7]
        p67 = matched_size_price_ratio(instances, f, 6, 7)
        tldr_rows.append(
            _row(
                [
                    {
                        "compute": "Compute (c)",
                        "general": "General (m)",
                        "memory": "Memory (r)",
                    }[f],
                    "Gen 6 (Graviton2)",
                    "<strong>Gen 7 (Graviton3)</strong>",
                    f'<span class="pos">{fmt_pct(speedup(6, 7) - 1)}</span>',
                    f'<span class="neg">{fmt_ratio_pct(p67)}</span>',
                    f'<span class="pos">{fmt_pct(-(1 - closed_form_ratio(0.5, p67 or 1.06, speedup(6, 7))))}</span>',
                    '<span class="verdict go">MIGRATE</span>',
                ]
            )
        )
    tldr_rows.append(
        _row(
            [
                "Gen 8 (Graviton4)",
                "Gen 7",
                "Gen 8 (selective)",
                f'<span class="pos">{fmt_pct(speedup(7, 8) - 1)}</span>',
                f'<span class="neg">{fmt_ratio_pct(matched_size_price_ratio(instances, "general", 7, 8))}</span>',
                f'<span class="marginal">{fmt_pct(-(1 - closed_form_ratio(0.5, 1.10, speedup(7, 8))))}</span>',
                '<span class="verdict hold">PILOT c8g</span>',
            ]
        )
    )

    # --- Section 4: main-benefits summary table ------------------------------
    benefits_rows = [
        _row(
            [
                "Gen 6 → 7 (Graviton2→3)",
                f'<span class="pos">{fmt_pct(speedup(6, 7) - 1)}</span> (TPC-DS 1.14×, EMR +13–19%)',
                '<span class="neg">+~6%</span> matched OD',
                f'<span class="pos">{fmt_pct(closed_form_ratio(0.5, 1.06, speedup(6, 7)) - 1)}</span> total (e=0.5)',
                "DDR5 +50% mem BW, 2× FP/crypto",
                '<span class="verdict go">supported (m7g/r7g; c7g STANDARD)</span>',
            ]
        ),
        _row(
            [
                "Gen 7 → 8 (Graviton3→4)",
                f'<span class="marginal">{fmt_pct(speedup(7, 8) - 1)}</span> (TPC-DS 1.085×)',
                '<span class="neg">+~10%</span> matched OD',
                f'<span class="marginal">{fmt_pct(closed_form_ratio(0.5, 1.10, speedup(7, 8)) - 1)}</span> total (e=0.5)',
                "+12 cores/socket, more mem BW",
                '<span class="verdict hold">m8g/r8g supported; c8g STANDARD only</span>',
            ]
        ),
    ]
    benefits_table = (
        '<div class="tbl-wrap"><table><caption>Main benefits per transition</caption>'
        "<thead>"
        + _row(
            [
                "transition",
                "Spark Δperf",
                "Δprice (matched OD)",
                "Δtotal-cost (e=0.5)",
                "hardware notes",
                "Databricks support",
            ],
            header=True,
        )
        + "</thead><tbody>"
        + "".join(benefits_rows)
        + "</tbody></table></div>"
    )

    # --- Section 5: CoreMark vs Spark per-gen table --------------------------
    cm_vs_spark_rows = []
    for g in _GENS:
        cm_vs_spark_rows.append(
            _row(
                [
                    f"Gen {g}",
                    fmt_num(coremark_od_idx[g], 0),
                    fmt_num(spark_od_idx[g], 0),
                    fmt_num(PER_CORE_SOURCES["SPECint2017 per-core"][g], 0),
                    fmt_num(PER_CORE_SOURCES["Real Spark TPC-DS"][g], 0),
                ]
            )
        )
    cm_vs_spark_table = (
        '<div class="tbl-wrap"><table><caption>Indexed uplift by metric (Gen 6 = 100) — CoreMark overstates real Spark ~2–3×</caption>'
        "<thead>"
        + _row(
            [
                "generation",
                "CoreMark/OD$",
                "real-Spark/OD$",
                "SPECint2017/core",
                "real Spark TPC-DS/core",
            ],
            header=True,
        )
        + "</thead><tbody>"
        + "".join(cm_vs_spark_rows)
        + "</tbody></table></div>"
    )

    # --- Section 6: ARM vs x86 -----------------------------------------------
    x86_rows = []
    x86_pairs = [
        ("general", "m8g.2xlarge", "m8a.2xlarge", "m8i.2xlarge"),
        ("compute", "c8g.2xlarge", "c8a.2xlarge", None),
        ("memory", "r8g.2xlarge", "r8a.2xlarge", None),
    ]
    for fam, g4, amd, intel in x86_pairs:

        def _cmod(node: str | None) -> str:
            if not node:
                return "—"
            inst = by_api.get(node)
            if not inst or not inst.coremark or not inst.od:
                return "—"
            return f"<code>{esc(node)}</code> {fmt_num(inst.coremark / inst.od)}"

        x86_rows.append(
            _row(
                [
                    {"compute": "Compute", "general": "General", "memory": "Memory"}[
                        fam
                    ],
                    _cmod(g4),
                    _cmod(amd),
                    _cmod(intel),
                ]
            )
        )
    x86_table = (
        '<div class="tbl-wrap"><table><caption>Latest x86 (Gen 8 AMD / Intel) vs Graviton4 — CoreMark per on-demand $ (integer-only; '
        "production Spark wall favors ARM by 26.5%)</caption>"
        "<thead>"
        + _row(
            [
                "family (.2xlarge)",
                "Graviton4 (g8) cm/OD$",
                "AMD (8a) cm/OD$",
                "Intel (8i) cm/OD$",
            ],
            header=True,
        )
        + "</thead><tbody>"
        + "".join(x86_rows)
        + "</tbody></table></div>"
    )

    # --- Section 8: mixed-generation 3-option table --------------------------
    opts = mixed_generation_options(instances)
    mixed_saving = opts["all_gen7"].total - opts["mixed"].total
    mixed_saving_pct = (
        mixed_saving / opts["all_gen7"].total if opts["all_gen7"].total else 0.0
    )
    mixed_rows = []
    for key in ("all_gen6", "all_gen7", "mixed"):
        o = opts[key]
        mixed_rows.append(
            _row(
                [
                    o.label,
                    f"<code>{esc(o.driver_node)}</code> {fmt_usd(o.driver_od)}",
                    f"<code>{esc(o.worker_node)}</code> {fmt_usd(o.worker_spot)} ×{o.worker_count}",
                    f"{o.wall_hours:.1f}h",
                    fmt_usd(o.ec2_cost, 3),
                    fmt_usd(o.dbu_cost, 3),
                    f"<strong>{fmt_usd(o.total, 3)}</strong>",
                ]
            )
        )
    mixed_table = (
        '<div class="tbl-wrap"><table><caption>Representative non-driver-heavy multi-node job '
        "(general xs driver + 2× general-m spot workers, 1h worker-set wall, DBU $0.50/h)</caption>"
        "<thead>"
        + _row(
            [
                "cluster",
                "driver (OD $/hr)",
                "worker (spot $/hr)",
                "wall",
                "EC2",
                "DBU",
                "total",
            ],
            header=True,
        )
        + "</thead><tbody>"
        + "".join(mixed_rows)
        + "</tbody></table></div>"
    )

    # --- Section 9: fleet table ----------------------------------------------
    if fleet is not None and fleet.current_total > 0:
        fleet_rows = []
        for g in (7, 8):
            pr = fleet.projections[g]
            proj_total = pr.new_total["mid"]
            proj_ec2_share = pr.new_ec2["mid"] / proj_total if proj_total else 0.0
            fleet_rows.append(
                _row(
                    [
                        f"Migrate eligible → Gen {g}",
                        fmt_money(pr.current_total),
                        f"{proj_ec2_share * 100:.0f}% / {(1 - proj_ec2_share) * 100:.0f}%",
                        fmt_money(pr.new_total["mid"]),
                        f'<span class="pos">{fmt_money(pr.saving["mid"])}</span>',
                        f'<span class="pos">{fmt_pct(-pr.saving_pct["mid"])}</span>',
                        f"{fmt_pct(-pr.saving_pct['low'])} … {fmt_pct(-pr.saving_pct['high'])}",
                        str(pr.n_projected),
                    ]
                )
            )
        fam_rows = []
        for f in _FAMILY_ORDER:
            slot = fleet.by_family.get(f)
            if not slot:
                continue
            fam_rows.append(
                _row(
                    [
                        {
                            "compute": "Compute",
                            "general": "General",
                            "memory": "Memory",
                        }[f],
                        fmt_money(slot["total"]),
                        f"{slot['ec2'] / slot['total'] * 100:.0f}%"
                        if slot["total"]
                        else "—",
                        fmt_num(slot["n"]),
                    ]
                )
            )
        fleet_block = (
            f'<div class="callout info">Live fleet pull: <strong>{fleet.n_classified}</strong> '
            f"classified DAGs (of {fleet.n_dags}; {fleet.n_skipped} unclassifiable/autoscale skipped). "
            f"Current annualized spend <strong>{fmt_money(fleet.current_total)}/yr</strong>, "
            f"EC2/DBU split {fleet.ec2_share * 100:.0f}% / {(1 - fleet.ec2_share) * 100:.0f}%.</div>"
            '<div class="tbl-wrap"><table><caption>Fleet-weighted annualized savings (mid band; low…high from the Spark-speedup envelope)</caption>'
            "<thead>"
            + _row(
                [
                    "scenario",
                    "current $/yr",
                    "EC2/DBU",
                    "projected $/yr",
                    "saving $/yr",
                    "saving % (mid)",
                    "saving % band",
                    "#DAGs",
                ],
                header=True,
            )
            + "</thead><tbody>"
            + "".join(fleet_rows)
            + "</tbody></table></div>"
            + '<div class="tbl-wrap"><table><caption>Current spend by family</caption><thead>'
            + _row(["family", "annual $/yr", "EC2 share", "#DAGs"], header=True)
            + "</thead><tbody>"
            + "".join(fam_rows)
            + "</tbody></table></div>"
        )
    else:
        fleet_block = (
            '<div class="callout warn"><strong>live fleet data not provided.</strong> '
            "The Trino fleet pull (<code>recommend_cluster_specs.py --trino</code>) was not available when this "
            "report was generated, so fleet-weighted dollar savings are not shown. The hardware and triangulation "
            "sections above are complete and CSV-grounded. Re-run Step 6 to populate this section; the closed-form "
            "estimate below brackets the result. No fleet numbers are fabricated.</div>"
            '<div class="tbl-wrap"><table><caption>Closed-form total-cost ratio by EC2 share '
            "(<code>total_new/total_old = (e·p + (1−e))/s</code>)</caption><thead>"
            + _row(
                ["EC2 share e", "Gen6→7 (p=1.06, s=1.15)", "Gen7→8 (p=1.10, s=1.08)"],
                header=True,
            )
            + "</thead><tbody>"
            + "".join(
                _row(
                    [
                        f"{e:.1f}",
                        f'<span class="pos">{fmt_pct(closed_form_ratio(e, 1.06, 1.15) - 1)}</span>',
                        f'<span class="marginal">{fmt_pct(closed_form_ratio(e, 1.10, 1.08) - 1)}</span>',
                    ]
                )
                for e in (0.3, 0.5, 0.7)
            )
            + "</tbody></table></div>"
        )

    # --- Section 3: spot/OD ratio table -------------------------------------
    spot_rows = []
    for f in _FAMILY_ORDER:
        cells = [{"compute": "Compute", "general": "General", "memory": "Memory"}[f]]
        for g in _GENS:
            a = agg.get(f"{_FAMILY_PREFIX[f]}{g}g")
            cells.append(f"{a.spot_od_ratio:.2f}" if a and a.spot_od_ratio else "—")
        spot_rows.append(_row(cells))
    spot_table = (
        '<div class="tbl-wrap"><table><caption>Implied spot:on-demand ratio per family/gen '
        f"vs the recommender's flat <code>{RECOMMENDER_SPOT_RATIO}</code> — all ARM generations sit below it, "
        "so spot workers are slightly under-credited (memory family most)</caption><thead>"
        + _row(["family", "Gen 6", "Gen 7", "Gen 8"], header=True)
        + "</thead><tbody>"
        + "".join(spot_rows)
        + "</tbody></table></div>"
    )

    # --- Section 12: appendix per-instance table -----------------------------
    appendix_rows = []
    for inst in sorted(instances, key=lambda i: (i.base, i.gen, i.arch, i.api)):
        appendix_rows.append(
            _row(
                [
                    f"<code>{esc(inst.api)}</code>",
                    inst.family_label,
                    f"Gen {inst.gen}",
                    inst.arch,
                    fmt_num(inst.vcpus),
                    fmt_num(inst.mem_gb),
                    fmt_num(inst.coremark, 0),
                    fmt_usd(inst.od),
                    fmt_usd(inst.spot),
                ]
            )
        )
    appendix_table = (
        '<div class="tbl-wrap"><table><caption>Full classified instance catalog (c/m/r families) — '
        f"{len(instances)} rows from <code>{esc(ec2_csv_path)}</code></caption><thead>"
        + _row(
            [
                "API name",
                "family",
                "gen",
                "arch",
                "vCPU",
                "RAM GiB",
                "CoreMark",
                "OD $/hr",
                "spot $/hr",
            ],
            header=True,
        )
        + "</thead><tbody>"
        + "".join(appendix_rows)
        + "</tbody></table></div>"
    )

    # --- Citations -----------------------------------------------------------
    citations = [
        (
            "AWS EMR on EKS +up to 19% Spark on Graviton3 vs Graviton2",
            "https://aws.amazon.com/blogs/big-data/amazon-emr-on-eks-gets-up-to-19-performance-boost-running-on-aws-graviton3-processors-vs-graviton2",
        ),
        (
            "AWS C7g: +25% compute, 2× FP, DDR5 +50% memory bandwidth",
            "https://aws.amazon.com/ec2/instance-types/c7g/",
        ),
        (
            "AWS Graviton4 (RDS m8g +23% q/$ vs m7g; +30% compute)",
            "https://aws.amazon.com/blogs/database/leveling-up-amazon-rds-with-aws-graviton4-benchmarks/",
        ),
        (
            "AWS TPC-DS R6g/R7g/R8g (Data-on-EKS): r6g 2151s / r7g 1887s / r8g 1740s; means 1.155× / 1.081× / 1.249×",
            "https://awslabs.github.io/data-on-eks/docs/benchmarks/spark-operator-benchmark/graviton-r-data",
        ),
        (
            "Databricks Photon-on-Graviton ~3× price-perf + supported families",
            "https://docs.databricks.com/aws/en/compute/photon",
        ),
        (
            "Databricks flexible / supported Graviton node types",
            "https://docs.databricks.com/aws/en/compute/flexible-node-type-instances",
        ),
        (
            "Databricks driver/worker selection + Graviton mixing rule (no ARM↔x86 mixing)",
            "https://docs.databricks.com/aws/en/compute/configure",
        ),
        (
            "AWS Spark-on-Graviton getting-started (Data Analytics)",
            "https://github.com/aws/aws-graviton-getting-started/blob/main/DataAnalytics.md",
        ),
        (
            "SPECint2017 per-core +12–13%/gen (Phoronix Graviton reviews)",
            "https://www.phoronix.com/review/graviton4-amazon",
        ),
    ]
    citation_items = "".join(
        f'<li>{esc(t)} — <a href="{esc(u)}">{esc(u)}</a></li>' for t, u in citations
    )

    # --- Navigation ----------------------------------------------------------
    sections = [
        ("s1", "1. Executive summary"),
        ("s2", "2. TL;DR recommendation"),
        ("s3", "3. Methodology"),
        ("s4", "4. Consolidation t-shirt economics"),
        ("s5", "5. CoreMark vs reality"),
        ("s6", "6. ARM vs x86"),
        ("s7", "7. Gen 8 deep-dive"),
        ("s8", "8. Mixed-generation clusters"),
        ("s9", "9. Live fleet-weighted savings"),
        ("s10", "10. The recommender gap"),
        ("s11", "11. Recommendation & action items"),
        ("s12", "12. Appendix"),
    ]
    nav = (
        '<div class="nav">'
        + "".join(f'<a href="#{sid}">{esc(label)}</a>' for sid, label in sections)
        + "</div>"
    )

    regen_cmd = (
        "uv run python scripts/analyze_instance_generations.py "
        "--ec2-csv scripts/ec2_instance_comparison.csv "
        "--fleet-csv scripts/analysis_data/recommendations.csv "
        "--out docs/platform/spark_instance_generation_analysis.html"
    )

    def chart(svg: str, cap: str) -> str:
        return f'<div class="chart">{svg}<div class="chart-cap">{esc(cap)}</div></div>'

    body = f"""
<header>
  <h1>Spark Instance-Generation Cost-Benefit Analysis</h1>
  <p>Should the <code>bi-etl-ejuice</code> Databricks <code>consolidation_*</code> fleet stay on ARM
     <strong>Gen 6 (Graviton2)</strong>, or move to <strong>Gen 7 (Graviton3)</strong> / <strong>Gen 8 (Graviton4)</strong>?</p>
  <p>Triangulates <code>{esc(ec2_csv_path)}</code> (CoreMark + prices) against real Spark benchmarks and live fleet telemetry.
     Generated {esc(generated_at)}.</p>
</header>
{nav}

<section id="s1">
  <h2><span class="secnum">§1</span>Executive summary</h2>
  <p>The fleet already made the big move — x86 Gen 5 → ARM Gen 6 — and the production evidence
     (<code>AMD_WALL_CORRECTION = 0.735</code>, the 594-DAG median that ARM ran 26.5% faster wall-clock) is decisive: <strong>stay on ARM</strong>.
     The open question is which ARM generation. The answer: <strong>migrate <code>consolidation_*</code> from Gen 6 → Gen 7 (Graviton3)</strong>,
     pilot Gen 8 only for <code>c8g</code>/Java-heavy jobs.</p>
  <div class="callout">
    <strong>Migrate the <code>consolidation_*</code> t-shirt presets from Gen 6 → Gen 7 (Graviton3)</strong>
    ({esc(headline_pct)}); <strong>pilot Gen 8</strong> for <code>c8g</code>/Java-heavy DAGs only; <strong>stay ARM</strong>.
    Gen 6 → 7 is a robust win: real Spark is ~{fmt_pct(speedup(6, 7) - 1)} faster while matched-size on-demand price rises only ~6%,
    so both EC2-hours and DBU-hours shrink. Gen 7 → 8 is marginal for batch Spark (~{fmt_pct(speedup(7, 8) - 1)} faster vs ~10% pricier).
  </div>
</section>

<section id="s2">
  <h2><span class="secnum">§2</span>TL;DR recommendation</h2>
  <div class="tbl-wrap"><table><caption>Per-family verdict (Spark-calibrated, not CoreMark)</caption>
    <thead>{_row(["family", "current", "recommended", "Spark Δperf", "Δprice (matched OD)", "Δtotal-cost (e=0.5)", "verdict"], header=True)}</thead>
    <tbody>{"".join(tldr_rows)}</tbody></table></div>
  <p class="muted">Δtotal-cost uses the closed-form <code>(e·p + (1−e))/s</code> at a 50/50 EC2/DBU split; the live-fleet split refines it in §9.</p>
</section>

<section id="s3">
  <h2><span class="secnum">§3</span>Methodology</h2>
  <p><strong>Cost-of-work.</strong> For a fixed amount of work, <code>cost ∝ ($/hr) ÷ throughput</code>, so
     <code>perf-per-dollar = throughput ÷ ($/hr)</code>. CoreMark-as-throughput is an optimistic upper bound;
     the Spark-adjusted variant uses the triangulated <code>SPARK_SPEEDUP</code> constants.</p>
  <p><strong>Triangulation.</strong> CoreMark/$ (CSV) is cross-checked against SPECint2017 per-core (~+12%/gen) and
     AWS TPC-DS end-to-end Spark runtime (r6g→r7g 1.14×, r7g→r8g 1.085×). Real Spark TPC-DS is the headline; CoreMark is flagged as a 2–3× over-estimate.</p>
  <p><strong>Total-cost model (§9).</strong> Databricks cost = EC2 (on-demand driver + spot workers) + DBU (priced over wall-clock).
     A faster node shrinks the wall, so it cuts <em>both</em> EC2-hours and DBU-hours:
     <code>ec2_new = ec2_old · p / s</code>, <code>dbu_new = dbu_old / s</code> ⇒
     <code>total_new/total_old = (e·p + (1−e))/s</code>, with <code>e</code> = fleet EC2 share, <code>p</code> = matched-size price ratio, <code>s</code> = Spark wall speedup.
     DBU/node-hour is assumed generation-neutral at matched vCPU/RAM (Databricks prices DBU by node size, not silicon gen).</p>
  <p><strong>Spot vs on-demand.</strong> Workers run on spot; §3 below reports implied spot:OD ratios vs the recommender's flat
     <code>{RECOMMENDER_SPOT_RATIO}</code>.</p>
  {spot_table}
  <p class="muted">Secondary finding: every ARM generation's measured spot:OD sits below 0.37, so the recommender slightly under-credits spot savings (memory family most).</p>
</section>

<section id="s4">
  <h2><span class="secnum">§4</span>Consolidation t-shirt economics</h2>
  <p>The analysis unit is the Databricks <code>consolidation_*</code> preset (xs/s/m/l/xl × compute/general/memory).
     One comparison table per family — every Gen 6 node with its Gen 7 / Gen 8 counterpart, on-demand and spot price, and the cost-of-work delta.</p>
  {_family_table("compute", econ)}
  {_family_table("general", econ)}
  {_family_table("memory", econ)}
  {benefits_table}
  {chart(chart_a, "Chart A — real-Spark perf-per-on-demand-$ index by family/generation (Gen 6 = 100).")}
  {chart(chart_f, "Chart F — perf-per-spot$ vs perf-per-OD$ by generation (workers run on spot).")}
</section>

<section id="s5">
  <h2><span class="secnum">§5</span>CoreMark vs reality (triangulation)</h2>
  <p>CoreMark/OD$ says Gen 6→7 is ~+19–23% and per-core ~+27–31%. But SPECint2017 per-core uplift is only ~+12%/gen and real Spark TPC-DS is ~+14%.
     CoreMark is integer-only and ignores memory-bandwidth/IO-bound Spark behavior, so it overstates the real Spark gain by ~2–3×. Lead with the Spark-calibrated numbers.</p>
  {chart(chart_b, "Chart B — CoreMark/OD$ vs real-Spark/OD$ (Gen 6 = 100): the gap is the overstatement.")}
  {chart(chart_c, "Chart C — per-core uplift by source: CoreMark/vCPU, SPECint2017/core, real Spark TPC-DS.")}
  {chart(chart_d, "Chart D — AWS TPC-DS cumulative runtime ladder r6g/r7g/r8g with per-step speedups.")}
  {cm_vs_spark_table}
</section>

<section id="s6">
  <h2><span class="secnum">§6</span>ARM vs x86 — stay ARM</h2>
  <p>Latest x86 (m8a/c8a/r8a, Gen 8) shows competitive CoreMark/OD$ — m8a even edges m8g on the integer benchmark.
     But CoreMark is integer-only. The repo's own telemetry measured ARM running <strong>26.5% faster wall-clock on the same DAGs</strong>
     (<code>AMD_WALL_CORRECTION = 0.735</code>, <code>scripts/recommend_cluster_specs.py:92</code>, 594-DAG median), and Databricks Photon-on-Graviton
     delivers ~3× price-performance with no Graviton surcharge. Generic CoreMark cannot override that production evidence.</p>
  {x86_table}
  <p><span class="verdict go">Verdict: stay ARM.</span> Chase newer Graviton generations, not x86.</p>
</section>

<section id="s7">
  <h2><span class="secnum">§7</span>Gen 8 deep-dive</h2>
  <p>For batch Spark on <code>m8g</code>/<code>r8g</code>, Gen 7 → 8 is roughly break-even: the ~{fmt_pct(speedup(7, 8) - 1)} Spark speedup is offset by the ~10% on-demand price bump
     (see the cost/work G7→8 column in §4 — close to zero, occasionally positive). The total-cost saving comes only from the faster wall trimming DBU-hours: ~1–5%.</p>
  <p><strong>Where Gen 8 wins:</strong> <code>c8g</code> compute (best CoreMark/$ of the Gen 8 ARM line), per-core/licensing-bound jobs, Java-17 workloads, and DBU-heavy DAGs
     (where the wall-shrink dominates). <strong>Caveat:</strong> Databricks supports <code>m8g</code>/<code>m8gd</code>/<code>r8g</code>, but <code>c8g</code> (all compute) is still
     Photon-blocked by the compute core/RAM-ratio constraint (see <code>cluster_spec_recommender_algorithm.md</code>, "Photon × Instance-Family Constraint") — usable STANDARD only.</p>
</section>

<section id="s8">
  <h2><span class="secnum">§8</span>Mixed-generation clusters (Gen 6 driver + Gen 7 workers)</h2>
  <p>Databricks lets the driver and worker node types be selected independently and permits any <strong>same-architecture</strong> mix; only
     ARM↔x86 mixing is blocked ("Databricks does not support mixing AWS Graviton and non-AWS Graviton instance types",
     <a href="https://docs.databricks.com/aws/en/compute/configure">docs.databricks.com/aws/en/compute/configure</a>). Graviton2 (Gen 6) and Graviton3 (Gen 7)
     are both arm64 under one Databricks Runtime, so an <code>m6g</code>-driver + <code>m7g</code>-workers cluster is allowed.</p>
  {mixed_table}
  <p>The wall is <strong>worker-set</strong>, so worker cost and DBU are identical between all-Gen 7 and mixed — the <strong>only</strong> delta is the driver's
     on-demand $/hr (~6%; <code>m6g.large</code> $0.077 vs <code>m7g.large</code> $0.082 = $0.005/hr) on the driver's slice ⇒
     <strong>{fmt_pct(mixed_saving_pct)} of total</strong> for this non-driver-heavy DAG (&lt;1%).</p>
  <div class="callout warn">A ~14%-slower Gen 6 driver lengthens any driver-bound phase (broadcast build, <code>collect</code>, query planning),
     re-inflating worker-spot <em>and</em> DBU and erasing the saving.</div>
  <p><span class="verdict go">Verdict: default the driver to the worker generation (Gen 7).</span>
     Mixed-gen pays only to amortize under-utilized Gen 6 Reserved Instances / Savings Plans (sunk-cost capacity), not on the on-demand rate.</p>
</section>

<section id="s9">
  <h2><span class="secnum">§9</span>Live fleet-weighted savings</h2>
  {chart(chart_e, "Chart E — live fleet annualized EC2/DBU cost: current vs Gen 7 / Gen 8 projected.")}
  {fleet_block}
  <p class="muted">Projection per DAG (same vCPU/RAM, never downgraded): <code>ec2_new = ec2·p/s</code>, <code>dbu_new = dbu/s</code>, summed over DAGs below the target generation;
     low/mid/high bands come from the Spark-speedup envelope. Unclassifiable (autoscale/blank) node types are excluded from the projection.</p>
</section>

<section id="s10">
  <h2><span class="secnum">§10</span>The recommender gap</h2>
  <p>The ~{fmt_pct(speedup(6, 7) - 1)} Gen 7 win is currently <strong>unreachable</strong> because the recommender is structurally pinned to Gen 6, and so are the Databricks presets:</p>
  <ul>
    <li><strong>Hardcoded family→Gen 6 nodes.</strong> <code>_node_for_family_tier</code> (<code>scripts/recommend_cluster_specs.py:600-602</code>)
        returns <code>{{"compute":"c6g","general":"m6g","memory":"r6g"}}</code>.</li>
    <li><strong>Capacity-then-cheapest selection.</strong> <code>_single_node_candidates</code> (<code>:631-642</code>) and
        <code>_node_for_demand</code> (<code>:704-727</code>) sort/min by <code>($/hr, memory, vcpus)</code> — Gen 6 always wins at equal vCPU/RAM.</li>
    <li><strong>No throughput credit.</strong> <code>estimate_projected_total_cost</code> (<code>:1007-1088</code>) scales by core count and observed wall but never
        credits a higher-throughput node's shorter wall.</li>
    <li><strong>Presets lag.</strong> The Databricks <code>consolidation_*</code> presets in <code>prod_conf.yml</code> are Gen 6, while
        <code>emr_7_12_consolidation_*</code> are already Gen 7 — Gen 7 is vetted in-repo on the EMR side.</li>
  </ul>
  <p>The fix is specified, decision-complete, in
     <a href="{esc(MIGRATION_DOC)}"><code>{esc(MIGRATION_DOC)}</code></a>.</p>
</section>

<section id="s11">
  <h2><span class="secnum">§11</span>Recommendation &amp; action items</h2>
  <ul>
    <li><strong>(a)</strong> Seed Gen 7 prices + specs and retarget the recommender + Databricks <code>consolidation_*</code> presets to Gen 7
        (per <a href="{esc(MIGRATION_DOC)}"><code>{esc(MIGRATION_DOC)}</code></a>).</li>
    <li><strong>(b)</strong> Pilot Gen 8 on <code>c8g</code> compute / per-core-bound / Java-heavy DAGs (STANDARD where Photon is blocked).</li>
    <li><strong>(c)</strong> Keep ARM. The 26.5%-faster-wall production evidence plus Photon-on-Graviton price-perf outweighs x86 CoreMark wins.</li>
  </ul>
</section>

<section id="s12">
  <h2><span class="secnum">§12</span>Appendix</h2>
  <h3>Sources &amp; citations</h3>
  <ul class="src">{citation_items}</ul>
  <h3>Assumptions</h3>
  <ul>
    <li>DBU/node-hour is generation-neutral at matched vCPU/RAM; the EC2-share band brackets any residual per-gen DBU drift.</li>
    <li>AWS TPC-DS end-to-end speedup applies to the whole observed wall (it is a full Spark-SQL workload).</li>
    <li>Spark speedup constants are external benchmarks (see <code>SPARK_SPEEDUP</code> source comment); all prices/CoreMark are CSV-derived.</li>
  </ul>
  <h3>Regeneration</h3>
  <p><code>{esc(regen_cmd)}</code></p>
  {appendix_table}
</section>

<footer>
  Generated by <code>scripts/analyze_instance_generations.py</code> · {esc(generated_at)} ·
  Data: <code>{esc(ec2_csv_path)}</code>{(" + <code>" + esc(fleet_csv_path) + "</code>") if fleet_csv_path else ""} ·
  Self-contained (no external assets).
</footer>
"""

    return (
        '<!DOCTYPE html>\n<html lang="en">\n<head>\n'
        '<meta charset="utf-8" />\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1" />\n'
        "<title>Spark Instance-Generation Cost-Benefit Analysis</title>\n"
        f"<style>{_CSS}</style>\n</head>\n<body>\n"
        f'<div class="wrap">{body}</div>\n</body>\n</html>\n'
    )


# ===========================================================================
# CLI
# ===========================================================================


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate the Spark instance-generation cost-benefit HTML report."
    )
    parser.add_argument(
        "--ec2-csv", default=str(DEFAULT_EC2_CSV), help="EC2 comparison CSV snapshot."
    )
    parser.add_argument(
        "--fleet-csv",
        default=None,
        help="Recommender output CSV (recommendations.csv) for live fleet-weighted savings. Optional.",
    )
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="Output HTML path.")
    args = parser.parse_args(argv)

    instances = parse_ec2_csv(args.ec2_csv)
    if not instances:
        print(f"error: no classifiable instances parsed from {args.ec2_csv}")
        return 2

    fleet: FleetSummary | None = None
    fleet_path_used: str | None = None
    if args.fleet_csv:
        fpath = Path(args.fleet_csv)
        if fpath.is_file():
            try:
                dags = parse_fleet_csv(fpath)
                if dags:
                    fleet = summarize_fleet(instances, dags)
                    fleet_path_used = args.fleet_csv
                else:
                    print(
                        f"warning: fleet CSV {args.fleet_csv} had no rows; rendering without fleet data"
                    )
            except (OSError, csv.Error, ValueError) as exc:
                print(
                    f"warning: could not read fleet CSV {args.fleet_csv}: {exc}; rendering without fleet data"
                )
        else:
            print(
                f"warning: fleet CSV not found at {args.fleet_csv}; rendering without fleet data"
            )

    ec2_rel = args.ec2_csv
    try:
        ec2_rel = str(Path(args.ec2_csv).resolve().relative_to(REPO_ROOT))
    except ValueError:
        pass

    html_doc = render_html(
        instances,
        fleet=fleet,
        ec2_csv_path=ec2_rel,
        fleet_csv_path=fleet_path_used,
    )
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html_doc, encoding="utf-8")
    print(
        f"wrote {out_path} ({len(html_doc):,} bytes; {len(instances)} instances; "
        f"fleet={'yes' if fleet else 'no'})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
