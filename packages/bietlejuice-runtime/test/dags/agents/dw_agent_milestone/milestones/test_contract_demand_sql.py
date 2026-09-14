"""Unit tests for Agents strategy SQL param rendering (scan_predicate stays raw)."""

from __future__ import annotations

from pathlib import Path

from bietlejuice.milestones.sql_runner import _apply_sql_params, resolve_sql_path

_REPO = Path(__file__).resolve().parents[7]
STRATEGIES_ROOT = (
    _REPO
    / "dags"
    / "agents"
    / "dw_agent_milestone"
    / "queries"
    / "dw"
    / "dim_agent_milestone"
    / "milestones"
)


def test_accreditation_scan_predicate_not_escaped():
    path = resolve_sql_path(str(STRATEGIES_ROOT), "accreditation_events.sql")
    text = path.read_text(encoding="utf-8")
    out = _apply_sql_params(
        text,
        {
            "action": "Accreditation",
            "scan_predicate": "aral.ts_revision >= TIMESTAMP('2024-06-08 12:00:00')",
        },
    )
    assert "Accreditation" in out
    assert "aral.ts_revision >= TIMESTAMP('2024-06-08 12:00:00')" in out
    assert "TIMESTAMP(''2024" not in out


def test_visit_sql_params_render_vb():
    path = resolve_sql_path(str(STRATEGIES_ROOT), "visit_events.sql")
    text = path.read_text(encoding="utf-8")
    out = _apply_sql_params(
        text,
        {
            "event_ts_expr": "vs.ts_schedule_confirmed",
            "scan_predicate": "1 = 1",
        },
    )
    assert "vs.ts_schedule_confirmed" in out
    assert "{scan_predicate}" not in out
    assert "{event_ts_expr}" not in out
    assert "{extra_filter}" not in text


def test_first_valid_listing_hardcodes_valid_flag():
    path = resolve_sql_path(str(STRATEGIES_ROOT), "first_valid_listing_events.sql")
    text = path.read_text(encoding="utf-8")
    assert "fl.is_first_listing_valid = true" in text
    assert "{extra_filter}" not in text


def test_ccv_uses_numeric_id_house_not_string_id_offer():
    """sale_offer.id_offer is Firestore STRING; CAST to BIGINT is always NULL."""
    path = resolve_sql_path(str(STRATEGIES_ROOT), "contract_signed_sale_events.sql")
    text = path.read_text(encoding="utf-8")
    assert "CAST(so.id_house AS BIGINT) AS sk_entity" in text
    assert "CAST(so.id_offer AS BIGINT)" not in text
    assert "datalake_sale_offer.sale_offer.id_house" in text


def test_metadata_milestones_registry_loads():
    from bietlejuice.milestones.registry import load_milestones_from_metadata_yaml

    meta = (
        _REPO
        / "dags"
        / "agents"
        / "dw_agent_milestone"
        / "metadata"
        / "dw"
        / "dim_agent_milestone.yml"
    )
    registry, sticky = load_milestones_from_metadata_yaml(
        meta.read_text(encoding="utf-8")
    )
    assert sticky == ("id_agent",)
    assert "VB" in registry
    assert registry["VB"]["sql_file"] == "visit_events.sql"
    assert registry["ACCREDITATION"]["params"]["action"] == "Accreditation"
    assert "TQC" in registry
    assert "TQC_TQA" not in registry
    assert "TQA" in registry
    assert registry["TQC"]["params"]["business_context"] == "SALE"
    assert registry["TQA"]["params"]["business_context"] == "RENT"


def test_tqc_sql_renders_sale_business_context():
    path = resolve_sql_path(
        str(STRATEGIES_ROOT), "demand_acquisition_funnel_events.sql"
    )
    text = path.read_text(encoding="utf-8")
    base_params = {
        "scan_predicate": "1 = 1",
        "ts_expr": "valid_from",
        "entity_expr": "id_referral",
        "entity_type": "datalake_agent_performance.fact_agent_demand_acquisition.id_referral",
        "same_agent_expr": "TRUE",
    }
    out = _apply_sql_params(text, {**base_params, "business_context": "SALE"})
    assert "fada.business_context = 'SALE'" in out
    assert "{business_context}" not in out
    assert "{scan_predicate}" not in out
    rent = _apply_sql_params(text, {**base_params, "business_context": "RENT"})
    assert "fada.business_context = 'RENT'" in rent
