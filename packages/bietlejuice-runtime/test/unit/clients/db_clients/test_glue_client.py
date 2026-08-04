"""Unit tests for GlueClient STS assume-role and boto3 Glue construction."""

import os
from unittest.mock import MagicMock, patch

from bietlejuice.clients.db_clients.glue_client import GlueClient


class TestGlueClient:
    def test_conn_without_role_uses_default_credentials(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("GLUE_ASSUME_ROLE_ARN", None)
            with patch(
                "bietlejuice.clients.db_clients.glue_client.boto3.client"
            ) as mock_boto_client:
                mock_glue = MagicMock()
                mock_boto_client.return_value = mock_glue

                client = GlueClient(role_arn=None)
                assert client.conn is mock_glue

                mock_boto_client.assert_called_once_with(
                    "glue", region_name="us-east-1"
                )

    def test_conn_reads_role_arn_from_glue_assume_role_arn_env(self):
        role_arn = "arn:aws:iam::111111111111:role/from-env"
        with patch.dict(os.environ, {"GLUE_ASSUME_ROLE_ARN": role_arn}, clear=False):
            with patch(
                "bietlejuice.clients.db_clients.glue_client.boto3.client"
            ) as mock_boto_client:
                mock_sts = MagicMock()
                mock_sts.assume_role.return_value = {
                    "Credentials": {
                        "AccessKeyId": "AKIAENV",
                        "SecretAccessKey": "secret-env",
                        "SessionToken": "token-env",
                    }
                }
                mock_glue = MagicMock()

                def client_side_effect(service, **kwargs):
                    if service == "sts":
                        return mock_sts
                    if service == "glue":
                        return mock_glue
                    raise AssertionError(f"unexpected service {service}")

                mock_boto_client.side_effect = client_side_effect

                client = GlueClient()
                assert client.conn is mock_glue

                mock_sts.assume_role.assert_called_once_with(
                    RoleArn=role_arn,
                    RoleSessionName="bietlejuice-glue-sync",
                )
                glue_calls = [
                    c for c in mock_boto_client.call_args_list if c[0][0] == "glue"
                ]
                assert len(glue_calls) == 1
                assert glue_calls[0][1]["aws_access_key_id"] == "AKIAENV"
                assert glue_calls[0][1]["aws_secret_access_key"] == "secret-env"
                assert glue_calls[0][1]["aws_session_token"] == "token-env"
                assert glue_calls[0][1]["region_name"] == "us-east-1"

    def test_update_table_passes_skip_archive_by_default(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("GLUE_ASSUME_ROLE_ARN", None)
            with patch(
                "bietlejuice.clients.db_clients.glue_client.boto3.client"
            ) as mock_boto_client:
                mock_glue = MagicMock()
                mock_boto_client.return_value = mock_glue

                client = GlueClient(role_arn=None)
                table_input = {"Name": "example_table"}
                client.update_table("datalake_example", table_input)

                mock_glue.update_table.assert_called_once_with(
                    DatabaseName="datalake_example",
                    TableInput=table_input,
                    SkipArchive=True,
                )

    def test_conn_with_explicit_role_arn_assumes_role(self):
        role_arn = "arn:aws:iam::222222222222:role/explicit"
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("GLUE_ASSUME_ROLE_ARN", None)
            with patch(
                "bietlejuice.clients.db_clients.glue_client.boto3.client"
            ) as mock_boto_client:
                mock_sts = MagicMock()
                mock_sts.assume_role.return_value = {
                    "Credentials": {
                        "AccessKeyId": "AKIAEXP",
                        "SecretAccessKey": "secret-exp",
                        "SessionToken": "token-exp",
                    }
                }
                mock_glue = MagicMock()

                def client_side_effect(service, **kwargs):
                    if service == "sts":
                        return mock_sts
                    if service == "glue":
                        return mock_glue
                    raise AssertionError(f"unexpected service {service}")

                mock_boto_client.side_effect = client_side_effect

                client = GlueClient(role_arn=role_arn)
                assert client.conn is mock_glue

                mock_sts.assume_role.assert_called_once_with(
                    RoleArn=role_arn,
                    RoleSessionName="bietlejuice-glue-sync",
                )


class TestGlueClientPartitionApis:
    def _client_with_mock_glue(self, mock_glue):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("GLUE_ASSUME_ROLE_ARN", None)
            with patch(
                "bietlejuice.clients.db_clients.glue_client.boto3.client",
                return_value=mock_glue,
            ):
                client = GlueClient(role_arn=None)
                _ = client.conn  # cache mock while patch is active
                return client

    def test_get_partitions_paginates_full_dicts(self):
        mock_glue = MagicMock()
        page1 = {
            "Partitions": [
                {"Values": ["2018", "10", "19"], "StorageDescriptor": {"Location": "a"}}
            ]
        }
        page2 = {
            "Partitions": [
                {"Values": ["2019", "01", "01"], "StorageDescriptor": {"Location": "b"}}
            ]
        }
        paginator = MagicMock()
        paginator.paginate.return_value = [page1, page2]
        mock_glue.get_paginator.return_value = paginator

        client = self._client_with_mock_glue(mock_glue)
        partitions = client.get_partitions("db", "tbl")

        assert len(partitions) == 2
        assert partitions[0]["Values"] == ["2018", "10", "19"]
        mock_glue.get_paginator.assert_called_once_with("get_partitions")

    def test_batch_update_partition_batches_of_100(self):
        mock_glue = MagicMock()
        mock_glue.batch_update_partition.return_value = {"Errors": []}

        client = self._client_with_mock_glue(mock_glue)
        entries = [
            {
                "PartitionValueList": [str(i)],
                "PartitionInput": {"Values": [str(i)]},
            }
            for i in range(250)
        ]

        updated = client.batch_update_partition("db", "tbl", entries)

        assert updated == 250
        assert mock_glue.batch_update_partition.call_count == 3
        first_batch = mock_glue.batch_update_partition.call_args_list[0][1]["Entries"]
        assert len(first_batch) == 100
        last_batch = mock_glue.batch_update_partition.call_args_list[2][1]["Entries"]
        assert len(last_batch) == 50

    def test_batch_update_partition_raises_on_errors(self):
        mock_glue = MagicMock()
        mock_glue.batch_update_partition.return_value = {
            "Errors": [
                {
                    "PartitionValues": ["2018", "10", "19"],
                    "ErrorDetail": {
                        "ErrorCode": "EntityNotFoundException",
                        "ErrorMessage": "missing",
                    },
                }
            ]
        }

        client = self._client_with_mock_glue(mock_glue)
        entries = [
            {
                "PartitionValueList": ["2018", "10", "19"],
                "PartitionInput": {"Values": ["2018", "10", "19"]},
            }
        ]

        try:
            client.batch_update_partition("db", "tbl", entries)
            raise AssertionError("expected RuntimeError")
        except RuntimeError as exc:
            assert "batch_update_partition failed" in str(exc)

    def test_batch_update_partition_empty_is_noop(self):
        mock_glue = MagicMock()
        client = self._client_with_mock_glue(mock_glue)
        assert client.batch_update_partition("db", "tbl", []) == 0
        mock_glue.batch_update_partition.assert_not_called()
