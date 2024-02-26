import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import MySqlConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_mission_control_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("extraction_type", type=str)
    parser.add_argument("partition_cols")
    parser.add_argument("date_filter_column", help="Date filter column")
    parser.add_argument("execution_date", type=str, help="DAG execution date")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    extraction_type = args.extraction_type
    partition_cols = json.loads(args.partition_cols)
    date_filter_column = args.date_filter_column
    execution_date = args.execution_date
    
    if extraction_type == "incremental":
        logger.info(
            f"""
                    m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                    table_name={table_name}, extraction_type={extraction_type}, date_filter_column={date_filter_column},
                    execution_date={execution_date}, partition_cols={args.partition_cols} msg=Starting spark job...
            """
        )
    else:
        logger.info(
            f"""
                    m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                    table_name={table_name}, extraction_type={extraction_type} msg=Starting spark job...
            """
        )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.MISSION_CONTROL
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    mysql_consumer = MySqlConsumer(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)

    # create database if it doesn't exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    if extraction_type == "incremental":
        df = mysql_consumer.get_incremental_data_from_table(
            table_name=table_name,
            date_filter_column=date_filter_column,
            date_filter_value=execution_date,
        )
        if not df.rdd.isEmpty():
            logger.info("m=__main__, msg=RDD is not empty. Loading into S3.")
            IncrementalTableLoaderPipeline(
                database_name,
                table_name.lower(),
                database_location,
                LayerEnum.RAW,
                None,
                partition_cols,
            ).load_and_register(df, format_options)
        else:
            logger.info("m=__main__, msg=RDD is empty")
    else:
        df = mysql_consumer.get_data_from_table(table_name)
        if not df.rdd.isEmpty():
            logger.info("m=__main__, msg=RDD is not empty. Loading into S3.")
            FullTableLoaderPipeline(
                database_name, table_name.lower(), database_location, LayerEnum.RAW, None
            ).load_and_register(df, format_options)
        else:
            logger.info("m=__main__, msg=RDD is empty")