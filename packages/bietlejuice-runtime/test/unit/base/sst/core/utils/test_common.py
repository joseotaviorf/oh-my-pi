import importlib
import sys
from unittest import mock

import pytest

_STUB_MODULES = [
    "bietlejuice.base.sst.core.metadata.sync_metadata",
    "bietlejuice.base.spark.delta_secondary_catalog_sync",
]
for _mod in _STUB_MODULES:
    sys.modules.setdefault(_mod, mock.MagicMock())

_secondary_catalog_sync_module = sys.modules[
    "bietlejuice.base.spark.delta_secondary_catalog_sync"
]

common_module = importlib.import_module("bietlejuice.base.sst.core.utils.common")


class TestValidatePartitionReadability:
    @mock.patch.object(common_module, "F")
    def test_executes_read_query_on_target_table(self, mock_f):
        # arrange
        spark = mock.MagicMock()
        table_df = mock.MagicMock()
        spark.read.table.return_value = table_df
        table_df.where.return_value = table_df

        # act
        common_module.validate_partition_readability(
            spark=spark,
            target_table="datalake_sfmc_clean.tb_sonia_ep2ds",
            partition_date="2026-04-15",
        )

        # assert
        spark.read.table.assert_called_once_with("datalake_sfmc_clean.tb_sonia_ep2ds")
        table_df.where.assert_called()


class TestResolveGlueTableName:
    @pytest.mark.parametrize(
        "target_table,expected",
        [
            (
                "datalake_salesforce_raw.events_case",
                "datalake_salesforce_raw.events_case",
            ),
            (
                "quintoandar_prod.datalake_salesforce_raw.events_case",
                "datalake_salesforce_raw.events_case",
            ),
        ],
    )
    def test_resolves_two_and_three_part_names(self, target_table, expected):
        assert common_module._resolve_glue_table_name(target_table) == expected

    def test_raises_for_unqualified_name(self):
        with pytest.raises(ValueError, match="qualified name"):
            common_module._resolve_glue_table_name("events_case")


def _mock_df_writer():
    writer = mock.MagicMock()
    writer.format.return_value = writer
    writer.mode.return_value = writer
    writer.partitionBy.return_value = writer
    writer.option.return_value = writer
    return writer


class TestValidateAndWriteCatalogSync:
    def test_common_module_lazy_loads_secondary_catalog_sync(self):
        assert not hasattr(common_module, "sync_delta_write_to_secondary_catalog")

    @mock.patch.object(
        _secondary_catalog_sync_module,
        "sync_delta_write_to_secondary_catalog",
    )
    @mock.patch.object(common_module, "sync_trino_metadata")
    @mock.patch.object(common_module, "_table_exists")
    def test_create_branch_syncs_trino_and_secondary_catalog(
        self, mock_table_exists, mock_sync_trino, mock_sync_secondary
    ):
        # arrange
        spark = mock.MagicMock()
        df = mock.MagicMock()
        df.write = _mock_df_writer()
        mock_table_exists.side_effect = [False, True]
        table_location = "s3a://bucket/raw/salesforce/events_case"
        target_table = "datalake_salesforce_raw.events_case"

        # act
        common_module.validate_and_write(
            spark=spark,
            df=df,
            target_table=target_table,
            table_location=table_location,
            partition_filter="partition_date = '2026-01-01'",
            partition_cols=["partition_date", "partition_hour"],
            sync_hive=True,
            sync_secondary_catalog=True,
        )

        # assert
        mock_sync_trino.assert_called_once_with(target_table, table_location, df)
        mock_sync_secondary.assert_called_once_with(
            spark=spark,
            full_table_name=target_table,
            table_location_s3=table_location,
            source_df=df,
            partition_col_names=["partition_date", "partition_hour"],
        )

    @mock.patch.object(
        _secondary_catalog_sync_module,
        "sync_delta_write_to_secondary_catalog",
    )
    @mock.patch.object(common_module, "sync_trino_metadata")
    @mock.patch.object(common_module, "_table_exists")
    def test_overwrite_branch_syncs_secondary_catalog(
        self, mock_table_exists, mock_sync_trino, mock_sync_secondary
    ):
        # arrange
        spark = mock.MagicMock()
        df = mock.MagicMock()
        df.columns = ["id_record", "partition_date", "partition_hour"]
        df.select.return_value = df
        df.write = _mock_df_writer()
        mock_table_exists.return_value = True
        spark.read.table.return_value.columns = df.columns
        table_location = "s3a://bucket/raw/salesforce/events_case"
        target_table = "quintoandar_prod.datalake_salesforce_raw.events_case"

        # act
        common_module.validate_and_write(
            spark=spark,
            df=df,
            target_table=target_table,
            table_location=table_location,
            partition_filter="partition_date = '2026-01-01'",
            partition_cols=["partition_date", "partition_hour"],
            sync_secondary_catalog=True,
        )

        # assert
        mock_sync_trino.assert_not_called()
        mock_sync_secondary.assert_called_once_with(
            spark=spark,
            full_table_name="datalake_salesforce_raw.events_case",
            table_location_s3=table_location,
            source_df=df,
            partition_col_names=["partition_date", "partition_hour"],
        )

    @mock.patch.object(
        _secondary_catalog_sync_module,
        "sync_delta_write_to_secondary_catalog",
    )
    @mock.patch.object(common_module, "sync_trino_metadata")
    @mock.patch.object(common_module, "_table_exists")
    def test_skips_secondary_sync_when_disabled(
        self, mock_table_exists, mock_sync_trino, mock_sync_secondary
    ):
        # arrange
        spark = mock.MagicMock()
        df = mock.MagicMock()
        df.columns = ["id_record"]
        df.select.return_value = df
        df.write = _mock_df_writer()
        mock_table_exists.return_value = True
        spark.read.table.return_value.columns = df.columns

        # act
        common_module.validate_and_write(
            spark=spark,
            df=df,
            target_table="datalake_salesforce_raw.events_case",
            table_location="s3a://bucket/raw/salesforce/events_case",
            partition_filter="partition_date = '2026-01-01'",
            partition_cols=["partition_date"],
            sync_secondary_catalog=False,
        )

        # assert
        mock_sync_secondary.assert_not_called()
