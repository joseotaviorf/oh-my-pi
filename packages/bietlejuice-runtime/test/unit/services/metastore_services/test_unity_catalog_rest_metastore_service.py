import os
import unittest
from collections import OrderedDict
from unittest.mock import MagicMock, patch

from bietlejuice.services.metastore_services.unity_catalog_rest_metastore_service import (
    UnityCatalogRestMetastoreService,
)


class TestUnityCatalogRestMetastoreService(unittest.TestCase):
    def _make_service(self, client=None, catalog="quintoandar_forno"):
        return UnityCatalogRestMetastoreService(
            uc_rest_client=client or MagicMock(),
            catalog_name=catalog,
        )

    def test_create_database_calls_ensure_schema(self):
        mock_client = MagicMock()
        svc = self._make_service(mock_client)

        svc.create_database("my_schema")

        mock_client.ensure_schema.assert_called_once_with(
            catalog_name="quintoandar_forno",
            schema_name="my_schema",
            comment="Managed by bietlejuice — synced from Spark metastore",
        )

    def test_create_external_table_creates_new_table(self):
        mock_client = MagicMock()
        mock_client.get_table.return_value = None
        svc = self._make_service(mock_client)

        schema = OrderedDict({"id": "int", "name": "string"})

        svc.create_external_table(
            database_name="db",
            table_name="tbl",
            table_location="s3://bucket/path/",
            table_schema=schema,
            partition_cols=[],
            format_options="DELTA",
        )

        mock_client.create_table.assert_called_once()
        call_kwargs = mock_client.create_table.call_args
        self.assertEqual(call_kwargs.kwargs["catalog_name"], "quintoandar_forno")
        self.assertEqual(call_kwargs.kwargs["schema_name"], "db")
        self.assertEqual(call_kwargs.kwargs["table_name"], "tbl")
        self.assertEqual(call_kwargs.kwargs["data_source_format"], "DELTA")

    def test_create_external_table_skips_when_table_exists(self):
        mock_client = MagicMock()
        mock_client.get_table.return_value = MagicMock()
        svc = self._make_service(mock_client)

        schema = OrderedDict({"id": "int"})

        svc.create_external_table(
            database_name="db",
            table_name="tbl",
            table_location="s3://bucket/path/",
            table_schema=schema,
            partition_cols=[],
            format_options="DELTA",
        )

        mock_client.get_table.assert_called_once_with("quintoandar_forno.db.tbl")
        mock_client.delete_table.assert_not_called()
        mock_client.create_table.assert_not_called()

    def test_drop_table_calls_delete(self):
        mock_client = MagicMock()
        svc = self._make_service(mock_client)

        svc.drop_table("db", "tbl")

        mock_client.delete_table.assert_called_once_with("quintoandar_forno.db.tbl")

    def test_get_table_names_delegates_to_client(self):
        mock_client = MagicMock()
        mock_client.list_tables.return_value = ["a", "b"]
        svc = self._make_service(mock_client)

        result = svc.get_table_names("db")
        self.assertEqual(result, ["a", "b"])

    def test_normalise_location_converts_s3a(self):
        result = UnityCatalogRestMetastoreService._normalise_location(
            "s3a://bucket/path"
        )
        self.assertEqual(result, "s3://bucket/path")

    def test_normalise_location_converts_s3n(self):
        result = UnityCatalogRestMetastoreService._normalise_location(
            "s3n://bucket/path"
        )
        self.assertEqual(result, "s3://bucket/path")

    def test_normalise_location_keeps_s3(self):
        result = UnityCatalogRestMetastoreService._normalise_location(
            "s3://bucket/path"
        )
        self.assertEqual(result, "s3://bucket/path")

    @patch.dict(os.environ, {"ENVIRONMENT": "prod"}, clear=False)
    def test_catalog_resolved_from_env(self):
        svc = UnityCatalogRestMetastoreService(
            uc_rest_client=MagicMock(),
        )
        self.assertEqual(svc._catalog, "quintoandar_prod")

    @patch.dict(os.environ, {"ENVIRONMENT": "invalid"}, clear=False)
    def test_catalog_raises_for_invalid_env(self):
        with self.assertRaises(ValueError):
            UnityCatalogRestMetastoreService(uc_rest_client=MagicMock())

    def test_build_uc_columns(self):
        schema = OrderedDict({"id": "int", "name": "string"})
        cols = UnityCatalogRestMetastoreService._build_uc_columns(schema, [])
        self.assertEqual(len(cols), 2)
        self.assertEqual(cols[0]["name"], "id")
        self.assertEqual(cols[1]["name"], "name")

    def test_resolve_format_string(self):
        self.assertEqual(
            UnityCatalogRestMetastoreService._resolve_format("delta"), "DELTA"
        )

    def test_resolve_format_dict(self):
        self.assertEqual(
            UnityCatalogRestMetastoreService._resolve_format({"format": "parquet"}),
            "PARQUET",
        )

    def test_resolve_format_default(self):
        self.assertEqual(
            UnityCatalogRestMetastoreService._resolve_format(123), "PARQUET"
        )

    def test_repair_table_partitions_is_noop(self):
        svc = self._make_service()
        svc.repair_table_partitions("db", "tbl")

    def test_add_partitions_is_noop(self):
        svc = self._make_service()
        svc.add_partitions("db", "tbl", [])
