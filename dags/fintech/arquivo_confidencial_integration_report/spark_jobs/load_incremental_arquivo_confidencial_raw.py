import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import MySqlConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_incremental_arquivo_confidencial_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("date_filter_column", help="Date filter column")
    parser.add_argument("execution_date", type=str, help="DAG execution date")
    parser.add_argument(
        "unixtime_measure", type=str, help="Column unixtime unit", nargs="?"
    )

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    schema = args.schema
    table_name = args.table_name
    date_filter_column = args.date_filter_column
    execution_date = args.execution_date
    unixtime_measure = args.unixtime_measure

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, schema={schema}
                table_name={table_name}, date_filter_column={date_filter_column}, unixtime_measure={unixtime_measure},
                execution_date={execution_date}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.ARQUIVO_CONFIDENCIAL
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    mysql_consumer = MySqlConsumer(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)

    # create database if it doesn't exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    df = mysql_consumer.get_incremental_data_from_table(
        table_name=table_name,
        date_filter_column=date_filter_column,
        date_filter_value=execution_date,
        unixtime_measure=unixtime_measure,
    )

    if df:
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            database_location=database_location,
            partitions=["year", "month", "day"],
        )
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            partitions=["year", "month", "day"],
            force_recreate=False,
        )
    else:
        logger.warning(
            f"""m=__main__, table_name={table_name}, execution_date={execution_date},
            msg=No data returned from Production database."""
        )
