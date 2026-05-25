import concurrent.futures
import json
import logging
import multiprocessing
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql.functions import lit
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_chat5a_messages_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _parse_arguments():
    """
    This method aims to get the arguments passed from the dag.
    """
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")
    parser.add_argument("table_name")
    parser.add_argument("partition_cols")

    return parser.parse_args()


def _load_partitions_into_datalake(hour):
    """
    This method aims to load the data received via s3 into the datalake, partitioned by hours.
    @hour: Hours parameter, received to access the bucket on s3.
    """

    proxy_path_hour = proxy_path_date + hour
    partition_cols = json.loads(args.partition_cols)

    df = s3_consumer.get_data_from_file(
        proxy_path_hour,
        format="json",
    )
    df = (
        df.withColumn("year", lit(execution_date.year))
        .withColumn("month", lit(execution_date.month))
        .withColumn("day", lit(execution_date.day))
        .withColumn("hour", lit(int(hour.replace("/", "").split("=")[1])))
    )

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{args.table_name}",
        format_options=format_options,
        partitions=partition_cols,
        compression="gzip",
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=args.table_name,
        format_options=format_options,
        database_location=database_location,
        partitions=partition_cols,
        force_recreate=False,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=database_name,
        table_name=args.table_name,
        partition_cols=partition_cols,
    )


if __name__ == "__main__":
    args = _parse_arguments()

    execution_date = datetime.strptime(args.execution_date, "%Y-%m-%d")

    logger.info(
        f"""
        m={JOB_NAME}, 
        environment={args.env}, datalake_bucket={args.datalake_bucket}, source={args.source},
        execution_date={args.execution_date},table_name={args.table_name}, partition_cols={args.partition_cols}, 
        msg=Starting spark job...
        """
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()

    format_options = SparkTableStorageFormat.DEFAULT_RAW

    db_info = DatalakeMetastoreService.get_db_info(
        args.env, args.source, args.datalake_bucket
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    table_name_proxy = args.table_name.replace("_", "-")
    year_proxy = execution_date.year
    month_proxy = str(execution_date.month).zfill(2)
    day = str(execution_date.day).zfill(2)

    proxy_path_date = f"s3://5a-ss-{table_name_proxy}-{args.env}/year={year_proxy}/month={month_proxy}/day={day}/"
    paths_bucket = dbutils.fs.ls(proxy_path_date)
    hour_list = [hour.name for hour in paths_bucket]

    max_cores = int(multiprocessing.cpu_count() * 0.6)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_cores) as executor:
        future_to_hour = {
            executor.submit(_load_partitions_into_datalake, hour): hour
            for hour in hour_list
        }
        for future in concurrent.futures.as_completed(future_to_hour):
            hour = future_to_hour[future]
            try:
                future.result()
            except Exception as e:
                print(f"Partition {hour} generated an exception: {e}")
