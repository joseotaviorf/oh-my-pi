"""Unit tests for sync_glue_json_partition_serde spark job."""

import sys
from unittest import mock

import pytest

sys.modules["quintoandar_logger"] = mock.MagicMock()
# Other cross suite tests stub ``bietlejuice.base.spark`` as a MagicMock, which
# makes real submodule imports fail ("is not a package"). Mirror the sync_metadata
# pattern: stub leaf modules before importing the job under test.
sys.modules["bietlejuice.base.spark"] = mock.MagicMock()
sys.modules["bietlejuice.base.spark.glue_catalog_helper"] = mock.MagicMock()
sys.modules["bietlejuice.services.metastore_services.glue_metastore_service"] = (
    mock.MagicMock()
)
sys.modules["bietlejuice.services.metastore_services.glue_partition_utils"] = (
    mock.MagicMock()
)

from dags.cross.base.spark_jobs import (  # noqa: E402
    sync_glue_json_partition_serde as job,
)


class TestSyncGlueJsonPartitionSerdeJob:
    @mock.patch.object(job.GlueCatalogHelper, "get_glue_client")
    @mock.patch.object(
        job.GlueCatalogHelper, "is_glue_catalog_enabled", return_value=True
    )
    @mock.patch.object(job, "GlueMetastoreService")
    def test_runs_type_coerce_then_partition_serde(
        self, mock_service_cls, _mock_enabled, mock_get_client
    ):
        glue_client = mock.MagicMock()
        mock_get_client.return_value = glue_client

        service = mock_service_cls.return_value
        service.coerce_json_table_column_types.return_value = {
            "scanned": 3,
            "updated": 1,
            "skipped": 0,
            "errors": 0,
        }
        service.sync_json_partition_serde.return_value = {
            "scanned": 10,
            "updated": 2,
            "skipped": 0,
            "errors": 0,
        }

        with mock.patch.object(
            job,
            "_json_table_names",
            return_value=["agreement_discounts"],
        ):
            totals = job.sync_glue_json_partition_serde(
                all_databases=False,
                database_name="datalake_cyber_raw",
                table_name=None,
                dry_run=True,
            )

        service.coerce_json_table_column_types.assert_called_once_with(
            "datalake_cyber_raw", "agreement_discounts", dry_run=True
        )
        service.sync_json_partition_serde.assert_called_once_with(
            "datalake_cyber_raw", "agreement_discounts", dry_run=True
        )
        assert totals["columns_updated"] == 1
        assert totals["partitions_updated"] == 2

    @mock.patch.object(job.GlueCatalogHelper, "get_glue_client")
    @mock.patch.object(
        job.GlueCatalogHelper, "is_glue_catalog_enabled", return_value=True
    )
    @mock.patch.object(job, "GlueMetastoreService")
    def test_skip_type_coerce_only_runs_serde(
        self, mock_service_cls, _mock_enabled, mock_get_client
    ):
        mock_get_client.return_value = mock.MagicMock()
        service = mock_service_cls.return_value
        service.sync_json_partition_serde.return_value = {
            "scanned": 1,
            "updated": 0,
            "skipped": 0,
            "errors": 0,
        }

        totals = job.sync_glue_json_partition_serde(
            all_databases=False,
            database_name="datalake_cyber_raw",
            table_name="t1",
            dry_run=False,
            skip_type_coerce=True,
        )

        service.coerce_json_table_column_types.assert_not_called()
        service.sync_json_partition_serde.assert_called_once()
        assert totals["columns_updated"] == 0

    @mock.patch.object(
        job.GlueCatalogHelper, "is_glue_catalog_enabled", return_value=True
    )
    def test_cannot_skip_both(self, _mock_enabled):
        with pytest.raises(ValueError, match="both"):
            job.sync_glue_json_partition_serde(
                all_databases=False,
                database_name="db",
                table_name="t",
                dry_run=True,
                skip_type_coerce=True,
                skip_partition_serde=True,
            )
