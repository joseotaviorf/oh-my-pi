"""
Tests for --target-database-name / --target-table-name argparse params across
the five CDC/DMS Spark job files.

Each test verifies that:
1. The argparse parser accepts the two optional flags.
2. When the flags are supplied, args.target_database_name and
   args.target_table_name carry the expected values.
3. When the flags are omitted, both attributes default to None.

No Spark session is required — only the parse_arguments() function of each
module is exercised.
"""

import sys
from unittest.mock import MagicMock

import pytest

# ---------------------------------------------------------------------------
# Stub out heavy Spark / Databricks imports before importing job modules
# ---------------------------------------------------------------------------
_SPARK_STUBS = [
    "pyspark",
    "pyspark.sql",
    "pyspark.sql.session",
    "pyspark.sql.functions",
    "pyspark.sql.window",
    "pyspark.sql.utils",
    "pyspark.context",
    "delta",
    "delta.tables",
    "quintoandar_logger",
    "bietlejuice.base.spark",
    "bietlejuice.base.spark.base_spark",
    "bietlejuice.base.spark.runtime_detector",
    "bietlejuice.base.spark.delta_secondary_catalog_sync",
    "bietlejuice.base.spark.unity_catalog_helper",
    "bietlejuice.base.spark.spark_table_property_helper",
    "bietlejuice.base.databricks.table_privileges",
    "bietlejuice.base.databricks.row_filter",
    "bietlejuice.base.airflow.enums.database_type_enum",
    "bietlejuice.base.cdc.reader.date_range_partition_reader",
    "bietlejuice.base.cdc.schema_treatment.cdc_schema_finder_factory",
    "bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment_factory",
    "bietlejuice.base.cdc.schema_treatment.schema_changes_notifier",
    "bietlejuice.base.cdc.primary_key_identifiers.raw_primary_key_identifier",
    "bietlejuice.base.cdc.primary_key_identifiers.clean_primary_key_identifier",
    "bietlejuice.base.notification.gchat_webhooks_enum",
    "bietlejuice.base.service.dag_packages_path_service",
    "bietlejuice.loaders.delta_loader",
]
for _mod in _SPARK_STUBS:
    sys.modules.setdefault(_mod, MagicMock())

from dags.cross.base.spark_jobs.load_cdc_clean import (  # noqa: E402
    parse_arguments as parse_cdc_clean,
)
from dags.cross.base.spark_jobs.load_cdc_raw import (  # noqa: E402
    parse_arguments as parse_cdc_raw,
)
from dags.cross.base.spark_jobs.load_cdc_transactional import (  # noqa: E402
    parse_arguments as parse_cdc_transactional,
)
from dags.cross.base.spark_jobs.load_dms_cdc_clean import (  # noqa: E402
    parse_arguments as parse_dms_cdc_clean,
)
from dags.cross.base.spark_jobs.load_dms_cdc_raw import (  # noqa: E402
    parse_arguments as parse_dms_cdc_raw,
)

# ---------------------------------------------------------------------------
# Minimal positional-arg sets required by each parser
# ---------------------------------------------------------------------------
_CDC_TRANSACTIONAL_POSITIONAL = [
    "prod",  # env
    "inc-bucket",  # incoming_bucket
    "dl-bucket",  # datalake_bucket
    "postgres",  # database_type
    "mydb",  # source_database
    "public",  # source_schema
    "orders",  # schema
    "order_items",  # table_name
    "2024-01-01",  # start_date
    "2024-01-02",  # end_date
    "[]",  # partitions
    "id",  # primary_keys
    "secret_key",  # dbutils_secret_key
    "{}",  # transactional_datatype_overrides
]

_CDC_RAW_POSITIONAL = [
    "prod",  # env
    "inc-bucket",  # incoming_bucket
    "dl-bucket",  # datalake_bucket
    "postgres",  # database_type
    "mydb",  # source_database
    "public",  # source_schema
    "orders",  # schema
    "order_items",  # table_name
    "2024-01-01",  # start_date
    "2024-01-02",  # end_date
    "id",  # primary_keys
    "secret_key",  # dbutils_secret_key
]

_CDC_CLEAN_POSITIONAL = [
    "my_dag",  # dag_name
    "prod",  # env
    "dl-bucket",  # datalake_bucket
    "docs-bucket",  # data_documentation_bucket
    "orders",  # schema
    "order_items",  # table_name
    "2024-01-01",  # start_date
    "2024-01-02",  # end_date
    "id",  # primary_keys
]

_DMS_CDC_RAW_POSITIONAL = [
    "prod",  # env
    "inc-bucket",  # incoming_bucket
    "dl-bucket",  # datalake_bucket
    "orders",  # schema
    "order_items",  # table_name
    "2024-01-01",  # start_date
    "2024-01-02",  # end_date
    "id",  # primary_keys
]

_DMS_CDC_CLEAN_POSITIONAL = [
    "my_dag",  # dag_name
    "prod",  # env
    "dl-bucket",  # datalake_bucket
    "docs-bucket",  # data_documentation_bucket
    "orders",  # schema
    "order_items",  # table_name
    "2024-01-01",  # start_date
    "2024-01-02",  # end_date
    "id",  # primary_keys
]

_VALIDATION_DB = "cluster_validation"
_VALIDATION_TABLE = "cluster_validation.datalake_orders_raw___order_items"


# ---------------------------------------------------------------------------
# Parametrized fixtures: (parser_fn, positional_args)
# ---------------------------------------------------------------------------
@pytest.mark.parametrize(
    "parser_fn, positional",
    [
        (parse_cdc_transactional, _CDC_TRANSACTIONAL_POSITIONAL),
        (parse_cdc_raw, _CDC_RAW_POSITIONAL),
        (parse_cdc_clean, _CDC_CLEAN_POSITIONAL),
        (parse_dms_cdc_raw, _DMS_CDC_RAW_POSITIONAL),
        (parse_dms_cdc_clean, _DMS_CDC_CLEAN_POSITIONAL),
    ],
    ids=[
        "load_cdc_transactional",
        "load_cdc_raw",
        "load_cdc_clean",
        "load_dms_cdc_raw",
        "load_dms_cdc_clean",
    ],
)
class TestValidationWriteTargetArgs:
    """Verify --target-database-name / --target-table-name in every CDC/DMS job."""

    def test_validation_flags_parsed_when_supplied(self, parser_fn, positional):
        """When both flags are passed, argparse stores them correctly."""
        argv = positional + [
            "--target-database-name",
            _VALIDATION_DB,
            "--target-table-name",
            _VALIDATION_TABLE,
        ]
        args = (
            parser_fn.__wrapped__(argv)
            if hasattr(parser_fn, "__wrapped__")
            else _parse_with_argv(parser_fn, argv)
        )
        assert args.target_database_name == _VALIDATION_DB
        assert args.target_table_name == _VALIDATION_TABLE

    def test_short_flags_parsed_when_supplied(self, parser_fn, positional):
        """Short forms -tdn / -ttn work as aliases for the long flags."""
        argv = positional + [
            "-tdn",
            _VALIDATION_DB,
            "-ttn",
            _VALIDATION_TABLE,
        ]
        args = _parse_with_argv(parser_fn, argv)
        assert args.target_database_name == _VALIDATION_DB
        assert args.target_table_name == _VALIDATION_TABLE

    def test_defaults_to_none_when_omitted(self, parser_fn, positional):
        """When the optional flags are not passed, both default to None."""
        args = _parse_with_argv(parser_fn, positional)
        assert args.target_database_name is None
        assert args.target_table_name is None

    def test_empty_string_normalised_to_none(self, parser_fn, positional):
        """Passing an empty string is normalised to None via the type= lambda."""
        argv = positional + [
            "--target-database-name",
            "",
            "--target-table-name",
            "",
        ]
        args = _parse_with_argv(parser_fn, argv)
        assert args.target_database_name is None
        assert args.target_table_name is None


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------


def _parse_with_argv(parser_fn, argv):
    """
    Each parse_arguments() calls parser.parse_args() with no arguments, which
    reads sys.argv[1:].  We patch sys.argv temporarily to inject our test
    values without touching the real command line.
    """
    original = sys.argv
    try:
        sys.argv = ["test"] + argv
        return parser_fn()
    finally:
        sys.argv = original
