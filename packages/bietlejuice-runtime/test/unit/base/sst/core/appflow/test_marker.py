"""Unit tests for the AppFlow client construction and STS assume-role support."""

import os
from unittest.mock import MagicMock, patch

from bietlejuice.base.sst.core.appflow.marker import (
    APPFLOW_ASSUME_ROLE_ARN_ENV,
    APPFLOW_ROLE_SESSION_NAME,
    build_appflow_client,
    describe_flow_status,
)

MARKER_BOTO3 = "bietlejuice.base.sst.core.appflow.marker.boto3.client"
CROSS_ACCOUNT_ROLE = "arn:aws:iam::632540934959:role/emr-prod-appflow-access"

ASSUMED_CREDENTIALS = {
    "Credentials": {
        "AccessKeyId": "AKIAASSUMED",
        "SecretAccessKey": "secret-assumed",
        "SessionToken": "token-assumed",
    }
}


def _sts_and_appflow_mocks():
    """Return (side_effect, mock_sts, mock_appflow) for a patched boto3.client."""
    mock_sts = MagicMock()
    mock_sts.assume_role.return_value = ASSUMED_CREDENTIALS
    mock_appflow = MagicMock()

    def side_effect(service, **kwargs):
        return mock_sts if service == "sts" else mock_appflow

    return side_effect, mock_sts, mock_appflow


class TestBuildAppflowClient:
    def test_without_role_uses_default_credentials(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop(APPFLOW_ASSUME_ROLE_ARN_ENV, None)
            with patch(MARKER_BOTO3) as mock_boto_client:
                mock_appflow = MagicMock()
                mock_boto_client.return_value = mock_appflow

                assert build_appflow_client() is mock_appflow

                mock_boto_client.assert_called_once_with(
                    "appflow", region_name="us-east-1"
                )

    def test_empty_role_arn_falls_back_to_default_credentials(self):
        """forno passes an empty string: the instance profile already sees the flows."""
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop(APPFLOW_ASSUME_ROLE_ARN_ENV, None)
            with patch(MARKER_BOTO3) as mock_boto_client:
                mock_boto_client.return_value = MagicMock()

                build_appflow_client(assume_role_arn="")

                mock_boto_client.assert_called_once_with(
                    "appflow", region_name="us-east-1"
                )

    def test_role_arn_assumes_role_and_scopes_credentials_to_appflow(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop(APPFLOW_ASSUME_ROLE_ARN_ENV, None)
            side_effect, mock_sts, mock_appflow = _sts_and_appflow_mocks()
            with patch(MARKER_BOTO3, side_effect=side_effect) as mock_boto_client:
                client = build_appflow_client(assume_role_arn=CROSS_ACCOUNT_ROLE)

                assert client is mock_appflow
                mock_sts.assume_role.assert_called_once_with(
                    RoleArn=CROSS_ACCOUNT_ROLE,
                    RoleSessionName=APPFLOW_ROLE_SESSION_NAME,
                )
                mock_boto_client.assert_any_call(
                    "appflow",
                    region_name="us-east-1",
                    aws_access_key_id="AKIAASSUMED",
                    aws_secret_access_key="secret-assumed",
                    aws_session_token="token-assumed",
                )

    def test_reads_role_arn_from_env_var(self):
        env_role = "arn:aws:iam::111111111111:role/from-env"
        with patch.dict(
            os.environ, {APPFLOW_ASSUME_ROLE_ARN_ENV: env_role}, clear=False
        ):
            side_effect, mock_sts, _ = _sts_and_appflow_mocks()
            with patch(MARKER_BOTO3, side_effect=side_effect):
                build_appflow_client()

                mock_sts.assume_role.assert_called_once_with(
                    RoleArn=env_role,
                    RoleSessionName=APPFLOW_ROLE_SESSION_NAME,
                )

    def test_explicit_role_arn_wins_over_env_var(self):
        with patch.dict(
            os.environ,
            {APPFLOW_ASSUME_ROLE_ARN_ENV: "arn:aws:iam::111111111111:role/from-env"},
            clear=False,
        ):
            side_effect, mock_sts, _ = _sts_and_appflow_mocks()
            with patch(MARKER_BOTO3, side_effect=side_effect):
                build_appflow_client(assume_role_arn=CROSS_ACCOUNT_ROLE)

                mock_sts.assume_role.assert_called_once_with(
                    RoleArn=CROSS_ACCOUNT_ROLE,
                    RoleSessionName=APPFLOW_ROLE_SESSION_NAME,
                )


class TestDescribeFlowStatus:
    def test_forwards_assume_role_arn_and_returns_flow_status(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop(APPFLOW_ASSUME_ROLE_ARN_ENV, None)
            side_effect, mock_sts, mock_appflow = _sts_and_appflow_mocks()
            mock_appflow.describe_flow.return_value = {"flowStatus": "Active"}
            with patch(MARKER_BOTO3, side_effect=side_effect):
                status = describe_flow_status(
                    "ReceivedDocumentEvent",
                    assume_role_arn=CROSS_ACCOUNT_ROLE,
                )

                assert status == "Active"
                mock_sts.assume_role.assert_called_once()
                mock_appflow.describe_flow.assert_called_once_with(
                    flowName="ReceivedDocumentEvent"
                )
