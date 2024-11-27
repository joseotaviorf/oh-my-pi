import json
import boto3
import logging

from typing import Tuple
from datetime import datetime, timedelta
from argparse import ArgumentParser
from http.client import HTTPException

from bietlejuice.services import S3Service
from bietlejuice.clients.db_clients import SparkClient

from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_into_s3"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

s3_service = S3Service(boto3.resource("s3"))
spark_client = SparkClient()

buckets = {
    "prod": "sale-unavailable-listings-s3-data-quintoandar-com-br",
    "forno": "5a-sale-unavailable-listings-forno",
}

def main():
    env, database_name, table_name, execution_date = (
        parse_arguments()
    )
    bucket = buckets[env]
    logger.info(
        f"""m=__main__, bucket= {bucket}, database_name={database_name}, 
        table_name={table_name}, execution_date={execution_date}"""
    )

    result = prepare_table(database_name, table_name, execution_date)
    destination_path = create_s3_path(bucket, table_name, execution_date)
    send_to_s3_bucket(result, table_name, destination_path)


def parse_arguments() -> Tuple[str, str, str, datetime]:
    
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env", help="Environment where the job is running")
    parser.add_argument("database_name", help="Name of the reverse etl schema")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    parser.add_argument(
        "execution_date", help="Date of the execution in the format YYYY-MM-DD"
    )

    args = parser.parse_args()

    env = args.env
    database_name = args.database_name
    table_name = args.table_name
    execution_date = datetime.fromisoformat(args.execution_date)

    return env, database_name, table_name, execution_date

def prepare_table(database_name: str, table_name: str, execution_date: datetime):
    """
    Retrieves a table from Spark, filters it by a specified execution date, and prepares its payload as a JSON string.

    Parameters:
    - database_name (str): Name of the Spark database containing the desired table.
    - table_name (str): Name of the table to retrieve and process.
    - execution_date (datetime): Date used to filter the table's rows. Rows with a matching year, month, and day are selected.
    """
    df = spark.table(f"{database_name}.{table_name}")
    filtered_df = df.filter(
        (df.year == execution_date.year)
        & (df.month == execution_date.month)
        & (df.day == execution_date.day)
    ).drop("year", "month", "day")

    houses = [row['sk_house'] for row in filtered_df.collect()]
    
    logger.info(
        f"m=__main__, message=Table retrieved: {len(houses)} rows"
    )

    return json.dumps({"table": table_name, "dt_load": (execution_date + timedelta(days=1)).strftime('%Y-%m-%d'), "payload": houses})

def create_s3_path(bucket: str, table_name: str, execution_date: datetime):
    """
    Constructs an S3 path string based on the given bucket, table name, and execution date.

    Parameters:
    - bucket (str): The name of the S3 bucket.
    - table_name (str): The name of the table, which will be part of the constructed path.
    - execution_date (datetime): The date for which the path needs to be created. The year, month, and day are extracted from this.
    """
    tomorrow = execution_date + timedelta(days=1)
    path = f"s3://{bucket}/reverse/{table_name}/year={tomorrow.year}/month={tomorrow.month}/day={tomorrow.day}"
    return path

def send_to_s3_bucket(file: str, table_name: str, path: str):
    """
    Uploads a specified file to an S3 bucket.

    Parameters:
    - file (str): The file path of the file to be uploaded.
    - table_name (str): The name of the table, used mainly for logging purposes.
    - path (str): The S3 bucket path where the file will be uploaded.
    """
    
    try:
        s3_service.upload_file(file, path)

        logger.info(
            f"m=__main__, message=successful S3 put_object for table {table_name}"
            )
        
    except Exception as e:

        raise HTTPException(
            f"m=__main__, message=UNSUCCESSFULL S3 put_object for table {table_name}, error={e}"
        )


if __name__ == "__main__":
    main()