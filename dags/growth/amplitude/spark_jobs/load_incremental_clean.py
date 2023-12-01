from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark.spark_table_storage_format import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.loaders.spark_metastore_loader import SparkMetastoreLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_incremental_clean"

logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(JOB_NAME)
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("table_name")
parser.add_argument("--partition_by", nargs="+", dest="partition_by", required=False)

if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    partition_cols = args.partition_by

    logger.info(
        f"m=__main__, date={execution_date}, source={source}, "
        f"table_name={table_name}, msg=Job started"
    )

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d")
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    db_clean_name = db_info["db_clean_databricks"]
    db_clean_path = db_info["db_clean_path"]
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=source, table_name=table_name, layer="clean"
    ).format(execution_date.year, execution_date.month, execution_date.day)

    df = spark_client.get_records(query)

    df_cols = df.columns

    if('id_app' in df_cols):
        df = df.withColumn("id_app",df.id_app.cast('bigint'))
    if('id_schema' in df_cols):
        df = df.withColumn("id_schema",df.id_schema.cast('bigint'))
    if('location_lat' in df_cols):
        df = df.withColumn("location_lat",df.location_lat.cast('string'))
    if('location_lng' in df_cols):
        df = df.withColumn("location_lng",df.location_lng.cast('string'))

    df = df.select(df_cols)

    s3_loader.load_df(
        df=df,
        format_options=format_options,
        s3_path=f"{db_clean_path}{table_name}",
        partitions=partition_cols,
        optimize_dataframe=False,
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=df,
        database_name=db_clean_name,
        table_name=table_name,
        format_options=format_options,
        database_location=db_clean_path,
        partitions=partition_cols,
        force_recreate=True,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=db_clean_name,
        table_name=table_name,
        partition_cols=partition_cols,
    )
