import io
import logging
from datetime import datetime
from argparse import ArgumentParser
from http.client import HTTPException

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

import boto3
from pyspark.sql.utils import AnalysisException

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_s3_data_into_external_bucket"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def __get_first_layer_folders_s3(bucket, prefix):
    s3_resource = boto3.resource("s3")
    datalakebucket = s3_resource.Bucket(bucket)
    tables = set()
    for object_summary in datalakebucket.objects.filter(Prefix=prefix):
        if "_test" not in object_summary.key:
            first_level = object_summary.key.split(prefix + "/")[1]
            first_level = first_level.split("/")[0]
            tables.add(first_level)
    return tables


def __build_warning_messages(environment, s3_path_prefix, table_list):

    messages = []
    for table_name in table_list:
        messages.append(
            f"⚠️\n"
            f"Validation: `{s3_path_prefix}/{table_name}`\n"
            f"Environment: *{environment}*\n"
            f"Status: *FAILED*\n"
            f"*Existence validation failed for `{datetime.now().strftime('%Y-%m-%d')}`\n"
        )

    return messages


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values ")
    parser.add_argument("datalake_bucket", help="bucket for forno/prod datalake")
    parser.add_argument("source", help="source name")
    parser.add_argument("external_bucket", help="bucket destination for files")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    external_bucket = args.external_bucket

    logger.info(
        f"""m=__main__, environment={environment}, source={source},
        datalake_bucket={datalake_bucket}, external_bucket={external_bucket}
        """
    )
    datalake_path_prefix = f"reverse/{source}"
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    execution_date = datetime.now()
    tables = __get_first_layer_folders_s3(datalake_bucket, datalake_path_prefix)

    s3_client = boto3.client("s3")

    tables_to_send_warning = []

    for table in tables:
        datalake_path = f"s3://{datalake_bucket}/{datalake_path_prefix}/{table}/year={execution_date.year}/month={execution_date.month}/day={execution_date.day}"
        try:
            df = s3_consumer.get_data_from_file(path=datalake_path, format="delta")
        except AnalysisException:
            tables_to_send_warning.append(table)
            df = None

        if df is not None:
            df = df.drop("year", "month", "day")

            if 'speech' in table:
                destination_path = f"speech_analytics/{table}/"
            else:
                destination_path = f"to_atento_{table}/"

            file_name = f'{table}_{(execution_date.strftime("%Y%m%d"))}.csv'
            with io.StringIO() as csv_buffer:
                df.toPandas().to_csv(csv_buffer, index=False, header=True)

                response = s3_client.put_object(
                    Bucket=external_bucket,
                    Key=destination_path + file_name,
                    Body=csv_buffer.getvalue(),
                    ACL="bucket-owner-full-control",
                )

                status = response.get("ResponseMetadata", {}).get("HTTPStatusCode")

                if status == 200:
                    logger.info(
                        f"m=__main__, message=successful S3 put_object for table {table}, status={status}"
                    )
                else:
                    raise HTTPException(
                        f"m=__main__, message=UNSUCCESSFULL S3 put_object for table {table}, status={status}"
                    )

    if tables_to_send_warning:
        base_dbutils = BaseDBUtils()
        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        DAG_NAME = f"reverse_{source}_access"
        config_service = ConfigurationService(DAG_NAME)
        webhook_key = config_service.get_config("notification_webhooks_keys")[
            "data_quality"
        ]
        gchat_webhook = dbutils.secrets.get(
            scope="quintoandar", key=webhook_key
        )

        messages = __build_warning_messages(
            environment,
            f"s3://{datalake_bucket}/{datalake_path_prefix}",
            tables_to_send_warning,
        )

        for message_content in messages:
            logger.info(f"m=__main__, message=sending gchat message: {message_content}")
            message = Message(content=message_content, destination=gchat_webhook)
            GChatService.send_message(message)
