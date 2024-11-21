import json
import logging
import multiprocessing
import concurrent.futures

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

from pyspark.sql.functions import lit

JOB_NAME = "load_kong_raw"

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

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    partition_cols = json.loads(args.partition_cols)
    execution_date = args.execution_date

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d")

    proxy_path = "s3://auditlogs.s3.sre.quintoandar.com.br/proxy/k8s.core-prd-green/{}/{}/{}/{}/kong-proxy.internal.kong-ingress*/*/*.gz" --> "s3://auditlogs.s3.sre.quintoandar.com.br/proxy/k8s.core-prd-*/{}/{}/{}/{}/kong*/*/*.gz"

    max_cores = int(multiprocessing.cpu_count() * 0.6)

    hour_list = [str(h).zfill(2) for h in range(24)]

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
        execution_date={execution_date}, partition_cols={partition_cols}"""
        "msg=Starting spark job..."
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    def load_partition(hour):

        df = s3_consumer.get_data_from_file(
            proxy_path.format(
                execution_date.year,
                str(execution_date.month).zfill(2),
                str(execution_date.day).zfill(2),
                str(hour).zfill(2),
            ),
            format="json",
        )

        df = df.where("container_name = 'kong-proxy' AND NOT RLIKE(message, 'error')")

        df = (
            df.withColumn("year", lit(execution_date.year))
            .withColumn("month", lit(execution_date.month))
            .withColumn("day", lit(execution_date.day))
            .withColumn("hour", lit(hour))
        )

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
            compression="gzip",
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
            partitions=partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=database_name,
            table_name=table_name,
            partition_cols=partition_cols,
        )

    with concurrent.futures.ThreadPoolExecutor(max_workers=max_cores) as executor:
        future_to_hour = {
            executor.submit(load_partition, hour): hour for hour in hour_list
        }
        for future in concurrent.futures.as_completed(future_to_hour):
            hour = future_to_hour[future]
            try:
                future.result()
            except Exception as e:
                print(f"Partition {hour} generated an exception: {e}")
