import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql.functions import *
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_databricks_usage_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("partition_cols")
    parser.add_argument("execution_date")
    add_validation_target_args(parser)

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    partition_cols = json.loads(args.partition_cols)
    execution_date = args.execution_date

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d")

    proxy_path = "s3://5a-databricks/usage-data/billable-usage/csv/workspaceId=*-usageMonth={}-{}.csv"

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
        execution_date={execution_date}, partition_cols={partition_cols}"""
        "msg=Starting spark job..."
    )

    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )
    spark_metastore_service.create_database(write_database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    if proxy_path:
        df = (
            spark.read.format("csv")
            .option("header", "true")
            .option("quote", '"')
            .option("escape", '"')
            .load(
                proxy_path.format(
                    execution_date.year, str(execution_date.month).zfill(2)
                )
            )
        )

        df = df.alias("df").select(
            "df.*",
            year(df.timestamp).alias("year"),
            month(df.timestamp).alias("month"),
            dayofmonth(df.timestamp).alias("day"),
        )

        s3_loader.load_df(
            df=df,
            s3_path=f"{write_location}{write_table_name}",
            format_options=format_options,
            partitions=partition_cols,
            compression="gzip",
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=write_database_name,
            table_name=write_table_name,
            format_options=format_options,
            database_location=write_location,
            partitions=partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=write_database_name,
            table_name=write_table_name,
            partition_cols=partition_cols,
        )
    else:
        logger.info("m=load_databricks_usage_raw, msg=S3 path does not exist.")
