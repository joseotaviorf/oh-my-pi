"""Unit tests for enrich_table_dictionary_with_spark_metastore in load_dag_inventory_raw."""

import importlib.util
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

_REPO_ROOT = Path(__file__).resolve().parents[6]

_STUBS = [
    "pyspark",
    "pyspark.sql",
    "pyspark.sql.functions",
    "pyspark.sql.types",
    "pyspark.sql.dataframe",
    "quintoandar_logger",
    "bietlejuice.base.db",
    "bietlejuice.base.spark",
    "bietlejuice.base.spark.spark_metastore_helper",
    "bietlejuice.clients.db_clients",
    "bietlejuice.loaders",
    "bietlejuice.loaders.s3_loader",
    "bietlejuice.services.configuration_service",
    "bietlejuice.services.metastore_services",
    "hierarchical_conf",
    "hierarchical_conf.hierarchical_conf",
    "boto3",
    "botocore",
    "botocore.exceptions",
]
for _mod in _STUBS:
    sys.modules.setdefault(_mod, MagicMock())

_JOB_PATH = (
    _REPO_ROOT / "dags/platform/dag_inventory/spark_jobs/load_dag_inventory_raw.py"
)
_spec = importlib.util.spec_from_file_location("load_dag_inventory_raw", _JOB_PATH)
assert _spec is not None and _spec.loader is not None
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)


def test_enrich_passes_transformation_grade():
    row = {
        "dag": "transformation_terminator_test",
        "task": "load-transformation-termination",
        "database": "terminator_test",
        "table": "termination",
        "layer": "transformation",
        "transformation_grade": "curated",
        "bucket": "5a-datalake-prod",
        "is_delta": True,
    }

    mock_instance = MagicMock()
    mock_instance.get_metastores_metadata.return_value = (
        "datalake_terminator_test_curated",
        "s3a://5a-datalake-prod/transformation/terminator_test/curated/",
    )
    mock_instance.get_table_names.return_value = ["termination"]

    with patch.object(
        _module, "SparkMetastoreHelper", return_value=mock_instance
    ) as mock_cls:
        result = _module.enrich_table_dictionary_with_spark_metastore([row])

    mock_cls.assert_called_once_with(
        "5a-datalake-prod",
        "transformation",
        "terminator_test",
        "termination",
        all_tables=False,
        transformation_grade="curated",
    )
    assert result == [
        {
            "dag": "transformation_terminator_test",
            "task": "load-transformation-termination",
            "files_location": "s3a://5a-datalake-prod/transformation/terminator_test/curated/termination",
            "table": "datalake_terminator_test_curated.termination",
            "layer": "transformation",
            "bucket": "5a-datalake-prod",
            "is_delta": True,
            "criticality": None,
        }
    ]


def test_enrich_skips_unresolvable_row_on_value_error():
    bad_row = {
        "dag": "transformation_pilot_bad",
        "task": "load-bad",
        "database": "pilot_bad",
        "table": "bad_table",
        "layer": "transformation",
        "transformation_grade": None,
        "bucket": "5a-datalake-prod",
        "is_delta": False,
    }
    good_row = {
        "dag": "clean_orders",
        "task": "load-orders",
        "database": "orders",
        "table": "orders",
        "layer": "clean",
        "bucket": "5a-datalake-prod",
        "is_delta": True,
    }

    good_instance = MagicMock()
    good_instance.get_metastores_metadata.return_value = (
        "datalake_orders_clean",
        "s3a://5a-datalake-prod/clean/orders/",
    )
    good_instance.get_table_names.return_value = ["orders"]

    with patch.object(
        _module,
        "SparkMetastoreHelper",
        side_effect=[
            ValueError("transformation_grade is required when layer is transformation"),
            good_instance,
        ],
    ):
        result = _module.enrich_table_dictionary_with_spark_metastore(
            [bad_row, good_row]
        )

    assert len(result) == 1
    assert result[0] == {
        "dag": "clean_orders",
        "task": "load-orders",
        "files_location": "s3a://5a-datalake-prod/clean/orders/orders",
        "table": "datalake_orders_clean.orders",
        "layer": "clean",
        "bucket": "5a-datalake-prod",
        "is_delta": True,
        "criticality": None,
    }
