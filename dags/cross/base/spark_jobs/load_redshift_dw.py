import json
from argparse import ArgumentParser

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum, DWMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import PostgresClient, SparkClient
from bietlejuice.loaders.redshift_loader import RedshiftLoader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.storage_services.s3_service import S3Service

JOB_NAME = "load_redshift_dw"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("spectrum_iam_role")
    parser.add_argument("dw_bucket")
    parser.add_argument("dw_schema")
    parser.add_argument("table_name")

    args = parser.parse_args()
    env = args.env
    spectrum_iam_role = args.spectrum_iam_role
    dw_bucket = args.dw_bucket
    dw_schema = args.dw_schema
    table_name = args.table_name

    logger.info(
        f"m={JOB_NAME}, env={env}, spectrum_iam_role={spectrum_iam_role}, "
        f"dw_bucket={dw_bucket}, dw_schema={dw_schema}, table_name={table_name}, "
        "msg=Job execution started"
    )

    dw_db_name, _ = DWMetastoreService.get_layer_info(
        env=env, schema=dw_schema, bucket=dw_bucket, layer=LayerEnum.DW.value
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    redshift_connection = json.loads(
        dbutils.secrets.get("quintoandar", DatabaseEnum.DW)
    )

    s3_client = S3Service(boto3.resource("s3"))
    spark_metastore_service = SparkMetastoreService(SparkClient())

    redshift_client = PostgresClient(
        dbname=redshift_connection["db"],
        host=redshift_connection["host"],
        port=redshift_connection["port"],
        user=redshift_connection["user"],
        password=redshift_connection["pwd"],
        keepalives_idle=200,
    )

    redshift_loader = RedshiftLoader(
        spectrum_iam_role, redshift_client, s3_client, dw_bucket
    )

    redshift_loader.load_table_from_metastore(
        metastore_service=spark_metastore_service,
        source_schema=dw_db_name,
        source_table_name=table_name,
        target_schema=dw_schema,
        target_table_name=table_name,
        overwrite=True,
    )
