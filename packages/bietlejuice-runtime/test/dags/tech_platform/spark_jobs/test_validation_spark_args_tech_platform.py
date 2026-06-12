"""Argparse validation-flag smoke tests for tech_platform custom Spark jobs."""

import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_SPARK_STUBS = [
    "pyspark",
    "pyspark.sql",
    "pyspark.sql.functions",
    "pyspark.sql.types",
    "pyspark.sql.dataframe",
    "pyspark.sql.utils",
    "pyspark.sql.window",
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

from dags.tech_platform.application_audit_logs.spark_jobs.application_audit_logs_load import (  # noqa: E402
    parse_arguments as parse_application_audit_logs_args,
)


# LoadSecurityDataGatewayFindingsRawJob subclasses BaseCoreModelSparkJob — need a
# real (non-mock) base class so Python's class machinery can build the subclass.
class _FakeBaseCoreModelSparkJob:
    def __init__(self, job_name: str):
        self.job_name = job_name
        self.logger = MagicMock()
        self.config_service = None

    def initialize_configuration(self, source: str) -> None:
        self.config_service = MagicMock()

    def initialize_spark_session(self):
        return MagicMock()

    def parse_args(self):
        pass

    def create_core_model(self, spark, args):
        pass

    def run_pipeline(self, df, args, spark) -> None:
        pass


_fake_base_module = MagicMock()
_fake_base_module.BaseCoreModelSparkJob = _FakeBaseCoreModelSparkJob
sys.modules.setdefault(
    "bietlejuice.base.spark.base_core_model_spark_job", _fake_base_module
)

from dags.tech_platform.crowdstrike.spark_jobs.load_crowdstrike_raw import (  # noqa: E402
    CrowdStrikeJobArgumentParser,
)
from dags.tech_platform.cypress_reports.spark_jobs.load_cypress_reports_raw import (  # noqa: E402
    parse_arguments as parse_cypress_reports_args,
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
from dags.tech_platform.security_data_gateway_findings.spark_jobs.load_security_data_gateway_findings_raw import (  # noqa: E402
    LoadSecurityDataGatewayFindingsRawJob,
)
from dags.tech_platform.zscaler.spark_jobs.load_zscaler_raw import (  # noqa: E402
    ZscalerJobArgumentParser,
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

_APPLICATION_AUDIT_LOGS_POSITIONAL = [
    "application_audit_logs",
    _TEST_ENV,
    _TEST_BUCKET,
    "application_audit_logs",
    "2024-01-01T00:00:00+00:00",
    "logs",
    '["year", "month", "day", "hour"]',
]

_CYPRESS_REPORTS_POSITIONAL = [
    _TEST_ENV,
    _TEST_BUCKET,
    "cypress_reports",
    "2024-01-01",
    "2024-01-02",
]

_TECH_PLATFORM_JOB_PATHS = [
    "dags/tech_platform/application_audit_logs/spark_jobs/application_audit_logs_load.py",
    "dags/tech_platform/cypress_reports/spark_jobs/load_cypress_reports_raw.py",
]

_ZSCALER_POSITIONAL = [
    _TEST_ENV,
    _TEST_BUCKET,
    "zscaler",
    "managed_devices",
    "2024-01-01",
    '["year", "month", "day"]',
    "full",
    "2024-01-01",
    "2024-01-02",
    "null",
    "{}",
]

_SECURITY_FINDINGS_POSITIONAL = [
    _TEST_ENV,
    _TEST_BUCKET,
    "datalake_security_data_gateway_raw",
    '["year", "month", "day"]',
    "2026-06-01",
]

_CLOUDZERO_JOB_PATHS = [
    "dags/tech_platform/reverse_integration_cloudzero/spark_jobs/load_contracts_to_cloudzero.py",
    "dags/tech_platform/reverse_integration_cloudzero/spark_jobs/load_api_requests_to_cloudzero.py",
]

_CLOUDZERO_JOBS_WITH_RESOLVE = {
    "dags/tech_platform/reverse_integration_cloudzero/spark_jobs/load_contracts_to_cloudzero.py",
}

_REPO_ROOT = Path(__file__).resolve().parents[6]


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
            (
                ZscalerJobArgumentParser.parse_args,
                _ZSCALER_POSITIONAL,
                "datalake_zscaler_raw___managed_devices",
            ),
            (
                LoadSecurityDataGatewayFindingsRawJob().parse_args,
                _SECURITY_FINDINGS_POSITIONAL,
                "datalake_security_data_gateway_raw___security_findings",
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
            (ZscalerJobArgumentParser.parse_args, _ZSCALER_POSITIONAL),
            (
                LoadSecurityDataGatewayFindingsRawJob().parse_args,
                _SECURITY_FINDINGS_POSITIONAL,
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
            (
                parse_application_audit_logs_args,
                _APPLICATION_AUDIT_LOGS_POSITIONAL,
                "datalake_application_audit_logs_clean___logs",
            ),
            (
                parse_cypress_reports_args,
                _CYPRESS_REPORTS_POSITIONAL,
                "datalake_cypress_reports_raw___cypress_reports",
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
        monkeypatch.setattr(
            "dags.tech_platform.application_audit_logs.spark_jobs.application_audit_logs_load.ConfigurationService",
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
            (
                parse_application_audit_logs_args,
                _APPLICATION_AUDIT_LOGS_POSITIONAL,
            ),
            (parse_cypress_reports_args, _CYPRESS_REPORTS_POSITIONAL),
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
        monkeypatch.setattr(
            "dags.tech_platform.application_audit_logs.spark_jobs.application_audit_logs_load.ConfigurationService",
            MagicMock(
                return_value=MagicMock(get_config=MagicMock(return_value="path"))
            ),
        )
        args = parse_fn()

        assert args.target_database_name is None
        assert args.target_table_name is None


@pytest.mark.parametrize("job_path", _TECH_PLATFORM_JOB_PATHS)
def test_tech_platform_jobs_register_validation_helpers(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text
    assert "resolve_datalake_write_target(" in text


@pytest.mark.parametrize("job_path", _CLOUDZERO_JOB_PATHS)
def test_cloudzero_jobs_register_validation_helpers(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    if job_path in _CLOUDZERO_JOBS_WITH_RESOLVE:
        assert "resolve_datalake_write_target(" in text
