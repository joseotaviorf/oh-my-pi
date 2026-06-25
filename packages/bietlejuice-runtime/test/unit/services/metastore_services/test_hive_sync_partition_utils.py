"""Unit tests for EMR Delta hive partition sync skip logic."""

import unittest
from unittest.mock import MagicMock, patch

from bietlejuice.services.metastore_services.hive_sync_partition_utils import (
    is_delta_table_in_catalog,
    should_skip_emr_hive_partition_sync,
)


class TestIsDeltaTableInCatalog(unittest.TestCase):
    @patch(
        "bietlejuice.services.metastore_services.hive_sync_partition_utils._lookup_delta_in_glue_catalog",
        return_value=True,
    )
    def test_uses_glue_when_delta(self, _mock_glue):
        self.assertTrue(is_delta_table_in_catalog("db", "table"))

    @patch(
        "bietlejuice.services.metastore_services.hive_sync_partition_utils._lookup_delta_in_glue_catalog",
        return_value=False,
    )
    def test_uses_glue_when_parquet(self, _mock_glue):
        self.assertFalse(is_delta_table_in_catalog("db", "table"))

    @patch(
        "bietlejuice.services.metastore_services.hive_sync_partition_utils._lookup_delta_in_glue_catalog",
        return_value=None,
    )
    @patch(
        "bietlejuice.services.metastore_services.hive_sync_partition_utils._is_delta_in_spark_catalog",
        return_value=True,
    )
    def test_falls_back_to_spark_catalog(self, _mock_spark, _mock_glue):
        spark = MagicMock()
        self.assertTrue(is_delta_table_in_catalog("db", "table", spark=spark))
        _mock_spark.assert_called_once_with("db", "table", spark)


class TestShouldSkipEmrHivePartitionSync(unittest.TestCase):
    @patch(
        "bietlejuice.services.metastore_services.hive_sync_partition_utils.RuntimeDetector.is_emr",
        return_value=False,
    )
    @patch(
        "bietlejuice.services.metastore_services.hive_sync_partition_utils.is_delta_table_in_catalog"
    )
    def test_databricks_never_skips(self, mock_is_delta, _mock_is_emr):
        mock_is_delta.return_value = True
        self.assertFalse(
            should_skip_emr_hive_partition_sync("db", "table_ingestion_metrics")
        )
        mock_is_delta.assert_not_called()

    @patch(
        "bietlejuice.services.metastore_services.hive_sync_partition_utils.RuntimeDetector.is_emr",
        return_value=True,
    )
    @patch(
        "bietlejuice.services.metastore_services.hive_sync_partition_utils.is_delta_table_in_catalog",
        return_value=True,
    )
    def test_emr_delta_skips(self, _mock_is_delta, _mock_is_emr):
        self.assertTrue(
            should_skip_emr_hive_partition_sync("db", "table_ingestion_metrics")
        )

    @patch(
        "bietlejuice.services.metastore_services.hive_sync_partition_utils.RuntimeDetector.is_emr",
        return_value=True,
    )
    @patch(
        "bietlejuice.services.metastore_services.hive_sync_partition_utils.is_delta_table_in_catalog",
        return_value=False,
    )
    def test_emr_parquet_does_not_skip(self, _mock_is_delta, _mock_is_emr):
        self.assertFalse(should_skip_emr_hive_partition_sync("db", "events"))
