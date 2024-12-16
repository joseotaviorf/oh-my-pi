import mock
from bietlejuice.clients.db_clients.spark_client import SparkClient
from bietlejuice.base.spark.base_spark import BaseSparkContext
from pyspark.sql.utils import AnalysisException


class TestDatabricksConsumer:
    @mock.patch.object(SparkClient, "get_records")
    def test_get_partition_values_from_table(
        self, mocked_get_records, databricks_consumer
    ):
        # arrange
        table_name = "<table_name>"
        expected_query = f"SHOW PARTITIONS <database_name>.{table_name}"

        # act
        databricks_consumer.get_partition_values_from_table(table_name)

        # assert
        mocked_get_records.assert_called_once_with(expected_query)

    @mock.patch.object(SparkClient, "get_records")
    @mock.patch(
        "bietlejuice.consumers.db_consumers.databricks_consumer.AnalysisException.getErrorClass"
    )
    @mock.patch("bietlejuice.base.spark.base_spark.BaseDBUtils")
    @mock.patch(
        "bietlejuice.consumers.db_consumers.databricks_consumer.SparkMetastoreService"
    )
    def test_get_partition_values_from_table_unity_catalog(
        self,
        mock_spark_metastore_service,
        mock_base_dbutils,
        mocked_get_error_class,
        mocked_get_records,
        databricks_consumer,
    ):
        # arrange
        mocked_get_records.side_effect = AnalysisException(
            desc="UC_COMMAND_NOT_SUPPORTED", stackTrace=""
        )
        mocked_get_error_class.return_value = "UC_COMMAND_NOT_SUPPORTED"
        mock_spark_metastore_service.return_value.get_table_path.return_value = (
            "<table_path>"
        )
        mock_spark_metastore_service.return_value.get_table_partition_keys.return_value = [
            ("year", "int"),
            ("month", "int"),
            ("day", "int"),
        ]
        mock_base_dbutils.return_value.discover_partition_values_in_path.return_value = [
            [2021, 1, 1],
            [2021, 1, 2],
        ]
        expected_df = BaseSparkContext.spark.createDataFrame(
            [["year=2021/month=1/day=1"], ["year=2021/month=1/day=2"]], ["partition"]
        )

        # act
        partition_values_df_result = databricks_consumer.get_partition_values_from_table(
            "<table_name>"
        )

        # assert
        assert partition_values_df_result.collect() == expected_df.collect()
