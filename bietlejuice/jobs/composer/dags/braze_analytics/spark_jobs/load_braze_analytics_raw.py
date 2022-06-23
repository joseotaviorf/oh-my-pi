import logging
from argparse import ArgumentParser
from pyspark.sql.types import DateType

from quintoandar_braze_api_client.clients import BrazeClient
from quintoandar_braze_api_client.factories import EndpointFactory

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
    BaseDBUtils,
    sc,
)


JOB_NAME = "load_braze_analytis_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("app_group")
    parser.add_argument("identifier")
    parser.add_argument("execution_date")
    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    app_group = args.app_group
    identifier = args.identifier
    execution_date = args.execution_date
    partition_cols = ["year", "month", "day"]

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
    endpoint = "analytics"
    table_name = f"{identifier}_{endpoint}_{app_group}"

    braze_client = BrazeClient(api_token=api_token, instance=instance)
    factory = EndpointFactory(braze_client)
    consumer_list = factory.build(identifier, "list")
    consumer_analytics = factory.build(identifier, endpoint)

    id_list = consumer_list.sync(reduce_key="id")

    results = consumer_analytics.sync(
        id_values=id_list, executor_type="spark", spark_context=sc, length=1
    )

    if identifier == "campaign":
        results = [item for sublist in results for item in sublist]
        df = spark_client.create_dataframe(results)
        df = df.withColumn("time", df["time"].cast(DateType()))
    elif identifier == "canvas":
        df = spark_client.create_dataframe(results)
        df = df.withColumn("time", df["stats"][0]["time"].cast(DateType()))

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("time")
        .output()
    )

    if not df.rdd.isEmpty():
        s3_loader.load_df(
            df=df,
            s3_path=f"{filesystem_path}{table_name}",
            format_options=file_type,
            partitions=partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=file_type,
            database_location=filesystem_path,
            partitions=partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=partition_cols,
        )

        spark_metastore_service.refresh_table(database_name, table_name)
