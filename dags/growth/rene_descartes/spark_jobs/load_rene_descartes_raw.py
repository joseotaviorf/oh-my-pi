import json
import re

import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import ConfigurationService

SOURCE = "rene_descartes"
JOB_NAME = "load_rene_descartes_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def extract_table_name_from_query(sql_file_path: str) -> str:
    """
    Function to extract table name from it's SQL file path.
    """
    if not sql_file_path.endswith('.sql'):
        raise Exception("Not an SQL file path.")
    else:
        return re.search('[a-z0-9_]+(.sql)', sql_file_path).group(0).replace('.sql','')


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")

    args = parser.parse_args()
    
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date

    config_service = ConfigurationService(source)
    raw_partition_cols = config_service.get_config("raw_partition_cols")

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.RENE_DESCARTES
    )
    conn_config = json.loads(conn_config_json)
    
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    # running extractions and load into datalake
    queries = DAGPackagesPathService.list_queries_files_in_spark_jobs(source, "raw")
    tables_names = [extract_table_name_from_query(query) for query in queries]

    for table_name in tables_names:
        query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
            source, 
            table_name, 
            "raw"
        ).format(load_start_date=load_start_date,load_end_date=load_end_date)        

        df = postgres_consumer.get_data_from_query(query)
        
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_dataframe_column("dt")
            .output()
        )    

        s3_loader.load_incremental_table(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
            partition_cols=raw_partition_cols,
            compression="gzip",
        )

        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            raw_partition_cols,
        )