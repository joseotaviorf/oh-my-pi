import importlib
import sys
from unittest import mock

import pytest
from trino.exceptions import Http502Error, Http503Error

_STUB_MODULES = [
    "bietlejuice.base.spark.base_spark",
    "bietlejuice.clients.db_clients.trino_client",
]
for _mod in _STUB_MODULES:
    sys.modules.setdefault(_mod, mock.MagicMock())

sync_metadata = importlib.import_module(
    "bietlejuice.base.sst.core.metadata.sync_metadata"
)


class TestSyncTrinoMetadata:
    @mock.patch.object(sync_metadata, "_get_trino_client")
    @mock.patch.object(sync_metadata, "sync_trino_table_schema")
    def test_swallows_http_502_error(self, mock_sync_schema, mock_get_client):
        # arrange
        mock_get_client.side_effect = Http502Error("error 502: bad gateway")
        df = mock.MagicMock()
        df.dtypes = [("id_record", "string")]

        # act / assert — must not raise
        sync_metadata.sync_trino_metadata(
            target_table="datalake_quality.contract_checks",
            table_location="s3a://bucket/quality/contract_checks",
            df=df,
        )
        mock_sync_schema.assert_not_called()

    @mock.patch.object(sync_metadata, "_get_trino_client")
    @mock.patch.object(sync_metadata, "sync_trino_table_schema")
    @pytest.mark.parametrize(
        "error",
        [
            Http503Error("error 503: service unavailable"),
            ConnectionError("connection refused"),
            RuntimeError("unexpected failure"),
        ],
    )
    def test_swallows_trino_unavailability_errors(
        self, mock_sync_schema, mock_get_client, error
    ):
        # arrange
        mock_get_client.side_effect = error
        df = mock.MagicMock()
        df.dtypes = [("id_record", "string")]

        # act / assert — must not raise
        sync_metadata.sync_trino_metadata(
            target_table="datalake_quality.contract_checks",
            table_location="s3a://bucket/quality/contract_checks",
            df=df,
        )
        mock_sync_schema.assert_not_called()
