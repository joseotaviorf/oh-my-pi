import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient, SparkClient
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_clean_external_tables")

parser = ArgumentParser(description="create_clean_external_tables")
parser.add_argument("env")
parser.add_argument("table_name")
parser.add_argument("--partition_by", nargs="+", dest="partition_by", required=False)

if __name__ == "__main__":
    args = parser.parse_args()
    env = args.env
    table_name = args.table_name
    partition_cols = args.partition_by

    # setup
    source = "amplitude"
    db_info = DatalakeMetastoreService.get_db_info(env, source)
    db_clean_databricks = db_info["db_clean_databricks"]
    db_clean_athena = db_info["db_clean_athena"]
    db_clean_path = db_info["db_clean_path"]

    # create athena external table
    logger.info(
        "m=__main__, table_name= {}, msg=Creating athena external table...".format(
            table_name
        )
    )

    spark_metastore_service = SparkMetastoreService(SparkClient())
    table_schema = spark_metastore_service.get_table_schema(
        db_clean_databricks, table_name
    )

    athena_metastore_service = AthenaMetastoreService(AthenaClient())
    athena_metastore_service.create_database(db_clean_athena)
    athena_metastore_service.drop_table(db_clean_athena, table_name)
    athena_metastore_service.create_external_table(
        database_name=db_clean_athena,
        table_name=table_name,
        table_location=db_clean_path + table_name,
        table_schema=table_schema,
        partition_cols=partition_cols,
        format_options=TableStorageFormat.DEFAULT_CLEAN,
    )
    athena_metastore_service.repair_table_partitions(db_clean_athena, table_name)

    logger.info("m=__main__, msg=External table created successfully.")
