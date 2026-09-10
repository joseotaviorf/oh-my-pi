"""
Unit tests for the reverse_s3 load_to_s3 Spark job.

Covers destination resolution, single-object promote (ACL / ContentType /
staging cleanup / leftover prefix), argparse, and cluster-validation skip.
Spark and S3 are injected or mocked — no real I/O.
"""

import os
import sys
import types
import unittest
from unittest.mock import MagicMock, patch

sys.modules.setdefault("quintoandar_logger", MagicMock())
sys.modules.setdefault("boto3", MagicMock())
sys.modules.setdefault("hierarchical_conf", MagicMock())
sys.modules.setdefault("hierarchical_conf.hierarchical_conf", MagicMock())

_mock_spark_client_cls = MagicMock()
_mock_spark_client_cls.return_value.conn = MagicMock()
_db_clients_stub = types.ModuleType("bietlejuice.clients.db_clients")
_db_clients_stub.SparkClient = _mock_spark_client_cls
sys.modules["bietlejuice.clients.db_clients"] = _db_clients_stub

from dags.people.reverse_s3.spark_jobs import load_to_s3 as job  # noqa: E402

MODULE_UNDER_TEST = "dags.people.reverse_s3.spark_jobs.load_to_s3"


def _s3_client_with_keys(keys_by_prefix):
    """
    Build a boto3-like client whose list_objects_v2 pages return `keys_by_prefix`.

    `keys_by_prefix` maps a prefix to a list of object keys. Unmapped prefixes
    return no contents.
    """

    def paginate(Bucket, Prefix):
        keys = keys_by_prefix.get(Prefix, [])
        yield {"Contents": [{"Key": key} for key in keys]}

    s3_client = MagicMock()
    s3_client.get_paginator.return_value.paginate.side_effect = paginate
    return s3_client


class TestIsSparkPartFile(unittest.TestCase):
    """Regression: Spark part files must be distinguished from _SUCCESS / CRC."""

    def test_accepts_csv_part_file(self):
        self.assertTrue(
            job._is_spark_part_file(
                "_staging/load_to_s3/t-abc/part-00000-uuid-c000.csv"
            )
        )

    def test_accepts_part_file_without_extension(self):
        self.assertTrue(job._is_spark_part_file("_staging/load_to_s3/t-abc/part-00000"))

    def test_rejects_success_marker(self):
        self.assertFalse(job._is_spark_part_file("_staging/load_to_s3/t-abc/_SUCCESS"))

    def test_rejects_crc_checksum(self):
        self.assertFalse(
            job._is_spark_part_file(
                "_staging/load_to_s3/t-abc/.part-00000-uuid-c000.csv.crc"
            )
        )


class TestStagingPrefixForDestination(unittest.TestCase):
    """Staging must live under the destination prefix for prefix-scoped IAM."""

    def test_scopes_staging_under_destination_directory(self):
        with patch(f"{MODULE_UNDER_TEST}.uuid.uuid4") as mock_uuid:
            mock_uuid.return_value.hex = "deadbeef"
            prefix = job._staging_prefix_for_destination(
                "orghealth/base_app_org_health.csv",
                "base_app_org_health",
            )
        self.assertEqual(
            prefix,
            "orghealth/_staging/load_to_s3/base_app_org_health-deadbeef",
        )

    def test_falls_back_to_bucket_root_when_key_has_no_directory(self):
        with patch(f"{MODULE_UNDER_TEST}.uuid.uuid4") as mock_uuid:
            mock_uuid.return_value.hex = "deadbeef"
            prefix = job._staging_prefix_for_destination("export.csv", "t")
        self.assertEqual(prefix, "_staging/load_to_s3/t-deadbeef")


class TestResolveDestination(unittest.TestCase):
    """Prod uses the declared destination; anything else redirects to people_bucket."""

    def test_missing_environment_raises(self):
        with patch.dict(os.environ, {}, clear=True):
            os.environ.pop("ENVIRONMENT", None)
            with self.assertRaises(RuntimeError) as ctx:
                job._resolve_destination("partner-bucket", "orghealth/export.csv")
        self.assertIn("ENVIRONMENT is required", str(ctx.exception))

    def test_blank_environment_raises(self):
        with patch.dict(os.environ, {"ENVIRONMENT": "  "}):
            with self.assertRaises(RuntimeError):
                job._resolve_destination("partner-bucket", "orghealth/export.csv")

    def test_prod_keeps_declared_destination_and_allows_acl(self):
        with patch.dict(os.environ, {"ENVIRONMENT": "prod"}):
            bucket, key, apply_acl = job._resolve_destination(
                "5a-base44-office", "orghealth/base_app_org_health.csv"
            )
        self.assertEqual(bucket, "5a-base44-office")
        self.assertEqual(key, "orghealth/base_app_org_health.csv")
        self.assertTrue(apply_acl)

    @patch(f"{MODULE_UNDER_TEST}.ConfigurationService")
    def test_forno_redirects_to_people_bucket_without_acl(self, mock_conf_cls):
        mock_conf_cls.return_value.get_config.return_value = (
            "people-s3-forno-data-quintoandar-com-br"
        )
        with patch.dict(os.environ, {"ENVIRONMENT": "forno"}):
            bucket, key, apply_acl = job._resolve_destination(
                "5a-base44-office", "orghealth/base_app_org_health.csv"
            )
        self.assertEqual(bucket, "people-s3-forno-data-quintoandar-com-br")
        self.assertEqual(key, "reverse_s3_test/orghealth/base_app_org_health.csv")
        self.assertFalse(apply_acl)
        mock_conf_cls.assert_called_once_with()


class TestPromoteSinglePartFileToKey(unittest.TestCase):
    """Single Spark part file is copied onto the exact destination object key."""

    def test_copy_sets_acl_and_csv_content_type(self):
        staging = "_staging/load_to_s3/t-abc"
        part_key = f"{staging}/part-00000-uuid-c000.csv"
        leftover = "orghealth/export.csv/part-00000"
        s3_client = _s3_client_with_keys(
            {
                f"{staging}/": [
                    f"{staging}/_SUCCESS",
                    part_key,
                    f"{staging}/.part-00000-uuid-c000.csv.crc",
                ],
                "orghealth/export.csv/": [leftover],
            }
        )

        job._promote_single_part_file_to_key(
            bucket="5a-base44-office",
            staging_prefix=staging,
            destination_key="orghealth/export.csv",
            file_format="csv",
            s3_client=s3_client,
            object_acl=job.CROSS_ACCOUNT_OBJECT_ACL,
        )

        s3_client.copy_object.assert_called_once_with(
            Bucket="5a-base44-office",
            CopySource={"Bucket": "5a-base44-office", "Key": part_key},
            Key="orghealth/export.csv",
            ContentType="text/csv",
            MetadataDirective="REPLACE",
            ACL=job.CROSS_ACCOUNT_OBJECT_ACL,
        )
        deleted = {
            obj["Key"]
            for call in s3_client.delete_objects.call_args_list
            for obj in call.kwargs["Delete"]["Objects"]
        }
        self.assertIn(leftover, deleted)

    def test_omits_acl_when_not_provided(self):
        staging = "_staging/load_to_s3/t-abc"
        part_key = f"{staging}/part-00000"
        s3_client = _s3_client_with_keys({f"{staging}/": [part_key]})

        job._promote_single_part_file_to_key(
            bucket="people-s3-forno-data-quintoandar-com-br",
            staging_prefix=staging,
            destination_key="reverse_s3_test/export.csv",
            file_format="csv",
            s3_client=s3_client,
            object_acl=None,
        )

        copy_kwargs = s3_client.copy_object.call_args.kwargs
        self.assertNotIn("ACL", copy_kwargs)
        self.assertEqual(copy_kwargs["ContentType"], "text/csv")

    def test_raises_when_no_part_file(self):
        staging = "_staging/load_to_s3/t-abc"
        s3_client = _s3_client_with_keys({f"{staging}/": [f"{staging}/_SUCCESS"]})

        with self.assertRaises(RuntimeError) as ctx:
            job._promote_single_part_file_to_key(
                bucket="bucket",
                staging_prefix=staging,
                destination_key="export.csv",
                file_format="csv",
                s3_client=s3_client,
            )
        self.assertIn("found=0", str(ctx.exception))
        s3_client.copy_object.assert_not_called()

    def test_raises_when_multiple_part_files(self):
        staging = "_staging/load_to_s3/t-abc"
        s3_client = _s3_client_with_keys(
            {
                f"{staging}/": [
                    f"{staging}/part-00000.csv",
                    f"{staging}/part-00001.csv",
                ]
            }
        )

        with self.assertRaises(RuntimeError) as ctx:
            job._promote_single_part_file_to_key(
                bucket="bucket",
                staging_prefix=staging,
                destination_key="export.csv",
                file_format="csv",
                s3_client=s3_client,
            )
        self.assertIn("found=2", str(ctx.exception))


class TestLoadTableIntoS3(unittest.TestCase):
    """End-to-end export with injected Spark and S3 clients."""

    @patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_prod_export_promotes_with_acl_and_cleans_staging(self):
        spark_session = MagicMock()
        df = MagicMock()
        spark_session.table.return_value = df
        mock_writer = MagicMock()
        staging = "orghealth/_staging/load_to_s3/base_app_org_health-deadbeef"
        part_key = f"{staging}/part-00000-uuid-c000.csv"
        s3_client = _s3_client_with_keys({f"{staging}/": [part_key]})

        with patch.dict(job._WRITERS, {"csv": mock_writer}):
            with patch(f"{MODULE_UNDER_TEST}.uuid.uuid4") as mock_uuid:
                mock_uuid.return_value.hex = "deadbeef"
                job.load_table_into_s3(
                    schema="reverse_s3",
                    table_name="base_app_org_health",
                    bucket="5a-base44-office",
                    key_prefix="orghealth/base_app_org_health.csv",
                    file_format="csv",
                    object_acl=job.CROSS_ACCOUNT_OBJECT_ACL,
                    spark_session=spark_session,
                    s3_client=s3_client,
                )

        spark_session.table.assert_called_once_with("reverse_s3.base_app_org_health")
        mock_writer.assert_called_once_with(df, f"s3://5a-base44-office/{staging}")
        copy_kwargs = s3_client.copy_object.call_args.kwargs
        self.assertEqual(copy_kwargs["ACL"], job.CROSS_ACCOUNT_OBJECT_ACL)
        self.assertEqual(copy_kwargs["Key"], "orghealth/base_app_org_health.csv")
        deleted = {
            obj["Key"]
            for call in s3_client.delete_objects.call_args_list
            for obj in call.kwargs["Delete"]["Objects"]
        }
        self.assertIn(part_key, deleted)

    @patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_export_succeeds_when_staging_delete_is_denied(self):
        spark_session = MagicMock()
        spark_session.table.return_value = MagicMock()
        staging = "orghealth/_staging/load_to_s3/t-deadbeef"
        part_key = f"{staging}/part-00000.csv"
        s3_client = _s3_client_with_keys({f"{staging}/": [part_key]})
        s3_client.delete_objects.side_effect = RuntimeError("AccessDenied")

        with patch.dict(job._WRITERS, {"csv": MagicMock()}):
            with patch(f"{MODULE_UNDER_TEST}.uuid.uuid4") as mock_uuid:
                mock_uuid.return_value.hex = "deadbeef"
                job.load_table_into_s3(
                    schema="reverse_s3",
                    table_name="t",
                    bucket="5a-base44-office",
                    key_prefix="orghealth/base_app_org_health.csv",
                    file_format="csv",
                    object_acl=job.CROSS_ACCOUNT_OBJECT_ACL,
                    spark_session=spark_session,
                    s3_client=s3_client,
                )

        s3_client.copy_object.assert_called_once()
        self.assertEqual(
            s3_client.copy_object.call_args.kwargs["Key"],
            "orghealth/base_app_org_health.csv",
        )

    @patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_staging_is_deleted_when_promote_fails(self):
        spark_session = MagicMock()
        spark_session.table.return_value = MagicMock()
        staging = "_staging/load_to_s3/t-deadbeef"
        part_key = f"{staging}/part-00000.csv"
        s3_client = _s3_client_with_keys({f"{staging}/": [part_key]})
        s3_client.copy_object.side_effect = RuntimeError("copy failed")

        with patch.dict(job._WRITERS, {"csv": MagicMock()}):
            with patch(f"{MODULE_UNDER_TEST}.uuid.uuid4") as mock_uuid:
                mock_uuid.return_value.hex = "deadbeef"
                with self.assertRaises(RuntimeError):
                    job.load_table_into_s3(
                        schema="reverse_s3",
                        table_name="t",
                        bucket="bucket",
                        key_prefix="export.csv",
                        file_format="csv",
                        spark_session=spark_session,
                        s3_client=s3_client,
                    )

        deleted = {
            obj["Key"]
            for call in s3_client.delete_objects.call_args_list
            for obj in call.kwargs["Delete"]["Objects"]
        }
        self.assertIn(part_key, deleted)

    @patch(f"{MODULE_UNDER_TEST}.ConfigurationService")
    def test_forno_does_not_apply_declared_acl(self, mock_conf_cls):
        mock_conf_cls.return_value.get_config.return_value = (
            "people-s3-forno-data-quintoandar-com-br"
        )
        spark_session = MagicMock()
        spark_session.table.return_value = MagicMock()
        staging = (
            "reverse_s3_test/orghealth/_staging/load_to_s3/base_app_org_health-deadbeef"
        )
        part_key = f"{staging}/part-00000.csv"
        s3_client = _s3_client_with_keys({f"{staging}/": [part_key]})

        with patch.dict(job._WRITERS, {"csv": MagicMock()}):
            with patch.dict(os.environ, {"ENVIRONMENT": "forno"}):
                with patch(f"{MODULE_UNDER_TEST}.uuid.uuid4") as mock_uuid:
                    mock_uuid.return_value.hex = "deadbeef"
                    job.load_table_into_s3(
                        schema="reverse_s3",
                        table_name="base_app_org_health",
                        bucket="5a-base44-office",
                        key_prefix="orghealth/base_app_org_health.csv",
                        file_format="csv",
                        object_acl=job.CROSS_ACCOUNT_OBJECT_ACL,
                        spark_session=spark_session,
                        s3_client=s3_client,
                    )

        copy_kwargs = s3_client.copy_object.call_args.kwargs
        self.assertNotIn("ACL", copy_kwargs)
        self.assertEqual(
            copy_kwargs["Key"],
            "reverse_s3_test/orghealth/base_app_org_health.csv",
        )


class TestParseArguments(unittest.TestCase):
    """Argparse contract: format choices and optional ACL."""

    def test_parses_optional_acl(self):
        argv = [
            "load_to_s3.py",
            "reverse_s3",
            "base_app_org_health",
            "5a-base44-office",
            "orghealth/base_app_org_health.csv",
            "csv",
            job.CROSS_ACCOUNT_OBJECT_ACL,
        ]
        with patch("sys.argv", argv):
            args = job.parse_arguments()
        self.assertEqual(args["file_format"], "csv")
        self.assertEqual(args["object_acl"], job.CROSS_ACCOUNT_OBJECT_ACL)

    def test_acl_is_optional(self):
        argv = [
            "load_to_s3.py",
            "reverse_s3",
            "internal_export",
            "people-s3-data-quintoandar-com-br",
            "exports/internal.csv",
            "CSV",
        ]
        with patch("sys.argv", argv):
            args = job.parse_arguments()
        self.assertEqual(args["file_format"], "csv")
        self.assertIsNone(args["object_acl"])
        self.assertIsNone(args["partition_columns"])

    def test_parses_partition_columns_with_none_acl_sentinel(self):
        """EMR spark-submit drops empty argv, so the ACL slot carries 'None'."""
        argv = [
            "load_to_s3.py",
            "reverse_s3",
            "comp_employee_roster",
            "quintoandar-inbound-wikpng8fowgxahxxccrd8j6ogxydnuse2a-s3alias",
            "quintoandar/comp_employee_roster",
            "parquet",
            job.CLI_NONE,
            "year,month,day",
        ]
        with patch("sys.argv", argv):
            args = job.parse_arguments()
        self.assertEqual(args["file_format"], "parquet")
        self.assertIsNone(args["object_acl"])
        self.assertEqual(args["partition_columns"], ["year", "month", "day"])

    def test_parses_single_partition_column(self):
        """A lone column has no comma; it must still parse as a partition."""
        argv = [
            "load_to_s3.py",
            "reverse_s3",
            "comp_employee_roster",
            "partner-bucket",
            "quintoandar/comp_employee_roster",
            "parquet",
            job.CLI_NONE,
            "day",
        ]
        with patch("sys.argv", argv):
            args = job.parse_arguments()
        self.assertIsNone(args["object_acl"])
        self.assertEqual(args["partition_columns"], ["day"])


class TestPartitionedParquetExport(unittest.TestCase):
    """Partitioned exports write directly without staging promote."""

    @patch(f"{MODULE_UNDER_TEST}._write_partitioned_parquet")
    def test_writes_partitioned_dataset_without_promote(self, mock_write):
        spark_session = MagicMock()
        spark_session.table.return_value = MagicMock()
        s3_client = MagicMock()

        with patch.dict(os.environ, {"ENVIRONMENT": "prod"}):
            job.load_table_into_s3(
                schema="reverse_s3",
                table_name="comp_employee_roster",
                bucket="quintoandar-inbound-wikpng8fowgxahxxccrd8j6ogxydnuse2a-s3alias",
                key_prefix="quintoandar/comp_employee_roster",
                file_format="parquet",
                partition_columns=["year", "month", "day"],
                spark_session=spark_session,
                s3_client=s3_client,
            )

        mock_write.assert_called_once()
        destination_uri = mock_write.call_args.args[1]
        self.assertEqual(
            destination_uri,
            "s3a://quintoandar-inbound-wikpng8fowgxahxxccrd8j6ogxydnuse2a-s3alias/"
            "quintoandar/comp_employee_roster/",
        )
        s3_client.copy_object.assert_not_called()
        s3_client.delete_objects.assert_not_called()

    def test_rejects_partition_columns_for_non_parquet_format(self):
        with patch.dict(os.environ, {"ENVIRONMENT": "prod"}):
            with self.assertRaises(ValueError) as ctx:
                job.load_table_into_s3(
                    schema="reverse_s3",
                    table_name="comp_employee_roster",
                    bucket="partner-bucket",
                    key_prefix="quintoandar/comp_employee_roster",
                    file_format="csv",
                    partition_columns=["year", "month", "day"],
                    spark_session=MagicMock(),
                    s3_client=MagicMock(),
                )
        self.assertIn("requires file_format parquet", str(ctx.exception))


class TestWritePartitionedParquet(unittest.TestCase):
    """The writer itself: dynamic overwrite, ZSTD, partitionBy."""

    def test_forces_dynamic_partition_overwrite(self):
        """Static mode would delete the whole prefix, dropping prior days."""
        df = MagicMock()

        job._write_partitioned_parquet(df, "s3a://bucket/prefix/", ["year", "month"])

        df.sparkSession.conf.set.assert_called_once_with(
            "spark.sql.sources.partitionOverwriteMode", "dynamic"
        )

    def test_writes_zstd_parquet_partitioned_by_columns(self):
        df = MagicMock()

        job._write_partitioned_parquet(
            df, "s3a://bucket/prefix/", ["year", "month", "day"]
        )

        writer = df.write.mode.return_value
        df.write.mode.assert_called_once_with("overwrite")
        writer.option.assert_called_once_with("compression", "zstd")
        writer.option.return_value.partitionBy.assert_called_once_with(
            "year", "month", "day"
        )
        writer.option.return_value.partitionBy.return_value.parquet.assert_called_once_with(
            "s3a://bucket/prefix/"
        )


class TestRun(unittest.TestCase):
    """Cluster-validation runs must not write to S3."""

    @patch(f"{MODULE_UNDER_TEST}.load_table_into_s3")
    @patch(f"{MODULE_UNDER_TEST}.is_validation_run", return_value=True)
    def test_skips_export_in_validation_mode(self, _mock_is_validation, mock_load):
        job.run(
            {
                "schema": "reverse_s3",
                "table_name": "base_app_org_health",
                "bucket": "5a-base44-office",
                "key_prefix": "orghealth/base_app_org_health.csv",
                "file_format": "csv",
                "object_acl": job.CROSS_ACCOUNT_OBJECT_ACL,
                "target_database_name": "validation_db",
                "target_table_name": "validation_table",
            }
        )
        mock_load.assert_not_called()

    @patch(f"{MODULE_UNDER_TEST}.load_table_into_s3")
    @patch(f"{MODULE_UNDER_TEST}.is_validation_run", return_value=False)
    def test_exports_when_not_validation_run(self, _mock_is_validation, mock_load):
        job.run(
            {
                "schema": "reverse_s3",
                "table_name": "base_app_org_health",
                "bucket": "5a-base44-office",
                "key_prefix": "orghealth/base_app_org_health.csv",
                "file_format": "csv",
                "object_acl": job.CROSS_ACCOUNT_OBJECT_ACL,
                "target_database_name": None,
                "target_table_name": None,
            }
        )
        mock_load.assert_called_once_with(
            schema="reverse_s3",
            table_name="base_app_org_health",
            bucket="5a-base44-office",
            key_prefix="orghealth/base_app_org_health.csv",
            file_format="csv",
            object_acl=job.CROSS_ACCOUNT_OBJECT_ACL,
            partition_columns=None,
        )


if __name__ == "__main__":
    unittest.main()
