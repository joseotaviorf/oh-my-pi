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

JOB_NAME = "load_data_to_clean"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description="load_data_to_clean")
    parser.add_argument("file_name", type=str, help="file name is equal table name")
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument(
        "days_interval_start", type=str, help="start interval of days to reprocess"
    )
    parser.add_argument(
        "days_interval_end", type=str, help="end interval of days to reprocess"
    )
    parser.add_argument("environment", type=str, help="forno/prod values")
    args = parser.parse_args()

    logger.info(
        "m=load_data_to_clean, file_name={}, execution_date={}, msg=print args spark "
        "jobs params".format(args.file_name, args.execution_date)
    )

    execution_date = args.execution_date
    table_name = file_name = args.file_name.replace("-", "_")
    days_interval_start = int(args.days_interval_start)
    days_interval_end = int(args.days_interval_end)
    environment = args.environment
    source = "zendesk"
    partition = ["year", "month", "day"]

    db_info = DatalakeMetastoreService.get_db_info(environment, source)

    spark_client = SparkClient()
    conn_config = {"db": db_info["db_raw_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, spark_client)

    dt_exec = datetime.strptime(execution_date, "%Y-%m-%d")
    for delta_day in range(days_interval_start - 1, days_interval_end):
        dt_execution = dt_exec + timedelta(days=-delta_day)
        year, month, day = dt_execution.year, dt_execution.month, dt_execution.day

        query_path = QUERIES_DATALAKE_PATH + source + "/{}.sql".format(table_name)
        query = FileService.get_query_from_file_name(query_path).format(
            db=db_info["db_raw_databricks"], year=year, month=month, day=day
        )
        df = databricks_consumer.get_data_from_query(query)

        spark_metastore_service = SparkMetastoreService(spark_client)
        database_name = db_info["db_clean_databricks"]
        spark_metastore_service.create_database(database_name)
        s3_loader = S3Loader(spark_metastore_service)

        s3_loader.load_incremental_table(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=SparkTableStorageFormat.DEFAULT_CLEAN,
            database_location=db_info["db_clean_path"],
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
