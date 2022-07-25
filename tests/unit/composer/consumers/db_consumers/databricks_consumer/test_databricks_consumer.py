import mock
from bietlejuice.jobs.composer.clients.db_clients.spark_client import SparkClient


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
