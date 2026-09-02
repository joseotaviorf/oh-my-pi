"""Unit tests for run_validation_suites Spark job secret loading."""

import importlib
import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db.database_enum import DatabaseEnum

_REPO_ROOT = Path(__file__).resolve().parents[7]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_MODULE_PATH = (
    "dags.platform.services_integration_validations.spark_jobs.run_validation_suites"
)

_IMPORT_MOCKS = {
    "quintoandar_logger": MagicMock(),
    "validations_engine": MagicMock(),
    "validations_engine.validations_engine": MagicMock(),
}

_mock_dbutils_at_import = MagicMock()
_mock_base_dbutils_cls = MagicMock()
_mock_base_dbutils_cls.return_value.get_dbutils.return_value = _mock_dbutils_at_import

with patch.dict("sys.modules", _IMPORT_MOCKS):
    with patch("bietlejuice.base.spark.BaseDBUtils", _mock_base_dbutils_cls):
        job = importlib.import_module(_MODULE_PATH)


class TestRequiredSecretKeys:
    def test_required_secret_keys_contains_enum_values(self):
        # arrange
        expected = {
            APIEnum.HUBSPOT,
            APIEnum.SURVICATE,
            APIEnum.MX_FACEBOOK,
            DatabaseEnum.CRM,
            DatabaseEnum.HEIMDALL,
            DatabaseEnum.CYBER,
        }
        # act
        actual = set(job.REQUIRED_SECRET_KEYS)
        # assert
        assert actual == expected


class TestReadConnectionAuthParams:
    def _mock_dbutils(self, secret_values, optional_raises=None):
        dbutils = MagicMock()
        optional_raises = optional_raises or set()

        def _get(scope, key):
            if key in optional_raises:
                raise KeyError(f"missing optional {key}")
            if key not in secret_values:
                raise KeyError(f"missing required {key}")
            return secret_values[key]

        dbutils.secrets.get.side_effect = _get
        dbutils.secrets.list = MagicMock()
        return dbutils

    def test_happy_path_parses_json_secrets(self):
        # arrange
        secret_values = {
            APIEnum.HUBSPOT: json.dumps({"token": "hubspot"}),
            APIEnum.SURVICATE: json.dumps({"api_key": "surv"}),
            APIEnum.MX_FACEBOOK: json.dumps({"token": "fb"}),
            DatabaseEnum.CRM: json.dumps({"host": "crm"}),
            DatabaseEnum.HEIMDALL: json.dumps({"host": "heim"}),
            DatabaseEnum.CYBER: json.dumps({"host": "cyber"}),
        }
        dbutils = self._mock_dbutils(secret_values)
        # act
        with patch.object(job, "dbutils", dbutils):
            result = job.read_connection_auth_params()
        # assert
        assert set(result.keys()) >= set(job.REQUIRED_SECRET_KEYS)
        assert result[APIEnum.HUBSPOT] == {"token": "hubspot"}
        assert result[DatabaseEnum.CRM] == {"host": "crm"}

    def test_non_json_secret_stored_as_raw_string(self):
        # arrange
        secret_values = {
            APIEnum.HUBSPOT: "plain-hubspot-token",
            APIEnum.SURVICATE: json.dumps({"api_key": "surv"}),
            APIEnum.MX_FACEBOOK: json.dumps({"token": "fb"}),
            DatabaseEnum.CRM: json.dumps({"host": "crm"}),
            DatabaseEnum.HEIMDALL: json.dumps({"host": "heim"}),
            DatabaseEnum.CYBER: json.dumps({"host": "cyber"}),
        }
        dbutils = self._mock_dbutils(secret_values)
        # act
        with patch.object(job, "dbutils", dbutils):
            result = job.read_connection_auth_params()
        # assert
        assert result[APIEnum.HUBSPOT] == "plain-hubspot-token"

    def test_missing_required_key_raises_runtime_error(self):
        # arrange
        secret_values = {
            APIEnum.HUBSPOT: json.dumps({"token": "hubspot"}),
            APIEnum.SURVICATE: json.dumps({"api_key": "surv"}),
            APIEnum.MX_FACEBOOK: json.dumps({"token": "fb"}),
            DatabaseEnum.CRM: json.dumps({"host": "crm"}),
            DatabaseEnum.HEIMDALL: json.dumps({"host": "heim"}),
        }
        dbutils = self._mock_dbutils(secret_values)
        # act / assert
        with patch.object(job, "dbutils", dbutils):
            with pytest.raises(RuntimeError, match="required secret missing"):
                job.read_connection_auth_params()

    def test_optional_gchat_keys_missing_do_not_raise(self):
        # arrange
        secret_values = {
            APIEnum.HUBSPOT: json.dumps({"token": "hubspot"}),
            APIEnum.SURVICATE: json.dumps({"api_key": "surv"}),
            APIEnum.MX_FACEBOOK: json.dumps({"token": "fb"}),
            DatabaseEnum.CRM: json.dumps({"host": "crm"}),
            DatabaseEnum.HEIMDALL: json.dumps({"host": "heim"}),
            DatabaseEnum.CYBER: json.dumps({"host": "cyber"}),
        }
        optional_raises = set(job.OPTIONAL_SECRET_KEYS)
        dbutils = self._mock_dbutils(secret_values, optional_raises=optional_raises)
        # act
        with patch.object(job, "dbutils", dbutils):
            result = job.read_connection_auth_params()
        # assert
        assert set(result.keys()) == set(job.REQUIRED_SECRET_KEYS)

    def test_dbutils_none_raises_runtime_error(self):
        # arrange / act / assert
        with patch.object(job, "dbutils", None):
            with pytest.raises(RuntimeError, match="dbutils is not available"):
                job.read_connection_auth_params()

    def test_never_calls_secrets_list(self):
        # arrange
        secret_values = {
            APIEnum.HUBSPOT: json.dumps({"token": "hubspot"}),
            APIEnum.SURVICATE: json.dumps({"api_key": "surv"}),
            APIEnum.MX_FACEBOOK: json.dumps({"token": "fb"}),
            DatabaseEnum.CRM: json.dumps({"host": "crm"}),
            DatabaseEnum.HEIMDALL: json.dumps({"host": "heim"}),
            DatabaseEnum.CYBER: json.dumps({"host": "cyber"}),
        }
        dbutils = self._mock_dbutils(secret_values)
        # act
        with patch.object(job, "dbutils", dbutils):
            job.read_connection_auth_params()
        # assert
        dbutils.secrets.list.assert_not_called()
