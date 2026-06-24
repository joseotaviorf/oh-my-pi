"""Shared AppFlow status marker contract.

Both the Spark pipeline that **writes** the marker
(``bietlejuice.base.sst.pipelines.salesforce.check_appflow_status``) and the
Airflow operator that **reads** it
(``bietlejuice.base.sst.airflow.operators.appflow_status_branch_operator``)
depend on this module so the on-disk shape stays in lock step.

Marker layout in S3::

    s3://<bucket>/<marker_prefix>/<target_table>/<partition_date>/<partition_hour>/<target_table>.json

Payload (JSON)::

    {
      "flow_name":      "<AppFlow flow name>",
      "event_path":     "<event_path config value>",
      "target_table":   "<target_table>",
      "partition_date": "<YYYY-MM-DD>",
      "partition_hour": "<HH>",
      "status":         "<flowStatus, empty when describe_flow failed>",
      "error":          "<error string or null>"
    }
"""

import json
from datetime import datetime, timezone
from typing import Optional, Union

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.utils.time import build_hour_window, standard_now

logger = QuintoAndarLogger("sst.core.appflow.marker")

ACTIVE_STATUS = "Active"
DEFAULT_REGION = "us-east-1"
DEFAULT_MARKER_PREFIX = "sst_runtime/appflow_status"


def extract_flow_name(event_path: str) -> str:
    """Return the AppFlow flow name encoded in ``event_path``.

    The flow name is the last segment after ``/`` in the configured
    ``event_path`` (e.g. ``raw/salesforce/CaseEvent`` -> ``CaseEvent``).
    """
    if not event_path:
        raise ValueError("event_path is empty; cannot derive AppFlow flow name.")
    return event_path.rstrip("/").rsplit("/", 1)[-1]


def build_marker_key(
    partition_date: str,
    partition_hour: str,
    target_table: str,
    marker_prefix: str = DEFAULT_MARKER_PREFIX,
) -> str:
    """Build the S3 key (without bucket) for the AppFlow status marker file."""
    prefix = marker_prefix.strip("/")
    return (
        f"{prefix}/{target_table}/{partition_date}/{partition_hour}/{target_table}.json"
    )


def write_status_marker(
    bucket: str, key: str, payload: dict, region_name: str = DEFAULT_REGION
) -> None:
    """Write ``payload`` as JSON to ``s3://bucket/key``."""
    s3_client = boto3.client("s3", region_name=region_name)
    s3_client.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(payload).encode("utf-8"),
        ContentType="application/json",
    )


def read_status_marker(
    bucket: str, key: str, region_name: str = DEFAULT_REGION
) -> dict:
    """Read and parse the JSON status marker from ``s3://bucket/key``."""
    s3_client = boto3.client("s3", region_name=region_name)
    response = s3_client.get_object(Bucket=bucket, Key=key)
    body = response["Body"].read()
    return json.loads(body.decode("utf-8"))


def describe_flow_status(flow_name: str, region_name: str = DEFAULT_REGION) -> str:
    """Return the current ``flowStatus`` reported by AppFlow for ``flow_name``."""
    client = boto3.client("appflow", region_name=region_name)
    response = client.describe_flow(flowName=flow_name)
    return response.get("flowStatus", "")


def parse_utc_ts(value: Optional[Union[str, datetime]]) -> Optional[datetime]:
    if value is None:
        return None

    if isinstance(value, datetime):
        return value.astimezone(timezone.utc)

    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def appflow_has_completed_hour(
    appflow_status: dict,
    partition_date: str,
    partition_hour: str,
) -> bool:
    _, expected_end_ts = build_hour_window(
        partition_date=partition_date,
        partition_hour=partition_hour,
    )

    last_execution_ts = parse_utc_ts(appflow_status.get("last_execution_timestamp"))
    expected_end_ts = parse_utc_ts(expected_end_ts)

    if last_execution_ts is None:
        logger.info(
            "m=appflow_has_completed_hour, msg=No last_execution_timestamp; "
            f"partition={partition_date} {partition_hour}"
        )
        return False

    completed_hour = last_execution_ts >= expected_end_ts
    logger.info(
        f"m=appflow_has_completed_hour, msg=partition={partition_date} {partition_hour} "
        f"last_execution_ts={last_execution_ts.isoformat()} "
        f"expected_end_ts={expected_end_ts.isoformat()} "
        f"flow_status={appflow_status.get('flow_status')!r} "
        f"last_execution_status={appflow_status.get('last_execution_status')!r} "
        f"completed_hour={completed_hour}"
    )

    return completed_hour


def get_latest_appflow_run(flow_name: str, region_name: str = DEFAULT_REGION) -> dict:
    client = boto3.client("appflow", region_name=region_name)

    request_time = standard_now()
    response = client.describe_flow(flowName=flow_name)
    last_run = response.get("lastRunExecutionDetails", {})

    return {
        "request_time": request_time,
        "flow_status": response.get("flowStatus", ""),
        "last_execution_status": last_run.get("mostRecentExecutionStatus"),
        "last_execution_timestamp": last_run.get("mostRecentExecutionTime").astimezone(
            timezone.utc
        ),
        "last_execution_message": last_run.get("mostRecentExecutionMessage"),
    }


def format_metric_payload(flow_name, appflow_payload, completed_hour, run_recovery):
    last_execution_ts = appflow_payload.get("last_execution_timestamp")
    last_execution_ts_str = (
        last_execution_ts.strftime("%Y-%m-%d %H:%M:%S")
        if last_execution_ts is not None
        else None
    )

    return {
        "name": flow_name,
        "status": appflow_payload.get("flow_status"),
        "request_time": appflow_payload.get("request_time"),
        "last_execution_status": appflow_payload.get("last_execution_status"),
        "last_execution_timestamp": last_execution_ts_str,
        "last_execution_message": appflow_payload.get("last_execution_message"),
        "has_completed_hour": completed_hour,
        "run_recovery": run_recovery,
    }


def save_appflow_metrics(
    spark,
    partition_date,
    partition_hour,
    job_name,
    payload,
    bucket,
    sync_hive=True,
):
    from pyspark.sql.types import StringType, StructField, StructType

    from bietlejuice.base.sst.core.utils.common import validate_and_write

    rows = {
        **payload,
        "partition_date": partition_date,
        "partition_hour": partition_hour,
        "job_name": job_name,
    }

    fields = [
        ("name", False),
        ("request_time", False),
        ("status", False),
        ("last_execution_status", True),
        ("last_execution_timestamp", True),
        ("last_execution_message", True),
        ("run_recovery", True),
        ("partition_date", False),
        ("partition_hour", True),
        ("job_name", False),
    ]

    schema = StructType(
        [
            StructField(name, StringType(), nullable=nullable)
            for name, nullable in fields
        ]
    )

    full_table_name = "datalake_sst_metrics.appflow_status"
    table_location = f"s3a://{bucket}/sst_metrics/appflow_status"
    df = spark.createDataFrame([rows], schema=schema).withColumn(
        "write_timestamp", standard_now(is_col=True)
    )
    validate_and_write(
        spark=spark,
        df=df,
        target_table=full_table_name,
        table_location=table_location,
        partition_filter=None,
        partition_cols=None,
        overwrite_schema=False,
        append=True,
        sync_hive=sync_hive,
        sync_secondary_catalog=True,
    )


def save_status_marker_as_table(
    spark,
    payload: dict,
    bucket: str,
    sync_hive: bool = True,
) -> None:
    """Persist the AppFlow status marker payload as a Delta table row.

    Writes the same data produced by :func:`write_status_marker` (the S3 JSON
    marker) into the ``datalake_sst_metrics.appflow_status`` Delta table so the
    status history is queryable via Trino and, optionally, synced to the Hive
    metastore.

    Spark imports are intentionally lazy so that this module remains safe to
    import in non-Spark contexts (e.g. the Airflow operator).

    Parameters
    ----------
    spark :
        Active ``SparkSession``.
    payload : dict
        Marker payload as built by the upstream check pipeline. Must contain
        ``target_table``, ``partition_date``, and ``partition_hour`` for the
        partition write, plus ``flow_name``, ``event_path``, ``status``, and
        ``error``.
    bucket : str
        S3 bucket used to resolve the Delta table location
        (``s3a://<bucket>/sst_metrics/appflow_status``).
    sync_hive : bool, optional
        When ``True``, syncs the table to the Hive/Trino metastore after
        writing. Defaults to ``True``.
    """

    from pyspark.sql.types import StringType, StructField, StructType

    from bietlejuice.base.sst.core.utils.common import (
        build_partition_filter,
        validate_and_write,
    )

    full_table_name = "datalake_sst_metrics.appflow_status"
    table_location = f"s3a://{bucket}/sst_metrics/appflow_status_marker"

    row = {
        **payload,
        "_write_timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }

    fields = [
        ("flow_name", True),
        ("event_path", True),
        ("target_table", False),
        ("partition_date", False),
        ("partition_hour", False),
        ("status", True),
        ("error", True),
        ("_write_timestamp", False),
    ]

    schema = StructType(
        [
            StructField(name, StringType(), nullable=nullable)
            for name, nullable in fields
        ]
    )

    df = spark.createDataFrame([row], schema=schema)

    partition_cols = ["partition_date", "partition_hour", "target_table"]
    partition_filter = build_partition_filter(
        {
            "target_table": payload["target_table"],
            "partition_date": payload["partition_date"],
            "partition_hour": payload["partition_hour"],
        }
    )

    validate_and_write(
        spark=spark,
        df=df,
        target_table=full_table_name,
        table_location=table_location,
        partition_filter=partition_filter,
        partition_cols=partition_cols,
        overwrite_schema=False,
        append=False,
        sync_hive=sync_hive,
    )
