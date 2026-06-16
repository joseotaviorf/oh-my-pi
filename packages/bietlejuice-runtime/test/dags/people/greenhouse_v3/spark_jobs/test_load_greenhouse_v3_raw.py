import sys
import unittest
from datetime import datetime
from unittest.mock import MagicMock, patch

mock_pyspark = MagicMock()
sys.modules["pyspark"] = mock_pyspark
sys.modules["pyspark.conf"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.functions"] = MagicMock()
sys.modules["pyspark.sql.types"] = MagicMock()
sys.modules["pyspark.sql.dataframe"] = MagicMock()
sys.modules["pyspark.context"] = MagicMock()

sys.modules["bietlejuice.jobs.common.helpers"] = MagicMock()
sys.modules["bietlejuice.jobs.common.raw_layer_loader"] = MagicMock()
sys.modules["quintoandar_logger"] = MagicMock()

from dags.people.greenhouse_v3.spark_jobs.load_greenhouse_v3_raw import (  # noqa: E402
    GreenhouseAPIV3,
    apply_validation_api_scope,
)

BASE_FILTERS_UPDATED_AT = {
    "updated_at_gte": "load_start_date",
    "updated_at_lt": "load_end_date",
}


class TestGreenhouseAPIV3ApplyDateFilters(unittest.TestCase):
    """Tests for GreenhouseAPIV3._apply_date_filters method."""

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_incremental_with_base_filters_adds_updated_at(self, mock_auth):
        """base_filters are resolved into multi-value updated_at params."""
        # arrange
        job_args = {
            "table_name": "application_stages",
            "params": {"per_page": 500},
            "base_filters": BASE_FILTERS_UPDATED_AT,
            "load_start_date": datetime(2025, 3, 1),
            "load_end_date": datetime(2025, 3, 2),
            "extraction_type": "incremental",
        }

        # act
        client = GreenhouseAPIV3(job_args)

        # assert
        self.assertIn("updated_at", client.params)
        self.assertEqual(
            client.params["updated_at"],
            "gte|2025-03-01T00:00:00Z|lt|2025-03-02T00:00:00Z",
        )
        self.assertEqual(client.params["per_page"], 500)

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_incremental_with_json_string_base_filters(self, mock_auth):
        """base_filters arriving as a JSON string (framework serialization) are parsed."""
        # arrange
        import json

        job_args = {
            "table_name": "application_stages",
            "params": {"per_page": 500},
            "base_filters": json.dumps(BASE_FILTERS_UPDATED_AT),
            "load_start_date": datetime(2025, 3, 1),
            "load_end_date": datetime(2025, 3, 2),
            "extraction_type": "incremental",
        }

        # act
        client = GreenhouseAPIV3(job_args)

        # assert
        self.assertIn("updated_at", client.params)
        self.assertEqual(
            client.params["updated_at"],
            "gte|2025-03-01T00:00:00Z|lt|2025-03-02T00:00:00Z",
        )

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_full_extraction_does_not_add_date_filters(self, mock_auth):
        """Full extraction leaves params untouched even with base_filters."""
        # arrange
        job_args = {
            "table_name": "applications",
            "params": {"per_page": 500},
            "base_filters": BASE_FILTERS_UPDATED_AT,
            "load_start_date": datetime(2025, 3, 1),
            "load_end_date": datetime(2025, 3, 2),
            "extraction_type": "full",
        }

        # act
        client = GreenhouseAPIV3(job_args)

        # assert
        self.assertNotIn("updated_at", client.params)
        self.assertEqual(client.params, {"per_page": 500})

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_default_extraction_type_is_full(self, mock_auth):
        """When extraction_type is missing, default to full (no date filters)."""
        # arrange
        job_args = {
            "table_name": "users",
            "params": {"per_page": 500},
            "base_filters": BASE_FILTERS_UPDATED_AT,
            "load_start_date": datetime(2025, 3, 1),
            "load_end_date": datetime(2025, 3, 2),
        }

        # act
        client = GreenhouseAPIV3(job_args)

        # assert
        self.assertNotIn("updated_at", client.params)

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_incremental_without_base_filters_skips(self, mock_auth):
        """Incremental extraction without base_filters skips date filtering."""
        # arrange
        job_args = {
            "table_name": "application_stages",
            "params": {"per_page": 500},
            "load_start_date": datetime(2025, 3, 1),
            "load_end_date": datetime(2025, 3, 2),
            "extraction_type": "incremental",
        }

        # act
        client = GreenhouseAPIV3(job_args)

        # assert
        self.assertNotIn("updated_at", client.params)

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_incremental_without_dates_does_not_add_filters(self, mock_auth):
        """base_filters with unresolved placeholders are skipped gracefully."""
        # arrange
        job_args = {
            "table_name": "application_stages",
            "params": {"per_page": 500},
            "base_filters": BASE_FILTERS_UPDATED_AT,
            "extraction_type": "incremental",
        }

        # act
        client = GreenhouseAPIV3(job_args)

        # assert
        self.assertNotIn("updated_at", client.params)

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_iso_8601_date_formatting(self, mock_auth):
        """Dates are formatted as ISO 8601 with Z suffix."""
        # arrange
        job_args = {
            "table_name": "application_stages",
            "params": {"per_page": 500},
            "base_filters": BASE_FILTERS_UPDATED_AT,
            "load_start_date": datetime(2025, 12, 31, 23, 59, 59),
            "load_end_date": datetime(2026, 1, 1, 0, 0, 0),
            "extraction_type": "incremental",
        }

        # act
        client = GreenhouseAPIV3(job_args)

        # assert
        self.assertEqual(
            client.params["updated_at"],
            "gte|2025-12-31T23:59:59Z|lt|2026-01-01T00:00:00Z",
        )

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_existing_params_preserved(self, mock_auth):
        """Existing params like per_page are not removed when date filters are added."""
        # arrange
        job_args = {
            "table_name": "application_stages",
            "params": {"per_page": 500, "status": "active"},
            "base_filters": BASE_FILTERS_UPDATED_AT,
            "load_start_date": datetime(2025, 6, 1),
            "load_end_date": datetime(2025, 6, 2),
            "extraction_type": "incremental",
        }

        # act
        client = GreenhouseAPIV3(job_args)

        # assert
        self.assertEqual(client.params["per_page"], 500)
        self.assertEqual(client.params["status"], "active")
        self.assertIn("updated_at", client.params)


class TestApplyValidationApiScope(unittest.TestCase):
    def test_validation_run_adds_filters_for_full_scan_table(self):
        job_args = {
            "table_name": "applications",
            "date_column_to_partition": "updated_at",
            "params": {"per_page": 500},
            "extraction_type": "full",
            "load_start_date": datetime(2025, 3, 1),
            "load_end_date": datetime(2025, 3, 2),
            "target_database_name": "cluster_validation",
            "target_table_name": "datalake_greenhouse_v3_raw___applications",
        }

        apply_validation_api_scope(job_args)

        self.assertEqual(job_args["extraction_type"], "incremental")
        self.assertEqual(
            job_args["base_filters"],
            {
                "updated_at_gte": "load_start_date",
                "updated_at_lt": "load_end_date",
            },
        )

    def test_validation_run_skips_static_reference_tables(self):
        job_args = {
            "table_name": "close_reasons",
            "params": {"per_page": 500},
            "extraction_type": "full",
            "target_database_name": "cluster_validation",
            "target_table_name": "datalake_greenhouse_v3_raw___close_reasons",
        }

        apply_validation_api_scope(job_args)

        self.assertEqual(job_args["extraction_type"], "full")
        self.assertNotIn("base_filters", job_args)

    def test_validation_run_preserves_existing_base_filters(self):
        job_args = {
            "table_name": "application_stages",
            "base_filters": BASE_FILTERS_UPDATED_AT,
            "extraction_type": "incremental",
            "target_database_name": "cluster_validation",
            "target_table_name": "datalake_greenhouse_v3_raw___application_stages",
        }

        apply_validation_api_scope(job_args)

        self.assertEqual(job_args["base_filters"], BASE_FILTERS_UPDATED_AT)

    def test_non_validation_run_is_noop(self):
        job_args = {
            "table_name": "applications",
            "extraction_type": "full",
        }

        apply_validation_api_scope(job_args)

        self.assertEqual(job_args["extraction_type"], "full")
        self.assertNotIn("base_filters", job_args)


class TestGreenhouseAPIV3Init(unittest.TestCase):
    """Tests for GreenhouseAPIV3.__init__ method."""

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_init_stores_extraction_type(self, mock_auth):
        """extraction_type is stored on the client instance."""
        # arrange
        job_args = {
            "table_name": "application_stages",
            "params": {"per_page": 500},
            "base_filters": BASE_FILTERS_UPDATED_AT,
            "load_start_date": datetime(2025, 3, 1),
            "load_end_date": datetime(2025, 3, 2),
            "extraction_type": "incremental",
        }

        # act
        client = GreenhouseAPIV3(job_args)

        # assert
        self.assertEqual(client.extraction_type, "incremental")
        self.assertEqual(client.base_filters, BASE_FILTERS_UPDATED_AT)

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_init_default_params(self, mock_auth):
        """Default params is empty dict when not provided."""
        # arrange
        job_args = {"table_name": "application_stages"}

        # act
        client = GreenhouseAPIV3(job_args)

        # assert
        self.assertEqual(client.params, {})
        self.assertEqual(client.base_filters, {})
        self.assertEqual(client.extraction_type, "full")
        self.assertIsNone(client.load_start_date)
        self.assertIsNone(client.load_end_date)


class TestGreenhouseAPIV3GetSecretKey(unittest.TestCase):
    """Tests for GreenhouseAPIV3._get_secret_key dynamic derivation."""

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_get_secret_key_returns_prefixed_uppercase_table_name(self, mock_auth):
        """Secret key is derived from APIEnum prefix + uppercase table name."""
        # arrange
        client = GreenhouseAPIV3({"table_name": "applications"})

        # act
        secret_key = client._get_secret_key()

        # assert
        self.assertEqual(secret_key, "GREENHOUSE_API_V3_APPLICATIONS")

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_get_secret_key_handles_multi_word_table(self, mock_auth):
        """Multi-word table names with underscores are uppercased correctly."""
        # arrange
        client = GreenhouseAPIV3({"table_name": "demographic_answer_options"})

        # act
        secret_key = client._get_secret_key()

        # assert
        self.assertEqual(secret_key, "GREENHOUSE_API_V3_DEMOGRAPHIC_ANSWER_OPTIONS")

    @patch.object(GreenhouseAPIV3, "_apply_authentication")
    def test_get_secret_key_raises_when_endpoint_is_none(self, mock_auth):
        """ValueError is raised when table_name was not provided."""
        # arrange
        client = GreenhouseAPIV3({"table_name": None})

        # act / assert
        with self.assertRaises(ValueError):
            client._get_secret_key()

    @patch(
        "dags.people.greenhouse_v3.spark_jobs"
        ".load_greenhouse_v3_raw.BasicAuthOAuth2ClientCredentials"
    )
    def test_apply_authentication_uses_dynamic_key(self, mock_oauth_cls):
        """_apply_authentication passes the per-table key, not the old static one."""
        # arrange
        mock_oauth_cls.return_value = MagicMock()
        GreenhouseAPIV3({"table_name": "candidates"})

        # assert
        mock_oauth_cls.assert_called_once_with(
            databricks_scope="PEOPLE",
            secret_key="GREENHOUSE_API_V3_CANDIDATES",
            token_url="https://auth.greenhouse.io/token",
            client_id_field="client_id",
            client_secret_field="client_secret",
        )


if __name__ == "__main__":
    unittest.main()
