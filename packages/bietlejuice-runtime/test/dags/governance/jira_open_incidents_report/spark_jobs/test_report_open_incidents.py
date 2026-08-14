"""Unit tests for the open-incidents Chat leaderboard formatter."""

import builtins
import importlib
import os
import sys
from datetime import datetime
from unittest.mock import MagicMock, patch


def _repo_root() -> str:
    cur = os.path.abspath(os.path.dirname(__file__))
    while cur != os.path.dirname(cur):
        if os.path.exists(os.path.join(cur, ".git")):
            return cur
        cur = os.path.dirname(cur)
    raise RuntimeError("Cannot find repo root")


_SRC_SPARK_JOBS = os.path.join(
    _repo_root(),
    "dags",
    "governance",
    "jira_open_incidents_report",
    "spark_jobs",
)
if _SRC_SPARK_JOBS not in sys.path:
    sys.path.insert(0, _SRC_SPARK_JOBS)

builtins.spark = MagicMock()

_IMPORT_TIME_MOCKS = {
    "bietlejuice": MagicMock(),
    "bietlejuice.base": MagicMock(),
    "bietlejuice.base.service": MagicMock(),
    "bietlejuice.base.service.dag_packages_path_service": MagicMock(),
    "bietlejuice.clients": MagicMock(),
    "bietlejuice.clients.db_clients": MagicMock(),
    "bietlejuice.loaders": MagicMock(),
    "bietlejuice.loaders.delta_loader": MagicMock(),
    "bietlejuice.services": MagicMock(),
    "bietlejuice.services.configuration_service": MagicMock(),
    "bietlejuice.services.metastore_services": MagicMock(),
    "quintoandar_logger": MagicMock(),
    "requests": MagicMock(),
    "yaml": MagicMock(),
    "pyspark": MagicMock(),
    "pyspark.sql": MagicMock(),
    "pyspark.sql.functions": MagicMock(),
}

with patch.dict("sys.modules", _IMPORT_TIME_MOCKS):
    _job = importlib.import_module("report_open_incidents")

_AS_OF = datetime(2026, 8, 14)


def test_format_message_empty():
    assert _job._format_message([], _AS_OF) == "No open DEI incidents as of 2026-08-14."


def test_format_message_leaderboard_by_line_count_desc():
    rows = [
        {
            "incident_owner": "Data Governance",
            "ts_created": datetime(2026, 3, 21),
        },
        {
            "incident_owner": "Data Governance",
            "ts_created": datetime(2026, 8, 13),
        },
        {
            "incident_owner": "Data Governance",
            "ts_created": datetime(2026, 7, 1),
        },
        {
            "incident_owner": "For Rent",
            "ts_created": datetime(2026, 8, 10),
        },
        {"incident_owner": None, "ts_created": datetime(2026, 1, 1)},
        {"incident_owner": "  ", "ts_created": None},
    ]

    message = _job._format_message(rows, _AS_OF)

    assert message == (
        "Open DEI incidents as of 2026-08-14 — 6 total:\n"
        "Data Governance: 3 opened DEI incidents (newest: 1d, oldest: 146d)"
        " | on going 0 | unassigned 3 | description not filled 3\n"
        "no owner: 2 opened DEI incidents (newest: 225d, oldest: 225d)"
        " | on going 0 | unassigned 2 | description not filled 2\n"
        "For Rent: 1 opened DEI incidents (newest: 4d, oldest: 4d)"
        " | on going 0 | unassigned 1 | description not filled 1"
    )


_MARKDOWN_TEMPLATE = (
    "**Incident format template** "
    "**Problem:** Here we describe what happened, bringing inputs like which DAG "
    "is broken, on which task, and available task Logs from Airflow/Databricks "
    "that are relevant to the incident "
    "**Cause:** Here we describe the incident root cause, or what we think could "
    "be the it when we can't really track it down. We bring inputs like "
    '"Spark loaded column X as INT even though it\'s STRING", or even logs that '
    "clarify the error, like lack of permissions to a given google sheet. "
    "**Solution:** Here we bring what was done to solve the problem, always "
    "keeping in mind that if it was an temporary solution, like "
    '"Increased cluster resources" or "Marked task as success" only to put out '
    "the fire, we need to make it clear on the card, so the responsible team can "
    "start working on the permanent solution. "
    "Complete Fill Guide: https://docs.google.com/document/d/example "
    "**Problem:** **Cause:** **Solution:** "
    "**Databricks Details (auto)** **Cluster Log Location:**"
)

_ADF_TEMPLATE = (
    '{"type":"doc","version":1,"content":[{"type":"panel","content":'
    '[{"type":"paragraph","content":['
    '{"type":"text","text":"Incident format template","marks":[{"type":"strong"}]},'
    '{"type":"hardBreak"},'
    '{"type":"text","text":"Problem:","marks":[{"type":"strong"}]},'
    '{"type":"text","text":" Here we describe what happened, bringing inputs '
    'like which DAG is broken, on which task, and available task Logs from '
    'Airflow/Databricks that are relevant to the incident"}'
    "]}]}]}"
)


def test_description_not_filled_when_empty_or_template():
    assert _job._is_description_filled(None) is False
    assert _job._is_description_filled("  ") is False
    assert _job._is_description_filled(_MARKDOWN_TEMPLATE) is False
    assert _job._is_description_filled(_ADF_TEMPLATE) is False


def test_description_filled_when_human_text_or_custom_writeup():
    filled_slots = (
        _MARKDOWN_TEMPLATE.split("Complete Fill Guide:")[0]
        + "Complete Fill Guide: https://example "
        + "**Problem:** DAG x failed on task y **Cause:** **Solution:**"
    )
    assert _job._is_description_filled(filled_slots) is True
    assert (
        _job._is_description_filled(
            "**Problem:**\nThe task `execute-job-cluster` failed.\n\n"
            "**Cause:** Graviton mismatch.\n\n**Solution:** Align node types."
        )
        is True
    )


def test_is_unassigned():
    assert _job._is_unassigned(None) is True
    assert _job._is_unassigned("  ") is True
    assert _job._is_unassigned("Ada Lovelace") is False


def test_card_status_on_going_vs_backlog():
    assert _job._is_on_going("Em andamento", "In Progress") is True
    assert _job._is_on_going("On going", "In Progress") is True
    assert _job._is_on_going("Tarefas pendentes", "To Do") is False
    assert _job._is_on_going("Backlog", "To Do") is False
    assert _job._is_on_going(None, None) is False


def test_format_message_hygiene_counts_mix_assigned_filled_on_going():
    rows = [
        {
            "incident_owner": "Data Fintech",
            "ts_created": datetime(2026, 8, 10),
            "assignee": None,
            "issue_description": _MARKDOWN_TEMPLATE,
            "current_status": "Backlog",
            "current_status_category": "To Do",
        },
        {
            "incident_owner": "Data Fintech",
            "ts_created": datetime(2026, 8, 12),
            "assignee": "Ada Lovelace",
            "issue_description": "**Problem:** Recupera load failed on merge.",
            "current_status": "On going",
            "current_status_category": "In Progress",
        },
        {
            "incident_owner": "Data Fintech",
            "ts_created": datetime(2026, 8, 13),
            "assignee": "Ada Lovelace",
            "issue_description": "**Problem:** Still in inbox.",
            "current_status": "Tarefas pendentes",
            "current_status_category": "To Do",
        },
    ]

    message = _job._format_message(rows, _AS_OF)

    assert message == (
        "Open DEI incidents as of 2026-08-14 — 3 total:\n"
        "Data Fintech: 3 opened DEI incidents (newest: 1d, oldest: 4d)"
        " | on going 1 | unassigned 1 | description not filled 1"
    )
