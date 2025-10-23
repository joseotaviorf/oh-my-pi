import logging
import json
from datetime import datetime
from argparse import ArgumentParser
from datetime import datetime, date
from typing import Tuple, List
import boto3
from bietlejuice.services import ConfigurationService
from pyspark.sql.functions import make_date
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_into_sns"
BATCH_SIZE = 1000

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


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


def parse_arguments() -> Tuple[str, str, str, str, datetime]:
    """
    Parse the arguments passed to the job.
    Returns a tuple with the DAG name, database name, table name, event type, load start and end date.
    """

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
    Load the table into SNS and log success/failure counts.
    """

    df = spark.table(f"{database_name}.{table_name}")

    filtered_df = df.filter(
        (make_date(df.year, df.month, df.day) >= load_start_date)
        & (make_date(df.year, df.month, df.day) <= load_end_date)
    ).drop("business_id", "year", "month", "day")

    # Checks if DataFrame is empty before processing
    if filtered_df.rdd.isEmpty():
        logger.info("No data found for the specified date range. No messages sent to SNS.")
        return

    region = sns_topic_arn.split(":")[3]

    # Initializes accumulators in the Driver
    success_counter = spark.sparkContext.accumulator(0)
    failure_counter = spark.sparkContext.accumulator(0)

    def send_partition_to_sns(partition):
        partition_logger = logging.getLogger(JOB_NAME)

        sns_client = boto3.client("sns", region_name=region)
        batch = []

        for row in partition:
            message = {"event_type": event_type, "payload": row.asDict()}
            batch.append(message)

            if len(batch) >= BATCH_SIZE:
                s_count, f_count = send_batch_to_sns(sns_client, sns_topic_arn, batch, partition_logger)

                # Adds to global accumulators
                success_counter.add(s_count)
                failure_counter.add(f_count)

                batch.clear()

        if batch:
            s_count, f_count = send_batch_to_sns(sns_client, sns_topic_arn, batch, partition_logger)
            success_counter.add(s_count)
            failure_counter.add(f_count)

    filtered_df.foreachPartition(send_partition_to_sns)

    # Logs the final aggregated summary
    total_success = success_counter.value
    total_failure = failure_counter.value
    total_processed = total_success + total_failure

    logger.info(
        f"Total SNS load summary. m=load_table_into_sns, status=complete, "
        f"total_messages_processed={total_processed}, "
        f"total_success_count={total_success}, total_failure_count={total_failure}"
    )

    if total_failure > 0:
        logger.warning(
            f"Some messages FAILED to send to SNS. m=load_table_into_sns, "
            f"failure_count={total_failure}"
        )
    else:
        logger.info(
            f"All {total_success} messages sent successfully to SNS. m=load_table_into_sns"
        )


def send_batch_to_sns(sns_client, sns_topic_arn: str, batch: List, logger_instance: logging.Logger) -> Tuple[int, int]:
    """
    Send a message to SNS.
    """
    success_count = 0
    failure_count = 0

    for message in batch:
        try:
            response = sns_client.publish(
                TopicArn=sns_topic_arn, Message=json.dumps(message, default=json_serial)
            )

            # Success log. This is the individual proof of message publication.
            logger_instance.debug(
                f"Message published successfully. m=send_batch_to_sns, "
                f"MessageId={response.get('MessageId')}, event_type={message.get('event_type')}"
            )
            success_count += 1

        except Exception as e:
            # Error log
            logger_instance.error(
                f"Failed to publish message to SNS. m=send_batch_to_sns, "
                f"error={e}, event_type={message.get('event_type')}, "
                f"payload_preview={str(message.get('payload', {}))[:100]}..."  # Logs only part of the payload
            )
            failure_count += 1

    return success_count, failure_count


def json_serial(obj):
    """JSON serializer for objects not serializable by default json code"""

    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    raise TypeError("Type %s not serializable" % type(obj))


if __name__ == "__main__":
    main()
