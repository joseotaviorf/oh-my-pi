import logging

from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.dags.teravoz import SOURCE, QUERIES_TERAVOZ_DATALAKE_PATH

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

from bietlejuice.jobs.composer.clients.db_clients import AthenaClient
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader

DATABRICKS_SCOPE = "quintoandar"

JOB_NAME = "load_data_to_clean"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description="load_teravoz_into_datalake")

    # args passed by Airflow task
    parser.add_argument("file_name", type=str, help="file name is equal table name")
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("athena_query_result_location")

    args = parser.parse_args()

    logger.info(
        "m=load_data_to_clean, file_name={}, execution_date={}, msg=print args spark "
        "jobs params".format(args.file_name, args.execution_date)
    )

    execution_date = args.execution_date
    table_name = file_name = args.file_name.replace("-", "_")
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location

    athena_client = AthenaClient(athena_query_result_location)

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", int(dt_execution.year)),
            ("month", int(dt_execution.month)),
            ("day", int(dt_execution.day)),
        ]
    )
    partitions_cols = list(partitions.keys())

    # get query to create event table
    query = FileService().get_query_from_file_name(
        QUERIES_TERAVOZ_DATALAKE_PATH + "/" + table_name + ".sql"
    )

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, SOURCE, datalake_bucket
    )

    conn_config = {"db": datalake_info["db_raw_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, SparkClient())
    df = databricks_consumer.get_data_from_query(query.format(**partitions))

    spark_metastore_service = SparkMetastoreService(SparkClient())

    # create database if not exists
    database_name = datalake_info["db_clean_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN
    database_location = datalake_info["db_clean_path"]
    spark_metastore_service.create_database(database_name)

    # loaders
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_loader.load_incremental_table(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partition_cols=partitions_cols,
    )
    spark_metastore_loader.update_metastore(
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partitions_cols,
        force_recreate=False,
    )
    # create partition into spark table
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partitions_cols,
    )

    spark_metastore_service.refresh_table(database_name, table_name)
