import unittest
from unittest.mock import patch, MagicMock
from bietlejuice.base.spark.spark_table_property_helper import SparkTablePropertyHelper


class TestSparkTablePropertyHelper(unittest.TestCase):
    @patch("bietlejuice.base.spark.spark_table_property_helper.BaseSparkContext")
    def test_get_property_when_it_exists(self, mock_base_spark_context):
        # arrange
        table_name = "test_table"
        property_name = "property_name"
        property_value = "property_value"
        prop_mock = MagicMock()
        prop_mock.key = property_name
        prop_mock.value = property_value
        mock_base_spark_context.spark.sql.return_value.collect.return_value = [
            prop_mock
        ]

        # act
        result = SparkTablePropertyHelper.get_property(
            table_name, property_name, mock_base_spark_context.spark
        )

        # assert
        self.assertEqual(result, property_value)

    @patch("bietlejuice.base.spark.spark_table_property_helper.BaseSparkContext")
    def test_get_table_properties(self, mock_base_spark_context):
        # arrange
        table_name = "test_table"
        prop_mock = MagicMock()
        prop_mock.key = "property_name"
        prop_mock.value = "property_value"
        mock_base_spark_context.spark.sql.return_value.collect.return_value = [
            prop_mock
        ]

        # act
        result = SparkTablePropertyHelper.get_table_properties(
            table_name, mock_base_spark_context.spark
        )

        # assert
        self.assertEqual(result, {prop_mock.key: prop_mock.value})

    @patch("bietlejuice.base.spark.spark_table_property_helper.BaseSparkContext")
    def test_set_property(self, mock_base_spark_context):
        # arrange
        table_name = "test_table"
        property_name = "property_name"
        property_value = "property_value"

        # act
        SparkTablePropertyHelper.set_property(
            table_name, property_name, property_value, mock_base_spark_context.spark
        )

        # assert
        mock_base_spark_context.spark.sql.assert_called_once_with(
            f"ALTER TABLE {table_name} SET TBLPROPERTIES ('{property_name}'='{property_value}')"
        )
