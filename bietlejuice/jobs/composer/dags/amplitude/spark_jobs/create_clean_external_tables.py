import logging
from argparse import ArgumentParser
from multiprocessing.dummy import Pool
from collections import OrderedDict

from pyspark.sql.functions import col
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.wrappers import AthenaClient
from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.dags.amplitude.spark_jobs.db_info import (
    AmplitudeDatabaseInfo,
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_clean_external_tables")

parser = ArgumentParser(description="create_clean_external_tables")
parser.add_argument("env")

NB_THREADS = 8


def create_clean_external_table(args):
    db_clean_athena, table_name, s3_table_path, consumer = args
    table_schema = consumer.get_table_schema(table_name).collect()
    table_schema = OrderedDict(
        [
            (row["col_name"], row["col_type"].lower().replace("timestamp", "string"))
            for row in table_schema
        ]
    )
    partition_by = ["year", "month", "day"]
    AthenaClient.create_external_table(
        database=db_clean_athena,
        table_name=table_name,
        s3_table_path=s3_table_path,
        table_schema=table_schema,
        partition_by=partition_by,
        drop=True,
        base_format=TableStorageFormat.DEFAULT_CLEAN,
    )
    AthenaClient.repair_table_partitions(db_clean_athena, table_name)


if __name__ == "__main__":
    args = parser.parse_args()
    env = args.env

    db_info = AmplitudeDatabaseInfo.get_db_info(env)
    db_clean_databricks = db_info["db_clean_databricks"]
    db_clean_athena = db_info["db_clean_athena"]
    db_clean_path = db_info["db_clean_path"]

    AthenaClient.execute_athena_query(
        "CREATE DATABASE IF NOT EXISTS `{}`".format(db_clean_athena), "default"
    )

    connection = {"db": db_clean_databricks}
    databricks_consumer = DatabricksConsumer(connection)
    df = databricks_consumer.get_table_names_and_sizes()
    tables = (
        df.select("table_name")
        .filter(
            col("table_name").rlike(r".+_events")
        )  # get only filtered event type tables
        .collect()
    )

    logger.info("m=__main__, msg=Creating clean external tables...")
    with Pool(NB_THREADS) as p:
        p.map(
            create_clean_external_table,
            [
                (
                    db_clean_athena,
                    table.table_name,
                    db_clean_path + table.table_name,
                    databricks_consumer,
                )
                for table in tables
            ],
        )
    logger.info("m=__main__, msg=All clean external tables were created successfully.")
