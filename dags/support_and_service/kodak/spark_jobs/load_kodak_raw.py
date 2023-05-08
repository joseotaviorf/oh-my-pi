import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_kodak_raw"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def _parse_arguments():
    """
    This method aims to get the arguments passed from the dag.
    """
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("source", type=str)
    parser.add_argument("table_name", type=str)
    parser.add_argument("execution_date", type=str)
    parser.add_argument("extraction_type", type=str, help="incremental/full")
    parser.add_argument(
        "date_filter_column",
        type=str,
        help="If incremental, filter by this column",
        default=None,
    )
    parser.add_argument("partition_cols", type=str)

    return parser.parse_args()

def get_conn_config():
    """
    This method is intended to return the database connection settings.
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.KODAK)
    return json.loads(conn_config_json)

def _load_dataframe_into_datalake(args, force_recreate=True):
    """
    This method takes the data from the table in the Postgres database, considering the
    parameters if it is incremental or full load. In addition to also loading this data into the datalake.
    @param args: Detailing parameters of the tables..
    @param force_recreate: bool. Indicates if it must force table recreation in metastore.
    """
    partition_cols = json.loads(args.partition_cols) if args.partition_cols else None
    
    conn_config = get_conn_config()
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    format_options = SparkTableStorageFormat.DEFAULT_RAW

    db_info = DatalakeMetastoreService.get_db_info(
        args.env, args.source, args.datalake_bucket
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    if args.extraction_type == "incremental":
        df = postgres_consumer.get_incremental_data_from_table(
            args.table_name, args.date_filter_column, args.execution_date
        )
        IncrementalTableLoaderPipeline(
            database_name=database_name,
            table_name=args.table_name,
            database_location=database_location,
            layer=LayerEnum.RAW,
            partitions=partition_cols,
            query=None
        ).load_and_register(df, format_options, force_recreate)
    else:
        df = postgres_consumer.get_data_from_table(args.table_name)
        FullTableLoaderPipeline(
            database_name=database_name,
            table_name=args.table_name,
            database_location=database_location,
            layer=LayerEnum.RAW,
            query=None
        ).load_and_register(df, format_options)

if __name__ == "__main__":
    args = _parse_arguments()

    logger.info(
        f"""
        m={JOB_NAME}, environment={args.env}, datalake_bucket={args.datalake_bucket}, execution_date={args.execution_date},
        table_name={args.table_name}, partition_cols={args.partition_cols}, msg=Starting spark job...
        """
    )

    _load_dataframe_into_datalake(args=args)
