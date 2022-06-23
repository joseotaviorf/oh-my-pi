import logging
from argparse import ArgumentParser

from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from quintoandar_logger import QuintoAndarLogger
from quintoandar_sirena_api_client.consumers import CONSUMERS
from quintoandar_sirena_api_client.clients import SirenaClient

JOB_NAME = "load_sirena_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


SCHEMA = """
    channel STRING COMMENT 'Enum: "whatsapp" "facebook"',
    channelId STRING COMMENT 'Communication Channel Id',
    templates ARRAY<
        STRUCT<
            key: STRING COMMENT 'Channel Template Key',
            name: STRING COMMENT 'Channel Template Display Name',
            body: STRING COMMENT 'Channel Body Message',
            template: STRING COMMENT 'Channel Template Message',
            channelKeys: STRING,
            keysConfig: STRING
        >
    >
"""


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name

    logger.info(
        f"m={JOB_NAME}, "
        f"environment={environment}, "
        f"source={source}, "
        f"datalake_bucket={datalake_bucket}, "
        f"msg=Spark job arguments"
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )

    file_type = SparkTableStorageFormat.DEFAULT_RAW
    filesystem_path = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    api_token = dbutils.secrets.get(scope="quintoandar", key=APIEnum.SIRENA)

    sirena_client = SirenaClient(api_token=api_token)
    consumer_channels = CONSUMERS["channels"](client=sirena_client)

    results = consumer_channels.sync()

    if results:
        df = spark_client.create_dataframe(results, schema=SCHEMA)
        s3_loader.load_df(
            df=df, s3_path=f"{filesystem_path}{table_name}", format_options=file_type
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=file_type,
            database_location=filesystem_path,
            force_recreate=True,
        )

        spark_metastore_service.refresh_table(database_name, table_name)
