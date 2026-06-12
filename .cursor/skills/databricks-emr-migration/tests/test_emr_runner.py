import unittest
from unittest.mock import patch

from emr_runner import (
    SqlStager,
    describe_cluster_json,
    parse_result_json,
    resolve_result_from_output,
)


class TestEmrRunner(unittest.TestCase):
    def test_parse_result_json_line(self) -> None:
        payload = {"count": 42, "schema": [], "sample": []}
        text = 'Step finished: COMPLETED\nRESULT_JSON={"count": 42, "schema": [], "sample": []}\n'
        self.assertEqual(parse_result_json(text), payload)

    def test_resolve_result_from_output_prefers_stdout(self) -> None:
        payload = {"count": 1, "schema": [], "sample": []}
        output = f'RESULT_JSON={{"count": 1, "schema": [], "sample": []}}'
        result, error = resolve_result_from_output(
            output,
            returncode=0,
            result_s3_uri="s3://bucket/key.json",
        )
        self.assertEqual(result, payload)
        self.assertIsNone(error)

    def test_emr_result_uri_for(self) -> None:
        with patch("emr_runner.load_staging_uri", return_value="s3://bucket/emr/staging/cli/"):
            stager = SqlStager(run_id="abc123", emr_env="prod")
        uri = stager.emr_result_uri_for(
            "fintech",
            "dw_credit_analysis",
            "dw",
            "dim_drop_reason",
        )
        self.assertEqual(
            uri,
            "s3://bucket/emr/staging/cli/migration-validate/abc123/"
            "fintech/dw_credit_analysis/dw/dim_drop_reason.emr.json",
        )

    def test_result_uri_for_legacy_alias(self) -> None:
        with patch("emr_runner.load_staging_uri", return_value="s3://bucket/emr/staging/cli/"):
            stager = SqlStager(run_id="abc123", emr_env="prod")
        self.assertEqual(
            stager.result_uri_for("fintech", "dw_credit_analysis", "dw", "dim_drop_reason"),
            stager.emr_result_uri_for("fintech", "dw_credit_analysis", "dw", "dim_drop_reason"),
        )

    def test_baseline_and_manifest_uris(self) -> None:
        with patch("emr_runner.load_staging_uri", return_value="s3://bucket/emr/staging/cli/"):
            stager = SqlStager(run_id="abc123", emr_env="prod")
        self.assertTrue(stager.baseline_uri_for("fintech", "dag", "dw", "t").endswith(".baseline.json"))
        self.assertTrue(stager.manifest_uri().endswith("/manifest.json"))

    def test_result_uri_for_isolated_by_layer(self) -> None:
        with patch("emr_runner.load_staging_uri", return_value="s3://bucket/emr/staging/cli/"):
            stager = SqlStager(run_id="abc123", emr_env="prod")
        dw_uri = stager.result_uri_for("fintech", "my_dag", "dw", "events")
        enrich_uri = stager.result_uri_for("fintech", "my_dag", "enrich", "events")
        self.assertNotEqual(dw_uri, enrich_uri)

    def test_describe_cluster_json_raises_on_cli_failure(self) -> None:
        with patch(
            "emr_runner.run_emr_cli",
            return_value=(1, "ExpiredToken"),
        ):
            with self.assertRaises(RuntimeError):
                describe_cluster_json("j-ABC123")


if __name__ == "__main__":
    unittest.main()
