import json
import logging
from argparse import ArgumentParser
from datetime import date, datetime, timedelta
from typing import Dict, Iterable, Iterator, List, Optional, Tuple

import boto3
from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.reverse_metastore_mapping import ReverseMetastoreMapping
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_gsc_metrics_into_sqs"
STATE_TABLE_NAME = "gsc_page_metrics_state"
MAX_ITEMS_PER_MESSAGE = 500
MAX_MESSAGE_SIZE_BYTES = 246 * 1024
METRIC_WINDOWS = ("7d", "30d", "90d")
METRIC_FIELDS = ("click", "impression", "ctr", "position", "posimp")
SNAPSHOT_LAG_DAYS = 7
METRIC_COLUMNS = tuple(
    f"gsc_{window}_{field}" for window in METRIC_WINDOWS for field in METRIC_FIELDS
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn


def parse_arguments() -> Tuple[str, str, str, str, str, Optional[str], Optional[str]]:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name", help="Name of the access DAG")
    parser.add_argument("datalake_bucket", help="Environment datalake bucket")
    parser.add_argument("database_name", help="Reverse database containing metrics")
    parser.add_argument("table_name", help="Current GSC metrics table")
    parser.add_argument("reference_date", help="DAG reference date")
    add_validation_target_args(parser)
    args = parser.parse_args()
    return (
        args.dag_name,
        args.datalake_bucket,
        args.database_name,
        args.table_name,
        args.reference_date,
        args.target_database_name,
        args.target_table_name,
    )


def _iso_ref_date(value) -> str:
    if isinstance(value, datetime):
        value = value.date()
    if isinstance(value, date):
        return f"{value.isoformat()}T00:00:00Z"
    return f"{value}T00:00:00Z"


def _window_payload(row, window: str, updated_at: str) -> Dict:
    return {
        "click": int(getattr(row, f"gsc_{window}_click")),
        "impression": int(getattr(row, f"gsc_{window}_impression")),
        "ctr": float(getattr(row, f"gsc_{window}_ctr")),
        "position": float(getattr(row, f"gsc_{window}_position")),
        "posimp": float(getattr(row, f"gsc_{window}_posimp")),
        "updated_at": updated_at,
    }


def build_payload(row) -> Dict:
    page_id = row.page_id
    if not page_id:
        raise ValueError("page_id must be present before publishing GSC metrics")
    updated_at = _iso_ref_date(row.ref_date)
    return {
        "id": page_id,
        "data": {
            "metrics": {
                "gsc": {
                    window: _window_payload(row, window, updated_at)
                    for window in METRIC_WINDOWS
                }
            }
        },
    }


def _serialized_size(payloads: List[Dict]) -> int:
    return len(json.dumps(payloads, separators=(",", ":")).encode("utf-8"))


def batch_payloads(
    payloads: Iterable[Dict],
    max_items: int = MAX_ITEMS_PER_MESSAGE,
    max_message_size_bytes: int = MAX_MESSAGE_SIZE_BYTES,
) -> Iterator[List[Dict]]:
    current_batch: List[Dict] = []
    for payload in payloads:
        if _serialized_size([payload]) > max_message_size_bytes:
            raise ValueError(
                f"One GSC metrics payload exceeds {max_message_size_bytes} bytes"
            )
        candidate = current_batch + [payload]
        if (
            len(candidate) > max_items
            or _serialized_size(candidate) > max_message_size_bytes
        ):
            yield current_batch
            current_batch = [payload]
        else:
            current_batch = candidate
    if current_batch:
        yield current_batch


def send_payload_batch(sqs_client, queue_url: str, batch: List[Dict]) -> None:
    sqs_client.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps(batch, separators=(",", ":")),
        MessageAttributes={
            "contentType": {
                "DataType": "String",
                "StringValue": "application/json",
            },
            "X-Tenant-ID": {
                "DataType": "String",
                "StringValue": "quintoandar",
            },
            "X-Missing-Routing": {
                "DataType": "String",
                "StringValue": "true",
            },
        },
    )


def _with_metrics_hash(dataframe: DataFrame) -> DataFrame:
    metrics_struct = F.struct(
        *[F.col(column_name).alias(column_name) for column_name in METRIC_COLUMNS]
    )
    return dataframe.withColumn(
        "metrics_hash",
        F.sha2(F.to_json(metrics_struct), 256),
    )


def _snapshot_ref_date(reference_date: str) -> date:
    """Close the snapshot before GSC's seven-day mutable period."""
    return date.fromisoformat(reference_date) - timedelta(days=SNAPSHOT_LAG_DAYS)


def _current_snapshot(
    database_name: str, table_name: str, reference_date: str
) -> DataFrame:
    snapshot_ref_date = _snapshot_ref_date(reference_date)
    current = spark.table(f"{database_name}.{table_name}")
    snapshot = current.filter(F.col("ref_date") == F.lit(snapshot_ref_date))
    if snapshot.limit(1).count() == 0:
        raise ValueError(
            f"{database_name}.{table_name} has no GSC metrics rows for "
            f"ref_date={snapshot_ref_date}"
        )
    return _with_metrics_hash(snapshot)


def _changed_rows(current: DataFrame, state_table: str) -> DataFrame:
    if not spark.catalog.tableExists(state_table):
        return current
    state = spark.table(state_table).select(
        "page_id",
        F.col("metrics_hash").alias("published_metrics_hash"),
    )
    return (
        current.alias("current")
        .join(state.alias("state"), on="page_id", how="left")
        .filter(
            F.col("state.published_metrics_hash").isNull()
            | (F.col("current.metrics_hash") != F.col("state.published_metrics_hash"))
        )
        .select("current.*")
    )


def _persist_published_state(
    changed: DataFrame,
    database_name: str,
    datalake_bucket: str,
) -> None:
    reverse_info = ReverseMetastoreMapping(
        database_name.removeprefix("reverse_"),
        datalake_bucket,
    ).get_all_reverse_info()
    state_updates = changed.select(
        "page_id",
        "metrics_hash",
        "ref_date",
    ).withColumn("published_at", F.current_timestamp())
    DeltaLoader(spark_client.conn).load_table(
        table_name=f"{database_name}.{STATE_TABLE_NAME}",
        path=f"{reverse_info['reverse_schema_path']}{STATE_TABLE_NAME}",
        source_df=state_updates,
        merge_on=["page_id"],
    )
    MetastoreServiceFactory.create_loader_metastore_service(spark_client).refresh_table(
        database_name, STATE_TABLE_NAME
    )


def publish_changed_metrics(
    datalake_bucket: str,
    database_name: str,
    table_name: str,
    queue_url: str,
    reference_date: str,
) -> None:
    state_table = f"{database_name}.{STATE_TABLE_NAME}"
    changed = _changed_rows(
        _current_snapshot(database_name, table_name, reference_date),
        state_table,
    ).cache()
    changed_count = changed.count()
    if changed_count == 0:
        logger.info("No changed GSC page metrics to publish")
        changed.unpersist()
        return

    message_count = 0
    try:
        sqs_client = boto3.client("sqs", region_name="us-east-1")
        payloads = (build_payload(row) for row in changed.toLocalIterator())
        for batch in batch_payloads(payloads):
            send_payload_batch(sqs_client, queue_url, batch)
            message_count += 1
        _persist_published_state(changed, database_name, datalake_bucket)
    finally:
        changed.unpersist()
    logger.info(f"Published {changed_count} GSC pages in {message_count} SQS messages")


def main() -> None:
    (
        dag_name,
        datalake_bucket,
        database_name,
        table_name,
        reference_date,
        target_database_name,
        target_table_name,
    ) = parse_arguments()
    if is_validation_run(target_database_name, target_table_name):
        logger.info("Skipping GSC SQS export in cluster validation mode")
        return
    queue_url = ConfigurationService(dag_name).get_config("sqs_queue_url")
    publish_changed_metrics(
        datalake_bucket,
        database_name,
        table_name,
        queue_url,
        reference_date,
    )


if __name__ == "__main__":
    main()
