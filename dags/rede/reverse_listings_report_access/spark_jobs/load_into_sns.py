import logging
import json
from datetime import datetime
from argparse import ArgumentParser
from datetime import datetime, date
from typing import Tuple
import boto3
from bietlejuice.services import ConfigurationService
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_into_sns"
BATCH_SIZE = 1000

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def main():
    dag_name, database_name, table_name, event_type, execution_date = (
        parse_arguments()
    )
    config_service = ConfigurationService(dag_name)
    sns_topic_arn = config_service.get_config("sns_topic_arn")
    logger.info(
        f"""m=__main__, database_name={database_name}, table_name={table_name},
        event_type={event_type}, sns_topic_arn={sns_topic_arn}, execution_date={execution_date}"""
    )

    load_table_into_sns(
        database_name, table_name, event_type, sns_topic_arn, execution_date
    )


def parse_arguments() -> Tuple[str, str, str, str, datetime]:
    """
    Parse the arguments passed to the job.
    Returns a tuple with the DAG name, database name, table name, event type, and execution date.
    """

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    parser.add_argument(
        "execution_date", help="Date of the execution in the format YYYY-MM-DD"
    )
    parser.add_argument("event_type", help="Type of event to be sent to SNS")

    args = parser.parse_args()

    dag_name = args.dag_name
    database_name = args.database_name
    table_name = args.table_name
    event_type = args.event_type
    execution_date = datetime.fromisoformat(args.execution_date)

    return dag_name, database_name, table_name, event_type, execution_date


def load_table_into_sns(
    database_name: str,
    table_name: str,
    event_type: str,
    sns_topic_arn: str,
    execution_date: datetime,
):
    """
    Load the table into SNS.
    """
    
    df = spark.table(f"{database_name}.{table_name}")

    filtered_df = df.filter(
        (df.year == execution_date.year)
        & (df.month == execution_date.month)
        & (df.day == execution_date.day)
    ).drop("business_id", "year", "month", "day")

    region = sns_topic_arn.split(":")[3]

    def send_partition_to_sns(partition):
        sns_client = boto3.client("sns", region_name=region)
        batch = []

        for row in partition:
            message = {"event_type": event_type, "payload": row.asDict()}
            batch.append(message)

            if len(batch) >= BATCH_SIZE:
                send_batch_to_sns(sns_client, sns_topic_arn, batch)
                batch.clear() 

        if batch:
            send_batch_to_sns(sns_client, sns_topic_arn, batch)

    filtered_df.foreachPartition(send_partition_to_sns)


def send_batch_to_sns(sns_client, sns_topic_arn: str, batch: list):
    """
    Send a message to SNS.
    """
    for message in batch:
        sns_client.publish(
            TopicArn=sns_topic_arn, Message=json.dumps(message, default=json_serial)
        )


def json_serial(obj):
    """JSON serializer for objects not serializable by default json code"""

    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    raise TypeError("Type %s not serializable" % type(obj))


if __name__ == "__main__":
    main()