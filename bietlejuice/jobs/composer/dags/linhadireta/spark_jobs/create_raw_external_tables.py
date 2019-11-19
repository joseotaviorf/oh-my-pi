import logging
from argparse import ArgumentParser
from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.wrappers import AthenaClient

JOB_NAME = "create_raw_external_tables"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env
    source = "linhadireta"

    db_info = DatalakeMetastoreService.get_db_info(environment, source)
    athena_db = db_info["db_raw_athena"]
    athena_client = AthenaClient()
    conn_config = {"db": db_info["db_raw_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, SparkClient())
    tables = databricks_consumer.get_table_names_and_sizes().collect()

    logger.info("m=__main__, msg=Creating raw external tables...")
    for table in tables:
        table_name = table.table_name
        table_schema = OrderedDict(
            [
                (row["col_name"], row["col_type"].lower())
                for row in databricks_consumer.get_table_schema(table_name).collect()
            ]
        )
        athena_client.overwrite_external_table(
            database=athena_db,
            table_name=table_name,
            s3_table_path=db_info["db_raw_path"] + table_name,
            table_schema=table_schema,
            partition_by=None,
            base_format=TableStorageFormat.DEFAULT_RAW,
        )

    logger.info("m=__main__, msg=All raw external tables were created successfully.")
