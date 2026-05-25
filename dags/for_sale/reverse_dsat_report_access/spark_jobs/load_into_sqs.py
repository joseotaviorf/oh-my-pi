import json
import logging
from argparse import ArgumentParser
from datetime import datetime
from typing import Tuple

import boto3
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_into_sqs"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def main():
    database_name, table_name, queue_url, execution_date = parse_arguments()
    logger.info(
        f"""m=__main__, database_name={database_name}, table_name={table_name},
        queue_url={queue_url}, execution_date={execution_date}"""
    )

    load_table_into_sqs(database_name, table_name, queue_url, execution_date)


def parse_arguments() -> Tuple[str, str, str, datetime]:
    """
    Parse the arguments passed to the job.
    Returns a tuple with the database name, table name, event type, ARN of the SQS topic and execution date.
    """

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    parser.add_argument("queue_url", help="ARN of the SQS topic")
    parser.add_argument(
        "execution_date", help="Date of the execution in the format YYYY-MM-DD"
    )

    args = parser.parse_args()

    database_name = args.database_name
    table_name = args.table_name
    queue_url = args.queue_url
    execution_date = datetime.fromisoformat(args.execution_date)

    return database_name, table_name, queue_url, execution_date


def load_table_into_sqs(
    database_name: str,
    table_name: str,
    queue_url: str,
    execution_date: datetime,
):
    """
    Load the table into SQS.
    """

    df = spark.table(f"{database_name}.{table_name}")
    filtered_df = df.filter(
        (df.year == execution_date.year)
        & (df.month == execution_date.month)
        & (df.day == execution_date.day)
    ).drop("year", "month", "day")
    message_contents = filtered_df.collect()
    payload = [{"payload": row.asDict()} for row in message_contents]

    sqs = boto3.client("sqs", region_name="us-east-1")
    for message in payload:
        try:
            message_body = json.dumps({"payload": message})
            sqs.send_message(
                QueueUrl=queue_url,
                MessageBody=message_body,
                MessageAttributes={
                    "contentType": {
                        "DataType": "String",
                        "StringValue": "application/json",
                    }
                },
            )
            print("Mensagem enviada com sucesso para a fila SQS.")
        except Exception as e:
            print(f"Erro ao enviar mensagem para a fila SQS: {e}")


if __name__ == "__main__":
    main()
