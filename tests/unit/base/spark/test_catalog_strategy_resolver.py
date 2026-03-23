import os
import unittest
from unittest.mock import MagicMock, patch

from bietlejuice.base.spark.catalog_strategy_resolver import (
    CatalogStrategyResolver,
)


class TestCatalogStrategyResolver(unittest.TestCase):

    @patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    @patch("bietlejuice.base.spark.glue_catalog_helper.GlueCatalogHelper")
    def test_databricks_runtime_adds_glue_service(self, mock_glue_helper, mock_runtime):
        mock_runtime.is_databricks.return_value = True
        mock_runtime.is_emr.return_value = False
        mock_glue_helper.is_glue_catalog_enabled.return_value = True
        mock_glue_helper.get_glue_client.return_value = MagicMock()

        spark_svc = MagicMock()
        services = CatalogStrategyResolver.get_active_services(spark_svc)

        self.assertEqual(len(services), 2)
        self.assertIs(services[0], spark_svc)

    @patch.dict(os.environ, {"ENVIRONMENT": "forno"}, clear=False)
    @patch("bietlejuice.base.spark.unity_catalog_rest_helper.UnityCatalogRestHelper")
    @patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    def test_emr_runtime_adds_uc_rest_service(self, mock_runtime, mock_uc_helper):
        mock_runtime.is_databricks.return_value = False
        mock_runtime.is_emr.return_value = True
        mock_uc_helper.is_uc_rest_enabled.return_value = True
        mock_uc_helper.get_uc_rest_client.return_value = MagicMock()

        spark_svc = MagicMock()
        services = CatalogStrategyResolver.get_active_services(spark_svc)

        self.assertEqual(len(services), 2)
        self.assertIs(services[0], spark_svc)

    @patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    def test_unknown_runtime_returns_spark_only(self, mock_runtime):
        mock_runtime.is_databricks.return_value = False
        mock_runtime.is_emr.return_value = False

        spark_svc = MagicMock()
        services = CatalogStrategyResolver.get_active_services(spark_svc)

        self.assertEqual(len(services), 1)
        self.assertIs(services[0], spark_svc)

    @patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    @patch("bietlejuice.base.spark.glue_catalog_helper.GlueCatalogHelper")
    def test_databricks_glue_unavailable_returns_spark_only(
        self, mock_glue_helper, mock_runtime
    ):
        mock_runtime.is_databricks.return_value = True
        mock_runtime.is_emr.return_value = False
        mock_glue_helper.is_glue_catalog_enabled.return_value = False

        spark_svc = MagicMock()
        services = CatalogStrategyResolver.get_active_services(spark_svc)

        self.assertEqual(len(services), 1)

    @patch("bietlejuice.base.spark.unity_catalog_rest_helper.UnityCatalogRestHelper")
    @patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    def test_emr_uc_rest_unavailable_returns_spark_only(
        self, mock_runtime, mock_uc_helper
    ):
        mock_runtime.is_databricks.return_value = False
        mock_runtime.is_emr.return_value = True
        mock_uc_helper.is_uc_rest_enabled.return_value = False

        spark_svc = MagicMock()
        services = CatalogStrategyResolver.get_active_services(spark_svc)

        self.assertEqual(len(services), 1)

    # -- sync_to_secondary_catalog tests ------------------------------------

    @patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    @patch("bietlejuice.base.spark.glue_catalog_helper.GlueCatalogHelper")
    def test_sync_dispatches_to_glue_on_databricks(
        self, mock_glue_helper, mock_runtime
    ):
        mock_runtime.is_databricks.return_value = True
        mock_runtime.is_emr.return_value = False

        CatalogStrategyResolver.sync_to_secondary_catalog(
            database_name="db",
            table_name="tbl",
            table_location="s3://path",
            table_schema={"id": "int"},
            partitions=[],
            format_str="DELTA",
        )

        mock_glue_helper.sync_table_to_glue.assert_called_once()

    @patch("bietlejuice.base.spark.unity_catalog_rest_helper.UnityCatalogRestHelper")
    @patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    def test_sync_dispatches_to_uc_rest_on_emr(self, mock_runtime, mock_uc_helper):
        mock_runtime.is_databricks.return_value = False
        mock_runtime.is_emr.return_value = True

        CatalogStrategyResolver.sync_to_secondary_catalog(
            database_name="db",
            table_name="tbl",
            table_location="s3://path",
            table_schema={"id": "int"},
            partitions=[],
            format_str="DELTA",
        )

        mock_uc_helper.sync_table_to_uc.assert_called_once()

    @patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    def test_sync_noop_on_unknown_runtime(self, mock_runtime):
        mock_runtime.is_databricks.return_value = False
        mock_runtime.is_emr.return_value = False

        CatalogStrategyResolver.sync_to_secondary_catalog(
            database_name="db",
            table_name="tbl",
            table_location="s3://path",
            table_schema={"id": "int"},
            partitions=[],
        )
