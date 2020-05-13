import logging
from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.dags.bigfone_event import (
    QUERIES_BIGFONE_EVENT_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.dags.bigfone_event.spark_jobs import SOURCE
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_incremental_to_datalake_layer"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description="load_incremental_to_datalake_layer")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("datalake_bucket")
    parser.add_argument(
        "source_layer", type=str, help="raw/clean values to get data from"
    )
    parser.add_argument(
        "target_layer", type=str, help="clean/enrich values to save data to"
    )
    parser.add_argument("table_name", type=str, help="table name")
    args = parser.parse_args()

    logger.info(
        "m=load_incremental_to_datalake_layer, table_name={}, execution_date={}, msg=print args spark "
        "jobs params".format(args.table_name, args.execution_date)
    )

    environment = args.environment
    execution_date = args.execution_date
    datalake_bucket = args.datalake_bucket
    source_layer = args.source_layer
    target_layer = args.target_layer
    table_name = args.table_name

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    source_db = db_info["db_" + source_layer + "_databricks"]
    conn_config = {"db": source_db}

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", dt_execution.year),
            ("month", dt_execution.month),
            ("day", dt_execution.day),
        ]
    )

    query_path = (
        f"{QUERIES_BIGFONE_EVENT_DATALAKE_PATH}/{target_layer}/{table_name}.sql"
    )
    query = FileService.get_query_from_file_name(query_path).format(**partitions)

    spark_client = SparkClient()
    databricks_consumer = DatabricksConsumer(conn_config, spark_client)
    df = databricks_consumer.get_data_from_query(query)

    df = SparkDataFrameService(df).optimize_partition(250000).output()

    database_name = db_info["db_" + target_layer + "_databricks"]
    format_options = SparkTableStorageFormat.get_storage(target_layer)
    database_location = db_info["db_" + target_layer + "_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    partition_cols = list(partitions.keys())
    s3_loader = S3Loader()
    s3_loader.load_incremental_table(
        df, database_name, table_name, format_options, database_location, partition_cols
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location, partition_cols
    )

    spark_metastore_service.create_new_partitions_from_df(
        database_name, table_name, df, partition_cols
    )

    spark_metastore_service.refresh_table(database_name, table_name)
