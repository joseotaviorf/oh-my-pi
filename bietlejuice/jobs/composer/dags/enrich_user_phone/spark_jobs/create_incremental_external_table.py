import logging
from collections import OrderedDict
from datetime import datetime
from argparse import ArgumentParser
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService

from bietlejuice.jobs.composer.clients.db_clients import SparkClient, AthenaClient
from bietlejuice.jobs.composer.dags.enrich_user_phone.spark_jobs import SOURCE
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)

JOB_NAME = "create_incremental_external_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("datalake_bucket")
    parser.add_argument("athena_query_result_location")
    parser.add_argument("layer", type=str, help="raw/clean/enrich values")
    parser.add_argument("table_name", type=str, help="table name")

    args = parser.parse_args()
    environment = args.env
    execution_date = args.execution_date
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location
    layer = args.layer
    table_name = args.table_name

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", dt_execution.year),
            ("month", dt_execution.month),
            ("day", dt_execution.day),
        ]
    )

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    spark_db = db_info["db_" + layer + "_databricks"]
    athena_db = db_info["db_" + layer + "_athena"]

    athena_client = AthenaClient(athena_query_result_location)
    athena_metastore_service = AthenaMetastoreService(athena_client)
    athena_metastore_service.create_database(athena_db)

    logger.info(
        "m=create_incremental_external_table, msg=Creating external table {}.{}".format(
            athena_db, table_name
        )
    )

    spark_metastore_service = SparkMetastoreService(SparkClient())
    table_schema = spark_metastore_service.get_table_schema(spark_db, table_name)

    existing_tables = [
        row["Data"][0]["VarCharValue"]
        for row in athena_metastore_service.get_table_names(athena_db)["ResultSet"][
            "Rows"
        ]
    ]
    if table_name not in existing_tables:
        athena_metastore_service.create_external_table(
            database_name=athena_db,
            table_name=table_name,
            table_location=db_info["db_" + layer + "_path"] + table_name,
            table_schema=table_schema,
            partition_cols=list(partitions.keys()),
            format_options=TableStorageFormat.get_storage(layer),
        )
        athena_metastore_service.repair_table_partitions(athena_db, table_name)
    else:
        athena_metastore_service.add_partitions(athena_db, table_name, [partitions])

    logger.info(
        "m=__main__, msg=External table {}.{} created successfully.".format(
            athena_db, table_name
        )
    )
