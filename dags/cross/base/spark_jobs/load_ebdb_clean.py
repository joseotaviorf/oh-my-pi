from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_ebdb_clean"
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("table_name")
    parser.add_argument("source")

    args = parser.parse_args()
    table_name = args.table_name
    source = args.source
    env = args.env
    datalake_bucket = args.datalake_bucket

    logger.info("m=running load-to-clean")

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=source, layer=LayerEnum.CLEAN.value, table_name=table_name
    )

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    spark_client = SparkClient()
    metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    database_name = db_info["db_clean_databricks"]
    database_location = db_info["db_clean_path"]
    metastore_service.create_database(database_name)
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN
    df = spark_client.get_records(query)

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        database_location=database_location,
    )

    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )
