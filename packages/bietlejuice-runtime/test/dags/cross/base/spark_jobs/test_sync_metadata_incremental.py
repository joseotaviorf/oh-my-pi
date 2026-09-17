"""Unit tests for the incremental partition sync mode of sync_metadata."""

import sys
from unittest.mock import MagicMock, patch

import pytest

sys.modules["quintoandar_logger"] = MagicMock()
sys.modules["hive_metastore_client"] = MagicMock()
sys.modules["hive_metastore_client.builders"] = MagicMock()
sys.modules["pyspark"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.types"] = MagicMock()
sys.modules["bietlejuice.base.db"] = MagicMock()
sys.modules["bietlejuice.base.db.database_enum"] = MagicMock()
sys.modules["bietlejuice.base.db.dw_metastore_mapping"] = MagicMock()
sys.modules["bietlejuice.base.hive"] = MagicMock()
sys.modules["bietlejuice.base.service.service_enum"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.base.spark.base_spark"] = MagicMock()
sys.modules["bietlejuice.base.spark.runtime_detector"] = MagicMock()
sys.modules["bietlejuice.base.spark.spark_session_factory"] = MagicMock()
sys.modules["bietlejuice.base.spark.spark_metastore_helper"] = MagicMock()
sys.modules["bietlejuice.loaders.hive_metastore_loader"] = MagicMock()
sys.modules["bietlejuice.metadata_propagator_pipeline"] = MagicMock()
sys.modules["bietlejuice.metadata_propagator_pipeline.lineage_tags_pipeline"] = (
    MagicMock()
)
sys.modules["bietlejuice.metadata_propagator_pipeline.raw_lineage_pipeline"] = (
    MagicMock()
)
sys.modules["bietlejuice.services.dag_metadata_service"] = MagicMock()
sys.modules["bietlejuice.services.metastore_services.hive_metastore_service"] = (
    MagicMock()
)
sys.modules["bietlejuice.services.metastore_services.hive_sync_partition_utils"] = (
    MagicMock()
)

from dags.cross.base.spark_jobs import sync_metadata  # noqa: E402

BASE_ARGV = [
    "sync_metadata",
    "test-bucket",
    "raw",
    "emlio",
    "--metadata-type",
    "tags",
    "emlio",
    "--bypass-propagate",
]


class TestSyncMetastoreTablePartitionsIncremental:
    def test_adds_given_partitions_without_enumeration(self):
        partition_values = [["2026", "7", "3"]]
        with (
            patch.object(sync_metadata, "SparkMetastoreHelper") as helper_cls,
            patch.object(sync_metadata, "HiveMetastoreClient") as client_cls,
            patch.object(sync_metadata, "HiveMetastoreService") as service_cls,
            patch.object(sync_metadata, "PartitionBuilder") as builder_cls,
            patch.object(
                sync_metadata, "_get_hive_metastore_host", return_value="hive-host"
            ),
        ):
            helper = helper_cls.return_value
            helper.spark_database_name = "datalake_emlio_raw"

            sync_metadata.sync_metastore_table_partitions_incremental(
                "test-bucket", "raw", "emlio", "emlio_logs", partition_values
            )

            helper_cls.assert_called_once_with(
                "test-bucket",
                "raw",
                "emlio",
                "emlio_logs",
                False,
                transformation_grade=None,
            )
            helper.validate_table_arguments.assert_called_once()
            # No partition enumeration: the full-reconcile entry point is untouched.
            helper.get_all_tables_metadata.assert_not_called()
            # Values are wrapped in thrift Partition objects, same as the full path.
            builder_cls.assert_called_once_with(
                values=["2026", "7", "3"],
                db_name="datalake_emlio_raw",
                table_name="emlio_logs",
            )
            client_cls.assert_called_once_with("hive-host")
            service_cls.return_value.add_partitions_to_table.assert_called_once_with(
                "datalake_emlio_raw",
                "emlio_logs",
                [builder_cls.return_value.build.return_value],
            )


class TestMainDispatch:
    def _run_main(self, extra_argv):
        with (
            patch.object(sync_metadata, "sync_metastore_table_structure") as structure,
            patch.object(sync_metadata, "sync_metastore_table_partitions") as full,
            patch.object(
                sync_metadata, "sync_metastore_table_partitions_incremental"
            ) as incremental,
            patch.object(sync_metadata, "BaseDBUtils") as dbutils_cls,
            patch.object(sync_metadata.RuntimeDetector, "is_emr", return_value=False),
            patch.object(sys, "argv", BASE_ARGV + extra_argv),
        ):
            dbutils_cls.return_value.get_dbutils.return_value = MagicMock()
            sync_metadata.main()
            return structure, full, incremental

    def test_partition_values_schedules_incremental_not_full(self):
        structure, full, incremental = self._run_main(
            ["--table-name", "emlio_logs", "--partition-values", '[["2026","7","3"]]']
        )

        structure.assert_called_once_with(
            "test-bucket", "raw", "emlio", "emlio_logs", False, None
        )
        incremental.assert_called_once_with(
            "test-bucket", "raw", "emlio", "emlio_logs", [["2026", "7", "3"]], None
        )
        full.assert_not_called()

    def test_no_partition_values_schedules_full_reconciliation(self):
        structure, full, incremental = self._run_main(["--table-name", "emlio_logs"])

        structure.assert_called_once()
        full.assert_called_once_with(
            "test-bucket", "raw", "emlio", "emlio_logs", False, None
        )
        incremental.assert_not_called()

    def test_transformation_grade_reaches_hive_sync_jobs(self):
        structure, full, incremental = self._run_main(
            ["--table-name", "emlio_logs", "--transformation-grade", "curated"]
        )

        structure.assert_called_once_with(
            "test-bucket", "raw", "emlio", "emlio_logs", False, "curated"
        )
        full.assert_called_once_with(
            "test-bucket", "raw", "emlio", "emlio_logs", False, "curated"
        )
        incremental.assert_not_called()

    def test_empty_partition_values_schedules_no_partition_job(self):
        structure, full, incremental = self._run_main(
            ["--table-name", "emlio_logs", "--partition-values", "[]"]
        )

        structure.assert_called_once()
        full.assert_not_called()
        incremental.assert_not_called()

    def test_all_tables_with_partition_values_raises(self):
        with pytest.raises(ValueError, match="single-table mode"):
            self._run_main(["--all-tables", "--partition-values", '[["2026","7","3"]]'])


class TestSyncMetadataEmptyCliArgs:
    def test_gsheets_argv_without_metadata_type(self):
        argv = [
            "prod-datalake",
            "clean",
            "gsheets_agents",
            "--table-name",
            "agents",
            "gsheets_agents",
            "--bypass-propagate",
        ]
        args = sync_metadata.build_arg_parser().parse_args(argv)
        assert args.metadata_type_value is None
        assert args.relative_file_path == "gsheets_agents"
        assert args.bypass_propagate is True

    def test_metadata_type_flag_sets_relative_file_path(self):
        argv = [
            "prod-datalake",
            "raw",
            "emlio",
            "--table-name",
            "emlio_logs",
            "--metadata-type",
            "tags",
            "emlio",
        ]
        args = sync_metadata.build_arg_parser().parse_args(argv)
        assert args.metadata_type_value == "tags"
        assert args.relative_file_path == "emlio"
