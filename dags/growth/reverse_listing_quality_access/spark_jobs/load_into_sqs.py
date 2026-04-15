"""
Sends listing_quality table rows to the MainListingQuality SQS queue.
Consumed by main-sqs-consumers application.
"""
import json
import logging
from argparse import ArgumentParser
from typing import Any, Dict, Tuple, Type, TypeVar

import boto3

from bietlejuice.services import ConfigurationService
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_into_sqs"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

T = TypeVar("T")

def safe_cast(value: str | None, target_type: Type[T]) -> T | None:
    return target_type(value) if value is not None else None

def parse_arguments() -> Tuple[str, str, str]:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    args = parser.parse_args()
    return args.dag_name, args.database_name, args.table_name


def row_to_message(row: Any) -> Dict[str, Any]:
    """Transform a listing_quality row to the payload expected by main-sqs-consumers."""
    return {
        "houseId": safe_cast(row.house_id, int),
        "jobId": safe_cast(row.job_id, int),
        "commentPhotographer": safe_cast(row.photographer_comment, str),
        "videoLink": safe_cast(row.link_video, str),
        "numInternalPhotos": safe_cast(row.num_internal_photos, int),
        "numBathroomPhotos": safe_cast(row.num_bathroom_photos, int),
        "imagesPerRoom": safe_cast(row.images_per_room, float),
        "propertyCondition": safe_cast(row.property_condition, float),
        "hasPlaque": safe_cast(row.has_plaque, bool),
        "analystQueue": safe_cast(row.analyst_queue, int),
    }


def main() -> None:
    dag_name, database_name, table_name = parse_arguments()

    config_service = ConfigurationService(dag_name)
    queue_url = config_service.get_config("sqs_queue_url")
    if not queue_url:
        raise ValueError(
            "sqs_queue_url must be set in prod_conf.yml or forno_conf.yml"
        )

    logger.info(f"Loading {database_name}.{table_name} into SQS")

    df = spark.table(f"{database_name}.{table_name}")
    rows = df.collect()

    sqs_client = boto3.client("sqs", region_name="us-east-1")
    message_attributes = {
        "contentType": {"DataType": "String", "StringValue": "application/json"},
        "X-Tenant-ID": {"DataType": "String", "StringValue": "quintoandar"},
    }

    sent = 0
    failed = 0
    for row in rows:
        try:
            message_body = json.dumps(row_to_message(row))
            sqs_client.send_message(
                QueueUrl=queue_url,
                MessageBody=message_body,
                MessageAttributes=message_attributes,
            )
            sent += 1
        except Exception as e:
            logger.error(f"Failed to send message: {e}")
            failed += 1

    logger.info(f"Sent {sent} messages to SQS, {failed} failed")


if __name__ == "__main__":
    main()
