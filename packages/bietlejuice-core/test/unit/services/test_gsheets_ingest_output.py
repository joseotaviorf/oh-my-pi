import sys
from contextlib import contextmanager
from unittest import mock
from unittest.mock import MagicMock, patch

from bietlejuice.services.gsheets_ingest_output import (
    emit_gsheets_ingest_output,
    gsheets_ingest_sidecar_s3_uri,
    pull_gsheets_ingest_output_json,
)

PROD_ARTIFACTS_URI = "s3://artifacts.s3.data.quintoandar.com.br"
PROD_ARTIFACTS_BUCKET = "artifacts.s3.data.quintoandar.com.br"
SIDECAR_KEY = (
    "emr-migration/_gsheets_ingest/bietlejuice.gsheets_agents/manual__2026.json"
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
    def test_builds_expected_path_from_bare_bucket(self):
        uri = gsheets_ingest_sidecar_s3_uri(
            PROD_ARTIFACTS_BUCKET,
            "bietlejuice.gsheets_agents",
            "manual__2026-01-01",
        )
        assert uri == (
            "s3://artifacts.s3.data.quintoandar.com.br/"
            "emr-migration/_gsheets_ingest/"
            "bietlejuice.gsheets_agents/manual__2026-01-01.json"
        )

    def test_strips_s3_scheme_from_configuration_service_value(self):
        uri = gsheets_ingest_sidecar_s3_uri(
            PROD_ARTIFACTS_URI,
            "bietlejuice.gsheets_people__validation",
            "val__20260825220013_d917",
        )
        assert uri == (
            "s3://artifacts.s3.data.quintoandar.com.br/"
            "emr-migration/_gsheets_ingest/"
            "bietlejuice.gsheets_people__validation/val__20260825220013_d917.json"
        )

    def test_does_not_write_under_people_or_datalake_bucket(self):
        uri = gsheets_ingest_sidecar_s3_uri(
            PROD_ARTIFACTS_URI,
            "bietlejuice.gsheets_people__validation",
            "val__20260825220013_d917",
        )
        assert "people-s3" not in uri
        assert "5a-datalake" not in uri
        assert uri.startswith("s3://artifacts.s3.data.quintoandar.com.br/")
        assert "/emr-migration/_gsheets_ingest/" in uri


class TestPullGsheetsIngestOutputJson:
    def test_returns_xcom_when_present(self):
        ti = MagicMock()
        ti.xcom_pull.return_value = '{"success_run": true, "sheets_to_be_ingested": []}'

        result = pull_gsheets_ingest_output_json(
            task_instance=ti,
            ingest_task_id="ingested-gsheets-id-info",
            artifacts_bucket=PROD_ARTIFACTS_URI,
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
                artifacts_bucket=PROD_ARTIFACTS_URI,
                dag_id="bietlejuice.gsheets_agents",
                run_id="manual__2026",
            )

        assert result == sidecar_body
        mock_boto_client.return_value.get_object.assert_called_once_with(
            Bucket=PROD_ARTIFACTS_BUCKET,
            Key=SIDECAR_KEY,
        )


class TestEmitIngestOutput:
    def test_databricks_uses_notebook_exit(self):
        dbutils = MagicMock()
        payload = {"success_run": True, "sheets_to_be_ingested": []}

        with _stubbed_runtime_detector(is_emr=False):
            emit_gsheets_ingest_output(
                dbutils,
                payload,
                PROD_ARTIFACTS_URI,
                "bietlejuice.gsheets_agents",
                "manual__2026",
            )

        dbutils.notebook.exit.assert_called_once_with(
            '{"success_run": true, "sheets_to_be_ingested": []}'
        )

    def test_emr_writes_sidecar_to_artifacts_emr_migration_prefix(self):
        dbutils = MagicMock()
        payload = {"success_run": True, "sheets_to_be_ingested": ["t1"]}

        with (
            _stubbed_runtime_detector(is_emr=True),
            patch("boto3.client") as mock_boto_client,
        ):
            emit_gsheets_ingest_output(
                dbutils,
                payload,
                PROD_ARTIFACTS_URI,
                "bietlejuice.gsheets_agents",
                "manual__2026",
            )

        mock_boto_client.return_value.put_object.assert_called_once_with(
            Bucket=PROD_ARTIFACTS_BUCKET,
            Key=SIDECAR_KEY,
            Body=b'{"success_run": true, "sheets_to_be_ingested": ["t1"]}',
        )
        dbutils.notebook.exit.assert_not_called()

    def test_emr_does_not_put_object_on_people_bucket(self):
        dbutils = MagicMock()
        payload = {"success_run": True, "sheets_to_be_ingested": []}

        with (
            _stubbed_runtime_detector(is_emr=True),
            patch("boto3.client") as mock_boto_client,
        ):
            emit_gsheets_ingest_output(
                dbutils,
                payload,
                PROD_ARTIFACTS_URI,
                "bietlejuice.gsheets_people__validation",
                "val__20260825220013_d917",
            )

        put_kwargs = mock_boto_client.return_value.put_object.call_args.kwargs
        assert put_kwargs["Bucket"] == PROD_ARTIFACTS_BUCKET
        assert put_kwargs["Bucket"] != "people-s3-data-quintoandar-com-br"
        assert put_kwargs["Key"].startswith("emr-migration/_gsheets_ingest/")
