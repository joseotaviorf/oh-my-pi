import json
import logging
from argparse import ArgumentParser
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService

# Masterfeed SQS export for reverse_rent_liquidity_score.rent_liquidity_score (rent liquidity score to Masterfeed).
# In dw_liquidity.fact_house_rent_liquidity you will find house_liquidity_score as the value stored in
# rent_liquidity_score: the probability that a house will be rented within 4 weeks after publication.
# The JSON payload exposes that value as rentLiquidityScore (see row_to_message).

JOB_NAME = "load_into_sqs"
SQS_BATCH_SIZE = 10  # send_message_batch API maximum
SQS_REGION = "us-east-1"
MIN_SQS_EXPORT_PARTITIONS = 16

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn


def parse_arguments() -> Tuple[str, str, str, Optional[str], Optional[str]]:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    add_validation_target_args(parser)
    args = parser.parse_args()
    return (
        args.dag_name,
        args.database_name,
        args.table_name,
        args.target_database_name,
        args.target_table_name,
    )


def json_safe_score(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, Decimal):
        return float(value)
    return value


def row_to_message(row) -> Dict[str, Any]:
    # rent_liquidity_score = house_liquidity_score for rent (P(rented within 4 weeks of publication)); JSON key rentLiquidityScore.
    """Build one SQS message: eventDate (epoch ms) and payload with houseId, rentLiquidityModelVersion, rentLiquidityScore."""
    return {
        "eventDate": int(row["eventDate"]),
        "payload": {
            "houseId": int(row["id_house"]),
            "rentLiquidityModelVersion": row["rent_liquidity_model_version"],
            "rentLiquidityScore": json_safe_score(row["rent_liquidity_score"]),
        },
    }


MESSAGE_ATTRIBUTES = {
    "contentType": {"DataType": "String", "StringValue": "application/json"},
}


def _send_sqs_batch(
    sqs_client: Any,
    queue_url: str,
    messages: List[Dict[str, Any]],
) -> Tuple[int, int]:
    """Send up to 10 independent SQS messages via send_message_batch. Returns (success, failed)."""
    if not messages:
        return 0, 0

    entries = [
        {
            "Id": str(idx),
            "MessageBody": json.dumps(message),
            "MessageAttributes": MESSAGE_ATTRIBUTES,
        }
        for idx, message in enumerate(messages)
    ]

    response = sqs_client.send_message_batch(QueueUrl=queue_url, Entries=entries)
    failed = response.get("Failed", [])
    if not failed:
        return len(messages), 0

    success = len(messages) - len(failed)
    retry_messages = [messages[int(entry["Id"])] for entry in failed]
    retry_success, retry_failed = _send_sqs_batch(sqs_client, queue_url, retry_messages)
    return success + retry_success, retry_failed


def _sqs_export_partitions() -> int:
    return max(MIN_SQS_EXPORT_PARTITIONS, spark.sparkContext.defaultParallelism)


def load_table_into_sqs(database_name: str, table_name: str, queue_url: str) -> None:
    logger.info("Loading %s.%s into SQS queue %s", database_name, table_name, queue_url)

    df = spark.table(f"{database_name}.{table_name}")
    df = df.select(
        "id_house",
        "rent_liquidity_model_version",
        "rent_liquidity_score",
        "dt_snapshot",
    )
    df = df.withColumn(
        "eventDate",
        (df["dt_snapshot"].cast("timestamp").cast("long") * 1000),
    )

    if df.rdd.isEmpty():
        logger.info("No rows in %s.%s; skipping SQS export", database_name, table_name)
        return

    success_counter = spark.sparkContext.accumulator(0)
    failure_counter = spark.sparkContext.accumulator(0)

    def send_partition_to_sqs(partition) -> None:
        sqs_client = boto3.client("sqs", region_name=SQS_REGION)
        batch: List[Dict[str, Any]] = []

        for row in partition:
            batch.append(row_to_message(row))
            if len(batch) >= SQS_BATCH_SIZE:
                sent, failed = _send_sqs_batch(sqs_client, queue_url, batch)
                success_counter.add(sent)
                failure_counter.add(failed)
                batch.clear()

        if batch:
            sent, failed = _send_sqs_batch(sqs_client, queue_url, batch)
            success_counter.add(sent)
            failure_counter.add(failed)

    export_partitions = _sqs_export_partitions()
    logger.info(
        "Repartitioning to %s partitions for parallel SQS export", export_partitions
    )
    df.repartition(export_partitions).foreachPartition(send_partition_to_sqs)

    total_success = success_counter.value
    total_failure = failure_counter.value
    total_processed = total_success + total_failure

    logger.info(
        "SQS export complete for %s.%s: processed=%s success=%s failed=%s",
        database_name,
        table_name,
        total_processed,
        total_success,
        total_failure,
    )

    if total_failure > 0:
        raise RuntimeError(
            f"Failed to send {total_failure} of {total_processed} messages to SQS"
        )


def main() -> None:
    dag_name, database_name, table_name, target_database_name, target_table_name = (
        parse_arguments()
    )

    if is_validation_run(target_database_name, target_table_name):
        logger.info(
            f"m={JOB_NAME}, msg=Skipping reverse SQS export in cluster validation mode"
        )
        return

    config_service = ConfigurationService(dag_name)
    queue_url = config_service.get_config("sqs_queue_url")
    load_table_into_sqs(database_name, table_name, queue_url)


if __name__ == "__main__":
    main()
