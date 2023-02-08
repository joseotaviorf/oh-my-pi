import json
import logging
import ast
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import MySqlConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_incremental_atta_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("db")
    parser.add_argument("date_filter_column")
    parser.add_argument("clean_partition_columns")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    db = args.db
    date_filter_column = args.date_filter_column
    clean_partition_columns = ast.literal_eval(args.clean_partition_columns)
    execution_date = args.execution_date


    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, table_name={table_name},
                db={db}, date_filter_column={date_filter_column}, clean_partition_columns={clean_partition_columns}, execution_date={execution_date}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.ATTA)
    conn_config = json.loads(conn_config_json)
    conn_config['db']=db
    spark_client = SparkClient()
    mysql_consumer = MySqlConsumer(conn_config, SparkClient())

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)


    df = mysql_consumer.get_incremental_data_from_table(
            table_name=table_name,
            date_filter_column= date_filter_column,
            date_filter_value=execution_date
    )
        # the table names in the datalake must be lowercase
    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name.lower()}",
        format_options=format_options,
        partitions=clean_partition_columns,
    )


    spark_metastore_loader.update_metastore(
        df,
        database_name,
        table_name.lower(),
        format_options,
        database_location,
        partitions=clean_partition_columns,
    )
    metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=clean_partition_columns,
        )
