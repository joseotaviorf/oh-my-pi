from datetime import datetime, timezone

from bietlejuice.observability.monitoring.sla_expectations import StaleDataCheck
from bietlejuice.observability.monitoring.stale_data import (
    finding_thread_key,
    format_finding_message,
    judge_stale_data,
)


def _check() -> StaleDataCheck:
    return StaleDataCheck(column="ts_assessed", max_age_hours=36)


class TestJudgeStaleData:
    def test_recent_data_no_finding(self):
        now = datetime(2026, 8, 3, 12, 0, tzinfo=timezone.utc)
        latest = datetime(2026, 8, 3, 10, 0, tzinfo=timezone.utc)
        assert (
            judge_stale_data(
                database="datalake_example",
                table="example",
                check=_check(),
                latest_data_at=latest,
                collection_method="delta_log",
                now=now,
            )
            is None
        )

    def test_stale_data_yields_finding(self):
        now = datetime(2026, 8, 5, 12, 0, tzinfo=timezone.utc)
        latest = datetime(2026, 8, 1, 10, 0, tzinfo=timezone.utc)
        finding = judge_stale_data(
            database="datalake_example",
            table="example",
            check=_check(),
            latest_data_at=latest,
            collection_method="delta_log",
            now=now,
        )
        assert finding is not None
        assert finding["signal_type"] == "stale_data"
        assert finding["age_hours"] > 36

    def test_null_latest_is_stale(self):
        finding = judge_stale_data(
            database="datalake_example",
            table="example",
            check=_check(),
            latest_data_at=None,
            collection_method="spark_max_fallback",
        )
        assert finding is not None
        assert finding["latest_data_at"] is None

    def test_thread_key_includes_column(self):
        finding = judge_stale_data(
            database="datalake_example",
            table="example",
            check=_check(),
            latest_data_at=None,
            collection_method="delta_log",
        )
        assert finding_thread_key(finding) == (
            "stale_data:datalake_example.example:ts_assessed"
        )

    def test_message_format(self):
        finding = judge_stale_data(
            database="datalake_example",
            table="example",
            check=_check(),
            latest_data_at=datetime(2026, 8, 1, 10, 0, tzinfo=timezone.utc),
            collection_method="delta_log",
            now=datetime(2026, 8, 5, 12, 0, tzinfo=timezone.utc),
        )
        finding["environment"] = "prod"
        finding["table_owner"] = "owner@example.com"
        finding["team_owner"] = "governance"
        text = format_finding_message(finding)
        assert text.startswith("[PROD] ⚠️ Stale Data Detected")
        assert "ts_assessed" in text
        assert "max age 36h" in text
