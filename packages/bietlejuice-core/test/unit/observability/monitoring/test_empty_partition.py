from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import numpy as np

from bietlejuice.observability.monitoring.empty_partition import (
    attach_latest_partition_with_data,
    attach_table_context,
    build_table_metrics_index,
    dedupe_to_latest,
    finding_thread_key,
    format_finding_message,
    format_partition_label,
    is_cdc_ingestion_row,
    is_partitioned_row,
    judge_empty_partitions,
    normalize_partition_key,
    partition_key_fingerprint,
    partition_matches_run_logical_date,
)
from bietlejuice.observability.monitoring.sla_expectations import ArrivalExpectation


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

    def test_judge_handles_numpy_partition_key(self):
        row = _row(
            rows_written=0, row_count=100, partition_key=np.array([], dtype=object)
        )
        row["partition_key"] = np.array(
            [{"name": "year", "value": "2026"}], dtype=object
        )
        assert judge_empty_partitions([row]) == []

        row["row_count"] = 0
        findings = judge_empty_partitions([row])
        assert len(findings) == 1


class TestPartitionMatchesRunLogicalDate:
    def test_aligned_partition(self):
        row = _row()
        assert partition_matches_run_logical_date(row) is True

    def test_misaligned_month(self):
        row = _row(
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "07"},
                {"name": "day", "value": "02"},
            ],
            run_logical_date="2026-08-02",
        )
        assert partition_matches_run_logical_date(row) is False

    def test_zero_padded_month_day(self):
        row = _row(
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "08"},
                {"name": "day", "value": "02"},
            ],
            run_logical_date="2026-08-02",
        )
        assert partition_matches_run_logical_date(row) is True


class TestPartitionKeyFingerprint:
    def test_sorts_and_formats(self):
        key = [
            {"name": "month", "value": "8"},
            {"name": "year", "value": "2026"},
        ]
        assert partition_key_fingerprint(key) == "month=8|year=2026"

    def test_empty_for_missing(self):
        assert partition_key_fingerprint(None) == ""
        assert partition_key_fingerprint([]) == ""


class TestDedupeToLatest:
    def test_keeps_highest_version(self):
        older = _row(version=5, rows_written=100, row_count=100)
        newer = _row(version=12, rows_written=0, row_count=0)
        result = dedupe_to_latest([older, newer])
        assert len(result) == 1
        assert result[0]["profiled_delta_version"] == 12


class TestJudgeEmptyPartitions:
    def test_both_zero_yields_finding(self):
        findings = judge_empty_partitions([_row(rows_written=0, row_count=0)])
        assert len(findings) == 1
        assert findings[0]["signal_type"] == "empty_partition"
        assert findings[0]["rows_written"] == 0
        assert findings[0]["row_count"] == 0

    def test_rows_written_zero_with_data_partition_skipped(self):
        assert judge_empty_partitions([_row(rows_written=0, row_count=7371)]) == []

    def test_rows_written_positive_with_empty_partition_yields_finding(self):
        findings = judge_empty_partitions([_row(rows_written=42, row_count=0)])
        assert len(findings) == 1

    def test_rows_written_nan_with_empty_partition_yields_finding(self):
        findings = judge_empty_partitions([_row(rows_written=np.nan, row_count=0)])
        assert len(findings) == 1

    def test_rows_written_none_with_empty_partition_yields_finding(self):
        findings = judge_empty_partitions([_row(rows_written=None, row_count=0)])
        assert len(findings) == 1

    def test_row_count_nan_skipped(self):
        assert judge_empty_partitions([_row(rows_written=0, row_count=np.nan)]) == []

    def test_row_count_none_skipped(self):
        assert judge_empty_partitions([_row(rows_written=0, row_count=None)]) == []

    def test_row_count_positive_skipped(self):
        assert judge_empty_partitions([_row(rows_written=0, row_count=42)]) == []

    def test_misaligned_run_date_skipped(self):
        row = _row(
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "07"},
                {"name": "day", "value": "08"},
            ],
            run_logical_date="2026-08-02",
        )
        assert judge_empty_partitions([row]) == []

    def test_non_partitioned_skipped(self):
        row = _row(partition_key=[])
        assert judge_empty_partitions([row]) == []

    def test_cdc_raw_layer_skipped(self):
        row = _row(layer="raw", row_count=0)
        assert judge_empty_partitions([row]) == []

    def test_mute_expectation_excludes(self):
        row = _row(row_count=0)
        expectations = {
            ("dw_rent", "fact_contracts"): ArrivalExpectation(mute=True),
        }
        assert judge_empty_partitions([row], expectations=expectations) == []

    def test_weekday_outside_days_of_week_skipped(self):
        # 2026-08-02 is Sunday (weekday=6)
        row = _row(
            row_count=0,
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "08"},
                {"name": "day", "value": "02"},
            ],
            run_logical_date="2026-08-02",
        )
        expectations = {
            ("dw_rent", "fact_contracts"): ArrivalExpectation(
                days_of_week={0, 1, 2, 3, 4}
            ),
        }
        assert judge_empty_partitions([row], expectations=expectations) == []

    def test_weekday_inside_days_of_week_alerts(self):
        # 2026-08-03 is Monday (weekday=0)
        row = _row(
            row_count=0,
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "08"},
                {"name": "day", "value": "03"},
            ],
            run_logical_date="2026-08-03",
        )
        expectations = {
            ("dw_rent", "fact_contracts"): ArrivalExpectation(
                days_of_week={0, 1, 2, 3, 4}
            ),
        }
        findings = judge_empty_partitions([row], expectations=expectations)
        assert len(findings) == 1

    def test_earliest_hour_before_on_today_skipped(self):
        row = _row(
            row_count=0,
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "08"},
                {"name": "day", "value": "03"},
            ],
            run_logical_date="2026-08-03",
        )
        expectations = {
            ("dw_rent", "fact_contracts"): ArrivalExpectation(earliest_hour=9),
        }
        now = datetime(2026, 8, 3, 8, 30, tzinfo=ZoneInfo("America/Sao_Paulo"))
        assert judge_empty_partitions([row], expectations=expectations, now=now) == []

    def test_earliest_hour_after_on_today_alerts(self):
        row = _row(
            row_count=0,
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "08"},
                {"name": "day", "value": "03"},
            ],
            run_logical_date="2026-08-03",
        )
        expectations = {
            ("dw_rent", "fact_contracts"): ArrivalExpectation(earliest_hour=9),
        }
        now = datetime(2026, 8, 3, 10, 0, tzinfo=ZoneInfo("America/Sao_Paulo"))
        findings = judge_empty_partitions([row], expectations=expectations, now=now)
        assert len(findings) == 1

    def test_earliest_hour_does_not_gate_past_day(self):
        row = _row(
            row_count=0,
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "08"},
                {"name": "day", "value": "02"},
            ],
            run_logical_date="2026-08-02",
        )
        expectations = {
            ("dw_rent", "fact_contracts"): ArrivalExpectation(earliest_hour=23),
        }
        now = datetime(2026, 8, 3, 8, 0, tzinfo=ZoneInfo("America/Sao_Paulo"))
        findings = judge_empty_partitions([row], expectations=expectations, now=now)
        assert len(findings) == 1

    def test_missing_partition_date_alerts_fail_safe(self):
        row = _row(
            row_count=0,
            partition_key=[{"name": "year", "value": "2026"}],
        )
        expectations = {
            ("dw_rent", "fact_contracts"): ArrivalExpectation(
                days_of_week={0, 1, 2, 3, 4}
            ),
        }
        findings = judge_empty_partitions([row], expectations=expectations)
        assert len(findings) == 1

    def test_no_expectation_alerts_by_default(self):
        findings = judge_empty_partitions([_row(row_count=0)])
        assert len(findings) == 1

    def test_thread_key_stable(self):
        finding = judge_empty_partitions([_row(row_count=0)])[0]
        assert finding_thread_key(finding).startswith(
            "empty_partition:dw_rent.fact_contracts:"
        )

    def test_message_human_format(self):
        expectations = {
            ("dw_rent", "fact_contracts"): ArrivalExpectation(
                days_of_week={0, 1, 2, 3, 4},
                earliest_hour=9,
                reason="Business-day loads",
            ),
        }
        row = _row(
            row_count=0,
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "08"},
                {"name": "day", "value": "03"},
            ],
            run_logical_date="2026-08-03",
        )
        finding = judge_empty_partitions([row], expectations=expectations)[0]
        finding["table_owner"] = "alice@quintoandar.com.br"
        finding["team_owner"] = "Data Governance"
        finding["environment"] = "forno"
        finding["latest_partition_with_data"] = "day=01|month=08|year=2026"
        text = format_finding_message(finding)
        assert text == (
            "[FORNO] ⚠️ Empty Partition Detected\n"
            "Table: `dw_rent.fact_contracts`\n"
            "Partition 2026-08-03 is empty (0 rows). Last with data: 2026-08-01.\n"
            "SLA: weekdays from 09h BRT.\n"
            "Action: verify the load produced rows for this partition.\n"
            "Contact: alice@quintoandar.com.br · Data Governance"
        )

    def test_message_without_sla_expectation(self):
        finding = judge_empty_partitions([_row(row_count=0)])[0]
        text = format_finding_message(finding)
        assert "SLA: no SLA (any empty partition alerts)." in text
        assert "Action: verify the load produced rows for this partition." in text

    def test_format_partition_label_from_fingerprint(self):
        assert format_partition_label("day=02|month=08|year=2026") == "2026-08-02"
        assert format_partition_label("year=2026/month=08/day=01") == "2026-08-01"

    def test_message_table_owner_shows_email(self):
        finding = judge_empty_partitions([_row(row_count=0)])[0]
        finding["table_owner"] = "alice@quintoandar.com.br"
        text = format_finding_message(finding)
        assert "Contact: alice@quintoandar.com.br" in text
        assert "<users/" not in text

    def test_message_includes_prod_environment_tag(self):
        finding = judge_empty_partitions([_row(row_count=0)])[0]
        finding["environment"] = "prod"
        text = format_finding_message(finding)
        assert text.startswith("[PROD] ⚠️ Empty Partition Detected")

    def test_message_unknown_owners(self):
        finding = judge_empty_partitions([_row(row_count=0)])[0]
        text = format_finding_message(finding)
        assert "[UNKNOWN] ⚠️ Empty Partition Detected" in text
        assert "Contact: unknown" in text
        assert "row_count" not in text
        assert "Profiled" not in text


class TestBuildTableMetricsIndex:
    def test_keeps_latest_version_per_run(self):
        older = {
            "database": "dw",
            "table": "fact",
            "run_logical_date": "2026-08-02",
            "profiled_delta_version": 3,
            "profiled_at": datetime(2026, 8, 2, tzinfo=timezone.utc),
            "latest_partition_value": "year=2026/month=08/day=01",
        }
        newer = {
            "database": "dw",
            "table": "fact",
            "run_logical_date": "2026-08-02",
            "profiled_delta_version": 9,
            "profiled_at": datetime(2026, 8, 3, tzinfo=timezone.utc),
            "latest_partition_value": "year=2026/month=08/day=02",
        }
        index = build_table_metrics_index([older, newer])
        assert index[("dw", "fact", "2026-08-02")]["latest_partition_value"] == (
            "year=2026/month=08/day=02"
        )


class TestAttachTableContext:
    def test_enriches_finding(self):
        findings = judge_empty_partitions([_row(rows_written=0, row_count=0)])
        index = build_table_metrics_index(
            [
                {
                    "database": "dw_rent",
                    "table": "fact_contracts",
                    "run_logical_date": "2026-08-02",
                    "profiled_delta_version": 1,
                    "profiled_at": datetime.now(timezone.utc),
                    "latest_partition_value": "year=2026/month=08/day=02",
                }
            ]
        )
        attach_table_context(findings, index)
        assert findings[0]["latest_partition_value"] == "year=2026/month=08/day=02"


class TestAttachLatestPartitionWithData:
    def test_picks_latest_partition_with_positive_row_count(self):
        empty_run = _row(row_count=0, run_logical_date="2026-08-02")
        older_with_data = _row(
            row_count=100,
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "08"},
                {"name": "day", "value": "01"},
            ],
            run_logical_date="2026-08-01",
        )
        newer_with_data = _row(
            row_count=50,
            partition_key=[
                {"name": "year", "value": "2026"},
                {"name": "month", "value": "08"},
                {"name": "day", "value": "03"},
            ],
            run_logical_date="2026-08-03",
        )
        findings = judge_empty_partitions([empty_run])
        attach_latest_partition_with_data(
            findings,
            [empty_run, older_with_data, newer_with_data],
        )
        assert findings[0]["latest_partition_with_data"] == "day=03|month=08|year=2026"

    def test_message_falls_back_to_table_latest_partition_value(self):
        finding = judge_empty_partitions([_row(row_count=0)])[0]
        finding["latest_partition_value"] = "year=2026/month=08/day=01"
        text = format_finding_message(finding)
        assert "Last with data: 2026-08-01" in text


class TestIsPartitionedRow:
    def test_requires_partition_key_entries(self):
        assert is_partitioned_row(_row()) is True
        assert is_partitioned_row({"partition_key": []}) is False


class TestIsCdcIngestionRow:
    def test_raw_layer_only(self):
        assert is_cdc_ingestion_row({"layer": "raw"}) is True
        assert is_cdc_ingestion_row({"layer": "dw"}) is False
