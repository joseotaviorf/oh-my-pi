import json
import logging
from argparse import ArgumentParser
from pyspark.sql.functions import to_timestamp, col

from quintoandar_logger import QuintoAndarLogger
from quintoandar_reclameaqui_api_client.clients import ReclameaquiClient
from quintoandar_reclameaqui_api_client.constants import EndpointEnum
from quintoandar_reclameaqui_api_client.consumers import ReclameaquiTicketConsumer

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)

from bietlejuice.jobs.composer.services import ConfigurationService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_tickets_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("execution_date")
    parser.add_argument("source")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    source = args.source

    config_service = ConfigurationService(source)
    tickets_endpoint_config = config_service.get_config("tickets")

    schema = tickets_endpoint_config.get("schema")
    partition_cols = tickets_endpoint_config.get("partition_cols")
    table_name = tickets_endpoint_config.get("raw_table_name")

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
            msg=print spark jobs args"
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.RECLAMEAQUI
    )

    credentials = json.loads(json_credentials)
    reclameaqui_client = ReclameaquiClient(credentials)
    consumer = ReclameaquiTicketConsumer(
        EndpointEnum.RETRIEVE_TICKETS.value["path"], client=reclameaqui_client
    )

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    database_name = datalake_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    response = consumer.sync(execution_date, 50)

    if response:

        df = spark_client.create_dataframe(data=response, schema=schema)
        df = df.withColumn("ts_load", to_timestamp(col("last_modification_date")))
        df = df.where(f"date(ts_load) = '{execution_date}'")
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_dataframe_column("ts_load")
            .output()
        )

        # loaders
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
        )
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            partition_cols,
            force_recreate=False,
        )
        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=partition_cols,
        )
    else:
        raise Exception(
            f"""m=__main__, table_name={table_name},
            msg=No data returned from API."""
        )
