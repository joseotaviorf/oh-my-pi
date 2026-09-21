"""Unit tests for sync_escalation_hierarchy's pure identity-resolution logic (no Spark runtime)."""

from __future__ import annotations

import importlib.util
import sys
from datetime import datetime
from pathlib import Path
from unittest.mock import MagicMock

_REPO_ROOT = Path(__file__).resolve().parents[7]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

# Stub the heavy/runtime-only bietlejuice modules this job imports but this
# test never exercises (Spark session, Postgres driver, Delta/metastore
# writers) — same convention as test_load_idactum_raw_args.py. setdefault
# avoids clobbering a real module another test in the same pytest process
# already imported; without stubbing bietlejuice.loaders itself (not just
# .delta_loader), an earlier test's own stub of the bare "bietlejuice.loaders"
# package can otherwise break this module's real submodule import when the
# whole suite runs in one process.
for _mod in (
    "bietlejuice.base.spark",
    "bietlejuice.clients.db_clients",
    "bietlejuice.loaders",
    "bietlejuice.loaders.delta_loader",
    "bietlejuice.services.metastore_services",
):
    sys.modules.setdefault(_mod, MagicMock())

_MODULE_PATH = (
    _REPO_ROOT
    / "dags/governance/jira_escalation_hierarchy/spark_jobs/sync_escalation_hierarchy.py"
)
_spec = importlib.util.spec_from_file_location(
    "sync_escalation_hierarchy", _MODULE_PATH
)
sync_escalation_hierarchy = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sync_escalation_hierarchy)

_build_manager_chain_by_email = sync_escalation_hierarchy._build_manager_chain_by_email
_build_protected_executive_emails = (
    sync_escalation_hierarchy._build_protected_executive_emails
)
_build_escalation_targets = sync_escalation_hierarchy._build_escalation_targets
_target_for_level = sync_escalation_hierarchy._target_for_level
_next_escalation_preview = sync_escalation_hierarchy._next_escalation_preview
_maybe_notify_escalation = sync_escalation_hierarchy._maybe_notify_escalation
_build_escalation_card = sync_escalation_hierarchy._build_escalation_card
EscalationPolicy = sync_escalation_hierarchy.EscalationPolicy


def test_build_manager_chain_by_email_happy_path():
    chain_rows = [
        {
            "own_email": "IC@quintoandar.com.br",
            "l4_email": "l4@quintoandar.com.br",
            "l3_email": "l3@quintoandar.com.br",
            "l2_email": "l2@quintoandar.com.br",
        }
    ]
    lookup = _build_manager_chain_by_email(chain_rows)
    assert lookup == {
        "ic@quintoandar.com.br": (
            "l4@quintoandar.com.br",
            "l3@quintoandar.com.br",
            "l2@quintoandar.com.br",
        )
    }


def test_build_manager_chain_by_email_no_chain_stays_none():
    chain_rows = [
        {
            "own_email": "solo@x.com",
            "l4_email": None,
            "l3_email": None,
            "l2_email": None,
        }
    ]
    assert _build_manager_chain_by_email(chain_rows) == {
        "solo@x.com": (None, None, None)
    }


def test_build_manager_chain_by_email_is_order_independent_on_duplicate_email():
    row_a = {
        "own_email": "dup@x.com",
        "l4_email": "a@x.com",
        "l3_email": None,
        "l2_email": None,
    }
    row_b = {
        "own_email": "dup@x.com",
        "l4_email": "b@x.com",
        "l3_email": None,
        "l2_email": None,
    }
    assert _build_manager_chain_by_email(
        [row_a, row_b]
    ) == _build_manager_chain_by_email([row_b, row_a])


def test_build_protected_executive_emails_lowercases_and_dedupes():
    rows = [
        {"email": "CEO@quintoandar.com.br"},
        {"email": "ceo@quintoandar.com.br"},
        {"email": None},
        {"email": ""},
    ]
    assert _build_protected_executive_emails(rows) == {"ceo@quintoandar.com.br"}


def test_build_escalation_targets_all_levels_escalate_normally():
    manager_emails = ("l4@x.com", "l3@x.com", "l2@x.com")
    targets = _build_escalation_targets(
        "assignee@x.com", manager_emails, set(), "DEI-1"
    )
    assert targets == (
        ("l4@x.com", "L4"),
        ("l3@x.com", "L3"),
        ("l2@x.com", "L2"),
    )


def test_build_escalation_targets_repeats_previous_level_for_protected_executive():
    """L3 is a VP/CEO — repeat L4's target instead of escalating to them."""
    manager_emails = ("l4@x.com", "cto@x.com", "l2@x.com")
    protected = {"cto@x.com"}
    targets = _build_escalation_targets(
        "assignee@x.com", manager_emails, protected, "DEI-1"
    )
    assert targets == (
        ("l4@x.com", "L4"),
        ("l4@x.com", "L4"),  # L3 repeats L4, never reaches the CTO
        ("l2@x.com", "L2"),  # L2 resumes normally once past the protected level
    )


def test_build_escalation_targets_cascades_down_to_assignee_when_l4_is_protected():
    manager_emails = ("ceo@x.com", "l3@x.com", "l2@x.com")
    protected = {"ceo@x.com"}
    targets = _build_escalation_targets(
        "assignee@x.com", manager_emails, protected, "DEI-1"
    )
    assert targets[0] == ("assignee@x.com", "L0")  # L4 repeats the assignee (L0)
    assert targets[1] == ("l3@x.com", "L3")  # L3 has a real, unprotected manager


def test_build_escalation_targets_no_hr_chain_entry_also_repeats_previous_level():
    manager_emails = ("l4@x.com", None, None)
    targets = _build_escalation_targets(
        "assignee@x.com", manager_emails, set(), "DEI-1"
    )
    assert targets == (
        ("l4@x.com", "L4"),
        ("l4@x.com", "L4"),
        ("l4@x.com", "L4"),
    )


def test_target_for_level():
    targets = (("l4@x.com", "L4"), ("l3@x.com", "L3"), ("l2@x.com", "L2"))
    assert _target_for_level("L0", "assignee@x.com", targets) == (
        "assignee@x.com",
        "L0",
    )
    assert _target_for_level("L4", "assignee@x.com", targets) == ("l4@x.com", "L4")
    assert _target_for_level("L3", "assignee@x.com", targets) == ("l3@x.com", "L3")
    assert _target_for_level("L2", "assignee@x.com", targets) == ("l2@x.com", "L2")
    assert _target_for_level(None, "assignee@x.com", targets) == (None, None)


def test_next_escalation_preview_points_to_next_level():
    targets = (("l4@x.com", "L4"), ("l3@x.com", "L3"), ("l2@x.com", "L2"))
    # Medium: L0=5, L4=8, L3=12, L2=16. Currently at L4 (days_open=8+2=10).
    days_until_next, next_email = _next_escalation_preview(
        "L4", 10, "Medium", "assignee@x.com", targets
    )
    assert days_until_next == 2  # L3 threshold (12) - 10
    assert next_email == "l3@x.com"


def test_next_escalation_preview_none_at_last_level():
    targets = (("l4@x.com", "L4"), ("l3@x.com", "L3"), ("l2@x.com", "L2"))
    assert (
        _next_escalation_preview("L2", 20, "Medium", "assignee@x.com", targets) is None
    )


def test_next_escalation_preview_skips_protected_executive_too():
    """The next level being previewed also respects the executive cascade."""
    targets = _build_escalation_targets(
        "assignee@x.com",
        ("l4@x.com", "cto@x.com", "l2@x.com"),
        {"cto@x.com"},
        "DEI-1",
    )
    # At L4, next is L3 — but L3's real manager is the protected CTO, so the
    # preview must show L4's own target repeated, not the CTO.
    _, next_email = _next_escalation_preview(
        "L4", 10, "Medium", "assignee@x.com", targets
    )
    assert next_email == "l4@x.com"


def test_escalation_policy_target_level_by_criticality():
    cases = [
        # (days_open, criticality, expected)
        (None, "Medium", None),
        (0, "Medium", None),
        (4, "Medium", None),
        (5, "Medium", "L0"),
        (7, "Medium", "L0"),
        (8, "Medium", "L4"),
        (11, "Medium", "L4"),
        (12, "Medium", "L3"),
        (15, "Medium", "L3"),
        (16, "Medium", "L2"),
        (100, "Medium", "L2"),
        (1, "Critical", "L0"),
        (2, "Critical", "L4"),
        (4, "Critical", "L2"),
        (0, "Critical", None),
        (7, "Low", None),
        (8, "Low", "L0"),
        (24, "Low", "L2"),
        # Missing/unrecognized criticality falls back to the Medium schedule.
        (5, None, "L0"),
        (5, "Unknown", "L0"),
    ]
    for days_open, criticality, expected in cases:
        assert EscalationPolicy.target_level(days_open, criticality) == expected, (
            days_open,
            criticality,
        )


def test_higher_criticality_escalates_faster_than_lower():
    """Same days_open, Critical must reach a level Low hasn't reached yet."""
    days_open = 4
    critical_level = EscalationPolicy.target_level(days_open, "Critical")
    low_level = EscalationPolicy.target_level(days_open, "Low")
    assert EscalationPolicy.rank(critical_level) > EscalationPolicy.rank(low_level)


def test_escalation_policy_is_new_level():
    assert EscalationPolicy.is_new_level("L4", "L0") is True
    assert EscalationPolicy.is_new_level("L0", "L4") is False
    assert EscalationPolicy.is_new_level("L4", "L4") is False
    assert EscalationPolicy.is_new_level("L0", None) is True
    assert EscalationPolicy.is_new_level(None, None) is False


def test_maybe_notify_escalation_sends_only_newly_reached_level_once(monkeypatch):
    """Full staged-escalation timeline: exactly one DM per level, in order, no repeats."""
    notified_state = {}
    sent = []

    def fake_get(issue_key, auth):
        return notified_state.get(issue_key)

    def fake_put(issue_key, level_name, as_of_date, auth):
        notified_state[issue_key] = level_name
        return True

    def fake_notify(webhook_base, email, card):
        sent.append(email)
        return True

    monkeypatch.setattr(
        sync_escalation_hierarchy, "_get_escalation_notified_level", fake_get
    )
    monkeypatch.setattr(
        sync_escalation_hierarchy, "_put_escalation_notified_level", fake_put
    )
    monkeypatch.setattr(sync_escalation_hierarchy, "_notify_hub", fake_notify)

    targets = (("l4@x.com", "L4"), ("l3@x.com", "L3"), ("l2@x.com", "L2"))
    results = [
        _maybe_notify_escalation(
            "DEI-1",
            days,
            "Medium",
            "assignee@x.com",
            "Pat Assignee",
            targets,
            "http://fake",
            "summary",
            datetime(2026, 1, 1),
            auth=None,
        )
        for days in (3, 5, 5, 6, 8, 8, 12, 16, 20)
    ]

    assert sent == ["assignee@x.com", "l4@x.com", "l3@x.com", "l2@x.com"]
    assert [r[0] if r else None for r in results] == [
        None,
        "L0",
        None,
        None,
        "L4",
        None,
        "L3",
        "L2",
        None,
    ]
    assert all(r[2] == "sent" for r in results if r is not None)


def test_maybe_notify_escalation_repeats_previous_level_never_reaches_executive(
    monkeypatch,
):
    """End-to-end: L3/L2 due, but both are protected -> both notify L4 instead."""
    monkeypatch.setattr(
        sync_escalation_hierarchy,
        "_get_escalation_notified_level",
        lambda issue_key, auth: "L4",
    )
    monkeypatch.setattr(
        sync_escalation_hierarchy, "_put_escalation_notified_level", lambda *a: True
    )
    sent = []
    monkeypatch.setattr(
        sync_escalation_hierarchy,
        "_notify_hub",
        lambda webhook_base, email, card: sent.append(email) or True,
    )

    targets = _build_escalation_targets(
        "assignee@x.com",
        ("l4@x.com", "cto@x.com", "ceo@x.com"),
        {"cto@x.com", "ceo@x.com"},
        "DEI-1",
    )
    result = _maybe_notify_escalation(
        "DEI-1",
        12,
        "Medium",
        "assignee@x.com",
        "Pat Assignee",
        targets,
        "http://fake",
        "summary",
        datetime(2026, 1, 1),
        auth=None,
    )
    assert result == ("L3", "l4@x.com", "sent")
    assert sent == ["l4@x.com"]


def test_maybe_notify_escalation_no_email_for_l0_reports_skipped(monkeypatch):
    """The only case where a target can still be missing: L0 with no assignee email."""
    monkeypatch.setattr(
        sync_escalation_hierarchy,
        "_get_escalation_notified_level",
        lambda issue_key, auth: None,
    )
    targets = _build_escalation_targets(
        None, ("l4@x.com", "l3@x.com", "l2@x.com"), set(), "DEI-1"
    )
    result = _maybe_notify_escalation(
        "DEI-1",
        5,
        "Medium",
        None,
        "the assignee",
        targets,
        "http://fake",
        "summary",
        datetime(2026, 1, 1),
        auth=None,
    )
    assert result == ("L0", None, "skipped_no_email")


def test_maybe_notify_escalation_no_webhook_configured_skips():
    targets = (("l4@x.com", "L4"), ("l3@x.com", "L3"), ("l2@x.com", "L2"))
    result = _maybe_notify_escalation(
        "DEI-1",
        8,
        "Medium",
        "assignee@x.com",
        "Pat Assignee",
        targets,
        None,
        "summary",
        datetime(2026, 1, 1),
        auth=None,
    )
    assert result is None


def test_maybe_notify_escalation_skips_instead_of_resending_on_read_failure(
    monkeypatch,
):
    """A transient read error must skip the issue, not be mistaken for "never
    notified" -- otherwise an already-sent level gets DMed again."""

    def raise_read_error(issue_key, auth):
        raise ConnectionError("Jira API blip")

    sent = []
    monkeypatch.setattr(
        sync_escalation_hierarchy,
        "_get_escalation_notified_level",
        raise_read_error,
    )
    monkeypatch.setattr(
        sync_escalation_hierarchy,
        "_notify_hub",
        lambda webhook_base, email, card: sent.append(email) or True,
    )

    targets = (("l4@x.com", "L4"), ("l3@x.com", "L3"), ("l2@x.com", "L2"))
    result = _maybe_notify_escalation(
        "DEI-1",
        8,
        "Medium",
        "assignee@x.com",
        "Pat Assignee",
        targets,
        "http://fake",
        "summary",
        datetime(2026, 1, 1),
        auth=None,
    )

    assert result is None
    assert sent == []


def test_maybe_notify_escalation_reports_write_failure_without_losing_the_send(
    monkeypatch,
):
    """The DM already went out; a failed idempotency write must surface as a
    distinct status so it's visible, not silently reported as a clean "sent"."""
    monkeypatch.setattr(
        sync_escalation_hierarchy,
        "_get_escalation_notified_level",
        lambda issue_key, auth: None,
    )
    monkeypatch.setattr(
        sync_escalation_hierarchy, "_put_escalation_notified_level", lambda *a: False
    )
    monkeypatch.setattr(
        sync_escalation_hierarchy,
        "_notify_hub",
        lambda webhook_base, email, card: True,
    )

    targets = (("l4@x.com", "L4"), ("l3@x.com", "L3"), ("l2@x.com", "L2"))
    result = _maybe_notify_escalation(
        "DEI-1",
        8,
        "Medium",
        "assignee@x.com",
        "Pat Assignee",
        targets,
        "http://fake",
        "summary",
        datetime(2026, 1, 1),
        auth=None,
    )

    assert result == ("L4", "l4@x.com", "sent_property_write_failed")


def test_put_escalation_notified_level_retries_once_before_failing(monkeypatch):
    calls = []

    class FakeResponse:
        def __init__(self, ok):
            self.ok = ok

        def raise_for_status(self):
            if not self.ok:
                raise ConnectionError("Jira API blip")

    def fake_put(url, json, auth, timeout):
        calls.append(url)
        # Fails once, then succeeds -- confirms the retry actually happens.
        return FakeResponse(ok=len(calls) == 2)

    monkeypatch.setattr(sync_escalation_hierarchy.requests, "put", fake_put)

    result = sync_escalation_hierarchy._put_escalation_notified_level(
        "DEI-1", "L4", "2026-01-01", auth=None
    )

    assert result is True
    assert len(calls) == 2


def test_escalation_notice_l3_names_assignee_and_explains_dei_context():
    notice = sync_escalation_hierarchy._escalation_notice("L3", "Maria Silva")
    assert "Maria Silva" in notice
    assert "second level" in notice
    assert "data incident" in notice
    assert "DEI" in notice
    assert "on your team" in notice


def test_format_assignee_display_name_prefers_jira_then_hr():
    names = {"ic@x.com": "HR Name"}
    assert (
        sync_escalation_hierarchy._format_assignee_display_name(
            "Jira Name", "ic@x.com", names
        )
        == "Jira Name"
    )
    assert (
        sync_escalation_hierarchy._format_assignee_display_name(None, "ic@x.com", names)
        == "HR Name"
    )


def test_build_escalation_card_escapes_html_in_summary():
    """A crafted summary must not inject markup into the Chat card -- the
    card's own lines use literal <b>/<a href> HTML, so unescaped reporter
    text would render as a clickable link inside a trusted DM."""
    malicious_summary = '<a href="https://evil.example">click here</a>'

    card = _build_escalation_card(
        "DEI-1", malicious_summary, 5, "L4", "L4", "Pat Assignee", None
    )

    text = card["card"]["sections"][0]["widgets"][0]["textParagraph"]["text"]
    assert '<a href="https://evil.example">' not in text
    assert "&lt;a href=" in text
    # The card's own trusted link (Open in Jira) must still render as real HTML.
    assert '<a href="https://quintoandar.atlassian.net/browse/DEI-1">' in text


def test_notify_hub_posts_dm_only_without_space(monkeypatch):
    captured = {}

    class FakeResponse:
        def raise_for_status(self):
            return None

    def fake_post(url, json, timeout):
        captured["url"] = url
        captured["payload"] = json
        return FakeResponse()

    monkeypatch.setattr(sync_escalation_hierarchy.requests, "post", fake_post)

    card = {"cardId": "escalation-DEI-1-L0", "card": {"header": {"title": "x"}}}
    assert sync_escalation_hierarchy._notify_hub("http://fake-hub", "ic@q.com", card)

    assert captured["payload"] == {
        "cardsV2": [card],
        "info": {"email": ["ic@q.com"]},
    }
    assert "space" not in captured["payload"]
