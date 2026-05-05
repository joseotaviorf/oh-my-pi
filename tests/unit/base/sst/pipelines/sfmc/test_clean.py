from types import SimpleNamespace
from unittest import mock

import pytest

from bietlejuice.base.sst.pipelines.sfmc import (
    clean as clean_module,
)


@pytest.fixture
def cfg():
    return SimpleNamespace(
        source_schema="datalake_sfmc_raw",
        target_schema="datalake_sfmc_clean",
        target_table="sonia_ep2ds",
        bucket="test-bucket",
        sync_hive=True,
        partition_date="2026-04-15",
    )


@pytest.fixture
def mock_f():
    with mock.patch.object(clean_module, "F") as mock_f:
        mock_f.col.return_value = mock.MagicMock(name="col_expression")
        mock_f.lit.return_value = mock.MagicMock(name="lit_expression")
        mock_f.current_timestamp.return_value = mock.MagicMock(
            name="current_timestamp_expression"
        )
        yield mock_f


class TestSfmcCleanPipeline:
    @mock.patch.object(clean_module, "partition_has_data")
    def test_skips_when_clean_already_has_partition(
        self,
        mock_partition_has_data,
        cfg,
        mock_f,
    ):
        # arrange
        spark = mock.MagicMock()
        mock_partition_has_data.return_value = True

        # act
        clean_module.sfmc_clean_pipeline(spark, cfg)

        # assert
        mock_partition_has_data.assert_called_once_with(
            spark,
            f"{cfg.target_schema}.{cfg.target_table}",
            cfg.partition_date,
        )

    @mock.patch.object(clean_module, "validate_and_write")
    @mock.patch.object(clean_module, "validate_partition_readability")
    @mock.patch.object(clean_module, "normalize_df_columns")
    @mock.patch.object(clean_module, "partition_has_data")
    def test_writes_clean_table_using_dag_partition_date(
        self,
        mock_partition_has_data,
        mock_normalize_df_columns,
        mock_validate_partition_readability,
        mock_validate_and_write,
        cfg,
        mock_f,
    ):
        # arrange
        spark = mock.MagicMock()
        source_df = mock.MagicMock(name="source_df")
        cleaned_df = mock.MagicMock(name="cleaned_df")

        mock_partition_has_data.return_value = False
        mock_normalize_df_columns.return_value = source_df

        source_df.withColumn.return_value = cleaned_df
        cleaned_df.withColumn.return_value = cleaned_df

        # act
        clean_module.sfmc_clean_pipeline(spark, cfg)

        # assert
        spark.read.table.assert_called_with(f"{cfg.source_schema}.{cfg.target_table}")
        mock_normalize_df_columns.assert_called_once_with(
            spark.read.table.return_value.where.return_value
        )
        mock_validate_and_write.assert_called_once_with(
            spark=spark,
            df=cleaned_df,
            target_table=f"{cfg.target_schema}.{cfg.target_table}",
            partition_filter=f"partition_date = '{cfg.partition_date}'",
            partition_cols=["partition_date"],
            overwrite_schema=True,
            table_location=f"s3a://{cfg.bucket}/clean/{cfg.target_schema}/{cfg.target_table}",
            sync_hive=cfg.sync_hive,
        )
        mock_validate_partition_readability.assert_called_once_with(
            spark=spark,
            target_table=f"{cfg.target_schema}.{cfg.target_table}",
            partition_date=cfg.partition_date,
        )
        mock_f.current_timestamp.assert_called_once_with()

    @mock.patch.object(clean_module, "validate_and_write")
    @mock.patch.object(clean_module, "validate_partition_readability")
    @mock.patch.object(clean_module, "normalize_df_columns")
    @mock.patch.object(clean_module, "partition_has_data")
    def test_raises_when_post_write_readback_fails(
        self,
        mock_partition_has_data,
        mock_normalize_df_columns,
        mock_validate_partition_readability,
        mock_validate_and_write,
        cfg,
        mock_f,
    ):
        # arrange
        spark = mock.MagicMock()
        source_df = mock.MagicMock(name="source_df")
        cleaned_df = mock.MagicMock(name="cleaned_df")

        mock_partition_has_data.return_value = False
        mock_normalize_df_columns.return_value = source_df

        source_df.withColumn.return_value = cleaned_df
        cleaned_df.withColumn.return_value = cleaned_df

        mock_validate_partition_readability.side_effect = Exception("readback failed")

        # act / assert
        with pytest.raises(RuntimeError) as exc_info:
            clean_module.sfmc_clean_pipeline(spark, cfg)

        assert "post-write readback failed" in str(exc_info.value)
        mock_validate_and_write.assert_called_once()

    @mock.patch.object(clean_module, "partition_has_data")
    def test_derives_source_table_from_source_schema_and_target_table(
        self,
        mock_partition_has_data,
        cfg,
        mock_f,
    ):
        # arrange
        spark = mock.MagicMock()
        mock_partition_has_data.return_value = True

        # act
        clean_module.sfmc_clean_pipeline(spark, cfg)

        # assert
        mock_partition_has_data.assert_called_once_with(
            spark,
            f"{cfg.target_schema}.{cfg.target_table}",
            cfg.partition_date,
        )
