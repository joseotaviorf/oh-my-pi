import json
import logging
from argparse import ArgumentParser

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, DWMetastoreService
from bietlejuice.jobs.composer.dags.dw_teravoz_fact_calls import DW_SCHEMA
from bietlejuice.jobs.composer.services import S3Service
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import PostgresClient, SparkClient
from bietlejuice.jobs.composer.loaders import RedshiftLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_dw_table_into_redshift"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dw_bucket", type=str, help="dw bucket")
    parser.add_argument(
        "table_name", type=str, help="table name that will be created in Redshift"
    )
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument(
        "spectrum_iam_role",
        type=str,
        help="permission for Spectrum to access the table",
    )

    args = parser.parse_args()
    dw_bucket = args.dw_bucket
    table_name = args.table_name
    env = args.env
    spectrum_iam_role = args.spectrum_iam_role

    logger.info(
        "m=__main__, table_name={}, dw_schema={}, env={}, msg=Job execution "
        "started".format(table_name, DW_SCHEMA, env)
    )

    dw_info = DWMetastoreService.get_dw_info(env, DW_SCHEMA, dw_bucket)

    s3_client = S3Service(boto3.resource("s3"))
    spark_metastore_service = SparkMetastoreService(SparkClient())

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

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

    redshift_loader = RedshiftLoader(
        spectrum_iam_role, redshift_client, s3_client, dw_info["dw_bucket"]
    )

    redshift_loader.load_table_from_metastore(
        metastore_service=spark_metastore_service,
        source_schema=dw_info["dw_schema_databricks"],
        source_table_name=table_name,
        target_schema=DW_SCHEMA,
        target_table_name=table_name,
        overwrite=True,
    )
