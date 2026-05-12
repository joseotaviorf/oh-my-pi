import os
import unittest
from collections import OrderedDict
from unittest.mock import MagicMock, patch

from bietlejuice.base.spark.unity_catalog_rest_helper import (
    UnityCatalogRestHelper,
)


class TestUnityCatalogRestHelper(unittest.TestCase):
    def setUp(self):
        UnityCatalogRestHelper.reset_client()

    @patch.dict(
        os.environ,
        {"DATABRICKS_UC_HOST": "https://test.databricks.com"},
        clear=False,
    )
    def test_is_uc_rest_enabled_with_host(self):
        self.assertTrue(UnityCatalogRestHelper.is_uc_rest_enabled())

    @patch.dict(os.environ, {}, clear=True)
    def test_is_uc_rest_disabled_without_host(self):
        self.assertFalse(UnityCatalogRestHelper.is_uc_rest_enabled())

    @patch.dict(
        os.environ,
        {"DATABRICKS_UC_HOST": "https://h", "UC_REST_DISABLED": "true"},
        clear=False,
    )
    def test_is_uc_rest_disabled_via_env_flag(self):
        self.assertFalse(UnityCatalogRestHelper.is_uc_rest_enabled())

    @patch.dict(os.environ, {}, clear=True)
    def test_sync_table_to_uc_noop_when_disabled(self):
        UnityCatalogRestHelper.sync_table_to_uc(
            database_name="db",
            table_name="tbl",
            table_location="s3://bucket/path",
            table_schema=OrderedDict({"id": "int"}),
            partitions=[],
        )

    @patch.dict(
        os.environ,
        {"DATABRICKS_UC_HOST": "https://h", "DATABRICKS_UC_TOKEN": "tok"},
        clear=False,
    )
    @patch(
        "bietlejuice.services.metastore_services.unity_catalog_rest_metastore_service.UnityCatalogRestMetastoreService"
    )
    def test_sync_table_to_uc_calls_service(self, mock_svc_cls):
        mock_svc = MagicMock()
        mock_svc_cls.return_value = mock_svc

        UnityCatalogRestHelper._uc_rest_client = MagicMock()

        schema = OrderedDict({"id": "int"})

        UnityCatalogRestHelper.sync_table_to_uc(
            database_name="db",
            table_name="tbl",
            table_location="s3://bucket/path",
            table_schema=schema,
            partitions=["year"],
            format_str="DELTA",
        )

        mock_svc.create_database.assert_called_once_with("db")
        mock_svc.create_external_table.assert_called_once()

    @patch.dict(
        os.environ,
        {"DATABRICKS_UC_HOST": "https://h", "DATABRICKS_UC_TOKEN": "tok"},
        clear=False,
    )
    @patch(
        "bietlejuice.services.metastore_services.unity_catalog_rest_metastore_service.UnityCatalogRestMetastoreService"
    )
    def test_sync_table_to_uc_swallows_exceptions(self, mock_svc_cls):
        mock_svc = MagicMock()
        mock_svc_cls.return_value = mock_svc
        mock_svc.create_database.side_effect = Exception("boom")

        UnityCatalogRestHelper._uc_rest_client = MagicMock()

        UnityCatalogRestHelper.sync_table_to_uc(
            database_name="db",
            table_name="tbl",
            table_location="s3://bucket/path",
            table_schema=OrderedDict({"id": "int"}),
            partitions=[],
        )

    @patch.dict(
        os.environ,
        {"DATABRICKS_UC_HOST": "https://h", "DATABRICKS_UC_TOKEN": "tok"},
        clear=False,
    )
    @patch(
        "bietlejuice.clients.db_clients.unity_catalog_rest_client.UnityCatalogRestClient"
    )
    def test_get_uc_rest_client_caches(self, mock_client_cls):
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client

        c1 = UnityCatalogRestHelper.get_uc_rest_client()
        c2 = UnityCatalogRestHelper.get_uc_rest_client()

        self.assertIs(c1, c2)
        mock_client_cls.assert_called_once()

    def test_reset_client(self):
        UnityCatalogRestHelper._uc_rest_client = MagicMock()
        UnityCatalogRestHelper.reset_client()
        self.assertIsNone(UnityCatalogRestHelper._uc_rest_client)
