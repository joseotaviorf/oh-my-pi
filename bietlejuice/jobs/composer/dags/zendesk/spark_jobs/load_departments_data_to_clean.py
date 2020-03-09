import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

DATABRICKS_SCOPE = "quintoandar"

JOB_NAME = "load_deparments_data_to_clean"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description="load_data_to_clean")
    parser.add_argument("file_name", type=str, help="file name is equal table name")
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")
    args = parser.parse_args()

    logger.info(
        "m=load_data_to_clean, file_name={}, execution_date={}, msg=print args spark "
        "jobs params".format(args.file_name, args.execution_date)
    )

    execution_date = args.execution_date
    table_name = file_name = args.file_name.replace("-", "_")
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = "zendesk"

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)

    spark_client = SparkClient()
    conn_config = {"db": db_info["db_raw_databricks"]}
    databricks_consumer = DatabricksConsumer(conn_config, spark_client)

    query_path = QUERIES_DATALAKE_PATH + source + "/{}.sql".format(table_name)
    query = FileService.get_query_from_file_name(query_path).format(
        db=db_info["db_raw_databricks"]
    )
    df = databricks_consumer.get_data_from_query(query)

    spark_metastore_service = SparkMetastoreService(spark_client)
    database_name = db_info["db_clean_databricks"]
    spark_metastore_service.create_database(database_name)
    s3_loader = S3Loader(spark_metastore_service)

    s3_loader.load_full_table(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format=SparkTableStorageFormat.DEFAULT_CLEAN,
        database_location=db_info["db_clean_path"],
    )
