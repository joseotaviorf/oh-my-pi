import os
import time
from datetime import datetime, timezone
from unittest.mock import MagicMock

import boto3
from moto import mock_aws as mock_s3
from pyspark.sql.types import StructType, _infer_schema

from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.spark.cluster_utils.aws_emr_cluster_utils import (
    AwsEmrClusterUtils,
    _maybe_b64decode,
    _parse_s3_uri,
    _secrets_manager_region,
)
from bietlejuice.base.spark.cluster_utils.factory import (
    get_emr_dbutils_facade,
    reset_emr_dbutils_facade,
    should_use_emr_cluster_utils,
)
from bietlejuice.base.spark.cluster_utils.fs_list_entry import FsListEntry


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

    def test_get_secret_decodes_base64_json(self, monkeypatch):
        monkeypatch.delenv("BIETL_SECRETS_MANAGER_SECRET_ID_TEMPLATE", raising=False)
        mock_client = MagicMock()
        mock_client.get_secret_value.return_value = {
            "SecretString": "eyJ0b2tlbiI6IngifQ=="
        }

        u = AwsEmrClusterUtils()
        u._secrets_client = mock_client
        assert u.get_secret("quintoandar", "CLOUDZERO_API_TOKEN") == '{"token":"x"}'

    def test_get_secret_leaves_plain_json_unchanged(self, monkeypatch):
        monkeypatch.delenv("BIETL_SECRETS_MANAGER_SECRET_ID_TEMPLATE", raising=False)
        mock_client = MagicMock()
        mock_client.get_secret_value.return_value = {"SecretString": '{"a": 1}'}

        u = AwsEmrClusterUtils()
        u._secrets_client = mock_client
        assert u.get_secret("quintoandar", "MY_KEY") == '{"a": 1}'

    def test_get_secret_decodes_base64_grafana_token(self, monkeypatch):
        monkeypatch.delenv("BIETL_SECRETS_MANAGER_SECRET_ID_TEMPLATE", raising=False)
        mock_client = MagicMock()
        mock_client.get_secret_value.return_value = {
            "SecretString": "Z2xzYV90ZXN0X3Rva2VuX25vdF9yZWFs"
        }

        u = AwsEmrClusterUtils()
        u._secrets_client = mock_client
        assert (
            u.get_secret("quintoandar", "GRAFANA_API_TOKEN")
            == "glsa_test_token_not_real"
        )

    def test_get_secret_decodes_base64_secret_binary(self, monkeypatch):
        monkeypatch.delenv("BIETL_SECRETS_MANAGER_SECRET_ID_TEMPLATE", raising=False)
        mock_client = MagicMock()
        mock_client.get_secret_value.return_value = {
            "SecretBinary": b"eyJ0b2tlbiI6IngifQ=="
        }

        u = AwsEmrClusterUtils()
        u._secrets_client = mock_client
        assert u.get_secret("quintoandar", "CLOUDZERO_API_TOKEN") == '{"token":"x"}'


class TestMaybeB64Decode:
    def test_decodes_base64_json(self):
        assert _maybe_b64decode("eyJ0b2tlbiI6IngifQ==") == '{"token":"x"}'

    def test_leaves_plain_json_unchanged(self):
        assert _maybe_b64decode('{"a": 1}') == '{"a": 1}'

    def test_decodes_base64_grafana_token(self):
        assert (
            _maybe_b64decode("Z2xzYV90ZXN0X3Rva2VuX25vdF9yZWFs")
            == "glsa_test_token_not_real"
        )

    def test_empty_string_unchanged(self):
        assert _maybe_b64decode("") == ""

    def test_invalid_base64_alphabet_unchanged(self):
        assert _maybe_b64decode("not-valid-base64!") == "not-valid-base64!"

    def test_strips_whitespace_before_decode(self):
        assert _maybe_b64decode(" eyJ0b2tlbiI6IngifQ== \n") == '{"token":"x"}'


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
        last_modified = datetime(2026, 8, 1, tzinfo=timezone.utc)
        dir_child_modified = datetime(2026, 7, 15, tzinfo=timezone.utc)
        mock_s3_client = MagicMock()
        mock_paginator = MagicMock()

        def paginate(**kwargs):
            if kwargs.get("Delimiter") == "/":
                return iter(
                    [
                        {
                            "CommonPrefixes": [{"Prefix": "raw/x/year=2024/"}],
                            "Contents": [
                                {
                                    "Key": "raw/x/_SUCCESS",
                                    "Size": 12,
                                    "LastModified": last_modified,
                                },
                            ],
                        }
                    ]
                )
            return iter(
                [
                    {
                        "Contents": [
                            {
                                "Key": "raw/x/year=2024/part.parquet",
                                "Size": 4,
                                "LastModified": dir_child_modified,
                            },
                        ],
                    }
                ]
            )

        mock_paginator.paginate.side_effect = paginate
        mock_s3_client.get_paginator.return_value = mock_paginator

        u = AwsEmrClusterUtils()
        u._s3_client = mock_s3_client
        entries = u.fs_ls("s3://bucket/raw/x/")
        assert any(e.isDir() and "year=2024" in e.name for e in entries)
        assert any(not e.isDir() and e.name == "_SUCCESS" for e in entries)

        success = next(e for e in entries if e.name == "_SUCCESS")
        assert success.size == 12
        assert success.modificationTime == int(last_modified.timestamp() * 1000)

        directory = next(e for e in entries if e.isDir() and "year=2024" in e.name)
        assert directory.size == 0
        assert directory.modificationTime == int(dir_child_modified.timestamp() * 1000)

    @mock_s3
    def test_s3_ls_modification_time_hightouch_filter(self):
        bucket = "hightouch-logs-test"
        prefix = "sync_id=1/"
        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket=bucket)
        s3.put_object(Bucket=bucket, Key=f"{prefix}a.parquet", Body=b"aaa")
        s3.put_object(Bucket=bucket, Key=f"{prefix}b.parquet", Body=b"bbb")

        now_ms = int(time.time() * 1000)
        start_ts = now_ms - 3_600_000
        end_ts = now_ms + 3_600_000

        entries = AwsEmrClusterUtils().fs_ls(f"s3://{bucket}/{prefix}")
        matched = [e.path for e in entries if start_ts <= e.modificationTime < end_ts]
        assert sorted(matched) == [
            f"s3://{bucket}/{prefix}a.parquet",
            f"s3://{bucket}/{prefix}b.parquet",
        ]

        past_start = int(datetime(2020, 1, 1, tzinfo=timezone.utc).timestamp() * 1000)
        past_end = int(datetime(2020, 1, 2, tzinfo=timezone.utc).timestamp() * 1000)
        assert [
            e.path for e in entries if past_start <= e.modificationTime < past_end
        ] == []

    @mock_s3
    def test_s3_ls_directory_modification_time_hightouch_sync_run_filter(self):
        # load_hightouch_sync_{runs,changelog} keep sync_run_id= dirs by modificationTime.
        bucket = "hightouch-logs-dirs-test"
        sync_prefix = "sync_id=1/"
        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket=bucket)
        s3.put_object(
            Bucket=bucket, Key=f"{sync_prefix}sync_run_id=10/part.parquet", Body=b"aaa"
        )
        s3.put_object(
            Bucket=bucket, Key=f"{sync_prefix}sync_run_id=11/part.parquet", Body=b"bbb"
        )

        now_ms = int(time.time() * 1000)
        start_ts = now_ms - 3_600_000
        end_ts = now_ms + 3_600_000

        entries = AwsEmrClusterUtils().fs_ls(f"s3://{bucket}/{sync_prefix}")
        dirs = [e for e in entries if e.isDir()]
        assert {e.name for e in dirs} == {"sync_run_id=10/", "sync_run_id=11/"}
        assert all(e.modificationTime > 0 for e in dirs)

        matched = [e.path for e in dirs if start_ts <= e.modificationTime < end_ts]
        assert sorted(matched) == [
            f"s3://{bucket}/{sync_prefix}sync_run_id=10/",
            f"s3://{bucket}/{sync_prefix}sync_run_id=11/",
        ]

        past_start = int(datetime(2020, 1, 1, tzinfo=timezone.utc).timestamp() * 1000)
        past_end = int(datetime(2020, 1, 2, tzinfo=timezone.utc).timestamp() * 1000)
        assert [
            e.path for e in dirs if past_start <= e.modificationTime < past_end
        ] == []


class TestFsListEntrySchema:
    def test_fields_match_databricks_fileinfo(self):
        assert FsListEntry._fields == ("path", "name", "size", "modificationTime")

    def test_infer_schema_from_namedtuple(self):
        schema = _infer_schema(FsListEntry("s3://b/k", "k", 3, 1))
        assert isinstance(schema, StructType)
        assert schema.fieldNames() == ["path", "name", "size", "modificationTime"]


class TestAwsEmrFsLsLocal:
    def test_local_ls_dir_and_file(self, tmp_path):
        content = b"hello-emr"
        (tmp_path / "file.txt").write_bytes(content)
        (tmp_path / "subdir").mkdir()

        entries = AwsEmrClusterUtils().fs_ls(str(tmp_path))
        by_name = {e.name: e for e in entries}

        directory = by_name["subdir/"]
        assert directory.name.endswith("/")
        assert directory.isDir() is True
        assert directory.size == 0

        file_entry = by_name["file.txt"]
        assert file_entry.isDir() is False
        assert file_entry.size == len(content)
        assert file_entry.modificationTime > 0
