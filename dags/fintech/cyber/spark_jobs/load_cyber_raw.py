import json
import logging
from argparse import ArgumentParser

from bietlejuice.base.db import DatalakeMetastoreService, DatabaseEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import OracleSparkConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.pipeline import FullTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger



JOB_NAME = "load_cyber_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def _get_conn_config(dbutils_secret_key):
      base_dbutils = BaseDBUtils()
      dbutils = base_dbutils.get_dbutils()
      conn_config_json = dbutils.secrets.get(
          scope="quintoandar", key=dbutils_secret_key
      )

      return json.loads(conn_config_json)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="name of the output table")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name},  msg=Starting spark job...
        """
    )

    conn_config = _get_conn_config(DatabaseEnum.CYBER)

    spark_client = SparkClient()

    oracle_consumer = OracleSparkConsumer(conn_config, spark_client)

    oracle_table_name = table_name.upper()
    df = oracle_consumer.get_data_from_table(oracle_table_name)
    if df.rdd.isEmpty():
        raise ValueError("There is no data to return")
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(SparkClient())
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    # create database if it doesn't exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    FullTableLoaderPipeline(
        database_name=database_name,
        table_name=table_name,
        database_location=database_location,
        layer=LayerEnum.RAW,
        query=None
    ).load_and_register(df, format_options)
