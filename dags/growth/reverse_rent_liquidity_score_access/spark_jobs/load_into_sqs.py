import json
import logging
from argparse import ArgumentParser
from decimal import Decimal
from typing import Any, Dict, List, Tuple

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.configuration_service import ConfigurationService

# Masterfeed SQS export for reverse_rent_liquidity_score.rent_liquidity_score (rent liquidity score to Masterfeed).
# In dw_liquidity.fact_house_rent_liquidity you will find house_liquidity_score as the value stored in
# rent_liquidity_score: the probability that a house will be rented within 4 weeks after publication.
# The JSON payload exposes that value as rentLiquidityScore (see transform_payload).

JOB_NAME = "load_into_sqs"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments() -> Tuple[str, str, str]:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    args = parser.parse_args()
    return args.dag_name, args.database_name, args.table_name


def json_safe_score(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, Decimal):
        return float(value)
    return value


def transform_payload(database_name: str, table_name: str) -> List[Dict[str, Any]]:
    # rent_liquidity_score = house_liquidity_score for rent (P(rented within 4 weeks of publication)); JSON key rentLiquidityScore.
    """Build JSON messages: eventDate (epoch ms) and payload with houseId, rentLiquidityModelVersion, rentLiquidityScore."""
    logger.info("Transforming payload for %s.%s", database_name, table_name)
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
    rows = df.collect()
    return [
        {
            "eventDate": int(row["eventDate"]),
            "payload": {
                "houseId": int(row["id_house"]),
                "rentLiquidityModelVersion": row["rent_liquidity_model_version"],
                "rentLiquidityScore": json_safe_score(row["rent_liquidity_score"]),
            },
        }
        for row in rows
    ]


def send_messages(
    sqs_client: Any, queue_url: str, messages: List[Dict[str, Any]]
) -> None:
    logger.info("Sending messages to SQS queue %s", queue_url)
    message_attributes = {
        "contentType": {"DataType": "String", "StringValue": "application/json"},
    }
    last_message: Dict[str, Any] = {}
    try:
        for last_message in messages:
            message_body = json.dumps(last_message)
            logger.info("Sending message to SQS: %s", message_body)
            sqs_client.send_message(
                QueueUrl=queue_url,
                MessageBody=message_body,
                MessageAttributes=message_attributes,
            )
        logger.info("Messages sent successfully")
    except Exception as e:
        logger.error("Error sending message to SQS: %s", e)
        logger.error("The last message attempted was %s", last_message)
        raise


def main() -> None:
    dag_name, database_name, table_name = parse_arguments()
    config_service = ConfigurationService(dag_name)
    queue_url = config_service.get_config("sqs_queue_url")
    payload = transform_payload(database_name, table_name)
    sqs = boto3.client("sqs", region_name="us-east-1")
    send_messages(sqs, queue_url, payload)


if __name__ == "__main__":
    main()
