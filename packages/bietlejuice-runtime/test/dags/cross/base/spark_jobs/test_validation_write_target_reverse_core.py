"""
Unit tests verifying validation write-target redirection for:
  - load_delta_table.py  (reverse/access workflow)
  - BaseCoreModelSparkJob  (all core_model jobs via shared base)
  - CoreBrokersBaseSparkJob  (brokers sub-hierarchy with its own pipeline runner)

Each test class verifies two concerns:
  1. Argparse correctly accepts --target-database-name / --target-table-name flags.
  2. When both flags are supplied, the DataFrameDeltaTableLoaderPipeline (or
     DeltaTableLoaderPipeline) is constructed with the redirected database,
     table, and S3 location rather than the production values.
"""

import importlib.util
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

# ---------------------------------------------------------------------------
# Repository root (worktree) resolved relative to this test file
# test file is at:
#   packages/bietlejuice-runtime/test/dags/cross/base/spark_jobs/
# repo root is 7 levels up:
#   spark_jobs -> base -> cross -> dags -> test -> bietlejuice-runtime -> packages -> <root>
# ---------------------------------------------------------------------------
_REPO_ROOT = Path(__file__).parents[7]
_SPARK_JOBS = _REPO_ROOT / "dags" / "cross" / "base" / "spark_jobs"
_BASE_CORE_JOB_PATH = (
    _REPO_ROOT
    / "packages"
    / "bietlejuice-runtime"
    / "src"
    / "bietlejuice"
    / "base"
    / "spark"
    / "base_core_model_spark_job.py"
)
_BROKERS_BASE_PATH = (
    _REPO_ROOT
    / "packages"
    / "bietlejuice-runtime"
    / "src"
    / "bietlejuice"
    / "base"
    / "core_models"
    / "core_brokers_base.py"
)

# ---------------------------------------------------------------------------
# Heavy Spark/Databricks stubs — installed before any lazy imports
# ---------------------------------------------------------------------------
_STUBS = [
    "quintoandar_logger",
    "pyspark",
    "pyspark.sql",
    "pyspark.sql.session",
    "pyspark.sql.functions",
    "pyspark.sql.context",
    "pyspark.context",
    "bietlejuice",
    "bietlejuice.base",
    "bietlejuice.base.spark",
    "bietlejuice.base.spark.base_spark",
    "bietlejuice.base.spark.runtime_detector",
    "bietlejuice.base.spark.spark_session_factory",
    "bietlejuice.base.databricks",
    "bietlejuice.base.databricks.row_filter",
    "bietlejuice.base.databricks.table_privileges",
    "bietlejuice.base.service",
    "bietlejuice.base.service.dag_packages_path_service",
    "bietlejuice.base.spark.spark_metastore_helper",
    "bietlejuice.base.validation",
    "bietlejuice.base.validation.target_resolver",
    "bietlejuice.pipeline",
    "bietlejuice.pipeline.delta_table_loader_pipeline",
    "bietlejuice.pipeline.dataframe_delta_table_loader_pipeline",
    "bietlejuice.base.pipeline",
    "bietlejuice.base.pipeline.layer_enum",
    "bietlejuice.base.notification",
    "bietlejuice.base.notification.gchat_webhooks_enum",
    "bietlejuice.services",
    "bietlejuice.services.configuration_service",
    "bietlejuice.services.messaging_services",
    "bietlejuice.services.messaging_services.gchat_service",
    "bietlejuice.services.messaging_services.message",
    "bietlejuice.base.core_models",
    "bietlejuice.base.core_models.helpers",
    "bietlejuice.base.core_models.helpers.schema_validator",
]

for _mod in _STUBS:
    sys.modules.setdefault(_mod, MagicMock())

# Make LayerEnum.CORE.value resolve to the string "core" so path assertions work.
_layer_enum_stub = sys.modules["bietlejuice.base.pipeline.layer_enum"]
_layer_enum_stub.LayerEnum = MagicMock()
_layer_enum_stub.LayerEnum.CORE.value = "core"
sys.modules["bietlejuice.base.pipeline"].LayerEnum = _layer_enum_stub.LayerEnum

# Make the pipeline stub a proper MagicMock with a callable class interface
_pipeline_stub_mod = sys.modules[
    "bietlejuice.pipeline.dataframe_delta_table_loader_pipeline"
]
_pipeline_stub_mod.DataFrameDeltaTableLoaderPipeline = MagicMock()


# ---------------------------------------------------------------------------
# Load the production modules under unique names and register in sys.modules
# so that patch() can locate them.
# ---------------------------------------------------------------------------


def _load_and_register(path: Path, sys_name: str):
    """Load a Python source file as a named module and register in sys.modules."""
    spec = importlib.util.spec_from_file_location(sys_name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[sys_name] = mod
    spec.loader.exec_module(mod)
    return mod


# Load BaseCoreModelSparkJob; it only depends on the stubs above.
_base_job_mod = _load_and_register(
    _BASE_CORE_JOB_PATH, "_test_base_core_model_spark_job"
)

# Register it so that core_brokers_base.py can ``from bietlejuice.base.spark.base_core_model_spark_job import``
sys.modules["bietlejuice.base.spark.base_core_model_spark_job"] = _base_job_mod  # type: ignore[assignment]

# Now load CoreBrokersBaseSparkJob (its import of BaseCoreModelSparkJob will resolve)
_brokers_base_mod = _load_and_register(_BROKERS_BASE_PATH, "_test_core_brokers_base")

# ---------------------------------------------------------------------------
# Module-level import of load_delta_table
# ---------------------------------------------------------------------------
from dags.cross.base.spark_jobs.load_delta_table import (  # noqa: E402
    parse_arguments as _parse_delta,
)

# ---------------------------------------------------------------------------
# Convenience references
# ---------------------------------------------------------------------------
_BaseCoreModelSparkJob = _base_job_mod.BaseCoreModelSparkJob
_CoreBrokersBaseSparkJob = _brokers_base_mod.CoreBrokersBaseSparkJob

# ---------------------------------------------------------------------------
# Helpers / shared arg builders
# ---------------------------------------------------------------------------

_DELTA_TABLE_POSITIONAL_ARGS = [
    "test_env",  # env
    "my-bucket",  # bucket
    "clean",  # layer
    "payments",  # database_base_name
    "enrich_payments",  # relative_query_path
    "charge",  # table_name
    "[]",  # partitions
    "2026-05-01",  # execution_date
    "full",  # extraction_type
    "{}",  # spark_session_configs
    "{}",  # additional_query_template_params
    '["id"]',  # merge_on
    "null",  # when_not_matched_insert_condition
    "null",  # when_matched_update_condition
    "null",  # when_matched_delete_condition
    "null",  # when_not_matched_by_source_delete_condition
    "{}",  # when_matched_operation
    "{}",  # when_not_matched_operation
]

_CORE_MODEL_POSITIONAL_ARGS = [
    "test_env",  # environment
    "my-bucket",  # bucket
    "core_house",  # dag_name
    "core_house",  # schema
    "house",  # table_name
]


# ---------------------------------------------------------------------------
# Part A: load_delta_table.py argparse
# ---------------------------------------------------------------------------


class TestLoadDeltaTableArgparse:
    """Verify parse_arguments() in load_delta_table.py accepts validation flags."""

    def _parse(self, extra_args=None):
        argv = ["prog"] + _DELTA_TABLE_POSITIONAL_ARGS + (extra_args or [])
        with patch("sys.argv", argv):
            return _parse_delta()

    def test_flags_absent_default_to_none(self):
        # Act
        args = self._parse()
        # Assert
        assert args.target_database_name is None
        assert args.target_table_name is None

    def test_flags_accepted_and_parsed(self):
        # Arrange
        extra_args = [
            "--target-database-name",
            "cluster_validation",
            "--target-table-name",
            "datalake_payments_clean___charge",
        ]
        # Act
        args = self._parse(extra_args)
        # Assert
        assert args.target_database_name == "cluster_validation"
        assert args.target_table_name == "datalake_payments_clean___charge"

    def test_empty_string_treated_as_none(self):
        """The lambda ``type=lambda arg: None if not arg else arg`` maps '' to None."""
        # Act
        args = self._parse(["--target-database-name", "", "--target-table-name", ""])
        # Assert
        assert args.target_database_name is None
        assert args.target_table_name is None


# ---------------------------------------------------------------------------
# Part B: BaseCoreModelSparkJob.parse_args()
# ---------------------------------------------------------------------------


class TestBaseCoreModelSparkJobArgparse:
    """Verify parse_args() in BaseCoreModelSparkJob accepts validation flags."""

    def _make_job(self):
        class _ConcreteJob(_BaseCoreModelSparkJob):
            def create_core_model(self, spark, args):
                pass

        return _ConcreteJob("test_job")

    def _parse(self, extra_args=None):
        job = self._make_job()
        argv = ["prog"] + _CORE_MODEL_POSITIONAL_ARGS + (extra_args or [])
        with patch("sys.argv", argv):
            return job.parse_args()

    def test_flags_absent_default_to_none(self):
        # Act
        args = self._parse()
        # Assert
        assert args.target_database_name is None
        assert args.target_table_name is None

    def test_flags_accepted_and_parsed(self):
        # Arrange
        extra_args = [
            "--target-database-name",
            "cluster_validation",
            "--target-table-name",
            "core_house___house",
        ]
        # Act
        args = self._parse(extra_args)
        # Assert
        assert args.target_database_name == "cluster_validation"
        assert args.target_table_name == "core_house___house"

    def test_empty_string_treated_as_none(self):
        # Act
        args = self._parse(["--target-database-name", "", "--target-table-name", ""])
        # Assert
        assert args.target_database_name is None
        assert args.target_table_name is None


# ---------------------------------------------------------------------------
# Part C: BaseCoreModelSparkJob.run_pipeline() write redirection
#
# The lazy import inside run_pipeline() does:
#   from bietlejuice.base.validation.target_resolver import validation_database_location
# Since bietlejuice.base.validation.target_resolver is a MagicMock stub we
# configure its .validation_database_location attribute directly.
# Similarly DataFrameDeltaTableLoaderPipeline is imported at module top-level
# of base_core_model_spark_job; we swap it via patch on the loaded module.
# ---------------------------------------------------------------------------


class TestBaseCoreModelSparkJobWriteRedirection:
    """Verify run_pipeline() redirects writes when validation flags are set."""

    def _make_args(self, target_db=None, target_table=None):
        args = MagicMock()
        args.bucket = "my-bucket"
        args.schema = "core_house"
        args.table_name = "house"
        args.partitions = None
        args.target_database_name = target_db
        args.target_table_name = target_table
        return args

    def _make_job(self):
        class _ConcreteJob(_BaseCoreModelSparkJob):
            def create_core_model(self, spark, args):
                pass

        job = _ConcreteJob("test_job")

        # Return None for all config keys except merge_on (which must be a list),
        # and overwrite_with_null (which must evaluate to False).
        def _get_config_side_effect(key, required=True, default=None):
            if key == "merge_on":
                return ["id"]
            return default

        job.get_config = MagicMock(side_effect=_get_config_side_effect)
        job.setup_table_privileges = MagicMock(return_value=MagicMock())
        return job

    def test_prod_writes_to_prod_schema(self):
        # Arrange
        pipeline_cls = MagicMock()
        args = self._make_args()
        job = self._make_job()
        dataframe = MagicMock()
        dataframe.columns = ["id", "name"]
        spark = MagicMock()
        spark.table.side_effect = Exception("table does not exist")
        # Act
        with patch.object(
            _base_job_mod, "DataFrameDeltaTableLoaderPipeline", pipeline_cls
        ):
            job.run_pipeline(dataframe, args, spark)
        # Assert
        call_kwargs = pipeline_cls.call_args.kwargs
        assert call_kwargs["database_name"] == "core_house"
        assert call_kwargs["table_name"] == "house"
        assert "core/core_house" in call_kwargs["database_location"]
        assert call_kwargs["target_database_name"] == "core_house"

    def test_validation_redirects_to_cluster_validation(self):
        # Arrange
        pipeline_cls = MagicMock()
        args = self._make_args(
            target_db="cluster_validation",
            target_table="core_house___house",
        )

        class _ConcreteJob(_BaseCoreModelSparkJob):
            def create_core_model(self, spark, args):
                pass

        job = _ConcreteJob("test_job")

        def _get_config_side_effect(key, required=True, default=None):
            if key == "merge_on":
                return ["id"]
            return default

        job.get_config = MagicMock(side_effect=_get_config_side_effect)
        job.setup_table_privileges = MagicMock(return_value=MagicMock())

        dataframe = MagicMock()
        dataframe.columns = ["id", "name"]
        spark = MagicMock()
        spark.table.side_effect = Exception("table does not exist")

        # The lazy import resolves to the stub's attribute
        sys.modules[
            "bietlejuice.base.validation.target_resolver"
        ].validation_database_location = lambda bucket, db: (
            f"s3a://{bucket}/validation/cluster_validation/{db}/"
        )
        # Act
        with patch.object(
            _base_job_mod, "DataFrameDeltaTableLoaderPipeline", pipeline_cls
        ):
            job.run_pipeline(dataframe, args, spark)
        # Assert
        call_kwargs = pipeline_cls.call_args.kwargs
        assert call_kwargs["database_name"] == "cluster_validation"
        assert call_kwargs["table_name"] == "core_house___house"
        assert "validation" in call_kwargs["database_location"]
        assert call_kwargs["target_database_name"] == "cluster_validation"
        assert call_kwargs["target_database_location"] == (
            "s3a://my-bucket/validation/cluster_validation/core_house/"
        )


# ---------------------------------------------------------------------------
# Part D: CoreBrokersBaseSparkJob._run_pipeline_with_config() write redirection
# ---------------------------------------------------------------------------


class TestCoreBrokersBaseWriteRedirection:
    """Verify _run_pipeline_with_config() redirects writes for validation DAGs."""

    def _make_args(self, target_db=None, target_table=None):
        args = MagicMock()
        args.bucket = "my-bucket"
        args.schema = "core_brokers"
        args.table_name = "brokers"
        args.partitions = None
        args.target_database_name = target_db
        args.target_table_name = target_table
        return args

    def _make_job(self):
        class _ConcreteBrokersJob(_CoreBrokersBaseSparkJob):
            def create_core_model(self, spark, args):
                pass

        job = _ConcreteBrokersJob()
        job.get_config = MagicMock(return_value=["id"])
        job.setup_table_privileges = MagicMock(return_value=MagicMock())
        return job

    def test_prod_writes_to_prod_schema(self):
        # Arrange
        pipeline_cls = MagicMock()
        args = self._make_args()
        job = self._make_job()
        dataframe = MagicMock()
        spark = MagicMock()
        # Act
        with patch.object(
            _brokers_base_mod, "DataFrameDeltaTableLoaderPipeline", pipeline_cls
        ):
            job._run_pipeline_with_config(
                dataframe,
                args,
                spark,
                merge_on_key="merge_on",
                update_condition_key="when_matched_update_condition",
            )
        # Assert
        call_kwargs = pipeline_cls.call_args.kwargs
        assert call_kwargs["database_name"] == "core_brokers"
        assert call_kwargs["table_name"] == "brokers"
        assert "core/core_brokers" in call_kwargs["database_location"]
        assert call_kwargs["target_database_name"] == "core_brokers"

    def test_validation_redirects_to_cluster_validation(self):
        # Arrange
        pipeline_cls = MagicMock()
        args = self._make_args(
            target_db="cluster_validation",
            target_table="core_brokers___brokers",
        )
        job = self._make_job()
        dataframe = MagicMock()
        spark = MagicMock()
        # Set validation_database_location on the stub (lazy import inside the if-block)
        sys.modules[
            "bietlejuice.base.validation.target_resolver"
        ].validation_database_location = lambda bucket, db: (
            f"s3a://{bucket}/validation/cluster_validation/{db}/"
        )
        # Act
        with patch.object(
            _brokers_base_mod, "DataFrameDeltaTableLoaderPipeline", pipeline_cls
        ):
            job._run_pipeline_with_config(
                dataframe,
                args,
                spark,
                merge_on_key="merge_on",
                update_condition_key="when_matched_update_condition",
            )
        # Assert
        call_kwargs = pipeline_cls.call_args.kwargs
        assert call_kwargs["database_name"] == "cluster_validation"
        assert call_kwargs["table_name"] == "core_brokers___brokers"
        assert "validation" in call_kwargs["database_location"]
        assert call_kwargs["target_database_name"] == "cluster_validation"
        assert call_kwargs["target_database_location"] == (
            "s3a://my-bucket/validation/cluster_validation/core_brokers/"
        )
