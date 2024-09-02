import io
import logging
import json
from argparse import ArgumentParser
from datetime import datetime
from http.client import HTTPException

import boto3
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_reverse_tiers"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def __send_warning_message(table_to_send_warning):
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    gchat_webhook = dbutils.secrets.get(scope="quintoandar", key=webhook_key)

    message_content = (
        f"⚠️\n"
        f"Validation: `s3://{datalake_bucket}/{datalake_path_prefix}/{table_to_send_warning}`\n"
        f"Environment: *{environment}*\n"
        f"Status: *FAILED*\n"
        f"*Existence validation failed for `{execution_date}`\n"
    )

    logger.info(f"m=__main__, message=sending gchat message: {message_content}")
    message = Message(content=message_content, destination=gchat_webhook)
    GChatService.send_message(message)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values ")
    parser.add_argument("source", help="source name")
    parser.add_argument("datalake_bucket", help="bucket for forno/prod datalake")
    parser.add_argument("external_bucket", help="bucket destination for files")
    parser.add_argument("table_to_send")
    parser.add_argument("webhook_key")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    external_bucket = args.external_bucket
    table_to_send = args.table_to_send
    webhook_key = args.webhook_key
    execution_date = args.execution_date

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d")

    datalake_path_prefix = f"reverse/{source}"

    logger.info(
        f"""m=__main__, environment={environment}, source={source},
        datalake_bucket={datalake_bucket}, external_bucket={external_bucket}
        """
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_client = boto3.client("s3")

    datalake_path = f"s3://{datalake_bucket}/{datalake_path_prefix}/{table_to_send}/year={execution_date.year}/month={execution_date.month}/day={execution_date.day}"

    try:
        df = s3_consumer.get_data_from_file(path=datalake_path, format="parquet")

        destination_path = f"v1/{table_to_send}/"
        file_name = (
            f'{table_to_send}_{(execution_date.strftime("%Y_%m_%d_%H_%M_%S%z"))}.csv'
        )

        with io.StringIO() as csv_buffer:
            df.toPandas().convert_dtypes().to_csv(csv_buffer, index=False, header=True)

            response = s3_client.put_object(
                Bucket=external_bucket,
                Key=destination_path + file_name,
                Body=csv_buffer.getvalue(),
                ACL="bucket-owner-full-control",
            )

        status = response.get("ResponseMetadata", {}).get("HTTPStatusCode")

        if status == 200:
            logger.info(
                f"m=__main__, message=successful S3 put_object for table {table_to_send}, status={status}"
            )
        else:
            raise HTTPException(
                f"m=__main__, message=UNSUCCESSFULL S3 put_object for table {table_to_send}, status={status}"
            )

    except AnalysisException:
        __send_warning_message(table_to_send)
