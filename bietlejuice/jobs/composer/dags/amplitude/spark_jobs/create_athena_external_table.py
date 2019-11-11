import logging
from argparse import ArgumentParser
from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.wrappers import AthenaClient
from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService

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
    partition_by = args.partition_by

    # setup
    source = "amplitude"
    db_info = DatalakeMetastoreService.get_db_info(env, source)
    db_clean_databricks = db_info["db_clean_databricks"]
    db_clean_athena = db_info["db_clean_athena"]
    db_clean_path = db_info["db_clean_path"]

    athena_client = AthenaClient()
    conn_config = {"db": db_clean_databricks}
    databricks_consumer = DatabricksConsumer(conn_config, SparkClient())

    # create athena external table
    logger.info(
        "m=__main__, table_name= {}, msg=Creating athena external table...".format(
            table_name
        )
    )

    athena_client.execute_athena_query(
        "CREATE DATABASE IF NOT EXISTS `{}`".format(db_clean_athena), "default"
    )

    table_schema = databricks_consumer.get_table_schema(table_name).collect()
    table_schema = OrderedDict(
        [
            (row["col_name"], row["col_type"].lower().replace("timestamp", "string"))
            for row in table_schema
        ]
    )

    athena_client.overwrite_external_table(
        database=db_clean_athena,
        table_name=table_name,
        s3_table_path=db_clean_path + table_name,
        table_schema=table_schema,
        partition_by=partition_by,
        base_format=TableStorageFormat.DEFAULT_CLEAN,
    )
    athena_client.repair_table_partitions(db_clean_athena, table_name)

    logger.info("m=__main__, msg=External table created successfully.")
