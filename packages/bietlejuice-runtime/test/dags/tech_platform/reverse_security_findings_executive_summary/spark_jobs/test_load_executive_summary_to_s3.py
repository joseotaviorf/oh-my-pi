"""
Unit tests for load_executive_summary_to_s3 Spark job.

Covers the reshape/ordering contract (schema_version 1, IDPLATF-8282) and the
validation-run / no-bucket skip paths, with Spark/S3 mocked out.
"""

import json
import sys
import unittest
from datetime import date
from pathlib import Path
from unittest.mock import MagicMock

import yaml

# Mock deps that require Spark/Databricks before importing the job
sys.modules["quintoandar_logger"] = MagicMock()
sys.modules["pyspark"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.session"] = MagicMock()
sys.modules["pyspark.sql.context"] = MagicMock()
sys.modules["pyspark.context"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.base.spark.base_spark"] = MagicMock()

from dags.tech_platform.reverse_security_findings_executive_summary.spark_jobs import (  # noqa: E402
    load_executive_summary_to_s3 as job,
)


def _fake_row(as_dict):
    row = MagicMock()
    row.asDict.return_value = as_dict
    return row


_FLAT_ROW = {
    "schema_version": "1",
    "as_of": "2026-09-10T15:14:59Z",
    "grain": "one table row; lake contract is (source, id_resource)",
    "total": 219387,
    "critical": 26164,
    "high_plus_critical": 140414,
    "classified_last_30d": 194372,
    "by_risk_level": [
        {"risk_level": "LOW", "count": 70961},
        {"risk_level": "CRITICAL", "count": 26164},
        {"risk_level": "MEDIUM", "count": 8012},
        {"risk_level": "HIGH", "count": 114250},
    ],
    "by_pii_type": [
        {"pii_type": "email", "count": 72651},
        {"pii_type": "full_name", "count": 195589},
    ],
    "by_resource_type": [
        {"resource_type": "google_drive_file", "count": 219387},
    ],
    "by_source": [
        {"source": "drive_historical_backfill", "count": 219387},
    ],
    "classified_by_day": [
        {"dt": date(2026, 9, 9), "count": 94657},
        {"dt": date(2026, 9, 8), "count": 25721},
    ],
}


class TestBuildPayload(unittest.TestCase):
    def _spark_client_returning(self, rows):
        spark_client = MagicMock()
        df = MagicMock()
        df.collect.return_value = rows
        spark_client.get_records.return_value = df
        return spark_client

    def test_nests_kpis_and_orders_arrays(self):
        spark_client = self._spark_client_returning([_fake_row(_FLAT_ROW)])

        payload = json.loads(
            job.build_payload(spark_client, "reverse_x.executive_summary")
        )

        self.assertEqual(payload["schema_version"], "1")
        self.assertEqual(payload["as_of"], "2026-09-10T15:14:59Z")
        self.assertEqual(
            payload["kpis"],
            {
                "total": 219387,
                "critical": 26164,
                "high_plus_critical": 140414,
                "classified_last_30d": 194372,
            },
        )

    def test_orders_by_risk_level_rank_critical_first(self):
        spark_client = self._spark_client_returning([_fake_row(_FLAT_ROW)])

        payload = json.loads(
            job.build_payload(spark_client, "reverse_x.executive_summary")
        )

        self.assertEqual(
            [item["risk_level"] for item in payload["by_risk_level"]],
            ["CRITICAL", "HIGH", "MEDIUM", "LOW"],
        )

    def test_orders_by_pii_type_by_count_desc(self):
        spark_client = self._spark_client_returning([_fake_row(_FLAT_ROW)])

        payload = json.loads(
            job.build_payload(spark_client, "reverse_x.executive_summary")
        )

        self.assertEqual(
            [item["pii_type"] for item in payload["by_pii_type"]],
            ["full_name", "email"],
        )

    def test_classified_by_day_sorted_ascending_with_string_dates(self):
        spark_client = self._spark_client_returning([_fake_row(_FLAT_ROW)])

        payload = json.loads(
            job.build_payload(spark_client, "reverse_x.executive_summary")
        )

        self.assertEqual(
            payload["classified_by_day"],
            [
                {"date": "2026-09-08", "count": 25721},
                {"date": "2026-09-09", "count": 94657},
            ],
        )

    def test_no_forbidden_columns_as_payload_keys(self):
        spark_client = self._spark_client_returning([_fake_row(_FLAT_ROW)])

        payload = json.loads(
            job.build_payload(spark_client, "reverse_x.executive_summary")
        )

        forbidden = {
            "actor_email",
            "id_resource",
            "resource_name",
            "shared_with",
            "source_raw_payload",
        }
        seen_keys = set()

        def _collect_keys(value):
            if isinstance(value, dict):
                seen_keys.update(value.keys())
                for nested in value.values():
                    _collect_keys(nested)
            elif isinstance(value, list):
                for item in value:
                    _collect_keys(item)

        _collect_keys(payload)
        self.assertEqual(seen_keys & forbidden, set())

    def test_raises_when_no_rows(self):
        spark_client = self._spark_client_returning([])

        with self.assertRaises(RuntimeError):
            job.build_payload(spark_client, "reverse_x.executive_summary")


class TestMainSkipPaths(unittest.TestCase):
    def test_is_validation_run_true_when_target_args_present(self):
        self.assertTrue(job.is_validation_run("validation_db", "validation_table"))

    def test_is_validation_run_false_when_no_target_args(self):
        self.assertFalse(job.is_validation_run(None, None))

    def test_forno_and_prod_conf_point_at_their_own_buckets(self):
        """
        Bucket/key come from ConfigurationService (per-env conf.yml), not a
        hardcoded dict — guard the conf files directly. Forno writes to its own
        smoke-test bucket (IDPLATF-8285, quintoandar/infrastructure#45315), not
        the Base44-owned prod bucket (IDPLATF-8284).
        """
        repo_root = Path(__file__).resolve().parents[7]
        dag_dir = (
            repo_root
            / "dags"
            / "tech_platform"
            / "reverse_security_findings_executive_summary"
        )

        with open(dag_dir / "forno_conf.yml") as forno_conf_file:
            forno_conf = yaml.safe_load(forno_conf_file)
        with open(dag_dir / "prod_conf.yml") as prod_conf_file:
            prod_conf = yaml.safe_load(prod_conf_file)

        self.assertEqual(
            forno_conf.get("executive_summary_s3_bucket"),
            "sdg-forno-executive-summary",
        )
        self.assertEqual(
            prod_conf.get("executive_summary_s3_bucket"), "5a-base44-office"
        )
        self.assertEqual(
            prod_conf.get("executive_summary_s3_key"),
            "security_data_gateway/executive_summary/current_summary.json",
        )


if __name__ == "__main__":
    unittest.main()
