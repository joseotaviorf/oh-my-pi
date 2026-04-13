"""Unit tests for event_config_resolution."""

import pytest

from bietlejuice.base.core_models.helpers.event_config_resolution import (
    resolve_event_configs,
    resolve_event_name,
    with_resolved_event_name,
)


def test_resolve_event_name_explicit_wins():
    assert (
        resolve_event_name(
            {
                "event_name": "ev_STATUS",
                "target_col": "other",
            }
        )
        == "ev_STATUS"
    )


def test_resolve_event_name_strips_whitespace():
    assert resolve_event_name({"event_name": "  ev_X  "}) == "ev_X"


def test_resolve_event_name_from_target_col():
    assert resolve_event_name({"target_col": "id_tenant"}) == "ev_id_tenant"


def test_resolve_event_name_empty_string_event_name_falls_back_to_target_col():
    assert resolve_event_name({"event_name": "", "target_col": "status"}) == "ev_status"


def test_resolve_event_name_raises_when_both_missing():
    with pytest.raises(ValueError, match="event_name' or 'target_col"):
        resolve_event_name({"tracked_col": "x"})


def test_resolve_event_name_raises_includes_index_when_given():
    with pytest.raises(ValueError) as exc_info:
        resolve_event_name({}, index=2)
    assert "index 2" in str(exc_info.value)


def test_with_resolved_event_name_copies_and_sets():
    raw = {"target_col": "rent", "target_type": "double"}
    out = with_resolved_event_name(raw)
    assert out["event_name"] == "ev_rent"
    assert "event_name" not in raw


def test_resolve_event_configs():
    configs = [
        {"target_col": "a", "event_name": "ev_A"},
        {"target_col": "b"},
    ]
    out = resolve_event_configs(configs)
    assert out[0]["event_name"] == "ev_A"
    assert out[1]["event_name"] == "ev_b"
