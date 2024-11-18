import unittest
import os
from unittest.mock import patch
from bietlejuice.base.databricks.table_privilege_type_enum import TablePrivilegeTypeEnum
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper


class TestUnityCatalogHelper(unittest.TestCase):
    @patch("bietlejuice.base.spark.unity_catalog_helper.BaseSparkContext")
    def test_is_default_catalog_using_unity_when_catalog_is_hive_metastore(
        self, mock_base_spark_context
    ):
        # arrange
        mock_base_spark_context.spark.catalog.currentCatalog.return_value = (
            "hive_metastore"
        )

        # act
        result = UnityCatalogHelper.is_default_catalog_using_unity()

        # assert
        self.assertEqual(result, False)

    @patch("bietlejuice.base.spark.unity_catalog_helper.BaseSparkContext")
    def test_is_default_catalog_using_unity_when_catalog_is_quintoandar_forno(
        self, mock_base_spark_context
    ):
        # arrange
        mock_base_spark_context.spark.catalog.currentCatalog.return_value = (
            "quintoandar_forno"
        )

        # act
        result = UnityCatalogHelper.is_default_catalog_using_unity()

        # assert
        self.assertEqual(result, True)

    @patch("bietlejuice.base.spark.unity_catalog_helper.BaseSparkContext")
    def test_is_default_catalog_using_unity_when_catalog_is_quintoandar_prod(
        self, mock_base_spark_context
    ):
        # arrange
        mock_base_spark_context.spark.catalog.currentCatalog.return_value = (
            "quintoandar_prod"
        )

        # act
        result = UnityCatalogHelper.is_default_catalog_using_unity()

        # assert
        self.assertEqual(result, True)

    @patch.dict(os.environ, {"ENVIRONMENT": "forno"})
    def test_get_environment_unity_catalog_forno(self):
        # arrange
        expected = "quintoandar_forno"

        # act
        result = UnityCatalogHelper.get_environment_unity_catalog()

        # assert
        self.assertEqual(result, expected)

    @patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_get_environment_unity_catalog_prod(self):
        # arrange
        expected = "quintoandar_prod"

        # act
        result = UnityCatalogHelper.get_environment_unity_catalog()

        # assert
        self.assertEqual(result, expected)

    @patch.dict(os.environ, {"ENVIRONMENT": "invalid"})
    def test_get_environment_unity_catalog_invalid(self):
        # act
        with self.assertRaises(ValueError):
            UnityCatalogHelper.get_environment_unity_catalog()

    @patch.dict(os.environ, {"ENVIRONMENT": "forno"})
    @patch("bietlejuice.base.spark.unity_catalog_helper.BaseSparkContext")
    def test_sync_passing_only_table_name(self, mock_base_spark_context):
        # arrange
        table_name = "table_name"
        expected = f"SYNC TABLE quintoandar_forno.{table_name} FROM hive_metastore.{table_name}"

        # act
        UnityCatalogHelper.sync_table_to_unity_catalog(table_name)

        # assert
        mock_base_spark_context.spark.sql.assert_called_once_with(expected)

    @patch.dict(os.environ, {"ENVIRONMENT": "forno"})
    @patch("bietlejuice.base.spark.unity_catalog_helper.BaseSparkContext")
    def test_sync_passing_different_catalogs(self, mock_base_spark_context):
        # arrange
        table_name = "table_name"
        source_catalog = "source_catalog"
        destination_catalog = "destination_catalog"
        expected = f"SYNC TABLE {destination_catalog}.{table_name} FROM {source_catalog}.{table_name}"

        # act
        UnityCatalogHelper.sync_table_to_unity_catalog(
            table_name, source_catalog, destination_catalog
        )

        # assert
        mock_base_spark_context.spark.sql.assert_called_once_with(expected)

    @patch.dict(os.environ, {"ENVIRONMENT": "forno"})
    @patch("bietlejuice.base.spark.unity_catalog_helper.BaseSparkContext")
    def test_grant_table_permission(self, mock_base_spark_context):
        # arrange
        table_name = "default.table_name"
        privilege_type = TablePrivilegeTypeEnum.ALL_PRIVILEGES
        principal = "principal"
        expected = f"GRANT ALL PRIVILEGES ON TABLE quintoandar_forno.default.table_name TO `principal`"

        # act
        UnityCatalogHelper.grant_table_permission(privilege_type, table_name, principal)

        # assert
        mock_base_spark_context.spark.sql.assert_called_once_with(expected)
