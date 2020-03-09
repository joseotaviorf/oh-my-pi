import logging
from argparse import ArgumentParser
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService

from bietlejuice.jobs.composer.clients.db_clients import SparkClient, AthenaClient
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)

JOB_NAME = "create_external_tables"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("storage", type=str, help="raw/clean values")
    parser.add_argument("table_name", type=str, help="table name")
    parser.add_argument(
        "--partition_by",
        nargs="+",
        dest="partition_by",
        required=False,
        help="how to partition tables",
    )
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    storage = args.storage
    table_name = args.table_name.replace("-", "_")
    partition_cols = args.partition_by
    source = "zendesk"

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_db = db_info["db_" + storage + "_databricks"]
    athena_db = db_info["db_" + storage + "_athena"]

    athena_client = AthenaClient()
    athena_metastore_service = AthenaMetastoreService(athena_client)
    athena_metastore_service.create_database(athena_db)

    spark_metastore_service = SparkMetastoreService(SparkClient())
    table_names = spark_metastore_service.get_table_names(spark_db)

    logger.info("m=__main__, msg=Creating {} external tables...".format(storage))

    table_schema = spark_metastore_service.get_table_schema(spark_db, table_name)
    athena_metastore_service.drop_table(athena_db, table_name)

    athena_metastore_service.create_external_table(
        database_name=athena_db,
        table_name=table_name,
        table_location=db_info["db_" + storage + "_path"] + table_name,
        table_schema=table_schema,
        partition_cols=partition_cols,
        format_options=TableStorageFormat.get_storage(storage),
    )

    if partition_cols:
        athena_metastore_service.repair_table_partitions(athena_db, table_name)

    logger.info(
        "m=__main__, msg=All {} external tables were created successfully.".format(
            storage
        )
    )
