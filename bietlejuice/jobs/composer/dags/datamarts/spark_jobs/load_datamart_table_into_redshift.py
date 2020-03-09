import json
import logging
from argparse import ArgumentParser

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DWMetastoreService, DatabaseEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient, PostgresClient
from bietlejuice.jobs.composer.consumers.db_consumers import (
    DatabricksConsumer,
    PostgresConsumer,
)
from bietlejuice.jobs.composer.loaders import RedshiftLoader
from bietlejuice.jobs.composer.services import S3Service
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_datamart_table_into_redshift"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()


@logger
def validate_load(spark_schema, redshift_schema, table_name):
    base_query = "select count(1) from {}." + table_name
    spark_query = base_query.format(spark_schema)
    redshift_query = base_query.format(redshift_schema)

    spark_client = SparkClient()
    databricks_consumer = DatabricksConsumer(
        conn_config={"db": spark_schema}, spark_client=spark_client
    )
    df_spark_result = databricks_consumer.get_data_from_query(spark_query)
    spark_result_count = df_spark_result.collect()[0][0]

    redshift_conn = json.loads(dbutils.secrets.get("quintoandar", DatabaseEnum.DW))
    postgres_consumer = PostgresConsumer(
        conn_config=redshift_conn, spark_client=spark_client
    )
    df_redshift_result = postgres_consumer.get_data_from_query(redshift_query)
    redshift_result_count = df_redshift_result.collect()[0][0]

    logger.info(
        f"m=validate_load, spark_result={spark_result_count}, "
        f"redshift_result={df_redshift_result}, msg=Validating results"
    )
    assert spark_result_count == redshift_result_count


parser = ArgumentParser(description=JOB_NAME)
parser.add_argument("env")
parser.add_argument("dw_bucket")
parser.add_argument("spectrum_iam_role")
parser.add_argument("dw_schema")
parser.add_argument("table_name")

if __name__ == "__main__":
    args = parser.parse_args()
    env = args.env
    dw_bucket = args.dw_bucket
    spectrum_iam_role = args.spectrum_iam_role
    dw_schema = args.dw_schema
    table_name = args.table_name

    logger.info(
        f"m=__main__, table_name={table_name}, dw_schema={dw_schema}, env={env}, "
        f"msg=Job execution started"
    )

    s3_client = S3Service(boto3.resource("s3"))
    dw_info = DWMetastoreService.get_dw_info(env, dw_schema, dw_bucket)
    redshift_conn = json.loads(dbutils.secrets.get("quintoandar", DatabaseEnum.DW))
    redshift_client = PostgresClient(
        dbname=redshift_conn["db"],
        host=redshift_conn["host"],
        port=redshift_conn["port"],
        user=redshift_conn["user"],
        password=redshift_conn["pwd"],
        keepalives_idle=200,
    )

    metastore_service = SparkMetastoreService(SparkClient())
    redshift_loader = RedshiftLoader(
        spectrum_iam_role, redshift_client, s3_client, dw_info["dw_bucket"]
    )
    redshift_loader.load_table_from_metastore(
        metastore_service=metastore_service,
        source_schema=dw_info["dw_schema_databricks"],
        source_table_name=table_name,
        target_schema=dw_schema,
        target_table_name=table_name,
        overwrite=True,
    )

    # load validation
    validate_load(dw_info["dw_schema_databricks"], dw_schema, table_name)
