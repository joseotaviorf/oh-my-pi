"""Resolve classic gsheets ingest-id task output (Databricks XCom or EMR S3 sidecar)."""

from __future__ import annotations

import json
import logging
from typing import Any, Callable, Optional
from urllib.parse import urlparse

logger = logging.getLogger(__name__)

GSHEETS_INGEST_OUTPUT_PREFIX = "GSHEETS_INGEST_OUTPUT="
# Airflow can GetObject this artifacts prefix (AllowAirflowEmrMigrationArtifacts).
# Do not write under the DAG datalake/people bucket — Airflow cannot read it.
GSHEETS_INGEST_S3_PREFIX = "emr-migration/_gsheets_ingest"


def _normalize_s3_bucket(artifacts_bucket: str) -> str:
    """Return the bucket host from a bare name or ``s3://`` URI."""
    value = artifacts_bucket.strip()
    parsed = urlparse(value)
    if parsed.scheme == "s3":
        return parsed.netloc
    return value.removeprefix("s3://").split("/", 1)[0]


def gsheets_ingest_sidecar_s3_uri(
    artifacts_bucket: str, dag_id: str, run_id: str
) -> str:
    """S3 URI where ``load_modified_gsheets_id`` writes JSON on EMR."""
    bucket = _normalize_s3_bucket(artifacts_bucket)
    return f"s3://{bucket}/{GSHEETS_INGEST_S3_PREFIX}/{dag_id}/{run_id}.json"


def emit_gsheets_ingest_output(
    dbutils: Any,
    output_payload: dict,
    artifacts_bucket: str,
    airflow_dag_id: Optional[str],
    airflow_run_id: Optional[str],
) -> None:
    """Publish ingest-id JSON for Databricks XCom or EMR S3 sidecar + stdout marker."""
    from bietlejuice.base.spark.runtime_detector import RuntimeDetector

    output_str = json.dumps(output_payload)
    if RuntimeDetector.is_emr():
        if airflow_dag_id and airflow_run_id:
            import boto3

            sidecar_uri = gsheets_ingest_sidecar_s3_uri(
                artifacts_bucket, airflow_dag_id, airflow_run_id
            )
            parsed = urlparse(sidecar_uri)
            boto3.client("s3").put_object(
                Bucket=parsed.netloc,
                Key=parsed.path.lstrip("/"),
                Body=output_str.encode("utf-8"),
            )
        print(f"{GSHEETS_INGEST_OUTPUT_PREFIX}{output_str}")
        return
    dbutils.notebook.exit(output_str)


def pull_gsheets_ingest_output_json(
    *,
    task_instance: Any,
    ingest_task_id: str,
    artifacts_bucket: str,
    dag_id: str,
    run_id: str,
    s3_client_factory: Optional[Callable[[], Any]] = None,
) -> Optional[str]:
    """Return ingest-id JSON from XCom or, on EMR, from the S3 sidecar.

    ``s3_client_factory`` is invoked only when XCom is empty. Airflow passes
    ``DatasetService._get_boto3_session_for_dataset_events`` (same assume-role
    as the dataset-events post action).
    """
    output = task_instance.xcom_pull(task_ids=ingest_task_id, key="output")
    if output:
        return output

    sidecar_uri = gsheets_ingest_sidecar_s3_uri(artifacts_bucket, dag_id, run_id)
    try:
        import boto3

        parsed = urlparse(sidecar_uri)
        client = (
            s3_client_factory() if s3_client_factory is not None else boto3.client("s3")
        )
        body = (
            client.get_object(Bucket=parsed.netloc, Key=parsed.path.lstrip("/"))
            .get("Body")
            .read()
            .decode("utf-8")
        )
        json.loads(body)
        return body
    except Exception as exc:
        logger.warning(
            "m=pull_gsheets_ingest_output_json, sidecar=%s, msg=Failed to read sidecar: %s",
            sidecar_uri,
            exc,
        )
        return None
