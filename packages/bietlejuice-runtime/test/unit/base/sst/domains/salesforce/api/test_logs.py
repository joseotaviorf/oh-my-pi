"""Unit tests for Salesforce API log conforming/persistence (daily vs hourly)."""

from unittest import mock

from pyspark.sql.types import (
    BooleanType,
    IntegerType,
    StringType,
    StructField,
    StructType,
)

from bietlejuice.base.sst.domains.salesforce.api.logs import (
    conform_and_save_api_logs,
    conform_api_logs,
)

INPUT_SCHEMA = StructType(
    [
        StructField("id_record", StringType(), True),
        StructField("idx", IntegerType(), True),
        StructField("api_logs", StringType(), True),
        StructField("success", BooleanType(), True),
        StructField("error", StringType(), True),
    ]
)


def _input_df(spark_session):
    return spark_session.createDataFrame(
        [("001abc", 0, '[{"status_code": 200}]', True, None)],
        schema=INPUT_SCHEMA,
    )


class TestConformApiLogs:
    def test_daily_output_stamps_null_partition_hour(self, spark_session):
        """The output schema is stable: the column is always present so
        validate_and_write's projection to the (now hour-aware) logs table
        columns resolves. NULL marks a daily-era row by design."""
        result_df = conform_api_logs(
            df=_input_df(spark_session),
            api_entity="Case",
            target_table="datalake_salesforce_raw.case_v2",
            job_name="salesforce_api_v2.load_case_v2",
            partition_date="2026-06-02",
        )

        assert dict(result_df.dtypes)["partition_hour"] == "string"
        result = result_df.collect()[0]
        assert result.partition_hour is None
        assert result.partition_date == "2026-06-02"
        assert result.entity_type == "Case"
        assert result.status_code == "200"

    def test_hourly_output_stamps_partition_hour(self, spark_session):
        result_df = conform_api_logs(
            df=_input_df(spark_session),
            api_entity="Case",
            target_table="datalake_salesforce_raw.case_v2",
            job_name="salesforce_api_v2.load_case_v2",
            partition_date="2026-06-02",
            partition_hour="00",
        )

        result = result_df.collect()[0]
        # "00" must be treated as a real hour, not a falsy value.
        assert result.partition_hour == "00"
        assert result.partition_date == "2026-06-02"


class TestConformAndSaveApiLogs:
    def _save(self, spark_session, **kwargs):
        conform_and_save_api_logs(
            spark=spark_session,
            df=_input_df(spark_session),
            api_entity="Case",
            target_table="datalake_salesforce_raw.case_v2",
            job_name="salesforce_api_v2.load_case_v2",
            partition_date="2026-06-02",
            bucket="5a-datalake-forno",
            **kwargs,
        )

    @mock.patch("bietlejuice.base.sst.domains.salesforce.api.logs.validate_and_write")
    def test_daily_filter_and_partition_cols(self, mock_write, spark_session):
        self._save(spark_session)

        kwargs = mock_write.call_args.kwargs
        assert kwargs["partition_cols"] == [
            "partition_date",
            "entity_type",
            "job_name",
        ]
        assert "partition_hour" not in kwargs["partition_filter"]

    @mock.patch("bietlejuice.base.sst.domains.salesforce.api.logs.validate_and_write")
    def test_hourly_filter_narrows_but_partition_cols_stay(
        self, mock_write, spark_session
    ):
        """The shared logs table keeps its physical partitioning; the hour only
        narrows the replaceWhere so a run overwrites just its own hour."""
        self._save(spark_session, partition_hour="13")

        kwargs = mock_write.call_args.kwargs
        assert kwargs["partition_cols"] == [
            "partition_date",
            "entity_type",
            "job_name",
        ]
        assert "partition_hour = '13'" in kwargs["partition_filter"]
        assert "partition_hour" in kwargs["df"].columns
