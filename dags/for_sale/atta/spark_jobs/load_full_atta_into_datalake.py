import json
import logging
from argparse import ArgumentParser
from pyspark.sql import functions as F
from pyspark.sql.types import DecimalType

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import MySqlConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_full_atta_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("db")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    db = args.db

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name}, db={db} msg=Starting full Spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.ATTA)
    conn_config = json.loads(conn_config_json)
    conn_config['db'] = db
    mysql_consumer = MySqlConsumer(conn_config, SparkClient())

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(SparkClient())

    # create database if it doesn't exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    df = mysql_consumer.get_data_from_table(table_name)

    if df:
        # Verificando e transformando colunas decimais
        for column in df.columns:
            if isinstance(df.schema[column].dataType, DecimalType) and df.schema[column].precision > 38:
                df = df.withColumn(column, F.col(column).cast("decimal(38,30)"))

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            database_location=database_location,
            max_records_per_file=100000,
        )
        spark_metastore_loader.update_metastore(
            df, database_name, table_name, format_options, database_location
        )
    else:
        logger.warning(
            f"""m=__main__, table_name={table_name}, msg=No data returned from Production database."""
        )
