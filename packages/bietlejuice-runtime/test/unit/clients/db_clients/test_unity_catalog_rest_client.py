import os
import sys
import unittest
from unittest.mock import MagicMock, patch

mock_databricks = MagicMock()
sys.modules.setdefault("databricks", mock_databricks)
sys.modules.setdefault("databricks.sdk", mock_databricks.sdk)
sys.modules.setdefault("databricks.sdk.service", mock_databricks.sdk.service)
sys.modules.setdefault(
    "databricks.sdk.service.catalog", mock_databricks.sdk.service.catalog
)

from bietlejuice.clients.db_clients.unity_catalog_rest_client import (  # noqa: E402
    UnityCatalogRestClient,
)


class TestUnityCatalogRestClient(unittest.TestCase):
    def setUp(self):
        mock_databricks.sdk.WorkspaceClient.reset_mock()

    @patch.dict(
        os.environ,
        {
            "DATABRICKS_UC_HOST": "https://test.databricks.com",
            "DATABRICKS_UC_TOKEN": "tok",
        },
        clear=False,
    )
    def test_build_client_creates_workspace_client(self):
        mock_ws = MagicMock()
        mock_databricks.sdk.WorkspaceClient.return_value = mock_ws

        client = UnityCatalogRestClient()
        result = client.conn

        mock_databricks.sdk.WorkspaceClient.assert_called_once_with(
            host="https://test.databricks.com", token="tok"
        )
        self.assertEqual(result, mock_ws)

    def test_build_client_raises_without_host(self):
        client = UnityCatalogRestClient(host=None, token="tok")
        with self.assertRaises(ValueError):
            _ = client.conn

    def test_ensure_schema_creates_when_not_exists(self):
        mock_ws = MagicMock()
        mock_ws.schemas.get.side_effect = Exception("not found")

        client = UnityCatalogRestClient(host="https://h", token="t")
        client._workspace_client = mock_ws
        client.ensure_schema("catalog", "schema_name", "comment")

        mock_ws.schemas.create.assert_called_once_with(
            name="schema_name", catalog_name="catalog"
        )

    def test_ensure_schema_skips_when_exists(self):
        mock_ws = MagicMock()
        mock_ws.schemas.get.return_value = MagicMock()

        client = UnityCatalogRestClient(host="https://h", token="t")
        client._workspace_client = mock_ws
        client.ensure_schema("catalog", "schema_name")

        mock_ws.schemas.create.assert_not_called()

    def test_delete_table_handles_not_found(self):
        mock_ws = MagicMock()
        mock_ws.tables.delete.side_effect = Exception("not found")

        client = UnityCatalogRestClient(host="https://h", token="t")
        client._workspace_client = mock_ws
        client.delete_table("catalog.schema.table")

    def test_get_table_returns_none_when_not_found(self):
        mock_ws = MagicMock()
        mock_ws.tables.get.side_effect = Exception("not found")

        client = UnityCatalogRestClient(host="https://h", token="t")
        client._workspace_client = mock_ws
        result = client.get_table("catalog.schema.table")

        self.assertIsNone(result)

    def test_list_tables_returns_names(self):
        mock_ws = MagicMock()
        mock_tbl1 = MagicMock()
        mock_tbl1.name = "table_a"
        mock_tbl2 = MagicMock()
        mock_tbl2.name = "table_b"
        mock_ws.tables.list.return_value = [mock_tbl1, mock_tbl2]

        client = UnityCatalogRestClient(host="https://h", token="t")
        client._workspace_client = mock_ws
        result = client.list_tables("catalog", "schema")

        self.assertEqual(result, ["table_a", "table_b"])

    def test_get_records_raises(self):
        client = UnityCatalogRestClient(host="https://h", token="t")
        with self.assertRaises(NotImplementedError):
            client.get_records("SELECT 1")

    def test_run_raises(self):
        client = UnityCatalogRestClient(host="https://h", token="t")
        with self.assertRaises(NotImplementedError):
            client.run("CREATE TABLE t")
