import json
import logging
from argparse import ArgumentParser
from datetime import date, datetime, timezone
from uuid import uuid4

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    is_validation_run,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_into_sns"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments() -> dict:
    """
    Parse the arguments passed to the job.
    Returns a dictionary with the database name, table name, event type,
    ARN of the SNS topic and chunk size.
    """

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    parser.add_argument("event_type", help="Type of event to be sent to SNS")
    parser.add_argument("sns_topic_arn", help="ARN of the SNS topic")
    parser.add_argument(
        "chunk_size", type=int, help="Chunk Size used for each table message"
    )

    add_validation_target_args(parser)
    args = parser.parse_args()

    return {
        "dag_name": args.dag_name,
        "database_name": args.database_name,
        "table_name": args.table_name,
        "event_type": args.event_type,
        "sns_topic_arn": args.sns_topic_arn,
        "chunk_size": args.chunk_size,
        "target_database_name": args.target_database_name,
        "target_table_name": args.target_table_name,
    }


def json_serial(obj):
    """JSON serializer for objects not serializable by default json code"""

    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")


def format_sns_message(message: dict):
    """
    Format a message to SNS.
    """
    return {"Id": message["id"], "Message": json.dumps(message, default=json_serial)}


def publish_message_to_sns(region: str, sns_topic_arn: str, message: dict):
    """
    Send a message to SNS.
    """
    sns_client = boto3.client("sns", region_name=region)
    sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=json.dumps(message, default=json_serial, ensure_ascii=False),
    )


def split_in_chunks(list_of_elements: list, chunk_size: int):
    """
    Yield successive n-sized chunks from list.
    """
    for i in range(0, len(list_of_elements), chunk_size):
        yield list_of_elements[i : i + chunk_size]


def load_table_into_sns(
    database_name: str,
    table_name: str,
    event_type: str,
    sns_topic_arn: str,
    chunk_size: int,
):
    """
    Load the table into SNS.
    """

    region = sns_topic_arn.split(":")[3]
    spark_client = SparkClient()

    df = spark.table(f"{database_name}.{table_name}")

    message_contents = [row.asDict() for row in df.collect()]
    message_chunks = split_in_chunks(message_contents, chunk_size)

    messages = [
        {
            "id_message": str(uuid4()),
            "ts_message": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S"),
            "event_type": event_type,
            "payload": chunk,
        }
        for chunk in message_chunks
    ]

    messages_batches_rdd = spark_client.conn.sparkContext.parallelize(messages)

    responses = messages_batches_rdd.map(
        lambda batch: publish_message_to_sns(region, sns_topic_arn, batch)
    ).collect()

    logger.info(f"msg=events requests responses={responses}")


def main():
    """
    Start the pipeline.
    """
    job_args_dict = parse_arguments()

    if is_validation_run(
        job_args_dict["target_database_name"],
        job_args_dict["target_table_name"],
    ):
        logger.info(
            f"m={JOB_NAME}, msg=Skipping reverse SNS export in cluster validation mode"
        )
        return

    config_service = ConfigurationService(job_args_dict["dag_name"])
    sns_topic_arn = config_service.get_config(job_args_dict["sns_topic_arn"])

    logger.info(
        f"""m=__main__, database_name={job_args_dict["database_name"]}, table_name={job_args_dict["table_name"]},
        event_type={job_args_dict["event_type"]}, sns_topic_arn={sns_topic_arn}"""
    )

    load_table_into_sns(
        database_name=job_args_dict["database_name"],
        table_name=job_args_dict["table_name"],
        event_type=job_args_dict["event_type"],
        sns_topic_arn=sns_topic_arn,
        chunk_size=job_args_dict["chunk_size"],
    )


if __name__ == "__main__":
    main()
