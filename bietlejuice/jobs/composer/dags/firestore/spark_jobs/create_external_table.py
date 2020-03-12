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


JOB_NAME = "create_external_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    # Gets arguments passed by Airflow task
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("athena_query_result_location")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("storage")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    source = args.source
    table_name = args.table_name
    storage = args.storage

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    db_databricks = db_info["db_{}_databricks".format(storage)]
    db_athena = db_info["db_{}_athena".format(storage)]
    db_path = db_info["db_{}_path".format(storage)]

    athena_metastore_service = AthenaMetastoreService(
        AthenaClient(athena_query_result_location)
    )
    spark_metastore_service = SparkMetastoreService(SparkClient())

    # Creates external table
    logger.info(
        "m=__main__, table_name= {}, msg=Creating {} external table...".format(
            table_name, storage
        )
    )
    table_schema = spark_metastore_service.get_table_schema(db_databricks, table_name)
    partition_cols = ["year", "month", "day"]
    athena_metastore_service.create_database(db_athena)
    athena_metastore_service.drop_table(db_athena, table_name)
    athena_metastore_service.create_external_table(
        database_name=db_athena,
        table_name=table_name,
        table_location=db_path + table_name,
        table_schema=table_schema,
        partition_cols=partition_cols,
        format_options=TableStorageFormat.get_storage(storage),
    )
    athena_metastore_service.repair_table_partitions(db_athena, table_name)

    logger.info("m=__main__, msg=External table created successfully.")
