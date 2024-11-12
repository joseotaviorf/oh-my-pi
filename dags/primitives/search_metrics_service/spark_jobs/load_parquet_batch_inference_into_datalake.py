import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from pyspark.sql.utils import AnalysisException
import pandas as pd

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat, SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_parquet_batch_inference_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def get_source_in_forno(environment, source):
    prod_string = "s3://data-science.s3.data"
    forno_string = "s3://data-science.s3.forno.data"
    if environment == "forno":
        return source.replace(prod_string, forno_string)
    return source


def main():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("source_root_path", help="name of the source")
    parser.add_argument(
        "date_to_ingest",
        help="Date to be used in filtering the files. Format: '%Y-%m-%d'",
    )
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("raw_partition_cols", help="list with partition cols")
    parser.add_argument("format", help="data format to load from S3. ")

    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.bucket
    source = args.source
    source_root_path = get_source_in_forno(environment, args.source_root_path)
    date_to_ingest = args.date_to_ingest
    table_name = args.table_name
    raw_partition_cols =  json.loads(args.raw_partition_cols.replace("'", '"'))
    _format = args.format


    logger.info(
        f"""
            m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
            source_root_path={source_root_path}, date_to_ingest={date_to_ingest}, table_name={table_name},
            msg=Starting spark job...
        """
    )
    print(
        f"""
            m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
            source_root_path={source_root_path}, date_to_ingest={date_to_ingest}, table_name={table_name},
            msg=Starting spark job...
        """
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.PARQUET

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    print("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    dt_end = datetime.strptime(date_to_ingest, "%Y-%m-%d") + timedelta(days=1)
    dt_start = dt_end - timedelta(days=90)
    dt_execution_list = list(pd.date_range(dt_start, dt_end, freq='d').strftime("%Y-%m-%d"))

    for date_granularity in ['day', 'week', 'month']:
        for date in dt_execution_list:
            try:
                df = s3_consumer.get_data_from_file(
                    f"{source_root_path}/date_granularity={date_granularity}/date={date}/",
                    _format
                )

                df = (
                    SparkDataFrameService()
                    .input(df)
                    .create_year_month_day_columns_from_dataframe_column("timestamp_available")
                    .output()
                )

                s3_loader.load_df(
                    df=df,
                    s3_path=f"{database_location}{table_name}",
                    format_options=format_options,
                    partitions=raw_partition_cols,
                )

                spark_metastore_loader.update_metastore(
                    df=df,
                    database_name=database_name,
                    table_name=table_name,
                    format_options=format_options,
                    database_location=database_location,
                    partitions=raw_partition_cols,
                )
                spark_metastore_service.create_new_partitions_from_df(
                    df=df,
                    database_name=database_name,
                    table_name=table_name,
                    partition_cols=raw_partition_cols,
                )

            except AnalysisException as e:
                logger.info(
                    f"""
                    m=__main__, msg=No data found for date_to_ingest={date_to_ingest}, source={source},
                    source_root_path={source_root_path}, table_name={table_name}.

                    Exception: {e}
                    """
                )
                print(
                    f"""
                    m=__main__, msg=No data found for date_to_ingest={date_to_ingest}, source={source},
                    source_root_path={source_root_path}, table_name={table_name}.

                    Exception: {e}
                    """
                )


if __name__ == "__main__":
    main()
