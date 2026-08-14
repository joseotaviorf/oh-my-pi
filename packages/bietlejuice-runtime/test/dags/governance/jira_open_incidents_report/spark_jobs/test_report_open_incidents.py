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
    "bietlejuice.loaders": MagicMock(),
    "bietlejuice.loaders.delta_loader": MagicMock(),
    "bietlejuice.services": MagicMock(),
    "bietlejuice.services.configuration_service": MagicMock(),
    "quintoandar_logger": MagicMock(),
    "requests": MagicMock(),
    "yaml": MagicMock(),
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
        "Data Governance: 3 opened DEI incidents (newest: 1d, oldest: 146d)\n"
        "no owner: 2 opened DEI incidents (newest: 225d, oldest: 225d)\n"
        "For Rent: 1 opened DEI incidents (newest: 4d, oldest: 4d)"
    )
