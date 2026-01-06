import json
from functools import reduce
from argparse import ArgumentParser
from pyspark.sql import DataFrame
from pyspark.sql.functions import lit, col, to_date
from pyspark.sql.types import StructType, StructField, StringType, DoubleType, IntegerType

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

from profound import Client
from profound.types import ReportResponse, ReportResult, Pagination

JOB_NAME = "load_profound_raw"

CATEGORY_ID = "92504126-efe7-4f21-b17a-344f300a685d"

logger = QuintoAndarLogger(JOB_NAME)

def get_profound_data(client: Client, metrics: list[str], dimensions: list[str], filters: list[str], offset: int = 0) -> ReportResponse:
    response = profound_client.reports.visibility(
        category_id=CATEGORY_ID,
        start_date=args.load_start_date,
        end_date=args.load_end_date,
        metrics=metrics,
        dimensions=dimensions,
        filters=filters,
        pagination=Pagination(limit=10000, offset=offset)
    )
    return response

def generate_dataframe(spark_client: SparkClient, response: ReportResult) -> DataFrame:
    if response and hasattr(response, "data") and response.data:
        df = spark_client.createDataFrame(response.data)
        for idx, dimension_name in enumerate(response.info.query.get("dimensions", [])):
            df = df.withColumn(dimension_name, element_at("dimensions", idx + 1))
        for idx, metric_name in enumerate(response.info.query.get("metrics", [])):
            df = df.withColumn(metric_name, element_at("metrics", idx + 1))
        df = df.drop("dimensions", "metrics")
        df = df.withColumn("date", to_date(col("date"), "yyyy-MM-dd"))
        return df

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("report_type")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.env}, source={args.source}, table_name=report_{args.report_type},
            load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, report_type={args.report_type},
            msg=print spark jobs args
        """
    )

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    report_type = args.report_type
    table_name = f"report_{report_type}"

    config_service = ConfigurationService(source)
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    tables_config = config_service.get_config("tables")
    report_config = tables_config.get(report_type)

    if not report_config:
        raise ValueError(f"Report type '{report_type}' not found in tables configuration")

    metrics = config_service.get_config("metrics")
    dimensions = report_config["dimensions"]
    filters = config_service.get_config("filters")

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials = dbutils.secrets.get(
        scope="quintoandar", key=APIEnum.PROFOUND
    )

    profound_client = Client(
        api_key=credentials,
    )

    spark_client = SparkClient()

    dfs = []
    
    try:
        response = get_profound_data(profound_client, metrics, dimensions, filters)

        df = generate_dataframe(spark_client, response)
        
        dfs.append(df)

        total_rows = response.info.total_rows
        limit = response.info.query.get("pagination", {}).get("limit", 10000)
        offset = limit

        while offset < total_rows:
            response = get_profound_data(profound_client, metrics, dimensions, filters, offset)
            df = generate_dataframe(spark_client, response)
            dfs.append(df)
            offset += limit
                
        logger.info(
            f"""
                m={JOB_NAME}, {len(total_rows)} rows extracted
                for the period {load_start_date} to {load_end_date}.
            """
        )
            
    except Exception as e:
        logger.error(
            f"""
                m={JOB_NAME}, error fetching data from Profound API: {str(e)}
            """
        )
        raise

    if dfs:
        df = reduce(DataFrame.unionAll, dfs)
        s3_loader = S3Loader()
        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

        db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]
        spark_metastore_service.create_database(database_name)

        s3_loader.load_df(
            df=df,
            format_options=SparkTableStorageFormat.DEFAULT_RAW,
            s3_path=f"{database_location}{table_name}",
            partitions=raw_partition_cols,
        )

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=SparkTableStorageFormat.DEFAULT_RAW,
            database_location=database_location,
            partitions=raw_partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=database_name,
            table_name=table_name,
            partition_cols=raw_partition_cols,
        )
    else:
        logger.info("m=__main__, msg=df empty.")

