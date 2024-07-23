import logging
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql.functions import udf, lit
from pyspark.sql.types import StructType, StructField, StringType
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger
from py4j.protocol import Py4JJavaError

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_columns_metastore_to_raw"


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_columns_from_metastore(spark_client, schemas_skip_list):
    final_df = get_empty_df(spark_client)
    databases = list_metastore_databases(spark_client, schemas_skip_list)

    for database in databases:
        tables = list_metastore_tables(spark_client, database)
        for table in tables:
            logging.info(f"m={JOB_NAME}, msg=Getting columns from {database}.{table}")
            try:
                columns_df = (
                    spark_client.get_records(f"SHOW COLUMNS IN {database}.{table}")
                    .withColumn("database_name", lit(database))
                    .withColumn("table_name", lit(table))
                )
            except Py4JJavaError as e:
                if "AccessDeniedException" in str(e):
                    logging.error(
                        f"Permission error. Skiping table {database_name}.{table}"
                    )
                    continue

                logging.error(
                    f"m={JOB_NAME}, msg=Error getting columns from {database}.{table}. Error: {e}"
                )
                raise e
            except AnalysisException as e:
                if "TABLE_OR_VIEW_NOT_FOUND" in str(e):
                    logging.error(
                        f"Table not found, check if it is a temporary table. Skiping table {database}.{table}"
                    )
                    continue
                raise e
            final_df = final_df.union(columns_df)

    final_df = final_df.coalesce(4)  # reducing number of partitions
    udf_extract_layer = udf(extract_layer_from_database_name)
    final_df = final_df.withColumn("layer", udf_extract_layer("database_name"))

    return final_df


def get_empty_df(spark_client):
    df_schema = StructType(
        [
            StructField("column_name", StringType(), True),
            StructField("database_name", StringType(), True),
            StructField("table_name", StringType(), True),
        ]
    )
    return spark_client.create_dataframe([], df_schema)


def list_metastore_databases(spark_client, schemas_skip_list):
    databases_df = (
        spark_client.get_records("SHOW DATABASES")
        .where(
            """databaseName not like '%_staging%'
               and databaseName not like 'temp_%'
               and databaseName not like 'igorgatis%'
               """
        )
        .collect()
    )
    databases = [
        db.databaseName
        for db in databases_df
        if db.databaseName not in schemas_skip_list
    ]
    return databases


def list_metastore_tables(spark_client, database):
    tables_df = (
        spark_client.get_records(f"SHOW TABLES IN {database}")
        .where("isTemporary = false")
        .drop("isTemporary")
        .collect()
    )
    return [tb.tableName for tb in tables_df]


def extract_layer_from_database_name(database_name):
    if database_name.startswith("dw_"):
        return LayerEnum.DW.value
    elif database_name.startswith("metric_"):
        return LayerEnum.METRIC.value
    elif database_name.startswith("datalake_"):
        if database_name.endswith("_raw"):
            return LayerEnum.RAW.value
        if database_name.endswith("_clean"):
            return LayerEnum.CLEAN.value
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

    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date_str = args.execution_date_str
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    logger.info(
        f"""m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, source={source},
        table_name={table_name}, execution_date_str={execution_date_str}
        msg=Job execution started."""
    )

    config_service = ConfigurationService(source)
    documentation_bucket = config_service.get_config("DOCUMENTATION_BUCKET")
    documentation_prefix = config_service.get_config("DOCUMENTATION_PATH")
    schemas_skip_list = config_service.get_config("DATABASE_SKIP_LIST")
    partition_cols = config_service.get_config("PARTITION_COLUMNS")

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    # Creating metrics dataframe
    metastore_columns_df = get_columns_from_metastore(spark_client, schemas_skip_list)
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
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader.update_metastore(
        metastore_columns_df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=metastore_columns_df,
        partition_cols=partition_cols,
    )
    spark_metastore_service.refresh_table(database_name, table_name)
