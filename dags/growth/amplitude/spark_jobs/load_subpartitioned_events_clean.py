"""
    This job intends to increment events tables that are on the clean layer.
    There are some tables with name like: {id_app}_{event_type}_events that sums
    up informations from events table by id_app and event_type with some extractions.

    Since amplitude updates its values every day, we need to load those clean tables
    in order to update its values.
"""

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.loaders.spark_metastore_loader import SparkMetastoreLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_subpartitioned_events_clean"

logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(JOB_NAME)
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("--tables_list", nargs="+", dest="tables_list", required=True)
parser.add_argument("--partition_by", nargs="+", dest="partition_by", required=False)


if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    tables_list = args.tables_list
    partition_by = args.partition_by

    logger.info(
        f"m=__main__, date={execution_date}, source={source}, "
        f"partition_by={str(partition_by)}, msg=Job started"
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

    for table_name in tables_list:

        logger.info(
            f"m=__main__, date={execution_date}, source={source}, "
            f"table_name={table_name}, msg=Retrieving records..."
        )

        query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
            dag_name=source, table_name=table_name, layer="clean"
        ).format(execution_date.year, execution_date.month, execution_date.day)

        df = spark_client.get_records(query)
        df = (
            SparkDataFrameService(df)
            .optimize_partitions_by_partition_columns(partition_by)
            .output()
        )

        s3_loader.load_df(
            df=df,
            s3_path=f"{db_clean_path}{table_name}",
            format_options=format_options,
            optimize_dataframe=False,
            partitions=partition_by,
        )
        spark_metastore_loader.update_metastore(
            df=df,
            database_name=db_clean_name,
            table_name=table_name,
            format_options=format_options,
            database_location=db_clean_path,
            partitions=partition_by,
        )
