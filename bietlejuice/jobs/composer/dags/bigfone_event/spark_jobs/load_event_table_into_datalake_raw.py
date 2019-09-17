import json
from argparse import ArgumentParser

from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import PostgreSQLConsumer
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.etl import FileService
from bietlejuice.jobs.composer.base.spark import (
    SparkMetastoreService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.loaders import SparkDataframeIntoDatalakeLoader
from bietlejuice.jobs.composer.dags.bigfone_event import (
    QUERIES_BIGFONE_EVENT_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.dags.bigfone_event.spark_jobs import (
    SOURCE,
    DATABRICKS_SCOPE,
    base_dbutils,
    spark_sql_client,
)


JOB_NAME = "load_event_table_into_datalake_raw"
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description="load_event_table_into_datalake_raw")

    # args passed by Airflow task
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")

    args = parser.parse_args()

    logger.info(
        "m={}, execution_date={}, environment={}, msg=print args spark jobs params".format(
            JOB_NAME, args.execution_date, args.environment
        )
    )

    execution_date = args.execution_date
    environment = args.environment
    table_name = "events"

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    query_filter = OrderedDict(
        [
            ("year", int(dt_execution.year)),
            ("month", int(dt_execution.month)),
            ("day", int(dt_execution.day)),
        ]
    )

    # creation date and event type partitions
    list_partitions = list(query_filter.keys())
    list_partitions.append("event")

    # get query to create event table
    query = FileService().get_query_from_file_name(
        QUERIES_BIGFONE_EVENT_DATALAKE_PATH + "/raw/" + table_name + ".sql"
    )

    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    # get BigFone credentials stored in Databricks secrets
    json_connection = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=SOURCE)

    # establish connection and get data from Event table
    connection = json.loads(json_connection)
    consumer = PostgreSQLConsumer(connection)
    event_table_data = consumer.get_data_from_query(query.format(**query_filter))

    datalake_info = DatalakeMetastoreService().get_db_info(environment, SOURCE)

    spark_service = SparkMetastoreService(
        datalake_info["db_raw_databricks"],
        datalake_info["db_raw_path"],
        spark_sql_client,
    )

    # loaders
    loader = SparkDataframeIntoDatalakeLoader(
        format=SparkTableStorageFormat.DEFAULT_RAW, metastore_service=spark_service
    )
    loader.overwrite_partition(
        df=event_table_data,
        partition_by_list=list_partitions,
        table_name=table_name,
        schema_merging=True,
    )

    # create partition into spark table
    spark_service.create_new_partitions_from_df(
        table_name=table_name, df=event_table_data, partition_by_list=list_partitions
    )
