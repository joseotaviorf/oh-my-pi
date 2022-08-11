import json
import logging

from datetime import datetime
from argparse import ArgumentParser

from google.cloud import bigquery
from google.oauth2 import service_account

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.services.configuration_service import ConfigurationService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_s3_data_into_bigquery"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def __get_auth(dbutils):
    """
    This method gets credentials for Navent's BigQuery API.
    @param dbutils: DBUtils.
    @return: dict and str
    """
    credentials = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.NAVENT_BIGQUERY)
    )

    return credentials


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values ")
    parser.add_argument("datalake_bucket", help="bucket for forno/prod datalake")
    parser.add_argument("source", help="source name")
    parser.add_argument("dag_name", help="full DAG name")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    dag_name = args.dag_name

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, source={source},
        dag_name={dag_name}, datalake_bucket={datalake_bucket}, msg=Starting Spark job...
        """
    )

    config_service = ConfigurationService(dag_name)
    bigquery_project_id = config_service.get_config("bigquery_project_id")
    tables = config_service.get_config("tables")

    datalake_path_prefix = f"reverse/{source}"

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials = __get_auth(dbutils)
    credentials = service_account.Credentials.from_service_account_info(credentials)

    bigquery_client = bigquery.Client(
        credentials=credentials, project=bigquery_project_id
    )

    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        source_format=bigquery.SourceFormat.CSV,
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    execution_date = datetime.now()

    for table in tables:
        table_name = table["table_name"]
        bigquery_table_id = table["bigquery_table_id"]

        datalake_path = f"s3://{datalake_bucket}/{datalake_path_prefix}/{table_name}/year={execution_date.year}/month={execution_date.month}/day={execution_date.day}"

        df = s3_consumer.get_data_from_file(path=datalake_path, format="parquet")

        if df is not None:
            try:
                df = df.drop("year", "month", "day")

                load_job = bigquery_client.load_table_from_dataframe(
                    dataframe=df.toPandas(),
                    destination=bigquery_table_id,
                    job_config=job_config,
                )

                load_job.result()

                logger.info(
                    f"""m={JOB_NAME}, environment={environment}, source={source}, table_name={table_name},
                    bigquery_table_id={bigquery_table_id}. Table successfully loaded into BigQuery!
                    """
                )

            except Exception as e:
                logger.error(
                    f"""m={JOB_NAME}, table_name={table_name}, bigquery_table_id={bigquery_table_id},
                    error_message={e}"""
                )
