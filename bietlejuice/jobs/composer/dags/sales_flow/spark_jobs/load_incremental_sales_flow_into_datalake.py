import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_incremental_sales_flow_into_datalake_raw"
BLOCK_LIST = ["change_owner_control", "flyway_schema_history"]

# if the table doesn't have an "updated_at" column to load it incrementally, then it is necessary to map it.
COLUMN_MAPPING = {"revinfo": "timestamp"}
UNIX_FORMAT_TABLES = ["revinfo"]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("source")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.env
    source = args.source
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date

    partition_cols = ["year", "month", "day"]

    logger.info(
        f"""
        m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        execution_date={execution_date}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.SALES_FLOW
    )

    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()

    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    tables = postgres_consumer.get_table_names_and_sizes().collect()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_loader = S3Loader()

    for table in tables:
        if table.table_name not in BLOCK_LIST:
            unixtime_measure = (
                "miliseconds" if table.table_name in UNIX_FORMAT_TABLES else None
            )
            df = postgres_consumer.get_incremental_data_from_table(
                table.table_name,
                COLUMN_MAPPING.get(table.table_name, "updated_at"),
                execution_date,
                unixtime_measure=unixtime_measure,
            )

            table_name = table.table_name.lower()

            s3_loader.load_incremental_table(
                df=df,
                database_name=database_name,
                table_name=table_name,
                format_options=format_options,
                database_location=database_location,
                partition_cols=partition_cols,
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
