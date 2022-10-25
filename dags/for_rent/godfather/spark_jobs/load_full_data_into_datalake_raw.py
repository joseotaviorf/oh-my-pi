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
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_full_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source

    logger.info(
        f"""
        m=load_full_data_into_datalake_raw, environment={environment}, datalake_bucket={datalake_bucket},
        source={source}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.GODFATHER
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()

    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    config_service = ConfigurationService(source)
    schemas = config_service.get_config("schemas")
    tables_allow_list = config_service.get_config("tables_allow_list")

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    logger.info("msg=Creating database in Spark Metastore if not exists...")

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    schema = json.dumps(schemas)
    postgres_consumer.conn_config["schema"] = schema

    tables = postgres_consumer.get_table_names_and_sizes().collect()

    for table in tables:
        table_name = table.table_name

        if table_name.lower() in tables_allow_list:
            logger.info(f"""msg=Getting table {table_name} from schema {schema}...""")

            df = postgres_consumer.get_data_from_table(table_name)

            s3_loader.load_df(
                df=df,
                s3_path=f"{database_location}{table_name.lower()}",
                format_options=format_options,
            )

            spark_metastore_loader.update_metastore(
                df, database_name, table_name.lower(), format_options, database_location
            )
