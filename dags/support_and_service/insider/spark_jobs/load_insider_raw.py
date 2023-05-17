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
from bietlejuice.pipeline import FullTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_insider_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def _parse_arguments():
    """
    This method aims to get the arguments passed from the dag.
    """
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    parser.add_argument("source")
    parser.add_argument("tables_config")

    return parser.parse_args()

def get_conn_config():
    """
    This method is intended to return the database connection settings.
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.INSIDER)
    return json.loads(conn_config_json)

def _load_dataframe_into_datalake(args, force_recreate=True):
    """
    This method takes the data from the table in the Postgres database, considering the
    parameters if it is incremental or full load. In addition to also loading this data into the datalake.
    @param args: Detailing parameters of the tables..
    @param force_recreate: bool. Indicates if it must force table recreation in metastore.
    """
    tables_config = json.loads(args.tables_config)
    conn_config = get_conn_config()

    spark_client = SparkClient()

    postgres_consumer = PostgresConsumer(conn_config, spark_client)
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    db_info = DatalakeMetastoreService.get_db_info(args.env, args.source, args.datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    metastore_service = SparkMetastoreService(spark_client)
    metastore_service.create_database(database_name)

    for table_name, infos in tables_config.items():
        if infos["raw_extraction_type"] == "full":
            df = postgres_consumer.get_data_from_table(table_name)
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
        m={JOB_NAME}, environment={args.env}, datalake_bucket={args.datalake_bucket}, 
        execution_date={args.execution_date}, tables_config={args.tables_config}, 
        msg=Starting spark job...
        """
    )

    max_cores = multiprocessing.cpu_count()
    with concurrent.futures.ProcessPoolExecutor(max_workers=max_cores) as executor:
        future = executor.submit(_load_dataframe_into_datalake, args)
        try:
            future.result()
        except Exception as e:
            print(f"Loading raw layer into datalake threw exception: {e}")
