import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

DATABRICKS_SCOPE = "quintoandar"

JOB_NAME = "load_chats_data_to_metastore"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description="load_data_to_metastore")
    parser.add_argument("file_name", type=str, help="file name is equal table name")
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument(
        "days_interval_start", type=str, help="start interval of days to reprocess"
    )
    parser.add_argument(
        "days_interval_end", type=str, help="end interval of days to reprocess"
    )
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument(
        "source_layer", type=str, help="raw/clean values to get data from"
    )
    parser.add_argument(
        "target_layer", type=str, help="clean/enrich values to save data to"
    )
    args = parser.parse_args()

    logger.info(
        "m=load_data_to_metastore, file_name={}, execution_date={}, msg=print args spark "
        "jobs params".format(args.file_name, args.execution_date)
    )

    execution_date = args.execution_date
    table_name = file_name = args.file_name.replace("-", "_")
    days_interval_start = int(args.days_interval_start)
    days_interval_end = int(args.days_interval_end)
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = "zendesk"
    source_layer = args.source_layer
    target_layer = args.target_layer
    partition = ["year", "month", "day"]

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)

    spark_client = SparkClient()
    spark_db = db_info["db_" + source_layer + "_databricks"]
    conn_config = {"db": spark_db}
    databricks_consumer = DatabricksConsumer(conn_config, spark_client)

    dt_exec = datetime.strptime(execution_date, "%Y-%m-%d")
    for delta_day in range(days_interval_start - 1, days_interval_end):
        dt_execution = dt_exec + timedelta(days=-delta_day)
        year, month, day = dt_execution.year, dt_execution.month, dt_execution.day

        query_path = (
            QUERIES_DATALAKE_PATH + source + f"/{target_layer}/{table_name}.sql"
        )
        query = FileService.get_query_from_file_name(query_path).format(
            db=spark_db, year=year, month=month, day=day
        )
        df = databricks_consumer.get_data_from_query(query)

        spark_metastore_service = SparkMetastoreService(spark_client)
        database_name = db_info["db_" + target_layer + "_databricks"]
        spark_metastore_service.create_database(database_name)
        s3_loader = S3Loader(spark_metastore_service)

        s3_loader.load_incremental_table(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=SparkTableStorageFormat.get_storage(target_layer),
            database_location=db_info["db_" + target_layer + "_path"],
            partition_cols=partition,
            schema_merging=True,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=partition,
        )

        spark_metastore_service.refresh_table(database_name, table_name)
