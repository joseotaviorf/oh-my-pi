import logging

from argparse import ArgumentParser
from quintoandar_braze_api_client.clients import BrazeClient
from quintoandar_braze_api_client.factories import EndpointFactory

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    SparkTableStorageFormat,
    BaseDBUtils,
    sc,
)


JOB_NAME = "load_braze_details_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("source")
    parser.add_argument("datalake_bucket")
    parser.add_argument("app_group")
    parser.add_argument("identifier")
    parser.add_argument("execution_datetime")
    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    app_group = args.app_group
    identifier = args.identifier
    execution_datetime = args.execution_datetime

    logger.info(
        f"m={JOB_NAME}, "
        f"environment={environment}, "
        f"source={source}, "
        f"datalake_bucket={datalake_bucket}, "
        f"app_group={app_group}, "
        f"identifier={identifier}, "
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

    api_token = dbutils.secrets.get(
        scope="quintoandar", key=getattr(APIEnum, f"BRAZE_{app_group.upper()}")
    )
    instance = "US-03"
    endpoint = "details"
    table_name = f"{identifier}_{endpoint}_{app_group}"

    braze_client = BrazeClient(api_token=api_token, instance=instance)
    factory = EndpointFactory(braze_client)
    list_consumer = factory.build(identifier, "list")
    consumer = factory.build(identifier, endpoint)

    id_list = list_consumer.sync(reduce_key="id")

    results = consumer.sync(id_values=id_list, executor_type="spark", spark_context=sc)

    df = spark_client.create_dataframe(results)
    if not df.rdd.isEmpty():
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
