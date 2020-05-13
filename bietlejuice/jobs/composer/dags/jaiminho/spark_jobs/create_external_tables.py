import logging
from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient, SparkClient
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)

JOB_NAME = "create_external_tables"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    # args passed by Airflow task
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("athena_query_result_location")
    parser.add_argument("datalake_layer", type=str, help="Datalake Layer [raw|clean]")
    parser.add_argument("source", type=str, help="Source")
    parser.add_argument("execution_date", type=str, help="Execution date DAG")
    parser.add_argument("table_name", type=str, help="table name")

    args = parser.parse_args()

    env = args.env
    dl_bucket = args.datalake_bucket
    athena_qrslt_loc = args.athena_query_result_location
    dl_layer = args.datalake_layer
    source = args.source
    execution_date = args.execution_date
    table_name = args.table_name

    logger.info(
        f"m=__main__, env={env}, datalake_layer={dl_layer}, source={source}, "
        f"table={table_name}, execution_date={execution_date}, msg=Job execution started"
    )

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", dt_execution.year),
            ("month", dt_execution.month),
            ("day", dt_execution.day),
        ]
    )
    partition_cols = list(partitions.keys())

    db_info = DatalakeMetastoreService.get_db_info(env, source, dl_bucket)
    athena_database_name = db_info[f"db_{dl_layer}_athena"]
    athena_ms_service = AthenaMetastoreService(AthenaClient(athena_qrslt_loc))
    athena_ms_service.create_database(athena_database_name)

    spark_ms_service = SparkMetastoreService(SparkClient())
    format_options = TableStorageFormat.get_storage(dl_layer)

    logger.info("m=__main__, msg=Creating external tables...")

    s3_database_path = db_info[f"db_{dl_layer}_path"]
    spark_ms_database_name = db_info[f"db_{dl_layer}_databricks"]

    logger.info(
        f"m=create_incremental_external_table, table={table_name}, msg=Creating external tables if not exists."
    )

    table_schema = spark_ms_service.get_table_schema(spark_ms_database_name, table_name)
    athena_ms_service.create_external_table(
        database_name=athena_database_name,
        table_name=table_name,
        table_location=s3_database_path + table_name,
        table_schema=table_schema,
        partition_cols=partition_cols,
        format_options=format_options,
    )

    athena_ms_service.add_partitions(
        database_name=athena_database_name,
        table_name=table_name,
        partitions=[partitions],
    )

    logger.info("m=__main__, msg=External tables were created successfully.")
