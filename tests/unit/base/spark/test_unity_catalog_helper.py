import unittest
from unittest.mock import patch
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper


class TestSparkTablePropertyHelper(unittest.TestCase):
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
