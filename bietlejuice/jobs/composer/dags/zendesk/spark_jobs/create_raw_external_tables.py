import logging
from argparse import ArgumentParser
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.spark import (
    SparkMetastoreService,
    spark,
    sqlContext,
)
from bietlejuice.jobs.composer.wrappers import SparkSQLCLient
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.wrappers import AthenaClient

JOB_NAME = "create_raw_external_tables"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env
    source = "zendesk"

    db_info = DatalakeMetastoreService.get_db_info(environment, source)
    db_raw_athena = db_info["db_raw_athena"]
    db_raw_path = db_info["db_raw_path"]
    athena_client = AthenaClient()
    athena_client.create_database(db_raw_athena)

    spark_metastore_service = SparkMetastoreService(
        db_info["db_raw_databricks"], db_raw_path, SparkSQLCLient(spark, sqlContext)
    )
    table_names = spark_metastore_service.get_table_names()
    logger.info("m=__main__, msg=Creating raw external tables...")
    for table_name in table_names:
        table_schema = spark_metastore_service.get_table_schema(table_name)
        athena_client.overwrite_external_table(
            database=db_raw_athena,
            table_name=table_name,
            s3_table_path=db_raw_path + table_name,
            table_schema=table_schema,
            partition_by=["year", "month", "day"],
            base_format=TableStorageFormat.DEFAULT_RAW,
        )
        athena_client.repair_table_partitions(db_raw_athena, table_name)
    logger.info("m=__main__, msg=All raw external tables were created successfully.")
