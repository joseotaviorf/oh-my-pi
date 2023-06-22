import io
import ast
import logging
from datetime import datetime
from argparse import ArgumentParser
from http.client import HTTPException

from quintoandar_logger import QuintoAndarLogger
from inmetro.messengers import SlackMessenger
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.base.notification.slack_webhooks_enum import SlackWebhooksEnum

import boto3
from pyspark.sql.utils import AnalysisException

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_s3_data_into_external_bucket"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def __build_warning_messages(environment, s3_path_prefix, table_list):

    messages = []
    for table_name in table_list:
        messages.append(
            f":warning:\n"
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
    parser.add_argument("context", help="context name")
    parser.add_argument("external_bucket", help="bucket destination for files")
    parser.add_argument("tables", help="tables list to export to destination")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    context = args.context
    external_bucket = args.external_bucket
    tables = ast.literal_eval(args.tables)

    logger.info(
        f"""m=__main__, environment={environment}, context={context},
        datalake_bucket={datalake_bucket}, external_bucket={external_bucket},
        tables={tables}
        """
    )
    datalake_path_prefix = f"enrich/{context}"
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    execution_date = datetime.now()

    s3_client = boto3.client("s3")

    tables_to_send_warning = []

    for table in tables:
        datalake_path = f"s3://{datalake_bucket}/{datalake_path_prefix}/{table}"
        try:
            df = s3_consumer.get_data_from_file(path=datalake_path, format="parquet")
        except AnalysisException:
            tables_to_send_warning.append(table)
            df = None

        if df is not None:
            destination_path = f"v1/{table}/"
            
            file_name = f"{table}.jsonl"

            with io.StringIO() as json_buffer:

                df.toPandas().to_json(
                    json_buffer, force_ascii=False, orient='records', lines=True
                )

                response = s3_client.put_object(
                    Bucket=external_bucket,
                    Key=destination_path + file_name,
                    Body=json_buffer.getvalue(),
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
        slack_webhook = dbutils.secrets.get(
            scope="quintoandar", key=SlackWebhooksEnum.ALERTS_AIRFLOW_DE_DAGS_INMETRO
        )

        messenger = SlackMessenger(slack_webhook)
        messages = __build_warning_messages(
            environment,
            f"s3://{datalake_bucket}/{datalake_path_prefix}",
            tables_to_send_warning,
        )
        messages_status = []
        for message in messages:
            logger.info(f"m=__main__, message=sending slack message: {message}")
            messenger.send_message(message)