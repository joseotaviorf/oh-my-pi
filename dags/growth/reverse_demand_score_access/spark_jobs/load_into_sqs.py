import json
import logging
from argparse import ArgumentParser
from typing import Optional, Tuple

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
)
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_into_sqs"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments() -> Tuple[str, str, str, Optional[str], Optional[str]]:
    """
    Parse the arguments passed to the job.
    Returns a tuple with the database name, table name, event type, ARN of the SQS topic and execution date.
    """

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("dag_name", help="Name of the database where the table is")
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


def transform_payload(database_name, table_name):
    logger.info(f"Transforming payload for {database_name}.{table_name}")

    df = spark.table(f"{database_name}.{table_name}")

    df = df.select(["id_house", "demand_score", "occupation_status", "dt_snapshot"])

    df = (
        df.withColumnRenamed("id_house", "houseId")
        .withColumnRenamed("demand_score", "listingAgeDemandScore")
        .withColumnRenamed("dt_snapshot", "eventDate")
        .withColumnRenamed("occupation_status", "occupationStatus")
    )

    df = df.withColumn(
        "eventDate", (df["eventDate"].cast("timestamp").cast("long") * 1000)
    )

    logger.info(f"Payload adjusted for {database_name}.{table_name}")

    message_contents = df.collect()

    payload = [
        {
            "eventDate": row["eventDate"],
            "payload": {
                "houseId": row["houseId"],
                "listingAgeDemandScore": row["listingAgeDemandScore"],
                "occupationStatus": row["occupationStatus"],
            },
        }
        for row in message_contents
    ]

    return payload


def send_message(sqs_client, queue_url, data):

    logger.info(f"Sending message to SQS queue {queue_url}")

    message_attributes = {
        "contentType": {"DataType": "String", "StringValue": "application/json"}
    }

    try:
        for message in data:
            message_body = json.dumps(message)

            logger.info(f"Sending message to SQS: {message_body}")

            sqs_client.send_message(
                QueueUrl=queue_url,
                MessageBody=message_body,
                MessageAttributes=message_attributes,
            )
        logger.info("Message send successfully")

    except Exception as e:
        logger.error(f"Error sending message to SQS: {e}")
        logger.error(f"The last message sent was {message}")


def main():
    dag_name, database_name, table_name, target_database_name, target_table_name = (
        parse_arguments()
    )

    if is_validation_run(target_database_name, target_table_name):
        logger.info(
            f"m={JOB_NAME}, msg=Skipping reverse SQS export in cluster validation mode"
        )
        return

    sqs = boto3.client("sqs", region_name="us-east-1")

    config_service = ConfigurationService(dag_name)

    queue_url = config_service.get_config("sqs_queue_url")

    payload = transform_payload(database_name, table_name)

    send_message(sqs, queue_url, payload)


if __name__ == "__main__":
    main()
