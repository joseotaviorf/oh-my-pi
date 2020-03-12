import logging
from argparse import ArgumentParser
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient, SparkClient
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)

JOB_NAME = "create_external_tables"
NB_THREADS = 16

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(description=JOB_NAME)
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("athena_query_result_location")
parser.add_argument("datalake_layer")
parser.add_argument("source")
parser.add_argument("schema")
parser.add_argument("--tables", nargs="+", dest="tables", required=False)
parser.add_argument(
    "--all", nargs="?", dest="all", required=False, default=False, const=True
)


@logger
def get_tables(all, tables):
    if not all and not tables:
        raise RuntimeError(
            "m=raise_for_error, msg=No --tables with tables list nor --all flag sent, "
            "nothing to do."
        )

    if all:
        db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
        db_databricks = db_info[f"db_{datalake_layer}_databricks"]
        spark_metastore_service = SparkMetastoreService(SparkClient())
        tables = spark_metastore_service.get_table_names(
            database_name=db_databricks, regex=f"{schema}_*"
        )

    return tables


@logger
def create_external_table(args):
    athena_ms_service, spark_ms_service, datalake_layer, table_name = args

    # get table metadata
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    db_path = db_info[f"db_{datalake_layer}_path"]
    db_athena = db_info[f"db_{datalake_layer}_athena"]
    db_databricks = db_info[f"db_{datalake_layer}_databricks"]

    table_schema = spark_ms_service.get_table_schema(db_databricks, table_name)
    athena_ms_service.create_external_table(
        database_name=db_athena,
        table_name=table_name,
        table_location=db_path + table_name,
        table_schema=table_schema,
        partition_cols=[],
        format_options=format_options,
    )

    logger.info(
        f"m=create_external_table, table={table_name}, msg=Finished creating table."
    )


if __name__ == "__main__":
    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    datalake_layer = args.datalake_layer
    source = args.source
    schema = args.schema
    tables = args.tables
    all = args.all

    logger.info(
        f"m=__main__, env={env}, datalake_layer={datalake_layer}, source={source}, "
        f"tables={tables}, all={all}, msg=Job execution started"
    )

    tables = get_tables(all, tables)

    athena_ms_service = AthenaMetastoreService(
        AthenaClient(athena_query_result_location)
    )
    spark_ms_service = SparkMetastoreService(SparkClient())
    format_options = getattr(
        TableStorageFormat, "DEFAULT_{}".format(datalake_layer.upper())
    )

    logger.info("m=__main__, msg=Creating external tables...")
    with Pool(NB_THREADS) as p:
        p.map(
            create_external_table,
            [
                (athena_ms_service, spark_ms_service, datalake_layer, table)
                for table in tables
            ],
        )
    logger.info("m=__main__, msg=External tables were created successfully.")
