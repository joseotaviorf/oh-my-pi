import unittest
from unittest.mock import MagicMock, patch

from pyspark.sql import DataFrame

from bietlejuice.jobs.common.raw_layer_loader import RawLayerLoader


class TestRawLayerLoader(unittest.TestCase):
    """Unit tests for RawLayerLoader incremental load options."""

    def setUp(self):
        self.spark_client = MagicMock()
        self.mock_df = MagicMock(spec=DataFrame)
        self.mock_df.isEmpty.return_value = False

    def _make_loader(self):
        return RawLayerLoader(
            spark_client=self.spark_client,
            environment="forno",
            source="greenhouse_audit_log",
            datalake_bucket="test-bucket",
            table_name="events",
            partition_cols=["year", "month", "day"],
            extraction_type="incremental",
        )

    @patch.object(RawLayerLoader, "_refresh_table")
    @patch.object(RawLayerLoader, "_apply_privileges_to_people_team")
    @patch.object(RawLayerLoader, "_update_metastore")
    @patch.object(RawLayerLoader, "_load_df_to_s3")
    @patch.object(RawLayerLoader, "_create_database_if_not_exists")
    def test_load_to_raw_default_calls_all_steps(
        self,
        mock_create_db,
        mock_s3,
        mock_meta,
        mock_priv,
        mock_refresh,
    ):
        """Default load_to_raw updates metastore with force_recreate, grants, refresh."""
        loader = self._make_loader()
        loader.load_to_raw(self.mock_df)

        mock_create_db.assert_called_once()
        mock_s3.assert_called_once_with(self.mock_df)
        mock_meta.assert_called_once_with(self.mock_df, force_recreate=True)
        mock_priv.assert_called_once()
        mock_refresh.assert_called_once()

    @patch.object(RawLayerLoader, "_refresh_table")
    @patch.object(RawLayerLoader, "_apply_privileges_to_people_team")
    @patch.object(RawLayerLoader, "_update_metastore")
    @patch.object(RawLayerLoader, "_load_df_to_s3")
    @patch.object(RawLayerLoader, "_create_database_if_not_exists")
    def test_load_to_raw_incremental_batch_skips_privileges_and_refresh(
        self,
        mock_create_db,
        mock_s3,
        mock_meta,
        mock_priv,
        mock_refresh,
    ):
        """Streaming batch can skip privileges and refresh until finalize."""
        loader = self._make_loader()
        loader.load_to_raw(
            self.mock_df,
            metastore_force_recreate=False,
            apply_table_privileges=False,
            refresh_table_after_load=False,
        )

        mock_meta.assert_called_once_with(self.mock_df, force_recreate=False)
        mock_priv.assert_not_called()
        mock_refresh.assert_not_called()

    @patch.object(RawLayerLoader, "_refresh_table")
    @patch.object(RawLayerLoader, "_apply_privileges_to_people_team")
    def test_finalize_raw_layer_visibility_applies_privileges_and_refresh(
        self,
        mock_priv,
        mock_refresh,
    ):
        """finalize_raw_layer_visibility runs grants and refresh only."""
        loader = self._make_loader()
        loader.finalize_raw_layer_visibility()

        mock_priv.assert_called_once()
        mock_refresh.assert_called_once()


if __name__ == "__main__":
    unittest.main()
