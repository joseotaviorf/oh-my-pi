"""Argparse validation-flag smoke tests for tech_platform custom Spark jobs."""

import sys
from unittest.mock import MagicMock

import pytest

_SPARK_STUBS = [
    "pyspark",
    "pyspark.sql",
    "pyspark.sql.functions",
    "pyspark.sql.types",
    "pyspark.sql.dataframe",
    "pyspark.sql.utils",
    "databricks",
    "databricks.sdk",
    "requests",
    "quintoandar_logger",
    "bietlejuice.loaders.delta_loader",
    "bietlejuice.services.configuration_service",
    "bietlejuice.base.spark",
    "bietlejuice.base.spark.base_spark",
    "bietlejuice.base.spark.unity_catalog_helper",
    "bietlejuice.base.databricks.table_privileges",
    "bietlejuice.clients.db_clients",
    "bietlejuice.services.metastore_services",
    "bietlejuice.loaders",
    "bietlejuice.loaders.s3_loader",
    "bietlejuice.jobs.common.helpers",
    "dateutil",
    "dateutil.parser",
]
for _mod in _SPARK_STUBS:
    sys.modules.setdefault(_mod, MagicMock())

from dags.tech_platform.crowdstrike.spark_jobs.load_crowdstrike_raw import (  # noqa: E402
    CrowdStrikeJobArgumentParser,
)
from dags.tech_platform.idn.spark_jobs.load_idn_raw import (  # noqa: E402
    IdnJobArgumentParser,
)
from dags.tech_platform.intune.spark_jobs.load_intune_raw import (  # noqa: E402
    IntuneJobArgumentParser,
)
from dags.tech_platform.iru.spark_jobs.load_iru_raw import (  # noqa: E402
    IruJobArgumentParser,
)
from dags.tech_platform.istio.spark_jobs.istio_logs_load import (  # noqa: E402
    parse_arguments as parse_istio_args,
)
from dags.tech_platform.opa.spark_jobs.opa_logs_load import (  # noqa: E402
    parse_arguments as parse_opa_args,
)
from dags.tech_platform.release_validations_tests.spark_jobs.load_release_validations_tests_raw import (  # noqa: E402
    parse_args as parse_release_validations_tests_args,
)

_VALIDATION_DB = "cluster_validation"
_TEST_ENV = "prod"
_TEST_BUCKET = "5a-datalake-prod"

_CROWDSTRIKE_POSITIONAL = [
    _TEST_ENV,
    _TEST_BUCKET,
    "crowdstrike",
    "managed_devices",
    "2024-01-01",
    '["year", "month", "day"]',
    "full",
    "2024-01-01",
    "2024-01-02",
    "null",
]

_IDN_POSITIONAL = [
    _TEST_ENV,
    _TEST_BUCKET,
    "idn",
    "identities",
    "2024-01-01",
    '["year", "month", "day"]',
    "full",
    "2024-01-01",
    "2024-01-02",
    "null",
    "{}",
]

_INTUNE_POSITIONAL = [
    _TEST_ENV,
    _TEST_BUCKET,
    "intune",
    "managed_devices",
    "2024-01-01",
    '["year", "month", "day"]',
    "full",
    "2024-01-01",
    "2024-01-02",
    "{}",
]

_IRU_POSITIONAL = [
    _TEST_ENV,
    _TEST_BUCKET,
    "iru",
    "managed_devices",
    "2024-01-01",
    '["year", "month", "day"]',
    "full",
    "2024-01-01",
    "2024-01-02",
    "null",
    "{}",
]

_RELEASE_VALIDATIONS_TESTS_POSITIONAL = [
    _TEST_ENV,
    _TEST_BUCKET,
    "release_validations_tests",
    "playwright_results",
    '["year", "month", "day"]',
    "2024-01-01",
]

_ISTIO_POSITIONAL = [
    "istio",
    _TEST_ENV,
    _TEST_BUCKET,
    "access_logs",
    "2024-01-01T00:00:00+00:00",
    "istio",
    '["year", "month", "day", "hour"]',
]

_OPA_POSITIONAL = [
    "opa",
    _TEST_ENV,
    _TEST_BUCKET,
    "access_logs",
    "2024-01-01T00:00:00+00:00",
    "opa",
    '["year", "month", "day", "hour"]',
]


class TestTechPlatformSparkJobValidationArgs:
    @pytest.mark.parametrize(
        "parse_fn,positional,validation_table",
        [
            (
                CrowdStrikeJobArgumentParser.parse_args,
                _CROWDSTRIKE_POSITIONAL,
                "datalake_crowdstrike_raw___managed_devices",
            ),
            (
                IdnJobArgumentParser.parse_args,
                _IDN_POSITIONAL,
                "datalake_idn_raw___identities",
            ),
            (
                IntuneJobArgumentParser.parse_args,
                _INTUNE_POSITIONAL,
                "datalake_intune_raw___managed_devices",
            ),
            (
                IruJobArgumentParser.parse_args,
                _IRU_POSITIONAL,
                "datalake_iru_raw___managed_devices",
            ),
            (
                parse_release_validations_tests_args,
                _RELEASE_VALIDATIONS_TESTS_POSITIONAL,
                "datalake_release_validations_tests_raw___playwright_results",
            ),
        ],
    )
    def test_dict_jobs_accept_validation_flags(
        self, parse_fn, positional, validation_table, monkeypatch
    ):
        monkeypatch.setattr(
            sys,
            "argv",
            ["job"]
            + positional
            + [
                "--target-database-name",
                _VALIDATION_DB,
                "--target-table-name",
                validation_table,
            ],
        )
        args = parse_fn()

        if isinstance(args, dict):
            assert args["target_database_name"] == _VALIDATION_DB
            assert args["target_table_name"] == validation_table
        else:
            assert args.target_database_name == _VALIDATION_DB
            assert args.target_table_name == validation_table

    @pytest.mark.parametrize(
        "parse_fn,positional",
        [
            (CrowdStrikeJobArgumentParser.parse_args, _CROWDSTRIKE_POSITIONAL),
            (IdnJobArgumentParser.parse_args, _IDN_POSITIONAL),
            (IntuneJobArgumentParser.parse_args, _INTUNE_POSITIONAL),
            (IruJobArgumentParser.parse_args, _IRU_POSITIONAL),
            (
                parse_release_validations_tests_args,
                _RELEASE_VALIDATIONS_TESTS_POSITIONAL,
            ),
        ],
    )
    def test_dict_jobs_default_without_validation_flags(
        self, parse_fn, positional, monkeypatch
    ):
        monkeypatch.setattr(sys, "argv", ["job"] + positional)
        args = parse_fn()

        if isinstance(args, dict):
            assert args.get("target_database_name") is None
            assert args.get("target_table_name") is None
        else:
            assert args.target_database_name is None
            assert args.target_table_name is None

    @pytest.mark.parametrize(
        "parse_fn,positional,validation_table",
        [
            (
                parse_istio_args,
                _ISTIO_POSITIONAL,
                "datalake_access_logs_clean___istio",
            ),
            (
                parse_opa_args,
                _OPA_POSITIONAL,
                "datalake_access_logs_clean___opa",
            ),
        ],
    )
    def test_log_jobs_accept_validation_flags(
        self, parse_fn, positional, validation_table, monkeypatch
    ):
        monkeypatch.setattr(
            sys,
            "argv",
            ["job"]
            + positional
            + [
                "--target-database-name",
                _VALIDATION_DB,
                "--target-table-name",
                validation_table,
            ],
        )
        monkeypatch.setattr(
            "dags.tech_platform.istio.spark_jobs.istio_logs_load.ConfigurationService",
            MagicMock(
                return_value=MagicMock(get_config=MagicMock(return_value="path"))
            ),
        )
        monkeypatch.setattr(
            "dags.tech_platform.opa.spark_jobs.opa_logs_load.ConfigurationService",
            MagicMock(
                return_value=MagicMock(get_config=MagicMock(return_value="path"))
            ),
        )
        args = parse_fn()

        assert args.target_database_name == _VALIDATION_DB
        assert args.target_table_name == validation_table

    @pytest.mark.parametrize(
        "parse_fn,positional",
        [
            (parse_istio_args, _ISTIO_POSITIONAL),
            (parse_opa_args, _OPA_POSITIONAL),
        ],
    )
    def test_log_jobs_default_without_validation_flags(
        self, parse_fn, positional, monkeypatch
    ):
        monkeypatch.setattr(sys, "argv", ["job"] + positional)
        monkeypatch.setattr(
            "dags.tech_platform.istio.spark_jobs.istio_logs_load.ConfigurationService",
            MagicMock(
                return_value=MagicMock(get_config=MagicMock(return_value="path"))
            ),
        )
        monkeypatch.setattr(
            "dags.tech_platform.opa.spark_jobs.opa_logs_load.ConfigurationService",
            MagicMock(
                return_value=MagicMock(get_config=MagicMock(return_value="path"))
            ),
        )
        args = parse_fn()

        assert args.target_database_name is None
        assert args.target_table_name is None
