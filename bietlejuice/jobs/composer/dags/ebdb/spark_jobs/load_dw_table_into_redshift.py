import json
import logging
from argparse import ArgumentParser

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.services import S3Service
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, BaseSparkContext
from bietlejuice.jobs.composer.clients.db_clients import PostgresClient, SparkClient
from bietlejuice.jobs.composer.loaders import RedshiftLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_dw_table_into_redshift"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()

parser = ArgumentParser(description=JOB_NAME)
parser.add_argument("table_name")
parser.add_argument("dw_schema")
parser.add_argument("env")


@logger
def validate_load(spark_schema, redshift_schema, table_name):
    base_query = "select count(1) from {}." + table_name
    spark_query = base_query.format(spark_schema)
    redshift_query = base_query.format(redshift_schema)

    # todo: use DatabricksConsumer to read data
    spark_result = spark_client.get_records(spark_query).collect()[0][0]
    redshift_result = redshift_client.get_records(redshift_query)[0][0]

    logger.info(
        "m=validate_load, spark_result={}, redshift_result={}, msg=Validating "
        "results".format(spark_result, redshift_result)
    )
    assert spark_result == redshift_result


if __name__ == "__main__":
    # job execution information
    args = parser.parse_args()
    table_name = args.table_name
    dw_schema = args.dw_schema
    env = args.env
    dw_info = DatalakeMetastoreService.get_dw_info(env, dw_schema)

    logger.info(
        "m=__main__, table_name={}, dw_schema={}, env={}, msg=Job execution "
        "started".format(table_name, dw_schema, env)
    )

    # instances setup
    s3_client = S3Service(boto3.resource("s3"))
    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)

    redshift_connection = json.loads(
        dbutils.secrets.get("quintoandar", DatabaseEnum.DW)
    )

    redshift_client = PostgresClient(
        dbname=redshift_connection["db"],
        host=redshift_connection["host"],
        port=redshift_connection["port"],
        user=redshift_connection["user"],
        password=redshift_connection["pwd"],
        keepalives_idle=200,
    )
    redshift_loader = RedshiftLoader(redshift_client, s3_client, dw_info["dw_bucket"])

    # load
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
