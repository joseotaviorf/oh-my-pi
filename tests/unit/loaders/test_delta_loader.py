from unittest import mock
from bietlejuice.loaders.delta_loader import DeltaLoader


class TestDeltaLoader:
    @mock.patch("bietlejuice.loaders.delta_loader.BaseSparkContext")
    def test_vacuum_table(self, mock_spark_context):
        table_name = "test_table"
        retention_hours = 24

        delta_loader = DeltaLoader()
        delta_loader.vacuum_table(table_name, retention_hours)

        mock_spark_context.spark.sql.assert_called_once_with(
            f"VACUUM test_table RETAIN 24 HOURS"
        )

    @mock.patch("bietlejuice.loaders.delta_loader.BaseSparkContext")
    def test_optimize_table_without_z_order(self, mock_spark_context):
        table_name = "test_table"

        delta_loader = DeltaLoader()
        delta_loader.optimize_table(table_name)

        mock_spark_context.spark.sql.assert_called_once_with(f"OPTIMIZE test_table")

    @mock.patch("bietlejuice.loaders.delta_loader.BaseSparkContext")
    def test_optimize_table_with_z_order(self, mock_spark_context):
        table_name = "test_table"
        z_order_by = ["column1", "column2"]

        delta_loader = DeltaLoader()
        delta_loader.optimize_table(table_name, z_order_by)

        mock_spark_context.spark.sql.assert_called_once_with(
            f"OPTIMIZE test_table ZORDER BY column1,column2"
        )
