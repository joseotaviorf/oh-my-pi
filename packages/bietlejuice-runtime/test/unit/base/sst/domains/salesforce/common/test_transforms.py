"""Unit tests for Salesforce CDC common transforms."""

import pytest
from pyspark.sql.types import (
    ArrayType,
    StringType,
    StructField,
    StructType,
)

from bietlejuice.base.sst.domains.salesforce.common.transforms import (
    filter_relevant_cdc_events,
)

_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("event_type", StringType(), True),
        StructField("changed_field", ArrayType(StringType()), True),
    ]
)

_TRACKED = ["Status", "Priority"]


@pytest.fixture
def cdc_events_df(spark_session):
    """One row per CDC scenario; `id` identifies the expected filter outcome."""
    data = [
        ("insert_event", "INSERT", None),
        ("delete_event", "DELETE", ["Status"]),
        ("update_relevant", "UPDATE", ["Status", "Subject"]),
        ("update_irrelevant", "UPDATE", ["Subject", "Description"]),
        ("update_null_fields", "UPDATE", None),
        ("update_empty_array", "UPDATE", []),
        ("update_empty_string", "UPDATE", [""]),
    ]
    return spark_session.createDataFrame(data, _SCHEMA)


class TestFilterRelevantCdcEvents:
    def test_returns_input_unchanged_when_tracked_columns_is_none(self, cdc_events_df):
        # arrange / act
        result = filter_relevant_cdc_events(cdc_events_df, tracked_columns=None)

        # assert
        assert result is cdc_events_df

    def test_returns_input_unchanged_when_tracked_columns_is_empty(self, cdc_events_df):
        # arrange / act
        result = filter_relevant_cdc_events(cdc_events_df, tracked_columns=[])

        # assert
        assert result is cdc_events_df

    def test_keeps_non_update_and_relevant_or_unreliable_update_events(
        self, cdc_events_df
    ):
        # arrange / act
        result = filter_relevant_cdc_events(cdc_events_df, _TRACKED)

        # assert
        kept_ids = {row["id"] for row in result.collect()}
        assert kept_ids == {
            "insert_event",  # non-UPDATE always kept
            "delete_event",  # non-UPDATE always kept
            "update_relevant",  # tracked field changed
            "update_null_fields",  # missing metadata -> kept
            "update_empty_array",  # empty metadata -> kept
            "update_empty_string",  # invalid metadata -> kept
        }
        # the only UPDATE with reliable, non-tracked changes is dropped
        assert "update_irrelevant" not in kept_ids

    def test_respects_custom_event_and_changed_field_column_names(self, spark_session):
        # arrange
        schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("op", StringType(), True),
                StructField("fields", ArrayType(StringType()), True),
            ]
        )
        df = spark_session.createDataFrame(
            [
                ("kept", "UPDATE", ["Status"]),
                ("dropped", "UPDATE", ["Subject"]),
            ],
            schema,
        )

        # act
        result = filter_relevant_cdc_events(
            df,
            _TRACKED,
            event_type_col="op",
            changed_fields_col="fields",
        )

        # assert
        kept_ids = {row["id"] for row in result.collect()}
        assert kept_ids == {"kept"}
