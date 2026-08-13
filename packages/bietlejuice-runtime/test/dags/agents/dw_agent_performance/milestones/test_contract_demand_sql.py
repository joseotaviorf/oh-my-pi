"""Unit tests for Agents strategy SQL param rendering (scan_predicate stays raw)."""

from __future__ import annotations

from pathlib import Path

from bietlejuice.milestones.sql_runner import _apply_sql_params, resolve_sql_path

_REPO = Path(__file__).resolve().parents[7]
STRATEGIES_ROOT = (
    _REPO
    / "dags"
    / "agents"
    / "dw_agent_performance"
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


def test_metadata_milestones_registry_loads():
    from bietlejuice.milestones.registry import load_milestones_from_metadata_yaml

    meta = (
        _REPO
        / "dags"
        / "agents"
        / "dw_agent_performance"
        / "metadata"
        / "dw"
        / "dim_agent_milestone.yml"
    )
    registry, sticky = load_milestones_from_metadata_yaml(
        meta.read_text(encoding="utf-8")
    )
    assert sticky == ("id_agent",)
    assert "first_vb" in registry
    assert registry["first_vb"]["sql_file"] == "visit_events.sql"
    assert registry["accreditation"]["params"]["action"] == "Accreditation"
