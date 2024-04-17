import json
import logging
import ast
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_betopera_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("partition_cols")
    parser.add_argument("tables_list")
    parser.add_argument("execution_date")
    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    partition_cols = ast.literal_eval(args.partition_cols)
    tables_list = ast.literal_eval(args.tables_list)
    execution_date = args.execution_date
    DATE_FILTER_COLUMN = "updated_at"

    logger.info(
        f"""
                m=__main__, environment={environment}, datalake_bucket={datalake_bucket}, source={source},
                partition_cols={partition_cols}, tables_list={tables_list}, execution_date={execution_date}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.BETOPERA
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    tables = postgres_consumer.get_table_names_and_sizes().collect()
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    for table in tables:
        if table.table_name in tables_list:
            df = postgres_consumer.get_incremental_data_from_table(
                table_name=table.table_name,
                date_filter_column=DATE_FILTER_COLUMN,
                date_filter_value=execution_date,
            )
            # the table names in the datalake must be lowercase
            s3_loader.load_df(
                df=df,
                s3_path=f"{database_location}{table.table_name.lower()}",
                format_options=format_options,
                partitions=partition_cols,
            )
            spark_metastore_loader.update_metastore(
                df,
                database_name,
                table.table_name.lower(),
                format_options,
                database_location,
                partitions=partition_cols,
            )
