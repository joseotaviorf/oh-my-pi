from datetime import datetime, timezone

import numpy as np

from bietlejuice.observability.monitoring.empty_partition import (
    finding_thread_key,
    format_finding_message,
    judge_empty_partitions,
    normalize_partition_key,
    partition_key_fingerprint,
)
from bietlejuice.observability.monitoring.sla_expectations import (
    EmptyPartitionCheck,
    TableSla,
)


def _row(
    database: str = "dw_rent",
    table: str = "fact_contracts",
    layer: str = "dw",
    partition_key: list | None = None,
    rows_written: int | float | None = 0,
    row_count: int | float | None = 0,
    version: int = 10,
    profiled_at: datetime | None = None,
    run_logical_date: str = "2026-08-02",
) -> dict:
    if partition_key is None:
        partition_key = [
            {"name": "year", "value": "2026"},
            {"name": "month", "value": "08"},
            {"name": "day", "value": "02"},
        ]
    return {
        "database": database,
        "table": table,
        "layer": layer,
        "partition_key": partition_key,
        "rows_written": rows_written,
        "row_count": row_count,
        "profiled_delta_version": version,
        "profiled_at": profiled_at or datetime.now(timezone.utc),
        "run_logical_date": run_logical_date,
    }


def _expectations() -> dict[tuple[str, str], TableSla]:
    return {
        ("dw_rent", "fact_contracts"): TableSla(checks=(EmptyPartitionCheck(),)),
    }


class TestNormalizePartitionKey:
    def test_numpy_struct_array(self):
        partition_key = np.array(
            [
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "7"},
                {"name": "day", "value": "26"},
            ],
            dtype=object,
        )
        normalized = normalize_partition_key(partition_key)
        assert normalized == [
            {"name": "year", "value": "2026"},
            {"name": "month", "value": "7"},
            {"name": "day", "value": "26"},
        ]
        assert partition_key_fingerprint(partition_key) == "day=26|month=7|year=2026"


class TestJudgeEmptyPartitions:
    def test_opt_in_empty_partition_yields_finding(self):
        findings = judge_empty_partitions(
            [_row(rows_written=0, row_count=0)],
            expectations=_expectations(),
        )
        assert len(findings) == 1
        assert findings[0]["signal_type"] == "empty_partition"

    def test_without_sla_no_alert(self):
        assert judge_empty_partitions([_row(rows_written=0, row_count=0)]) == []

    def test_rows_written_zero_with_data_partition_skipped(self):
        assert (
            judge_empty_partitions(
                [_row(rows_written=0, row_count=7371)],
                expectations=_expectations(),
            )
            == []
        )

    def test_non_year_month_day_partition_skipped(self):
        row = _row(
            row_count=0,
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "08"},
            ],
        )
        assert judge_empty_partitions([row], expectations=_expectations()) == []

    def test_misaligned_run_date_skipped(self):
        row = _row(
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "07"},
                {"name": "day", "value": "08"},
            ],
            run_logical_date="2026-08-02",
        )
        assert judge_empty_partitions([row], expectations=_expectations()) == []

    def test_cdc_raw_layer_skipped(self):
        row = _row(layer="raw", row_count=0)
        assert judge_empty_partitions([row], expectations=_expectations()) == []

    def test_thread_key_stable(self):
        finding = judge_empty_partitions(
            [_row(row_count=0)],
            expectations=_expectations(),
        )[0]
        assert finding_thread_key(finding).startswith(
            "empty_partition:dw_rent.fact_contracts:"
        )

    def test_message_human_format(self):
        row = _row(
            row_count=0,
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "08"},
                {"name": "day", "value": "03"},
            ],
            run_logical_date="2026-08-03",
        )
        finding = judge_empty_partitions([row], expectations=_expectations())[0]
        finding["table_owner"] = "alice@quintoandar.com.br"
        finding["team_owner"] = "Data Governance"
        finding["environment"] = "forno"
        finding["latest_partition_with_data"] = "day=01|month=08|year=2026"
        text = format_finding_message(finding)
        assert text == (
            "[FORNO] ⚠️ Empty Partition Detected\n"
            "Table: `dw_rent.fact_contracts`\n"
            "Partition 2026-08-03 is empty (0 rows). Last with data: 2026-08-01.\n"
            "SLA: empty_partition opt-in.\n"
            "Action: verify the load produced rows for this partition.\n"
            "Contact: alice@quintoandar.com.br · Data Governance"
        )
