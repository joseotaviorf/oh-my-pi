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
from bietlejuice.formatters.string_formatter import StringFormatter


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


def _load_table_data(table_details):
    """
    This method takes the data from the table in the Postgres database, considering the
    parameters if it is incremental or full load.
    @param table_details: Information about the table returned by the database.
    """
    table_name = table_details.table_name
    raw_table_name = StringFormatter.set_alphanumeric_snake_case(table_name)

    if raw_table_name in incremental_tables:
        date_column = incremental_tables.get("raw_table_name").get("date_column")
        unixtime_measure = incremental_tables.get("raw_table_name").get(
            "unixtime_measure"
        )

        df = postgres_consumer.get_incremental_data_by_granularity_from_table(
            table_name, date_column, execution_date, unixtime_measure
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
        df = postgres_consumer.get_data_from_table(table_name)

        _load_dataframe_in_datalake(df=df, table_name=raw_table_name)


SOURCE = "inspections"
JOB_NAME = "load_inspections_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("incremental_tables")
    parser.add_argument("partition_cols")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    incremental_tables = json.loads(args.incremental_tables)
    partition_cols = json.loads(args.partition_cols)
    execution_date = args.execution_date

    logger.info(
        f"""m=__main__, environment={environment}, datalake_bucket={datalake_bucket},
        execution_date={execution_date}, partition_cols={partition_cols},
        incremental_tables={incremental_tables}"""
        "msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.INSPECTIONS
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    tables = postgres_consumer.get_table_names_and_sizes().collect()

    map(_load_table_data, tables)
