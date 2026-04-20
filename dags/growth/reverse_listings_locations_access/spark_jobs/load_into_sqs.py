import json
import logging
from argparse import ArgumentParser
from typing import Dict, List, Tuple

import boto3

from bietlejuice.services import ConfigurationService
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_into_sqs"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

MAX_MESSAGE_SIZE_BYTES = (
    246 * 1024
)  # SQS maximum message size is 256KB, we'll use 246KB as a safe limit

VALID_BUSINESS_CONTEXTS = {"RENT", "SALE"}


def parse_arguments() -> Tuple[str, str, str]:
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")

    args = parser.parse_args()

    return args.dag_name, args.database_name, args.table_name


def is_valid(row) -> bool:
    mandatory_fields = [
        "city",
        "city_id",
        "business_contexts",
        "count_rent",
        "count_sale",
        "navent_count_rent",
        "navent_count_sale",
        "state",
        "state_code",
        "country_code",
        "country",
        "centroid_lat",
        "centroid_lng",
    ]

    for field in mandatory_fields:
        if not hasattr(row, field):
            return False

        value = getattr(row, field)
        if not value and value != 0:
            return False

    mandatory_coordinates = ["centroid_lat", "centroid_lng"]

    for field in mandatory_coordinates:
        if not hasattr(row, field) or getattr(row, field) is None:
            return False

    if not isinstance(row.business_contexts, (list, set)):
        return False

    if not row.business_contexts:
        return False

    if not set(row.business_contexts).issubset(VALID_BUSINESS_CONTEXTS):
        return False

    if not isinstance(row.city_id, int) or row.city_id <= 0:
        return False

    count_fields = [
        "count_rent",
        "count_sale",
        "navent_count_rent",
        "navent_count_sale",
    ]
    for field in count_fields:
        if not isinstance(getattr(row, field), int) or getattr(row, field) < 0:
            return False

    return True


def row_to_dict(row) -> Dict:
    return {
        "street": row.street if row.street else None,
        "neighborhood": row.neighborhood if row.neighborhood else None,
        "neighborhood_id": int(row.neighborhood_id) if row.neighborhood_id else None,
        "city": row.city,
        "city_id": row.city_id,
        "business_contexts": row.business_contexts,
        "count_rent": int(row.count_rent),
        "count_sale": int(row.count_sale),
        "navent_count_rent": int(row.navent_count_rent),
        "navent_count_sale": int(row.navent_count_sale),
        "state": row.state,
        "state_code": row.state_code,
        "country_code": row.country_code,
        "country": row.country,
        "centroid_lat": float(row.centroid_lat),
        "centroid_lng": float(row.centroid_lng),
    }


def batch_rows_into_messages(rows: List) -> List[List[Dict]]:
    JSON_OVERHEAD_PER_ITEM = 2

    batches = []
    current_batch = []
    current_batch_size = 0

    for row in rows:
        if not is_valid(row):
            continue

        row_dict = row_to_dict(row)
        item_size = len(json.dumps(row_dict).encode("utf-8")) + JSON_OVERHEAD_PER_ITEM
        potential_new_size = current_batch_size + item_size

        if potential_new_size >= MAX_MESSAGE_SIZE_BYTES:
            if current_batch:
                batches.append(current_batch)

            current_batch = [row_dict]
            current_batch_size = item_size

        else:
            current_batch.append(row_dict)
            current_batch_size = potential_new_size

    if current_batch:
        batches.append(current_batch)

    return batches


def send_batch_to_sqs(
    sqs_client, queue_url: str, batch: List[Dict], logger_instance: logging.Logger
) -> Tuple[int, int]:
    message_attributes = {
        "contentType": {"DataType": "String", "StringValue": "application/json"},
        "X-Tenant-ID": {"DataType": "String", "StringValue": "quintoandar"},
    }

    logger_instance.info(f"Sending batch to SQS, batch_size={len(batch)}")

    try:
        message_body = json.dumps(batch)
        sqs_client.send_message(
            QueueUrl=queue_url,
            MessageBody=message_body,
            MessageAttributes=message_attributes,
        )
        return 1, 0
    except Exception as e:
        logger_instance.error(
            f"Error sending batch to SQS: {e}, batch_size={len(batch)}"
        )
        return 0, 1


def process_partition_to_sqs(partition, queue_url: str):
    partition_logger = logging.getLogger(JOB_NAME)
    sqs_client = boto3.client("sqs", region_name="us-east-1")

    partition_rows = list(partition)

    if not partition_rows:
        return

    batches = batch_rows_into_messages(partition_rows)

    for batch in batches:
        send_batch_to_sqs(sqs_client, queue_url, batch, partition_logger)


def load_table_into_sqs(database_name: str, table_name: str, queue_url: str) -> None:
    logger.info(f"Loading table {database_name}.{table_name} into SQS")

    df = spark.table(f"{database_name}.{table_name}")

    df.foreachPartition(
        lambda partition: process_partition_to_sqs(partition, queue_url)
    )

    logger.info(
        f"Completed processing and sending data from "
        f"{database_name}.{table_name} to SQS"
    )


def main():
    dag_name, database_name, table_name = parse_arguments()

    config_service = ConfigurationService(dag_name)
    queue_url = config_service.get_config("sqs_queue_url")

    load_table_into_sqs(database_name, table_name, queue_url)


if __name__ == "__main__":
    main()
