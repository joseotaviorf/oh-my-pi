import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql.functions import current_timestamp, lit
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.pipeline import LayerEnum

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (SparkDataFrameService,
                                    SparkTableStorageFormat)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.pipeline import (FullTableLoaderPipeline,
                                  IncrementalTableLoaderPipeline)
JOB_NAME = "load_paschoalotto_raw"


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("source_root_path", help="name of the source")
    parser.add_argument("date_to_ingest", help="Date to be used in filtering the files. Format: '%Y-%m-%d'",)
    parser.add_argument("table_name", help="translated table name (based on original_table_name)")
    parser.add_argument("load_incremental", help="indicates wheter the load is incremental or not (full)")
    parser.add_argument("partition_cols", help="table partition")
    parser.add_argument("format", help="S3 object format")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    source_root_path = args.source_root_path
    date_to_ingest = args.date_to_ingest
    table_name = args.table_name
    load_incremental = json.loads(args.load_incremental)
    partition_cols = json.loads(args.partition_cols)
    format = json.loads(args.format)

    logger.info(
        f"""m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        source_root_path={source_root_path}, partition_cols= {partition_cols}, date_to_ingest={date_to_ingest},
        table_name={table_name}, load_incremental = {load_incremental}.
        msg=Starting spark job...
        """)

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.PARQUET

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    file_name = f"{table_name}_{date_to_ingest}.{format}"
    s3_path = f"{source_root_path}/{file_name}"

    logger.info(
        f"""m=__main__, msg=File name to be processed: {s3_path}"""
    )
    try:
        df = s3_consumer.get_data_from_file(path=s3_path, format=format)
    except AnalysisException as error:
        logger.warning(
            f"""
            m=__main__, msg=No data found for {s3_path}, table_name={table_name}.

            Exception: {error}
            """
        )
        raise error

    df = df.withColumn("s3_file_name", lit(file_name))
    df = df.withColumn("ts_load", current_timestamp())
    datetime_file = datetime.strptime(date_to_ingest, "%Y-%m-%d")

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_date(datetime_file)
        .output()
    )
    df.show(3)

    if load_incremental:
        IncrementalTableLoaderPipeline(
            database_name=database_name,
            table_name=table_name,
            database_location=database_location,
            layer=LayerEnum.RAW,
            query=None,
            partitions=partition_cols,
        ).load_and_register(df, format_options)
    else:
        FullTableLoaderPipeline(
            database_name=database_name,
            table_name=table_name,
            database_location=database_location,
            layer=LayerEnum.RAW,
            query=None
        ).load_and_register(df, format_options)
