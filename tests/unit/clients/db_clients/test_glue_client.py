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
