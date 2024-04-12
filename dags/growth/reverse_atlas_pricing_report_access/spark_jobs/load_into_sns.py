import logging
import json

from argparse import ArgumentParser
from datetime import datetime, date, timezone
from typing import Tuple

import boto3
from uuid import uuid4

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.clients.db_clients import SparkClient

JOB_NAME = "load_into_sns"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments() -> Tuple[str, str, str, str, datetime]:
    """
    Parse the arguments passed to the job.
    Returns a tuple with the database name, table name, event type, ARN of the SNS topic and execution date.
    """

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    parser.add_argument("event_type", help="Type of event to be sent to SNS")
    parser.add_argument("sns_topic_arn", help="ARN of the SNS topic")

    args = parser.parse_args()

    database_name = args.database_name
    table_name = args.table_name
    event_type = args.event_type
    sns_topic_arn = args.sns_topic_arn

    return database_name, table_name, event_type, sns_topic_arn

def json_serial(obj):
    """JSON serializer for objects not serializable by default json code"""

    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    raise TypeError("Type %s not serializable" % type(obj))

def format_sns_message(message: dict):
    """
    Format a message to SNS.
    """
    return {'Id': message['id'], 'Message': json.dumps(message, default=json_serial)}

def publish_message_to_sns(region: str, sns_topic_arn: str, message: dict):
    """
    Send a message to SNS.
    """
    sns_client = boto3.client("sns", region_name=region)
    sns_client.publish(
        TopicArn=sns_topic_arn, Message=json.dumps(message, default=json_serial)
    )

def split_in_chunks(list_of_elements: list, chunk_size: int):
    """
    Yield successive n-sized chunks from list.
    """
    for i in range(0, len(list_of_elements), chunk_size):
        yield list_of_elements[i:i + chunk_size]

def load_table_into_sns(
    database_name: str,
    table_name: str,
    event_type: str,
    sns_topic_arn: str,
):
    """
    Load the table into SNS.
    """

    region = sns_topic_arn.split(":")[3]
    spark_client = SparkClient()

    df = spark.table(f"{database_name}.{table_name}")

    message_contents = df.collect()
    messages = [
      {
          "id_message": str(uuid4()),
          "ts_message": datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S'),
          "event_type": event_type,
          "payload": row.asDict()
      } for row in message_contents
    ]

    messages_batches = split_in_chunks(messages, 100)
    messages_batches_rdd = spark_client.conn.sparkContext.parallelize(
        messages_batches
    )

    responses = messages_batches_rdd.map(
        lambda batch: publish_message_to_sns(
            region, sns_topic_arn, batch
        )
    ).collect()

    logger.info(
        "msg=events requests responses={}".format(responses)
    )

def main():
    """
    Start the pipeline.
    """
    database_name, table_name, event_type, sns_topic_arn = (
        parse_arguments()
    )
    logger.info(
        f"""m=__main__, database_name={database_name}, table_name={table_name},
        event_type={event_type}, sns_topic_arn={sns_topic_arn}"""
    )

    load_table_into_sns(
        database_name, table_name, event_type, sns_topic_arn,
    )

if __name__ == "__main__":
    main()
