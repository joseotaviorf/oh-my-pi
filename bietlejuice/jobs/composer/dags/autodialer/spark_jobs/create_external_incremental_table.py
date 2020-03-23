import logging

from argparse import ArgumentParser
from collections import OrderedDict
from datetime import datetime
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient, SparkClient
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)

JOB_NAME = "create_external_incremental_tables"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
NB_THREADS = 8


@logger
def get_tables(all_tables, tables, env, source, datalake_bucket, datalake_layer):
    if not all_tables and not tables:
        raise RuntimeError(
            "m=raise_for_error, msg=No table list nor --all were passed through method call, "
            "nothing to do."
        )
    logger.info(
        f"m=get_tables,msg=Getting tables from Athena Metastore. Value from tables {tables}."
    )
    if all_tables:
        db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
        db_databricks = db_info[f"db_{datalake_layer}_databricks"]
        spark_metastore_service = SparkMetastoreService(SparkClient())
        tables = spark_metastore_service.get_table_names(database_name=db_databricks)
    logger.info(f"m=get_tables,msg=Returned tables {tables}.")

    return tables


@logger
def create_incremental_external_table(args):
    (
        env,
        athena_ms_service,
        spark_ms_service,
        datalake_bucket,
        datalake_layer,
        table_name,
        format_options,
        partitions_cols,
        partition_values,
    ) = args

    logger.info(
        f"m=create_incremental_external_table, table={table_name}, msg=Creating external tables if not exists."
    )

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    db_path = db_info[f"db_{datalake_layer}_path"]
    db_athena_name = db_info[f"db_{datalake_layer}_athena"]
    db_databricks = db_info[f"db_{datalake_layer}_databricks"]

    logger.info(
        f"m=create_incremental_external_table, table={table_name}, msg=Creating external tables if not exists."
    )

    table_schema = spark_ms_service.get_table_schema(db_databricks, table_name)
    athena_ms_service.create_external_table(
        database_name=db_athena_name,
        table_name=table_name,
        table_location=db_path + table_name,
        table_schema=table_schema,
        partition_cols=partitions_cols,
        format_options=format_options,
    )

    logger.info(
        f"m=create_incremental_external_table, table={table_name}, msg=Finished creating table."
    )

    if partition_values:
        athena_ms_service.add_partitions(
            database_name=db_athena_name,
            table_name=table_name,
            partitions=partition_values,
        )


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    # args passed by Airflow task
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("athena_query_result_location")
    parser.add_argument("datalake_layer", type=str, help="Datalake Layer [raw|clean]")
    parser.add_argument("source", type=str, help="Source")
    parser.add_argument("execution_date", type=str, help="Execution date DAG")
    parser.add_argument("--tables", nargs="+", dest="tables", required=False)
    parser.add_argument(
        "--all", nargs="?", dest="all_tables", required=False, default=False, const=True
    )

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    datalake_layer = args.datalake_layer
    source = args.source
    execution_date = args.execution_date
    tables = args.tables
    all_tables = args.all_tables

    logger.info(
        f"m=__main__, env={environment}, datalake_layer={datalake_layer}, source={source}, "
        f"tables={tables}, all={all_tables}, execution_date={execution_date}, msg=Job execution started"
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
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)

    athena_ms_service = AthenaMetastoreService(
        AthenaClient(athena_query_result_location)
    )

    logger.info("m=__main__, msg=Creating Athena database if not exists...")
    athena_ms_service.create_database(db_info[f"db_{datalake_layer}_athena"])

    spark_ms_service = SparkMetastoreService(SparkClient())

    tables = get_tables(
        all_tables=all_tables,
        tables=tables,
        env=environment,
        source=source,
        datalake_bucket=datalake_bucket,
        datalake_layer=datalake_layer,
    )

    format_options = TableStorageFormat.get_storage(datalake_layer)

    logger.info("m=__main__, msg=Creating external tables...")
    with Pool(NB_THREADS) as process:
        process.map(
            create_incremental_external_table,
            [
                (
                    environment,
                    athena_ms_service,
                    spark_ms_service,
                    datalake_bucket,
                    datalake_layer,
                    table_name,
                    format_options,
                    partition_cols,
                    [partitions],
                )
                for table_name in tables
            ],
        )
    logger.info("m=__main__, msg=External tables were created successfully.")
