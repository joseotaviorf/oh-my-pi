import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import MongoConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService


JOB_NAME = "load_cidade_alerta_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

BLOCK_LIST = ["audit", "messages_broadcast", "messages", "messages_routing"]

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env
    source = "cidade_alerta"

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.CIDADE_ALERTA
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()
    mongo_consumer = MongoConsumer(conn_config)

    tables = mongo_consumer.get_table_names_and_sizes().collect()
    db_info = DatalakeMetastoreService.get_db_info(environment, source)
    metastore_service = SparkMetastoreService(spark_client)
    loader = S3Loader(metastore_service)

    # create database if not exists
    database_name = db_info["db_raw_databricks"]
    metastore_service.create_database(database_name)

    for table in tables:
        table_name = table.table_name.replace(".", "_")

        if table_name not in BLOCK_LIST:
            df = mongo_consumer.get_data_from_table(table_name)
            df = (
                SparkDataFrameService()
                .input(df)
                .convert_struct_type_to_string()
                .convert_array_type_to_json()
                .output()
            )

            loader.load_full_table(
                df=df,
                database_name=db_info["db_raw_databricks"],
                table_name=table_name.lower(),
                format=SparkTableStorageFormat.DEFAULT_RAW,
                database_location=db_info["db_raw_path"],
            )
