import sys
from contextlib import contextmanager
from unittest import mock
from unittest.mock import MagicMock, patch

from bietlejuice.services.gsheets_ingest_output import (
    emit_gsheets_ingest_output,
    gsheets_ingest_sidecar_s3_uri,
    pull_gsheets_ingest_output_json,
)


@contextmanager
def _stubbed_runtime_detector(is_emr: bool):
    runtime_detector_module = MagicMock()
    runtime_detector_module.RuntimeDetector.is_emr.return_value = is_emr
    stubs = {
        "bietlejuice.base.spark": MagicMock(),
        "bietlejuice.base.spark.runtime_detector": runtime_detector_module,
    }
    with mock.patch.dict(sys.modules, stubs):
        yield


class TestGsheetsIngestSidecarUri:
    def test_builds_expected_path(self):
        uri = gsheets_ingest_sidecar_s3_uri(
            "prod-datalake", "bietlejuice.gsheets_agents", "manual__2026-01-01"
        )
        assert (
            uri
            == "s3://prod-datalake/_gsheets_ingest/bietlejuice.gsheets_agents/manual__2026-01-01.json"
        )


class TestPullGsheetsIngestOutputJson:
    def test_returns_xcom_when_present(self):
        ti = MagicMock()
        ti.xcom_pull.return_value = '{"success_run": true, "sheets_to_be_ingested": []}'

        result = pull_gsheets_ingest_output_json(
            task_instance=ti,
            ingest_task_id="ingested-gsheets-id-info",
            datalake_bucket="prod-datalake",
            dag_id="bietlejuice.gsheets_agents",
            run_id="manual__2026",
        )

        assert result == '{"success_run": true, "sheets_to_be_ingested": []}'
        ti.xcom_pull.assert_called_once_with(
            task_ids="ingested-gsheets-id-info", key="output"
        )

    def test_reads_s3_sidecar_when_xcom_missing(self):
        ti = MagicMock()
        ti.xcom_pull.return_value = None
        sidecar_body = '{"success_run": true, "sheets_to_be_ingested": ["t1"]}'

        with patch("boto3.client") as mock_boto_client:
            mock_boto_client.return_value.get_object.return_value = {
                "Body": MagicMock(read=MagicMock(return_value=sidecar_body.encode()))
            }
            result = pull_gsheets_ingest_output_json(
                task_instance=ti,
                ingest_task_id="ingested-gsheets-id-info",
                datalake_bucket="prod-datalake",
                dag_id="bietlejuice.gsheets_agents",
                run_id="manual__2026",
            )

        assert result == sidecar_body
        mock_boto_client.return_value.get_object.assert_called_once_with(
            Bucket="prod-datalake",
            Key="_gsheets_ingest/bietlejuice.gsheets_agents/manual__2026.json",
        )


class TestEmitIngestOutput:
    def test_databricks_uses_notebook_exit(self):
        dbutils = MagicMock()
        payload = {"success_run": True, "sheets_to_be_ingested": []}

        with _stubbed_runtime_detector(is_emr=False):
            emit_gsheets_ingest_output(
                dbutils,
                payload,
                "prod-datalake",
                "bietlejuice.gsheets_agents",
                "manual__2026",
            )

        dbutils.notebook.exit.assert_called_once_with(
            '{"success_run": true, "sheets_to_be_ingested": []}'
        )

    def test_emr_writes_sidecar(self):
        dbutils = MagicMock()
        payload = {"success_run": True, "sheets_to_be_ingested": ["t1"]}

        with (
            _stubbed_runtime_detector(is_emr=True),
            patch("boto3.client") as mock_boto_client,
        ):
            emit_gsheets_ingest_output(
                dbutils,
                payload,
                "prod-datalake",
                "bietlejuice.gsheets_agents",
                "manual__2026",
            )

        mock_boto_client.return_value.put_object.assert_called_once()
        dbutils.notebook.exit.assert_not_called()
