import logging
from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_incremental_to_datalake_layer"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description="load_incremental_to_datalake_layer")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("source", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument(
        "target_layer", type=str, help="the data lake layer to save data to"
    )
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("table_name", type=str, help="table name")
    args = parser.parse_args()

    env = args.environment
    source = args.source
    dl_bucket = args.datalake_bucket
    target_layer = args.target_layer
    execution_date = args.execution_date
    table_name = args.table_name

    db_info = DatalakeMetastoreService.get_db_info(env, source, dl_bucket)
    database_name = db_info["db_" + target_layer + "_databricks"]

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", dt_execution.year),
            ("month", dt_execution.month),
            ("day", dt_execution.day),
        ]
    )

    query_path = f"{QUERIES_DATALAKE_PATH}{source}/{target_layer}/{table_name}.sql"
    query = FileService.get_query_from_file_name(query_path).format(**partitions)

    spark_metastore_service = SparkMetastoreService(SparkClient())
    spark_metastore_service.create_database(database_name)

    databricks_consumer = DatabricksConsumer(
        conn_config={"db": database_name}, spark_client=SparkClient()
    )
    df = databricks_consumer.get_data_from_query(query)

    format_options = SparkTableStorageFormat.get_storage(target_layer)
    database_location = db_info["db_" + target_layer + "_path"]
    partition_cols = list(partitions.keys())
    s3_loader = S3Loader()

    s3_loader.load_incremental_table(
        df=df,
        database_name="",
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partition_cols=partition_cols,
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partitions=partition_cols,
        force_recreate=False,
    )

    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partition_cols,
    )

    spark_metastore_service.refresh_table(
        database_name=database_name, table_name=table_name
    )
