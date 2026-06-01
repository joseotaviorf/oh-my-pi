import ast
import logging
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql.functions import col, udf
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_columns_metastore_to_raw"
INFORMATION_SCHEMA_COLUMNS_TABLE_NAME = "system.information_schema.columns"


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_columns_from_metastore():
    df_columns = spark.table(INFORMATION_SCHEMA_COLUMNS_TABLE_NAME)
    final_df = (
        df_columns.filter(f"table_catalog = '{spark.catalog.currentCatalog()}'")
        .select(
            col("column_name"),
            col("table_schema").alias("database_name"),
            col("table_name"),
        )
        .where(
            """database_name not like '%_staging%'
        and database_name not like '%_temp%'
        and (database_name like 'datalake_%'
        or database_name like 'dw_%'
        or database_name like 'metric_%'
        or database_name like 'reverse_%'
        or database_name like 'core_%'
        or database_name = 'sandbox')
        """
        )
    )

    final_df = final_df.coalesce(4)  # reducing number of partitions
    udf_extract_layer = udf(extract_layer_from_database_name)
    final_df = final_df.withColumn("layer", udf_extract_layer("database_name"))

    return final_df


def extract_layer_from_database_name(database_name):
    if database_name.startswith("dw_"):
        return LayerEnum.DW.value
    elif database_name.startswith("metric_"):
        return LayerEnum.METRIC.value
    elif database_name.startswith("core_"):
        return LayerEnum.CORE.value
    elif database_name.startswith("datalake_"):
        if database_name.endswith("_raw"):
            return LayerEnum.RAW.value
        if database_name.endswith("_clean"):
            return LayerEnum.CLEAN.value
        if database_name.endswith("_transactional"):
            return LayerEnum.TRANSACTIONAL.value
        else:
            return LayerEnum.ENRICH.value
    return ""


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str)
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("source", type=str)
    parser.add_argument("table_name", type=str)
    parser.add_argument("execution_date_str", type=str)
    parser.add_argument("partitions", type=str)
    parser.add_argument("documentation_bucket", type=str)
    parser.add_argument("documentation_prefix", type=str)

    add_validation_target_args(parser)
    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date_str = args.execution_date_str
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")
    partition_cols = ast.literal_eval(args.partitions)
    documentation_bucket = args.documentation_bucket
    documentation_prefix = args.documentation_prefix

    bucket_suffix = (
        ".data.quintoandar.com.br"
        if env == "prod"
        else ".forno.data.quintoandar.com.br"
    )
    documentation_bucket = documentation_bucket + bucket_suffix

    logger.info(
        f"""m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, source={source},
        table_name={table_name}, execution_date_str={execution_date_str}, documentation_bucket={documentation_bucket}
        msg=Job execution started."""
    )

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
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

    # Creating metrics dataframe
    metastore_columns_df = get_columns_from_metastore()
    metastore_columns_df = (
        SparkDataFrameService()
        .input(metastore_columns_df)
        .create_year_month_day_columns_from_date(execution_date)
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )

    # loaders
    s3_loader.load_df(
        df=metastore_columns_df,
        s3_path=f"{write_location}{write_table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader.update_metastore(
        metastore_columns_df,
        write_database_name,
        write_table_name,
        format_options,
        write_location,
        partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=write_database_name,
        table_name=write_table_name,
        df=metastore_columns_df,
        partition_cols=partition_cols,
    )
    spark_metastore_service.refresh_table(write_database_name, write_table_name)
