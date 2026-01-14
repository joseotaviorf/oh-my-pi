import logging
import json
from datetime import datetime
from argparse import ArgumentParser
from datetime import datetime, date
from typing import Tuple, List, Dict
import boto3
from bietlejuice.services import ConfigurationService
from pyspark.sql.functions import make_date
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_into_sns"
BATCH_SIZE = 1000

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_temporary_credentials() -> Dict[str, str]:
    """
    Get temporary AWS credentials from the driver's instance profile.
    These credentials can be broadcast to workers in USER_ISOLATION mode.
    """
    session = boto3.Session()
    credentials = session.get_credentials()
    frozen_credentials = credentials.get_frozen_credentials()
    
    return {
        "aws_access_key_id": frozen_credentials.access_key,
        "aws_secret_access_key": frozen_credentials.secret_key,
        "aws_session_token": frozen_credentials.token
    }


def main():
    dag_name, database_name, table_name, event_type, load_start_date, load_end_date, sns_topic_arn = (
        parse_arguments()
    )
    config_service = ConfigurationService(dag_name)
    sns_topic_arn = config_service.get_config(sns_topic_arn)
    logger.info(
        f"""m=__main__, database_name={database_name}, table_name={table_name},
        event_type={event_type}, sns_topic_arn={sns_topic_arn}, load_start_date={load_start_date},
        load_end_date={load_end_date}"""
    )

    load_table_into_sns(
        database_name, table_name, event_type, sns_topic_arn, load_start_date, load_end_date
    )


def parse_arguments() -> Tuple[str, str, str, str, datetime, datetime, str]:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    parser.add_argument(
        "load_start_date", help="Start date of the load in the format YYYY-MM-DD"
    )
    parser.add_argument(
        "load_end_date", help="End date of the load in the format YYYY-MM-DD"
    )
    parser.add_argument("event_type", help="Type of event to be sent to SNS")
    parser.add_argument("sns_topic_arn", help="ARN of the SNS topic to send the messages to")

    args = parser.parse_args()

    dag_name = args.dag_name
    database_name = args.database_name
    table_name = args.table_name
    event_type = args.event_type
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    sns_topic_arn = args.sns_topic_arn

    return dag_name, database_name, table_name, event_type, load_start_date, load_end_date, sns_topic_arn


def load_table_into_sns(
    database_name: str,
    table_name: str,
    event_type: str,
    sns_topic_arn: str,
    load_start_date: datetime,
    load_end_date: datetime,
):
    """
    Load the table into SNS.
    """
    df = spark.table(f"{database_name}.{table_name}")

    filtered_df = df.filter(
        (make_date(df.year, df.month, df.day) >= load_start_date)
        & (make_date(df.year, df.month, df.day) <= load_end_date)
    ).drop("business_id", "year", "month", "day")

    region = sns_topic_arn.split(":")[3]

    # Get temporary credentials from driver's instance profile and broadcast to workers
    # This is required for USER_ISOLATION mode where workers don't have direct access to instance profile
    logger.info("m=load_table_into_sns, msg=Obtaining temporary AWS credentials from driver")
    temp_credentials = get_temporary_credentials()
    credentials_broadcast = spark.sparkContext.broadcast(temp_credentials)
    logger.info("m=load_table_into_sns, msg=Credentials broadcast to workers successfully")

    def send_partition_to_sns(partition):
        # Get credentials from broadcast variable
        creds = credentials_broadcast.value
        sns_client = boto3.client(
            "sns",
            region_name=region,
            aws_access_key_id=creds["aws_access_key_id"],
            aws_secret_access_key=creds["aws_secret_access_key"],
            aws_session_token=creds["aws_session_token"]
        )
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