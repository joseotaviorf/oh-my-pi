from unittest import mock

from pyspark.sql.types import (
    BooleanType,
    IntegerType,
    StringType,
    StructField,
    StructType,
)

from bietlejuice.base.sst.domains.salesforce.api.api_logs import (
    TRACKSALE_SERVICE_NAME,
    conform_and_save_tracksale_api_logs,
    conform_tracksale_api_logs,
)


class TestConformTracksaleApiLogs:
    def test_conform_adds_service_name_and_metadata(self, spark_session):
        # arrange
        input_schema = StructType(
            [
                StructField("id_record", StringType(), True),
                StructField("idx", IntegerType(), True),
                StructField("status_code", IntegerType(), True),
                StructField("api_logs", StringType(), True),
                StructField("success", BooleanType(), True),
                StructField("error", StringType(), True),
            ]
        )
        input_df = spark_session.createDataFrame(
            [
                (
                    "Dispatch_code",
                    0,
                    200,
                    '{"dispatch_code":"Dispatch_code","status":{"inserted":1,"invalid":0,"duplicated":0}}',
                    True,
                    None,
                )
            ],
            schema=input_schema,
        )

        # act
        result_df = conform_tracksale_api_logs(
            df=input_df,
            api_entity="253",
            target_table="reverse_tracksale_test.lost_pp",
            job_name="reverse_tracksale_access.load_targets_into_tracksale",
            partition_date="2026-08-17",
        )
        result = result_df.collect()[0]

        # assert
        assert result.id_record == "Dispatch_code"
        assert result.entity_type == "253"
        assert result.status_code == 200
        assert result.query_idx == 0
        assert result.success is True
        assert result.error is None
        assert result.target_table == "reverse_tracksale_test.lost_pp"
        assert result.job_name == "reverse_tracksale_access.load_targets_into_tracksale"
        assert result.partition_date == "2026-08-17"
        assert result.service_name == TRACKSALE_SERVICE_NAME
        assert result.load_ts is not None


class TestConformAndSaveTracksaleApiLogs:
    @mock.patch(
        "bietlejuice.base.sst.domains.salesforce.api.api_logs.validate_and_write"
    )
    def test_save_uses_tracksale_service_partition_filter(
        self, mock_validate_and_write, spark_session
    ):
        # arrange
        input_schema = StructType(
            [
                StructField("id_record", StringType(), True),
                StructField("idx", IntegerType(), True),
                StructField("status_code", IntegerType(), True),
                StructField("api_logs", StringType(), True),
                StructField("success", BooleanType(), True),
                StructField("error", StringType(), True),
            ]
        )
        input_df = spark_session.createDataFrame(
            [
                (
                    "Dispatch_code",
                    0,
                    200,
                    '{"dispatch_code":"Dispatch_code"}',
                    True,
                    None,
                )
            ],
            schema=input_schema,
        )

        # act
        conform_and_save_tracksale_api_logs(
            spark=spark_session,
            df=input_df,
            api_entity="253",
            target_table="reverse_tracksale_test.lost_pp",
            job_name="reverse_tracksale_access.load_targets_into_tracksale",
            partition_date="2026-08-17",
            bucket="5a-datalake-forno",
        )

        # assert
        mock_validate_and_write.assert_called_once()
        call_kwargs = mock_validate_and_write.call_args.kwargs
        assert call_kwargs["target_table"] == "datalake_sst_metrics.api_logs"
        assert (
            call_kwargs["table_location"]
            == "s3a://5a-datalake-forno/sst_metrics/api_logs"
        )
        assert call_kwargs["partition_cols"] == [
            "partition_date",
            "entity_type",
            "job_name",
            "service_name",
            "target_table",
        ]
        saved_df = call_kwargs["df"]
        assert saved_df.filter("service_name = 'tracksale'").count() == 1

    @mock.patch(
        "bietlejuice.base.sst.domains.salesforce.api.api_logs.validate_and_write"
    )
    def test_partition_filter_isolates_tables_sharing_a_campaign(
        self, mock_validate_and_write, spark_session
    ):
        """Tables sharing a campaign_code must not overwrite each other's logs."""
        # arrange
        input_df = spark_session.createDataFrame(
            [("Dispatch_code", 0, 200, "{}", True, None)],
            schema=StructType(
                [
                    StructField("id_record", StringType(), True),
                    StructField("idx", IntegerType(), True),
                    StructField("status_code", IntegerType(), True),
                    StructField("api_logs", StringType(), True),
                    StructField("success", BooleanType(), True),
                    StructField("error", StringType(), True),
                ]
            ),
        )
        shared_args = {
            "spark": spark_session,
            "df": input_df,
            "api_entity": "242",
            "job_name": "reverse_tracksale_access.load_targets_into_tracksale",
            "partition_date": "2026-08-17",
            "bucket": "5a-datalake-forno",
        }

        # act
        conform_and_save_tracksale_api_logs(
            target_table="reverse_tracksale_test.lost_pp", **shared_args
        )
        conform_and_save_tracksale_api_logs(
            target_table="reverse_tracksale_test.lost_iq", **shared_args
        )

        # assert
        first_filter, second_filter = (
            call.kwargs["partition_filter"]
            for call in mock_validate_and_write.call_args_list
        )
        assert "target_table = 'reverse_tracksale_test.lost_pp'" in first_filter
        assert "target_table = 'reverse_tracksale_test.lost_iq'" in second_filter
        assert first_filter != second_filter
