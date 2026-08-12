"""Argparse unit tests for load_idactum_raw (no Spark runtime)."""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

sys.modules.setdefault("pyspark", MagicMock())
sys.modules.setdefault("pyspark.sql", MagicMock())
sys.modules.setdefault("pyspark.sql.functions", MagicMock())

for _mod in (
    "bietlejuice.base.databricks.table_privileges",
    "bietlejuice.base.db",
    "bietlejuice.base.spark",
    "bietlejuice.base.spark.unity_catalog_helper",
    "bietlejuice.clients.db_clients",
    "bietlejuice.consumers.s3_consumer",
    "bietlejuice.loaders",
    "bietlejuice.loaders.s3_loader",
    "bietlejuice.services.configuration_service",
    "bietlejuice.services.metastore_services",
):
    sys.modules.setdefault(_mod, MagicMock())

# Real validation arg helpers (light dependency).
from bietlejuice.base.validation.spark_args import (  # noqa: E402
    add_validation_target_args as _real_add_validation_target_args,
)

sys.modules["bietlejuice.base.validation.spark_args"] = MagicMock(
    add_validation_target_args=_real_add_validation_target_args,
    resolve_datalake_write_target=MagicMock(),
)

from dags.cross.base.spark_jobs.load_idactum_raw import (  # noqa: E402
    build_arg_parser,
)


@pytest.mark.parametrize(
    "argv,expected_fields",
    [
        (
            ["prod", "bucket", "idactum_buyers", "2026-08-07", "idactum_buyers"],
            "",
        ),
        (
            [
                "prod",
                "bucket",
                "idactum_buyers",
                "2026-08-07",
                "idactum_buyers",
                "--target-database-name",
                "cluster_validation",
                "--target-table-name",
                "datalake_idactum_buyers___idactum_buyers",
            ],
            "",
        ),
        (
            [
                "prod",
                "bucket",
                "idactum_transactions",
                "2026-08-07",
                "idactum_transactions",
                "data_transacao,data_declaracao_transacao",
            ],
            "data_transacao,data_declaracao_transacao",
        ),
        (
            [
                "prod",
                "bucket",
                "idactum_buyers",
                "2026-08-07",
                "idactum_buyers",
                "",
            ],
            "",
        ),
    ],
)
def test_build_arg_parser_optional_timestamp_ntz_fields(argv, expected_fields):
    args = build_arg_parser().parse_args(argv)
    assert args.timestamp_ntz_fields == expected_fields
    assert args.source in {"idactum_buyers", "idactum_transactions"}
