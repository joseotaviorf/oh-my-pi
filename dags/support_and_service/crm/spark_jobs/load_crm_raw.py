import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.db import DatabaseEnum
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient, MongoClient
from bietlejuice.consumers.db_consumers import MongoConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.base.spark import SparkDataFrameService


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
    if not df.rdd.isEmpty():
        logger.info(
            f"m=_load_dataframe_in_datalake, msg=Loading data into s3 bucket..."
        )

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
    logger.info(f"m=_load_table_data, msg=Extracting data from Mongo database...")

    if table_details.get("is_incremental"):
        date_column = table_details["date_column"]

        df = mongo_consumer.get_incremental_data_from_table(
            table_name=raw_table_name,
            column_name=date_column,
            execution_date=execution_date,
        )

        df = (
            SparkDataFrameService()
            .input(df)
            .optimize_partition(10000)
            .create_year_month_day_columns_from_date(dt_execution)
            .output()
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
        df = mongo_consumer.get_data_from_table(table_name=raw_table_name)

        _load_dataframe_in_datalake(df=df, table_name=raw_table_name)


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_crm_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("raw_table_name", help="table name")
    parser.add_argument("table_details")
    parser.add_argument("partition_cols")
    parser.add_argument("execution_date", type=str, help="DAG execution date")

    args = parser.parse_args()
    environment = args.env
    source = args.source
    datalake_bucket = args.datalake_bucket
    raw_table_name = args.raw_table_name
    table_details = json.loads(args.table_details)
    partition_cols = json.loads(args.partition_cols)
    execution_date = args.execution_date

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
        execution_date={execution_date}, partition_cols={partition_cols},
        raw_table_name={raw_table_name}"""
        "msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=DatabaseEnum.CRM)
    conn_config = json.loads(conn_config_json)

    spark_client = SparkClient()

    mongo_consumer = MongoConsumer(
        mongo_client=MongoClient(conn_config), spark_client=spark_client
    )

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info(
        f"m=__main__, msg=Creating database in Spark Metastore if not exists..."
    )
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    _load_table_data(raw_table_name=raw_table_name, table_details=table_details)
