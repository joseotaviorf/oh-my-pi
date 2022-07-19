import logging
from argparse import ArgumentParser
from datetime import datetime
from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient, SparkClient
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("update_athena_table_daily_partition")

parser = ArgumentParser(description="update_athena_table_daily_partition")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("athena_query_result_location")
parser.add_argument("source")
parser.add_argument("table_name")
parser.add_argument("stage")

if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    source = args.source
    table_name = args.table_name
    stage = args.stage

    logger.info(
        "m=__main__, execution_date={}, env={}, source={}, "
        "table_name{}, stage={}, msg=Job started".format(
            execution_date, env, source, table_name, stage
        )
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    # setup
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    athena_metastore_service = AthenaMetastoreService(
        AthenaClient(athena_query_result_location)
    )

    # get table metadata
    db_athena = db_info["db_{}_athena".format(stage)]

    # create athena external table if not exist
    existing_tables = [
        row["Data"][0]["VarCharValue"]
        for row in athena_metastore_service.get_table_names(db_athena)["ResultSet"][
            "Rows"
        ]
    ]
    if table_name not in existing_tables:
        logger.info(
            "m=__main__, table_name= {}, msg=Creating athena external table...".format(
                table_name
            )
        )
        format_options = TableStorageFormat.get_storage(stage)
        db_databricks = db_info["db_{}_databricks".format(stage)]
        db_path = db_info["db_{}_path".format(stage)]

        spark_metastore_service = SparkMetastoreService(SparkClient())
        table_schema = spark_metastore_service.get_table_schema(
            db_databricks, table_name
        )
        athena_metastore_service.create_external_table(
            database_name=db_athena,
            table_name=table_name,
            table_location=db_path + table_name,
            table_schema=table_schema,
            partition_cols=["year", "month", "day"],
            format_options=format_options,
        )
        athena_metastore_service.repair_table_partitions(db_athena, table_name)
        logger.info("m=__main__, msg=External table created successfully.")

    # add daily partition
    partitions = [OrderedDict([("year", year), ("month", month), ("day", day)])]
    athena_metastore_service.add_partitions(
        database_name=db_athena, table_name=table_name, partitions=partitions
    )
