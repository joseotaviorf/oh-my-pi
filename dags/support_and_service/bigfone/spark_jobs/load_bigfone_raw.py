import json
import logging
from argparse import ArgumentParser
import multiprocessing
import concurrent.futures

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline


JOB_NAME = "load_bigfone_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def _parse_arguments():
    """
    This method aims to get the arguments passed from the dag.
    """
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")
    parser.add_argument("tables_info")
    parser.add_argument("partition_cols")

    return parser.parse_args()

def get_conn_config():
    """
    This method is intended to return the database connection settings.
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.BIGFONE)
    return json.loads(conn_config_json)

def _load_dataframes_into_datalake(args, force_recreate=False):
    """
    This method takes the data from the table in the Postgres database, considering the
    parameters if it is incremental or full load. In addition to also loading this data into the datalake.
    @param args: Detailing parameters of the tables..
    @param force_recreate: bool. Indicates if it must force table recreation in metastore.
    """

    tables_info = json.loads(args.tables_info)
    partition_cols = json.loads(args.partition_cols)

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

    for table_name, infos in tables_info.items():
        if infos["raw_extraction_type"] == "incremental":
            df = postgres_consumer.get_incremental_data_from_table(
                table_name.capitalize(), infos.get("date_filter_column"), args.execution_date
            )
            IncrementalTableLoaderPipeline(
                database_name=database_name, 
                table_name=table_name, 
                database_location=database_location, 
                layer=LayerEnum.RAW,
                query=None,
                partitions=partition_cols
            ).load_and_register(df, format_options, force_recreate)
        else:
            df = postgres_consumer.get_data_from_table(table_name.capitalize())
            FullTableLoaderPipeline(
                database_name=database_name, 
                table_name=table_name, 
                database_location=database_location, 
                layer=LayerEnum.RAW,
                query=None
            ).load_and_register(df, format_options)

if __name__ == "__main__":

    args = _parse_arguments()

    logger.info(
        f"""
            m=__main__, JOB_NAME={JOB_NAME}
            environment={args.env}, datalake_bucket={args.datalake_bucket}, source={args.source},
            execution_date={args.execution_date}, tables_info={args.tables_info}, partition_cols={args.partition_cols}
            msg=Starting spark job...
        """
    )

    max_cores = multiprocessing.cpu_count()
    with concurrent.futures.ProcessPoolExecutor(max_workers=max_cores) as executor:
        future = executor.submit(_load_dataframes_into_datalake, args)
        try:
            future.result()
        except Exception as e:
            print(f"Loading raw layer into datalake threw exception: {e}")
