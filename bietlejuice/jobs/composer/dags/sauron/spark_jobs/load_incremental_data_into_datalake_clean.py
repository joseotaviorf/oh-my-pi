import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.services import FileService


JOB_NAME = "load_incremental_data_into_datalake_clean"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod environment")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("datalake_bucket", help="name of the bucket in forno/prod")
    parser.add_argument("execution_date", help="DAG execution date")
    parser.add_argument("table_name", help="table name")

    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    table_name = args.table_name.lower()

    logger.info(
        f"""
        m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        execution_date={execution_date}, table_name={table_name}, msg=Starting spark job...
        """
    )

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = {
        "year": dt_execution.year,
        "month": dt_execution.month,
        "day": dt_execution.day,
    }
    partition_cols = list(partitions.keys())

    layer = LayerEnum.CLEAN
    clean_query = FileService().get_query_from_file_name(
        f"{QUERIES_DATALAKE_PATH}{source}/{layer}/{table_name}.sql"
    )

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_clean_databricks"]
    database_location = db_info["db_clean_path"]

    conn_config = {"db": db_info["db_raw_databricks"]}

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    consumer = DatabricksConsumer(conn_config, spark_client)

    df = consumer.get_data_from_query(clean_query.format(**partitions))

    format_options = SparkTableStorageFormat.DEFAULT_CLEAN

    s3_loader = S3Loader()

    if not df:
        logger.warn(
            f"""
                m=__main__, msg=Table {table_name} doesn't have data for date {execution_date}
           """
        )
    else:
        df = SparkDataFrameService().input(df).optimize_partition(200000).output()

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

        spark_metastore_service.refresh_table(database_name, table_name)
