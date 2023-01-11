import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService


def _load_dataframe_in_datalake(
    df, table_name, is_incremental=False, force_recreate=True
):
    """
    This method loads the dataframe into the s3 bucket and updates the metastore.
    @param df: DataFrame.
    @param table_name: table name in raw layer.
    @param is_incremental: bool. True indicates that the table will be loaded incrementally.
    By default, this parameter is set to False.
    @param force_recreate: bool. Indicates if it must force table recreation in metastore.
    """
    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols if is_incremental else None,
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partitions=partition_cols if is_incremental else [],
        force_recreate=force_recreate,
    )


def _load_table_data(raw_table_name, table_details):
    """
    This method takes the data from the table in the Postgres database, considering the
    parameters if it is incremental or full load.
    @param raw_table_name: table name in raw layer.
    @param table_details: Information about the table returned by the database.
    """
    if table_details.get("is_incremental"):
        date_column = table_details["date_column"]
        unixtime_measure = table_details.get("unixtime_measure")

        df = postgres_consumer.get_incremental_data_by_granularity_from_table(
            raw_table_name, date_column, execution_date, unixtime_measure
        )

        _load_dataframe_in_datalake(
            df=df, table_name=raw_table_name, is_incremental=True, force_recreate=False
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=raw_table_name,
            df=df,
            partition_cols=partition_cols,
        )
    else:
        df = postgres_consumer.get_data_from_table(raw_table_name)

        _load_dataframe_in_datalake(df=df, table_name=raw_table_name)


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_terminator_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_details")
    parser.add_argument("raw_table_name")
    parser.add_argument("partition_cols")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_details = json.loads(args.table_details)
    raw_table_name = args.raw_table_name
    partition_cols = json.loads(args.partition_cols)
    execution_date = args.execution_date

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
        execution_date={execution_date}, partition_cols={partition_cols},
        raw_table_name={raw_table_name}"""
        "msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=DatabaseEnum.TERMINATOR
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    _load_table_data(raw_table_name, table_details)
