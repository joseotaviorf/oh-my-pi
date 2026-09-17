import importlib.util
import sys
from datetime import date
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_BIETLEJUICE_MOCKS = [
    "bietlejuice.base.db.reverse_metastore_mapping",
    "bietlejuice.base.validation.spark_args",
    "bietlejuice.clients.db_clients",
    "bietlejuice.loaders.delta_loader",
    "bietlejuice.services.configuration_service",
    "bietlejuice.services.metastore_services",
    "quintoandar_logger",
]
for _module in _BIETLEJUICE_MOCKS:
    sys.modules.setdefault(_module, MagicMock())

_JOB_PATH = (
    Path(__file__).resolve().parents[7]
    / "dags/growth/reverse_gsc_metrics_access/spark_jobs/load_into_sqs.py"
)
_SPEC = importlib.util.spec_from_file_location("reverse_gsc_load_into_sqs", _JOB_PATH)
assert _SPEC is not None and _SPEC.loader is not None
load_into_sqs = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(load_into_sqs)


@pytest.mark.parametrize(
    ("reference_date", "expected_snapshot_ref_date"),
    [
        ("2026-09-14", date(2026, 9, 7)),
        ("2026-01-05", date(2025, 12, 29)),
    ],
)
def test_snapshot_ref_date_closes_at_d_minus_seven(
    reference_date: str,
    expected_snapshot_ref_date: date,
):
    # Arrange / Act
    snapshot_ref_date = load_into_sqs._snapshot_ref_date(reference_date)

    # Assert
    assert snapshot_ref_date == expected_snapshot_ref_date


def test_snapshot_ref_date_rejects_invalid_reference_date():
    # Arrange / Act / Assert
    with pytest.raises(ValueError):
        load_into_sqs._snapshot_ref_date("2026/09/14")
