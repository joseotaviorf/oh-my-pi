import boto3
import json
from argparse import ArgumentParser
import logging

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext, BaseDBUtils
from bietlejuice.jobs.composer.base.s3 import S3Service
from bietlejuice.jobs.composer.wrappers import RedshiftClient
from bietlejuice.jobs.composer.loaders import RedshiftLoader
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient
from bietlejuice.jobs.composer.base.spark import SparkMetastoreService
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService

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

    spark_result = spark_sql_client.run(spark_query).collect()[0][0]
    redshift_result = redshift_client.run_query(redshift_query)[0][0]

    logger.info(
        "m=__main__, spark_result={}, redshift_result={}, msg=Validating results".format(
            spark_result, redshift_result
        )
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
        "m=__main__, table_name={}, dw_schema={}, env={}, msg=Job execution started".format(
            table_name, dw_schema, env
        )
    )

    # instances setup
    s3_client = S3Service(boto3.resource("s3"))
    spark_sql_client = SparkSQLCLient(spark, sqlContext)
    spark_metastore_service = SparkMetastoreService(
        dw_info["dw_schema_databricks"], dw_info["dw_schema_path"], spark_sql_client
    )

    redshift_connection = json.loads(dbutils.secrets.get("quintoandar", "ENV_DW"))
    redshift_client = RedshiftClient(redshift_connection)
    redshift_loader = RedshiftLoader(redshift_client, s3_client, dw_info["dw_bucket"])

    # load
    redshift_loader.load_spark_table_into_redshift(
        metastore_service=spark_metastore_service,
        source_table_name=table_name,
        target_schema=dw_schema,
        target_table_name=table_name,
        overwrite=True,
    )

    # load validation
    validate_load(dw_info["dw_schema_databricks"], dw_schema, table_name)
