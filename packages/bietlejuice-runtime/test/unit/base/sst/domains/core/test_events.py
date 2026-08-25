"""Unit tests for shared SST CDC event helpers."""

from unittest import mock

from bietlejuice.base.sst.domains.core import events as events_module

TARGET_TABLE = "events_case"
PARTITION_DATE = "2026-08-21"
PARTITION_HOUR = "10"
RAW_SCHEMA = "datalake_salesforce_raw"
CLEAN_SCHEMA = "datalake_salesforce_clean"


def _chained_df(name="df"):
    df = mock.MagicMock(name=name)
    df.where.return_value = df
    df.join.return_value = df
    df.select.return_value = df
    df.distinct.return_value = df
    return df


class TestRetrieveMissingEvents:
    def test_returns_ids_present_in_raw_and_missing_from_clean(self):
        spark = mock.MagicMock()
        raw = _chained_df("raw")
        clean = _chained_df("clean")
        missing = _chained_df("missing")
        spark.read.table.side_effect = [raw, clean]
        raw.join.return_value = missing
        missing.select.return_value = missing
        missing.distinct.return_value = missing
        missing.collect.return_value = [
            {"id_record": "001AAA"},
            {"id_record": "001BBB"},
        ]

        with mock.patch.object(events_module, "F"):
            result = events_module.retrieve_missing_events(
                spark=spark,
                target_table=TARGET_TABLE,
                partition_date=PARTITION_DATE,
                partition_hour=PARTITION_HOUR,
                raw_schema=RAW_SCHEMA,
                clean_schema=CLEAN_SCHEMA,
            )

        assert result == ["001AAA", "001BBB"]
        spark.read.table.assert_any_call(f"{RAW_SCHEMA}.{TARGET_TABLE}")
        spark.read.table.assert_any_call(f"{CLEAN_SCHEMA}.{TARGET_TABLE}")
        raw.join.assert_called_once_with(clean, on="id_record", how="left_anti")

    def test_returns_empty_list_when_nothing_is_missing(self):
        spark = mock.MagicMock()
        raw = _chained_df("raw")
        clean = _chained_df("clean")
        missing = _chained_df("missing")
        spark.read.table.side_effect = [raw, clean]
        raw.join.return_value = missing
        missing.select.return_value = missing
        missing.distinct.return_value = missing
        missing.collect.return_value = []

        with mock.patch.object(events_module, "F"):
            result = events_module.retrieve_missing_events(
                spark=spark,
                target_table=TARGET_TABLE,
                partition_date=PARTITION_DATE,
                partition_hour=PARTITION_HOUR,
                raw_schema=RAW_SCHEMA,
                clean_schema=CLEAN_SCHEMA,
            )

        assert result == []
