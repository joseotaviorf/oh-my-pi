from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.etl import FileService
from bietlejuice.jobs.composer.base.spark import (
    SparkMetastoreService,
    SparkTableStorageFormat,
    spark,
    sqlContext,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.dags.bigfone_event import (
    QUERIES_BIGFONE_EVENT_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.dags.bigfone_event.spark_jobs import SOURCE
from bietlejuice.jobs.composer.loaders import SparkDataframeIntoDatalakeLoader
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient

JOB_NAME = "load_event_table_into_datalake_clean"
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description="load_event_table_into_datalake_clean")

    # args passed by Airflow task
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")

    args = parser.parse_args()

    logger.info(
        "m=__main__, execution_date={}, environment={}, msg=print args spark jobs "
        "params".format(args.execution_date, args.environment)
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
        QUERIES_BIGFONE_EVENT_DATALAKE_PATH + "/clean/" + table_name + ".sql"
    )

    datalake_info = DatalakeMetastoreService().get_db_info(environment, SOURCE)

    conn_config = {"db": datalake_info["db_raw_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, SparkClient())
    event_table_data = databricks_consumer.get_data_from_query(
        query.format(**query_filter)
    )

    spark_metastore_service = SparkMetastoreService(
        datalake_info["db_clean_databricks"],
        datalake_info["db_clean_path"],
        SparkSQLCLient(spark, sqlContext),
    )

    # create database if not exists
    spark_metastore_service.create_database()

    # loaders
    loader = SparkDataframeIntoDatalakeLoader(
        format=SparkTableStorageFormat.DEFAULT_CLEAN,
        metastore_service=spark_metastore_service,
    )
    loader.overwrite_partition(
        df=event_table_data,
        partition_by_list=list_partitions,
        table_name=table_name,
        schema_merging=True,
    )

    # create partition into spark table
    spark_metastore_service.create_new_partitions_from_df(
        table_name=table_name, df=event_table_data, partition_by_list=list_partitions
    )
