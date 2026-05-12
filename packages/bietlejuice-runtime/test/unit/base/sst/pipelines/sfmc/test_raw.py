from types import SimpleNamespace
from unittest import mock

import pytest

from bietlejuice.base.sst.pipelines.sfmc import (
    raw as raw_module,
)


@pytest.fixture
def cfg():
    return SimpleNamespace(
        target_schema="datalake_sfmc_raw",
        target_table="tb_sonia_ep2ds",
        partition_date="2026-04-15",
        bucket="test-bucket",
        external_key="EXTERNAL_KEY",
    )


@pytest.fixture
def mock_f():
    with mock.patch.object(raw_module, "F") as mock_f:
        mock_f.col.return_value = mock.MagicMock(name="col_expression")
        mock_f.lit.return_value = mock.MagicMock(name="lit_expression")
        mock_f.current_timestamp.return_value = mock.MagicMock(
            name="current_timestamp_expression"
        )
        yield mock_f


class TestSfmcRawPipeline:
    @mock.patch.object(raw_module, "resolve_api_credentials")
    @mock.patch.object(raw_module, "partition_has_data")
    def test_skips_when_partition_already_exists(
        self,
        mock_partition_has_data,
        mock_resolve_api_credentials,
        cfg,
        mock_f,
    ):
        # arrange
        spark = mock.MagicMock()
        mock_partition_has_data.return_value = True

        # act
        raw_module.sfmc_raw_pipeline(spark, cfg)

        # assert
        mock_partition_has_data.assert_called_once_with(
            spark,
            f"{cfg.target_schema}.{cfg.target_table}",
            cfg.partition_date,
        )
        mock_resolve_api_credentials.assert_not_called()
        spark.createDataFrame.assert_not_called()

    @mock.patch.object(raw_module, "validate_and_write")
    @mock.patch.object(raw_module, "fetch_object_rows")
    @mock.patch.object(raw_module, "get_access_token")
    @mock.patch.object(raw_module, "resolve_api_credentials")
    @mock.patch.object(raw_module, "partition_has_data")
    def test_skips_write_when_api_returns_no_rows(
        self,
        mock_partition_has_data,
        mock_resolve_api_credentials,
        mock_get_sfmc_access_token,
        mock_fetch_object_rows,
        mock_validate_and_write,
        cfg,
        mock_f,
    ):
        # arrange
        spark = mock.MagicMock()
        mock_partition_has_data.return_value = False
        mock_resolve_api_credentials.return_value = {
            "client_id": "client",
            "client_secret": "secret",
            "auth_url": "https://auth.example.com",
            "rest_url": "https://rest.example.com",
            "soap_url": "https://soap.example.com",
        }
        mock_get_sfmc_access_token.return_value = "TOKEN"
        mock_fetch_object_rows.return_value = []

        # act
        raw_module.sfmc_raw_pipeline(spark, cfg)

        # assert
        spark.createDataFrame.assert_not_called()
        mock_validate_and_write.assert_not_called()

    @mock.patch.object(raw_module, "validate_and_write")
    @mock.patch.object(raw_module, "align_and_cast_with_schema")
    @mock.patch.object(raw_module, "build_schema_columns")
    @mock.patch.object(raw_module, "get_data_extension_schema")
    @mock.patch.object(raw_module, "fetch_object_rows")
    @mock.patch.object(raw_module, "get_access_token")
    @mock.patch.object(raw_module, "resolve_api_credentials")
    @mock.patch.object(raw_module, "partition_has_data")
    def test_writes_raw_table_when_rows_are_returned(
        self,
        mock_partition_has_data,
        mock_resolve_api_credentials,
        mock_get_sfmc_access_token,
        mock_fetch_object_rows,
        mock_get_data_extension_schema,
        mock_build_schema_columns,
        mock_align_and_cast_with_schema,
        mock_validate_and_write,
        cfg,
        mock_f,
    ):
        # arrange
        spark = mock.MagicMock()
        raw_df = spark.createDataFrame.return_value
        typed_df = mock.MagicMock(name="typed_df")

        mock_partition_has_data.return_value = False
        mock_resolve_api_credentials.return_value = {
            "client_id": "client",
            "client_secret": "secret",
            "auth_url": "https://auth.example.com",
            "rest_url": "https://rest.example.com",
            "soap_url": "https://soap.example.com",
        }
        mock_get_sfmc_access_token.return_value = "TOKEN"
        mock_fetch_object_rows.return_value = [
            {"keys": {"id_user": "123"}, "values": {"amount": "100"}}
        ]

        mock_get_data_extension_schema.return_value = [
            {"field_name": "id_user", "field_type": "Number"}
        ]
        mock_build_schema_columns.return_value = {"id_user": "Number"}
        mock_align_and_cast_with_schema.return_value = typed_df
        typed_df.withColumn.return_value = typed_df

        # act
        raw_module.sfmc_raw_pipeline(spark, cfg)

        # assert — normalize_row flattens keys/values into a flat dict
        spark.createDataFrame.assert_called_once_with(
            [{"amount": "100", "id_user": "123"}]
        )
        mock_get_data_extension_schema.assert_called_once_with(
            soap_url="https://soap.example.com",
            access_token="TOKEN",
            customer_key=cfg.external_key,
        )
        mock_build_schema_columns.assert_called_once()
        mock_align_and_cast_with_schema.assert_called_once_with(
            raw_df, {"id_user": "Number"}
        )
        mock_validate_and_write.assert_called_once_with(
            spark=spark,
            df=typed_df,
            target_table=f"{cfg.target_schema}.{cfg.target_table}",
            partition_filter=f"partition_date = '{cfg.partition_date}'",
            partition_cols=["partition_date"],
            overwrite_schema=True,
            table_location=f"s3a://{cfg.bucket}/raw/{cfg.target_schema}/{cfg.target_table}",
        )
        mock_f.current_timestamp.assert_called_once_with()

    @mock.patch.object(raw_module, "validate_and_write")
    @mock.patch.object(raw_module, "get_data_extension_schema")
    @mock.patch.object(raw_module, "fetch_object_rows")
    @mock.patch.object(raw_module, "get_access_token")
    @mock.patch.object(raw_module, "resolve_api_credentials")
    @mock.patch.object(raw_module, "partition_has_data")
    def test_skips_write_when_schema_fetch_fails(
        self,
        mock_partition_has_data,
        mock_resolve_api_credentials,
        mock_get_sfmc_access_token,
        mock_fetch_object_rows,
        mock_get_data_extension_schema,
        mock_validate_and_write,
        cfg,
        mock_f,
    ):
        # arrange
        spark = mock.MagicMock()
        mock_partition_has_data.return_value = False
        mock_resolve_api_credentials.return_value = {
            "client_id": "client",
            "client_secret": "secret",
            "auth_url": "https://auth.example.com",
            "rest_url": "https://rest.example.com",
            "soap_url": "https://soap.example.com",
        }
        mock_get_sfmc_access_token.return_value = "TOKEN"
        mock_fetch_object_rows.return_value = [{"id_user": 123}]
        mock_get_data_extension_schema.side_effect = ValueError(
            "No DataExtensionField metadata returned"
        )

        # act / assert
        with pytest.raises(ValueError) as exc_info:
            raw_module.sfmc_raw_pipeline(spark, cfg)

        assert "No DataExtensionField metadata returned" in str(exc_info.value)
        mock_validate_and_write.assert_not_called()

    @mock.patch.object(raw_module, "validate_and_write")
    @mock.patch.object(raw_module, "resolve_api_credentials")
    @mock.patch.object(raw_module, "partition_has_data")
    def test_raises_and_does_not_write_when_credential_resolution_fails(
        self,
        mock_partition_has_data,
        mock_resolve_api_credentials,
        mock_validate_and_write,
        cfg,
        mock_f,
    ):
        # arrange
        spark = mock.MagicMock()
        mock_partition_has_data.return_value = False
        mock_resolve_api_credentials.side_effect = RuntimeError("credentials failure")

        # act / assert
        with pytest.raises(RuntimeError) as exc_info:
            raw_module.sfmc_raw_pipeline(spark, cfg)

        assert "credentials failure" in str(exc_info.value)
        spark.createDataFrame.assert_not_called()
        mock_validate_and_write.assert_not_called()
