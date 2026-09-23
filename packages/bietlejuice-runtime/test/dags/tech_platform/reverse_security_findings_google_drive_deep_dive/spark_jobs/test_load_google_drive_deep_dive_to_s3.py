"""
Unit tests for load_google_drive_deep_dive_to_s3 Spark job.

Covers the reshape/pivot/ordering contract (schema_version 1) and the
validation-run / no-bucket skip paths, with Spark/S3 mocked out.
"""

import json
import re
import sys
import unittest
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

from dags.tech_platform.reverse_security_findings_google_drive_deep_dive.spark_jobs import (  # noqa: E402
    load_google_drive_deep_dive_to_s3 as job,
)

EMAIL_RE = re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")

_FLAT_ROW = {
    "schema_version": "1",
    "as_of": "2026-09-17T12:00:00Z",
    "org_units_with_findings": 2,
    "shared_drives_affected": 96,
    "external_users_with_pii_access": 317,
    "exposed_beyond_domain": 168370,
    "pii_findings_total": 433553,
    "total_findings": 433576,
    "by_mime_type": [
        {"label": "application/pdf", "risk_level": "HIGH", "count": 138243},
        {"label": "application/pdf", "risk_level": "LOW", "count": 35683},
        {"label": "text/plain", "risk_level": "LOW", "count": 25686},
    ],
    "top_shared_drives": [
        {"label": "[LEGADO] Legal Ops", "risk_level": "LOW", "count": 60222},
        {"label": "4MATT", "risk_level": "HIGH", "count": 27637},
    ],
    "top_external_users": [
        {
            "label": "partner.user@partner-domain.com",
            "risk_level": "HIGH",
            "count": 27602,
        },
        {
            "label": "someone.else@another-domain.com",
            "risk_level": "CRITICAL",
            "count": 3681,
        },
    ],
    "top_owners": [],
    "by_org_unit": [
        {"label": "/quintoandar.com.br", "risk_level": "HIGH", "count": 232073},
        {"label": "(empty)", "risk_level": "LOW", "count": 9207},
    ],
    "riskiest_combinations": [
        {"pii_type": "full_name", "has_external": True, "count": 127674},
        {"pii_type": "address", "has_external": True, "count": 116929},
        {"pii_type": "email", "has_external": False, "count": 200},
    ],
    "exposure_matrix": [
        {"has_external": True, "risk_level": "CRITICAL", "count": 5320},
        {"has_external": True, "risk_level": "HIGH", "count": 107844},
        {"has_external": False, "risk_level": "CRITICAL", "count": 30421},
    ],
}


def _fake_row(as_dict):
    row = MagicMock()
    row.asDict.return_value = as_dict
    return row


class TestBuildPayload(unittest.TestCase):
    def _spark_client_returning(self, rows):
        spark_client = MagicMock()
        df = MagicMock()
        df.collect.return_value = rows
        spark_client.get_records.return_value = df
        return spark_client

    def _build(self, flat_row=_FLAT_ROW):
        spark_client = self._spark_client_returning([_fake_row(flat_row)])
        return json.loads(
            job.build_payload(spark_client, "reverse_x.google_drive_deep_dive")
        )

    def test_nests_kpis(self):
        payload = self._build()

        self.assertEqual(payload["schema_version"], "1")
        self.assertEqual(payload["as_of"], "2026-09-17T12:00:00Z")
        self.assertEqual(
            payload["kpis"],
            {
                "org_units_with_findings": 2,
                "shared_drives_affected": 96,
                "external_users_with_pii_access": 317,
                "exposed_beyond_domain": 168370,
            },
        )
        self.assertEqual(payload["pii_findings_total"], 433553)
        self.assertEqual(payload["total_findings"], 433576)

    def test_exposed_pct_note_computed_from_kpis(self):
        payload = self._build()

        self.assertEqual(
            payload["exposed_pct_note"],
            "38.8% of findings have at least one external-domain grantee",
        )

    def test_pivots_by_mime_type_into_label_count_mix_ordered_by_count_desc(self):
        payload = self._build()

        self.assertEqual(
            payload["by_mime_type"],
            [
                {
                    "label": "application/pdf",
                    "count": 173926,
                    "mix": {
                        "CRITICAL": 0,
                        "HIGH": 138243,
                        "MEDIUM": 0,
                        "LOW": 35683,
                    },
                },
                {
                    "label": "text/plain",
                    "count": 25686,
                    "mix": {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 25686},
                },
            ],
        )

    def test_top_owners_empty_today_with_note(self):
        payload = self._build()

        self.assertEqual(payload["top_owners"], [])
        self.assertIn("top_owners_note", payload)
        self.assertIn("0% populated", payload["top_owners_note"])

    def test_riskiest_combinations_formats_label_and_sorts_desc(self):
        payload = self._build()

        self.assertEqual(
            [item["label"] for item in payload["riskiest_combinations"]],
            [
                "full_name · EXTERNAL_GRANTEE",
                "address · EXTERNAL_GRANTEE",
                "email · INTERNAL_ONLY",
            ],
        )
        self.assertEqual(
            [item["count"] for item in payload["riskiest_combinations"]],
            [127674, 116929, 200],
        )

    def test_exposure_matrix_shape(self):
        payload = self._build()

        self.assertEqual(
            payload["exposure_matrix"]["sharing_states"],
            ["EXTERNAL_GRANTEE", "INTERNAL_ONLY"],
        )
        self.assertEqual(
            payload["exposure_matrix"]["risk_levels"],
            ["CRITICAL", "HIGH", "MEDIUM", "LOW"],
        )
        self.assertEqual(
            payload["exposure_matrix"]["cells"]["EXTERNAL_GRANTEE"]["CRITICAL"], 5320
        )
        self.assertEqual(
            payload["exposure_matrix"]["cells"]["EXTERNAL_GRANTEE"]["HIGH"], 107844
        )
        self.assertEqual(
            payload["exposure_matrix"]["cells"]["INTERNAL_ONLY"]["CRITICAL"], 30421
        )
        self.assertEqual(
            payload["exposure_matrix"]["cells"]["INTERNAL_ONLY"]["MEDIUM"], 0
        )

    def test_no_forbidden_columns_as_payload_keys(self):
        payload = self._build()

        forbidden = {
            "actor_email",
            "id_resource",
            "resource_name",
            "shared_with",
            "source_raw_payload",
            "email",
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

    def test_no_raw_email_value_outside_the_two_approved_panels(self):
        """
        CORESEC-73: Privacy approved raw (unhashed) emails only in
        top_external_users and top_owners (internal/partner Workspace accounts,
        not customer PII) — every other panel must stay email-free.
        """
        payload = self._build()
        approved_panels = {"top_external_users", "top_owners"}

        def _collect_values(value, out):
            if isinstance(value, dict):
                for nested in value.values():
                    _collect_values(nested, out)
            elif isinstance(value, list):
                for item in value:
                    _collect_values(item, out)
            elif isinstance(value, str):
                out.append(value)

        strings = []
        for key, value in payload.items():
            if key in approved_panels:
                continue
            _collect_values(value, strings)

        for value in strings:
            self.assertIsNone(
                EMAIL_RE.search(value), f"found a raw email-shaped value: {value!r}"
            )

    def test_top_external_users_and_top_owners_carry_raw_email_labels(self):
        flat_row = dict(_FLAT_ROW)
        flat_row["top_owners"] = [
            {"label": "owner.one@quintoandar.com.br", "risk_level": "HIGH", "count": 5},
        ]
        payload = self._build(flat_row)

        self.assertEqual(
            {item["label"] for item in payload["top_external_users"]},
            {"partner.user@partner-domain.com", "someone.else@another-domain.com"},
        )
        self.assertEqual(
            [item["label"] for item in payload["top_owners"]],
            ["owner.one@quintoandar.com.br"],
        )

    def test_raises_when_no_rows(self):
        spark_client = self._spark_client_returning([])

        with self.assertRaises(RuntimeError):
            job.build_payload(spark_client, "reverse_x.google_drive_deep_dive")


class TestMainSkipPaths(unittest.TestCase):
    def test_is_validation_run_true_when_target_args_present(self):
        self.assertTrue(job.is_validation_run("validation_db", "validation_table"))

    def test_is_validation_run_false_when_no_target_args(self):
        self.assertFalse(job.is_validation_run(None, None))

    def test_forno_and_prod_conf_point_at_their_own_buckets(self):
        """
        Bucket/key come from ConfigurationService (per-env conf.yml), not a
        hardcoded dict — guard the conf files directly. These keys live in the
        shared core conf.yml (not a per-DAG conf.yml): EMR jobs never get the
        `dags` package on sys.path, so ConfigurationService can't resolve a
        per-DAG conf.yml there. Both envs share the executive_summary/ prefix
        (and its existing IDPLATF-8284 IAM grant); prod also shares the
        executive summary's bucket (Base44-owned), forno shares its own
        smoke-test bucket.
        """
        repo_root = Path(__file__).resolve().parents[7]
        core_config_dir = (
            repo_root
            / "packages"
            / "bietlejuice-core"
            / "src"
            / "bietlejuice"
            / "config"
        )

        with open(core_config_dir / "forno_conf.yml") as forno_conf_file:
            forno_conf = yaml.safe_load(forno_conf_file)
        with open(core_config_dir / "prod_conf.yml") as prod_conf_file:
            prod_conf = yaml.safe_load(prod_conf_file)

        self.assertEqual(
            forno_conf.get("google_drive_deep_dive_s3_key"),
            "security_data_gateway/executive_summary/google_drive_deep_dive.json",
        )
        self.assertEqual(
            prod_conf.get("google_drive_deep_dive_s3_bucket"), "5a-base44-office"
        )
        self.assertEqual(
            prod_conf.get("google_drive_deep_dive_s3_key"),
            "security_data_gateway/executive_summary/google_drive_deep_dive.json",
        )


if __name__ == "__main__":
    unittest.main()
