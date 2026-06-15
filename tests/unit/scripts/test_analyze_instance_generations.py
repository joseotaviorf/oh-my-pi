"""Unit tests for scripts/analyze_instance_generations.py.

Stdlib only — no Trino, no network. The aggregate/preset assertions are pinned
against the committed CSV snapshot (scripts/ec2_instance_comparison.csv); the
fleet-projection and mixed-generation assertions use in-memory fixtures.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from scripts import analyze_instance_generations as aig  # noqa: E402
from scripts.analyze_instance_generations import (  # noqa: E402
    FleetDag,
    aggregate_by_prefix,
    classify_node,
    closed_form_ratio,
    matched_size_price_ratio,
    mixed_generation_options,
    num,
    parse_ec2_csv,
    preset_economics,
    price,
    project_fleet,
    render_html,
)

CSV_PATH = REPO_ROOT / "scripts" / "ec2_instance_comparison.csv"


@pytest.fixture(scope="module")
def instances():
    return parse_ec2_csv(CSV_PATH)


# ---------------------------------------------------------------------------
# Value parsing
# ---------------------------------------------------------------------------


def test_price_parsing():
    assert price("$0.0384 hourly") == 0.0384
    assert price("$1.6128 hourly") == 1.6128
    assert price("") is None
    assert price(None) is None


def test_num_parsing():
    assert num("19,098.549") == 19098.549
    assert num("2 GiB") == 2
    assert num("1 vCPUs") == 1
    assert num("") is None
    assert num(None) is None


# ---------------------------------------------------------------------------
# Generation + architecture classification
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "node,family,gen,arch",
    [
        ("m6g.2xlarge", "general", 6, "ARM"),
        ("r7gd.4xlarge", "memory", 7, "ARM"),
        ("c8g.xlarge", "compute", 8, "ARM"),
        ("m8a.16xlarge", "general", 8, "AMD"),
        ("c5.large", "compute", 5, "Intel"),
    ],
)
def test_classify_node(node, family, gen, arch):
    nc = classify_node(node)
    assert nc is not None
    assert (nc.family, nc.gen, nc.arch) == (family, gen, arch)


def test_classify_node_rejects_non_cmr():
    assert classify_node("i3.large") is None
    assert classify_node("t3.medium") is None
    assert classify_node("") is None


# ---------------------------------------------------------------------------
# Prefix aggregation — pinned to the committed CSV (±0.5%)
# ---------------------------------------------------------------------------

_EXPECTED_CM_PER_OD = {
    "c6g": 579807,
    "c7g": 691901,
    "c8g": 737647,
    "m6g": 512494,
    "m7g": 631762,
    "m8g": 626042,
    "r6g": 387476,
    "r7g": 467888,
    "r8g": 468343,
}


def test_aggregate_by_prefix_cm_per_od(instances):
    agg = aggregate_by_prefix(instances)
    for prefix, expected in _EXPECTED_CM_PER_OD.items():
        assert prefix in agg, prefix
        got = agg[prefix].cm_per_od
        assert got is not None
        assert abs(got - expected) / expected < 0.005, (prefix, got, expected)


def test_aggregate_has_efficiency_metrics(instances):
    agg = aggregate_by_prefix(instances)
    c6g = agg["c6g"]
    assert c6g.cm_per_vcpu and c6g.cm_per_spot and c6g.spot_od_ratio
    # ARM spot:OD sits below the recommender's flat 0.37.
    assert c6g.spot_od_ratio < 0.37


# ---------------------------------------------------------------------------
# Preset economics
# ---------------------------------------------------------------------------


def test_preset_economics_general_m(instances):
    rows = {(r.family, r.tier): r for r in preset_economics(instances)}
    gm = rows[("general", "m")]
    assert gm.nodes[6] == "m6g.2xlarge"
    assert gm.nodes[7] == "m7g.2xlarge"
    assert gm.nodes[8] == "m8g.2xlarge"
    assert abs(gm.od[6] - 0.308) < 0.001
    assert abs(gm.od[7] - 0.326) < 0.002
    assert abs(gm.od[8] - 0.359) < 0.001
    assert abs(gm.price_ratio_67 - 1.060) < 0.005  # +6.0%
    assert abs(gm.price_ratio_78 - 1.100) < 0.005  # +10%
    # Faster Spark wall outpaces the +6% price -> cheaper per unit work.
    assert gm.cost_of_work_67 < 0


def test_preset_economics_memory_xl(instances):
    rows = {(r.family, r.tier): r for r in preset_economics(instances)}
    rx = rows[("memory", "xl")]
    assert rx.nodes[6] == "r6g.8xlarge"
    assert rx.nodes[7] == "r7g.8xlarge"
    assert rx.nodes[8] == "r8g.8xlarge"
    assert abs(rx.od[6] - 1.613) < 0.002
    assert abs(rx.price_ratio_67 - 1.062) < 0.01  # +6.2%
    assert abs(rx.price_ratio_78 - 1.100) < 0.005  # +10%


def test_compute_xs_cell_nodes(instances):
    rows = {(r.family, r.tier): r for r in preset_economics(instances)}
    cxs = rows[("compute", "xs")]
    assert cxs.nodes[6] == "c6g.large"
    assert cxs.nodes[7] == "c7g.large"
    assert cxs.nodes[8] == "c8g.large"


def test_matched_size_price_ratio(instances):
    assert abs(matched_size_price_ratio(instances, "general", 6, 7) - 1.06) < 0.01
    assert abs(matched_size_price_ratio(instances, "memory", 7, 8) - 1.10) < 0.005
    assert matched_size_price_ratio(instances, "compute", 6, 6) == 1.0


# ---------------------------------------------------------------------------
# Closed-form total-cost ratio
# ---------------------------------------------------------------------------


def test_closed_form_gen6_to_7_band():
    # Gen6->7: p=1.06, s=1.15 -> 9..12% saving across e in [0.3, 0.7].
    for e in (0.3, 0.5, 0.7):
        saving = 1 - closed_form_ratio(e, 1.06, 1.15)
        assert 0.085 <= saving <= 0.125, (e, saving)


def test_closed_form_gen7_to_8_band():
    # Gen7->8: p=1.10, s=1.08 -> 1..5% saving across e in [0.3, 0.7].
    for e in (0.3, 0.5, 0.7):
        saving = 1 - closed_form_ratio(e, 1.10, 1.08)
        assert 0.0 < saving <= 0.055, (e, saving)


# ---------------------------------------------------------------------------
# Fleet projection on a 2-DAG fixture
# ---------------------------------------------------------------------------


def _dag(dag_id, gen, ec2, dbu, *, family="general", tier="m"):
    node = aig._preset_node(family, gen, tier)
    return FleetDag(
        dag_id=dag_id,
        driver_node=node,
        worker_node=node,
        worker_count=2,
        total_cost=ec2 + dbu,
        ec2_cost=ec2,
        dbu_cost=dbu,
        arm_days=1.0,
        runs_per_day=1.0,
        wall_p50_min=30.0,
        family=family,
        gen=gen,
        arch="ARM",
        tier=tier,
    )


def test_fleet_projection_gen7_positive(instances):
    # DAG A: gen6 EC2 60 / DBU 40; DAG B: gen6 EC2 30 / DBU 70.
    dags = [_dag("A", 6, 60.0, 40.0), _dag("B", 6, 30.0, 70.0)]
    pr = project_fleet(instances, dags, 7)
    assert pr.n_projected == 2
    assert pr.saving["mid"] > 0
    assert 0.09 <= pr.saving_pct["mid"] <= 0.12


def test_fleet_projection_gen8_marginal(instances):
    # Gen7 fleet projected to Gen8: 1..5% saving.
    dags = [_dag("A", 7, 60.0, 40.0), _dag("B", 7, 30.0, 70.0)]
    pr = project_fleet(instances, dags, 8)
    assert pr.n_projected == 2
    assert 0.01 <= pr.saving_pct["mid"] <= 0.05


def test_fleet_projection_never_downgrades(instances):
    # A gen8 DAG is never projected when targeting gen7.
    dags = [_dag("A", 8, 60.0, 40.0)]
    pr = project_fleet(instances, dags, 7)
    assert pr.n_projected == 0
    assert pr.saving["mid"] == pytest.approx(0.0, abs=1e-9)


def test_fleet_projection_tracks_ec2_dbu_separately(instances):
    # EC2 and DBU scale differently (p/s vs 1/s), so projected split != current.
    dags = [_dag("A", 6, 60.0, 40.0), _dag("B", 6, 30.0, 70.0)]
    pr = project_fleet(instances, dags, 7)
    assert pr.new_ec2["mid"] + pr.new_dbu["mid"] == pytest.approx(
        pr.new_total["mid"]
    )
    cur_ec2_share = 90.0 / 200.0
    proj_ec2_share = pr.new_ec2["mid"] / pr.new_total["mid"]
    assert proj_ec2_share != pytest.approx(cur_ec2_share)


# ---------------------------------------------------------------------------
# Mixed-generation 3-option model
# ---------------------------------------------------------------------------


def test_mixed_generation_under_one_percent(instances):
    opts = mixed_generation_options(instances)
    g7 = opts["all_gen7"]
    mixed = opts["mixed"]
    # Mixed (Gen6 driver) is cheaper than all-Gen7 only by the driver OD delta.
    saving = g7.total - mixed.total
    assert saving > 0
    assert saving / g7.total < 0.01
    # Worker cost + DBU are identical (wall is worker-set).
    assert mixed.worker_spot == g7.worker_spot
    assert mixed.dbu_cost == g7.dbu_cost


# ---------------------------------------------------------------------------
# Report rendering — no fleet data
# ---------------------------------------------------------------------------


def test_render_html_without_fleet(instances):
    out = render_html(instances, fleet=None)
    assert out.startswith("<!DOCTYPE html>")
    assert "live fleet data not provided" in out
    assert "Graviton3" in out
    assert "<svg" in out
    # Six charts.
    assert out.count("<svg") == 6
    # Headline + key markers.
    assert "1.14" in out
    assert "1.08" in out
    # Per-family t-shirt cells.
    assert "c6g.large" in out
    assert "m6g.2xlarge" in out
    assert "r6g.8xlarge" in out
    assert "c7g.large" in out and "c8g.large" in out
    # Mixed-generation table + migration-doc link.
    assert "Mixed: Gen 6 driver + Gen 7 workers" in out
    assert "recommender_multigeneration_migration_plan.md" in out


def test_render_html_with_fleet(instances):
    dags = [_dag("A", 6, 60.0, 40.0), _dag("B", 6, 30.0, 70.0)]
    summary = aig.summarize_fleet(instances, dags)
    out = render_html(instances, fleet=summary)
    assert "live fleet data not provided" not in out
    assert "$/yr" in out
    assert out.count("<svg") == 6
