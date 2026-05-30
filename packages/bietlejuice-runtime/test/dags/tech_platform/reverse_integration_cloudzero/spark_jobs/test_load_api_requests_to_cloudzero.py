"""
Unit tests for load_api_requests_to_cloudzero Spark job.

Tests pure helpers (auto_step_seconds, promql_duration_from_step_seconds),
secret/config getters with mocked dbutils, and Grafana/Prometheus/CloudZero
flows with mocked HTTP.
"""

import json
import runpy
import sys
import unittest
from datetime import datetime
from unittest.mock import MagicMock, patch

# Mock deps that require Spark/Databricks before importing the job
sys.modules["quintoandar_logger"] = MagicMock()
mock_pyspark = MagicMock()
sys.modules["pyspark"] = mock_pyspark
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.session"] = MagicMock()
sys.modules["pyspark.sql.context"] = MagicMock()
sys.modules["pyspark.context"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.base.spark.base_spark"] = MagicMock()

from dags.tech_platform.reverse_integration_cloudzero.spark_jobs import (  # noqa: E402
    load_api_requests_to_cloudzero as job,
)

_TEST_ENVIRONMENT = "forno"
_TEST_EXECUTION_DATE = "2025-01-15"
_MAIN_ARGV = ["script", _TEST_ENVIRONMENT, _TEST_EXECUTION_DATE]


class TestAutoStepSeconds(unittest.TestCase):
    """Tests for auto_step_seconds."""

    def test_full_day_range(self):
        """86400 seconds (24h) yields step ~786 (86400/110)."""
        self.assertEqual(
            job.auto_step_seconds(86400),
            max(60, 86400 // job.AUTO_STEP_MAX_POINTS),
        )
        self.assertGreaterEqual(job.auto_step_seconds(86400), 60)

    def test_min_step_60(self):
        """Step is at least 60 seconds."""
        self.assertEqual(job.auto_step_seconds(1000), 60)
        self.assertEqual(job.auto_step_seconds(5000), 60)

    def test_large_range(self):
        """Larger range gives proportionally larger step."""
        step_small = job.auto_step_seconds(86400)
        step_large = job.auto_step_seconds(86400 * 2)
        self.assertGreater(step_large, step_small)


class TestPromqlDurationFromStepSeconds(unittest.TestCase):
    """Tests for promql_duration_from_step_seconds."""

    def test_hours(self):
        self.assertEqual(job.promql_duration_from_step_seconds(3600), "1h")
        self.assertEqual(job.promql_duration_from_step_seconds(7200), "2h")

    def test_minutes(self):
        self.assertEqual(job.promql_duration_from_step_seconds(900), "15m")
        self.assertEqual(job.promql_duration_from_step_seconds(60), "1m")

    def test_seconds(self):
        self.assertEqual(job.promql_duration_from_step_seconds(30), "30s")
        self.assertEqual(job.promql_duration_from_step_seconds(45), "45s")


class TestGetGrafanaUrl(unittest.TestCase):
    """Tests for get_grafana_url with mocked dbutils."""

    def test_default_when_no_secret_no_env(self):
        with patch.dict("os.environ", {}, clear=False):
            url = job.get_grafana_url(None)
        self.assertEqual(url, job.DEFAULT_GRAFANA_URL)

    def test_env_override(self):
        with patch.dict("os.environ", {"GRAFANA_URL": "https://custom.grafana.com/"}):
            url = job.get_grafana_url(None)
        self.assertEqual(url, "https://custom.grafana.com")

    def test_secret_override(self):
        dbutils = MagicMock()
        dbutils.secrets.get.return_value = "  https://secret.grafana.com  "
        url = job.get_grafana_url(dbutils)
        self.assertEqual(url, "https://secret.grafana.com")
        dbutils.secrets.get.assert_called_once_with(
            scope=job.DATABRICKS_SCOPE, key="GRAFANA_URL"
        )


class TestGetGrafanaDatasourceName(unittest.TestCase):
    """Tests for get_grafana_datasource_name."""

    def test_default_when_no_secret(self):
        with patch.dict("os.environ", {}, clear=False):
            name = job.get_grafana_datasource_name(None)
        self.assertEqual(name, job.DEFAULT_GRAFANA_DATASOURCE_NAME)

    def test_secret_override(self):
        dbutils = MagicMock()
        dbutils.secrets.get.return_value = "my-datasource"
        name = job.get_grafana_datasource_name(dbutils)
        self.assertEqual(name, "my-datasource")


MODULE_UNDER_TEST = "dags.tech_platform.reverse_integration_cloudzero.spark_jobs.load_api_requests_to_cloudzero"


class TestResolveDatasourceUidByName(unittest.TestCase):
    """Tests for resolve_datasource_uid_by_name."""

    def test_requires_token(self):
        with self.assertRaises(RuntimeError) as ctx:
            job.resolve_datasource_uid_by_name(
                "https://grafana.com", "metrics-prod", ""
            )
        self.assertIn("GRAFANA_API_TOKEN", str(ctx.exception))

    @patch(f"{MODULE_UNDER_TEST}.requests")
    def test_returns_uid_from_response(self, mock_requests):
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {"uid": "abc123", "name": "metrics-prod"}
        mock_session = MagicMock()
        mock_session.get.return_value = mock_response
        mock_requests.Session.return_value = mock_session
        uid = job.resolve_datasource_uid_by_name(
            "https://grafana.com", "metrics-prod", "token123"
        )
        self.assertEqual(uid, "abc123")

    @patch(f"{MODULE_UNDER_TEST}.requests")
    def test_raises_when_uid_missing_in_response(self, mock_requests):
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {"name": "metrics-prod"}
        mock_session = MagicMock()
        mock_session.get.return_value = mock_response
        mock_requests.Session.return_value = mock_session
        with self.assertRaises(RuntimeError) as ctx:
            job.resolve_datasource_uid_by_name(
                "https://grafana.com", "metrics-prod", "token123"
            )
        self.assertIn("uid", str(ctx.exception))


class TestQueryPrometheusViaGrafana(unittest.TestCase):
    """Tests for query_prometheus_via_grafana response parsing."""

    @patch(f"{MODULE_UNDER_TEST}.requests")
    def test_parses_instant_result(self, mock_requests):
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {
            "status": "success",
            "data": {
                "result": [
                    {"metric": {"app": "service-a"}, "value": [12345, "100.5"]},
                    {"metric": {"app": "service-b"}, "value": [12345, "200"]},
                ]
            },
        }
        mock_session = MagicMock()
        mock_session.get.return_value = mock_response
        mock_requests.Session.return_value = mock_session
        result = job.query_prometheus_via_grafana(
            "https://grafana.com",
            "uid1",
            "sum(rate(x[1h])) by (app)",
            datetime(2025, 1, 15, 23, 59, 59),
            api_token="",
        )
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0][0], {"app": "service-a"})
        self.assertEqual(result[0][1], 100.5)
        self.assertEqual(result[1][0], {"app": "service-b"})
        self.assertEqual(result[1][1], 200.0)

    @patch(f"{MODULE_UNDER_TEST}.requests")
    def test_raises_on_api_error_status(self, mock_requests):
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {"status": "error", "error": "bad query"}
        mock_session = MagicMock()
        mock_session.get.return_value = mock_response
        mock_requests.Session.return_value = mock_session
        with self.assertRaises(RuntimeError) as ctx:
            job.query_prometheus_via_grafana(
                "https://grafana.com", "uid1", "invalid", datetime(2025, 1, 1)
            )
        self.assertIn("error", str(ctx.exception).lower())


class TestQueryRangeViaGrafana(unittest.TestCase):
    """Tests for query_range_via_grafana and aggregation."""

    @patch(f"{MODULE_UNDER_TEST}.requests")
    def test_aggregates_values_per_series(self, mock_requests):
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {
            "status": "success",
            "data": {
                "result": [
                    {
                        "metric": {"app": "svc-a"},
                        "values": [[1000, "10"], [2000, "20"], [3000, "15"]],
                    },
                ]
            },
        }
        mock_session = MagicMock()
        mock_session.get.return_value = mock_response
        mock_requests.Session.return_value = mock_session
        start = datetime(2025, 1, 15, 0, 0, 0)
        end = datetime(2025, 1, 15, 23, 59, 59)
        result = job.query_range_via_grafana(
            "https://grafana.com",
            "uid1",
            "sum(increase(x[1h])) by (app)",
            start,
            end,
            3600,
        )
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0][0], {"app": "svc-a"})
        self.assertEqual(result[0][1], 45.0)  # 10 + 20 + 15

    @patch(f"{MODULE_UNDER_TEST}.requests")
    def test_raises_on_error_status(self, mock_requests):
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {"status": "error"}
        mock_session = MagicMock()
        mock_session.get.return_value = mock_response
        mock_requests.Session.return_value = mock_session
        start = datetime(2025, 1, 15)
        end = datetime(2025, 1, 15, 23, 59, 59)
        with self.assertRaises(RuntimeError):
            job.query_range_via_grafana(
                "https://grafana.com", "uid1", "query", start, end, 3600
            )


class TestSendApiRequestsToCloudZero(unittest.TestCase):
    """Tests for send_api_requests_to_cloudzero."""

    @patch(f"{MODULE_UNDER_TEST}.requests")
    def test_builds_payload_with_associated_cost(self, mock_requests):
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_session = MagicMock()
        mock_session.post.return_value = mock_response
        mock_requests.Session.return_value = mock_session
        job.send_api_requests_to_cloudzero(
            records=[
                ({"app": "service-a"}, 100.5),
                ({"app": "service-b"}, 200.7),
            ],
            execution_date="2025-01-15",
            cloudzero_token="Bearer tok",
            dimension_label="app",
            dimension_key="custom:API",
        )
        call_args = mock_requests.Session.return_value.post.call_args
        self.assertIn("cloudzero.com", call_args[0][0])
        self.assertIn(job.CLOUDZERO_METRIC_NAME, call_args[0][0])
        payload = call_args[1]["json"]
        self.assertEqual(len(payload["records"]), 2)
        self.assertEqual(
            payload["records"][0]["value"], 100
        )  # int(round(100.5)) in Py3
        self.assertEqual(
            payload["records"][0]["associated_cost"], {"custom:API": "service-a"}
        )
        self.assertEqual(payload["records"][1]["value"], 201)
        self.assertEqual(
            payload["records"][1]["associated_cost"], {"custom:API": "service-b"}
        )

    @patch(f"{MODULE_UNDER_TEST}.requests")
    def test_empty_records_does_not_post(self, mock_requests):
        job.send_api_requests_to_cloudzero(
            records=[],
            execution_date="2025-01-15",
            cloudzero_token="Bearer tok",
            dimension_label="app",
            dimension_key="custom:API",
        )
        mock_requests.Session.return_value.post.assert_not_called()

    def test_fallback_to_unknown_when_label_missing(self):
        records = [({"other": "x"}, 42.0)]
        with patch(f"{MODULE_UNDER_TEST}.requests") as mock_requests:
            mock_response = MagicMock()
            mock_response.raise_for_status = MagicMock()
            mock_session = MagicMock()
            mock_session.post.return_value = mock_response
            mock_requests.Session.return_value = mock_session
            job.send_api_requests_to_cloudzero(
                records=records,
                execution_date="2025-01-15",
                cloudzero_token="Bearer tok",
                dimension_label="app",
                dimension_key="custom:API",
            )
            payload = mock_requests.Session.return_value.post.call_args[1]["json"]
            self.assertEqual(
                payload["records"][0]["associated_cost"]["custom:API"], "unknown"
            )

    @patch(f"{MODULE_UNDER_TEST}.requests")
    def test_uses_k8s_workload_dimension_when_requested(self, mock_requests):
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_session = MagicMock()
        mock_session.post.return_value = mock_response
        mock_requests.Session.return_value = mock_session
        job.send_api_requests_to_cloudzero(
            records=[({"app": "listing-service"}, 50000)],
            execution_date="2025-01-15",
            cloudzero_token="Bearer tok",
            dimension_label="app",
            dimension_key="K8s:Workload",
        )
        payload = mock_requests.Session.return_value.post.call_args[1]["json"]
        self.assertEqual(
            payload["records"][0]["associated_cost"],
            {"K8s:Workload": "listing-service"},
        )


def _run_job_main():
    """Execute the job module as __main__ (same as python -m ...)."""
    runpy.run_module(
        job.__name__,
        run_name="__main__",
        alter_sys=True,
    )


class TestMain(unittest.TestCase):
    """Tests for main entry point with full mocks."""

    @patch("bietlejuice.base.spark.BaseDBUtils")
    def test_main_success_with_datasource_resolution(self, mock_base_dbutils):
        # runpy re-executes the module and re-imports requests; mock requests in sys.modules
        mock_dbutils = MagicMock()
        mock_dbutils.secrets.get.side_effect = lambda scope=None, key=None: {
            "CLOUDZERO_API_TOKEN": json.dumps({"token": "cloudzero-token"}),
            "GRAFANA_DATASOURCE_UID": "",
            "GRAFANA_API_TOKEN": "grafana-token",
            "PROMETHEUS_REQUESTS_DIMENSION_LABEL": "app",
        }.get(key, "")
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils

        resp_resolve = MagicMock()
        resp_resolve.raise_for_status = MagicMock()
        resp_resolve.json.return_value = {"uid": "resolved-uid"}
        resp_range = MagicMock()
        resp_range.raise_for_status = MagicMock()
        resp_range.json.return_value = {
            "status": "success",
            "data": {
                "result": [
                    {"metric": {"app": "my-app"}, "values": [[1, "1000"]]},
                ]
            },
        }
        resp_post = MagicMock()
        resp_post.raise_for_status = MagicMock()
        mock_session = MagicMock()
        mock_session.get.side_effect = [resp_resolve, resp_range]
        mock_session.post.return_value = resp_post
        mock_requests = MagicMock()
        mock_requests.Session.return_value = mock_session

        with patch.dict("sys.modules", {"requests": mock_requests}):
            with patch("sys.argv", _MAIN_ARGV):
                _run_job_main()

        self.assertEqual(mock_session.get.call_count, 2)
        self.assertEqual(mock_session.post.call_count, 1)
        post_call = mock_session.post.call_args
        payload = post_call[1]["json"]
        self.assertEqual(
            payload["records"][0]["associated_cost"]["custom:API"], "my-app"
        )
        self.assertEqual(payload["records"][0]["value"], 1000)

    @patch("bietlejuice.base.spark.BaseDBUtils")
    def test_main_raises_when_dbutils_unavailable(self, mock_base_dbutils):
        mock_base_dbutils.return_value.get_dbutils.return_value = None
        with patch("sys.argv", _MAIN_ARGV):
            with self.assertRaises(RuntimeError) as ctx:
                _run_job_main()
        self.assertIn("dbutils", str(ctx.exception).lower())

    @patch("bietlejuice.base.spark.BaseDBUtils")
    def test_main_raises_when_cloudzero_token_invalid(self, mock_base_dbutils):
        mock_dbutils = MagicMock()
        mock_dbutils.secrets.get.return_value = json.dumps({"invalid": "no token key"})
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils
        with patch("sys.argv", _MAIN_ARGV):
            with self.assertRaises(RuntimeError) as ctx:
                _run_job_main()
        self.assertIn("token", str(ctx.exception).lower())

    @patch("bietlejuice.base.spark.BaseDBUtils")
    def test_main_uses_uid_when_set(self, mock_base_dbutils):
        mock_dbutils = MagicMock()
        mock_dbutils.secrets.get.side_effect = lambda scope=None, key=None: {
            "CLOUDZERO_API_TOKEN": json.dumps({"token": "cz-token"}),
            "GRAFANA_DATASOURCE_UID": "my-uid-123",
            "PROMETHEUS_REQUESTS_DIMENSION_LABEL": "app",
        }.get(key, "")
        mock_base_dbutils.return_value.get_dbutils.return_value = mock_dbutils

        resp_range = MagicMock()
        resp_range.raise_for_status = MagicMock()
        resp_range.json.return_value = {"status": "success", "data": {"result": []}}
        resp_post = MagicMock()
        resp_post.raise_for_status = MagicMock()
        mock_session = MagicMock()
        mock_session.get.return_value = resp_range
        mock_session.post.return_value = resp_post
        mock_requests = MagicMock()
        mock_requests.Session.return_value = mock_session

        with patch.dict("sys.modules", {"requests": mock_requests}):
            with patch("sys.argv", _MAIN_ARGV):
                _run_job_main()

        mock_session.get.assert_called_once()
        self.assertIn("my-uid-123", mock_session.get.call_args[0][0])
        # Empty result -> send_api_requests_to_cloudzero does not post
        mock_session.post.assert_not_called()


if __name__ == "__main__":
    unittest.main()
