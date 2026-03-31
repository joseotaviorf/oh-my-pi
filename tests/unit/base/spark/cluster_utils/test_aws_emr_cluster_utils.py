import os
from unittest.mock import MagicMock

from bietlejuice.base.spark.cluster_utils.aws_emr_cluster_utils import (
    AwsEmrClusterUtils,
    _parse_s3_uri,
    _secrets_manager_region,
)
from bietlejuice.base.spark.cluster_utils.factory import (
    get_emr_dbutils_facade,
    reset_emr_dbutils_facade,
    should_use_emr_cluster_utils,
)
from bietlejuice.base.spark.base_spark import BaseDBUtils


class TestParseS3Uri:
    def test_bucket_and_key(self):
        assert _parse_s3_uri("s3://my-bucket/path/to/obj") == (
            "my-bucket",
            "path/to/obj",
        )

    def test_bucket_only(self):
        assert _parse_s3_uri("s3://my-bucket") == ("my-bucket", "")


class TestSecretsManagerRegion:
    def test_default_us_east_1(self, monkeypatch):
        monkeypatch.delenv("AWS_SECRETS_MANAGER_REGION", raising=False)
        monkeypatch.delenv("AWS_DEFAULT_REGION", raising=False)
        assert _secrets_manager_region() == "us-east-1"

    def test_aws_secrets_manager_region_wins(self, monkeypatch):
        monkeypatch.setenv("AWS_SECRETS_MANAGER_REGION", "sa-east-1")
        monkeypatch.setenv("AWS_DEFAULT_REGION", "us-west-2")
        assert _secrets_manager_region() == "sa-east-1"


class TestAwsEmrClusterUtilsSecrets:
    def test_get_secret_default_template_key_only(self, monkeypatch):
        monkeypatch.delenv("BIETL_SECRETS_MANAGER_SECRET_ID_TEMPLATE", raising=False)
        mock_client = MagicMock()
        mock_client.get_secret_value.return_value = {"SecretString": '{"a": 1}'}

        u = AwsEmrClusterUtils()
        u._secrets_client = mock_client
        out = u.get_secret("quintoandar", "MY_KEY")
        assert out == '{"a": 1}'
        mock_client.get_secret_value.assert_called_once_with(SecretId="MY_KEY")

    def test_get_secret_custom_scope_key_template(self, monkeypatch):
        monkeypatch.setenv("BIETL_SECRETS_MANAGER_SECRET_ID_TEMPLATE", "{scope}/{key}")
        mock_client = MagicMock()
        mock_client.get_secret_value.return_value = {"SecretString": '{"a": 1}'}

        u = AwsEmrClusterUtils()
        u._secrets_client = mock_client
        u.get_secret("quintoandar", "MY_KEY")
        mock_client.get_secret_value.assert_called_once_with(
            SecretId="quintoandar/MY_KEY"
        )


class TestBaseDBUtilsEmrBranch:
    def setup_method(self):
        reset_emr_dbutils_facade()

    def teardown_method(self):
        reset_emr_dbutils_facade()
        os.environ.pop("SPARK_RUNTIME", None)

    def test_get_dbutils_uses_emr_facade_when_spark_runtime_emr(self, monkeypatch):
        monkeypatch.setenv("SPARK_RUNTIME", "emr")
        assert should_use_emr_cluster_utils() is True
        dbutils = BaseDBUtils().get_dbutils()
        assert dbutils is get_emr_dbutils_facade()
        assert hasattr(dbutils, "secrets")
        assert hasattr(dbutils, "fs")

    def test_get_dbutils_not_emr_does_not_use_singleton_path(self, monkeypatch):
        monkeypatch.setenv("SPARK_RUNTIME", "databricks")
        assert should_use_emr_cluster_utils() is False


class TestAwsEmrFsLsS3:
    def test_s3_ls_prefix(self):
        mock_s3 = MagicMock()
        mock_paginator = MagicMock()
        mock_paginator.paginate.return_value = iter(
            [
                {
                    "CommonPrefixes": [{"Prefix": "raw/x/year=2024/"}],
                    "Contents": [
                        {"Key": "raw/x/_SUCCESS"},
                    ],
                }
            ]
        )
        mock_s3.get_paginator.return_value = mock_paginator

        u = AwsEmrClusterUtils()
        u._s3_client = mock_s3
        entries = u.fs_ls("s3://bucket/raw/x/")
        assert any(e.isDir() and "year=2024" in e.name for e in entries)
        assert any(not e.isDir() and e.name == "_SUCCESS" for e in entries)
