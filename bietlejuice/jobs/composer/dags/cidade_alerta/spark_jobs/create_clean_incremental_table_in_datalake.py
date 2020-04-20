import logging
import sys

from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.dags.cidade_alerta import (
    SOURCE,
    QUERIES_CIDADE_ALERTA_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.services import FileService

JOB_NAME = "create_clean_incremental_table_in_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date", type=str, help="DAG execution date")
    args = parser.parse_args()

    table_name = args.table_name
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", dt_execution.year),
            ("month", dt_execution.month),
            ("day", dt_execution.day),
        ]
    )
    partition_cols = list(partitions.keys())

    query = FileService().get_query_from_file_name(
        QUERIES_CIDADE_ALERTA_DATALAKE_PATH + "/clean/" + table_name + ".sql"
    )

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    spark_client = SparkClient()

    conn_config = {"db": db_info["db_raw_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, spark_client)
    df = databricks_consumer.get_data_from_query(query.format(**partitions))

    spark_metastore_service = SparkMetastoreService(spark_client)
    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(db_info["db_clean_databricks"])

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    if df is None:
        logger.warning("m=__main__, msg=no incremental data to process here")
        sys.exit()

    df = (
        SparkDataFrameService()
        .input(df)
        .optimize_partition(200000)
        .create_columns_from_dict(partitions)
        .output()
    )
    database_name = db_info["db_clean_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN
    database_location = db_info["db_clean_path"]
    s3_loader.load_incremental_table(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partition_cols=partition_cols,
    )

    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location, partition_cols
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partition_cols,
    )

    spark_metastore_service.refresh_table(database_name, table_name)
