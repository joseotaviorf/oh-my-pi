import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from langfuse import Langfuse
from pyspark.sql.functions import lit

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
)
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_languse_raw"
SOURCE = "langfuse"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_langfuse_data(langfuse, execution_date, table_name):
    """Retrieves data from Langfuse API for the specified table and execution date."""
    if table_name == "scores":
        resp = langfuse.api.score_v_2.get(from_timestamp=execution_date)
    elif table_name == "traces":
        resp = langfuse.api.trace.list(from_timestamp=execution_date)
    elif table_name == "observations":
        resp = langfuse.api.observations.get_many(from_start_time=execution_date)
    else:
        raise Exception(f"Table {table_name} not found")

    json_data = [json.dumps(x.dict(), default=str) for x in resp.data]
    return json_data

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name")
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    parser.add_argument("table_name")

    args = parser.parse_args()
    dag_name = args.dag_name
    environment = args.env
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    execution_date_str = args.execution_date
    execution_date = datetime.fromisoformat(execution_date_str)
    partition_cols = ["year", "month", "day", "hour"]

    config_service = ConfigurationService(dag_name)
    langfuse_host = config_service.get_config("langfuse_host")

    logger.info(f"m=dag_name={dag_name}, environment={environment}, datalake_bucket={datalake_bucket}")
    logger.info(f"m=table_name={table_name}, execution_date_str={execution_date_str}")
 

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    langfuse_pk = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key='LANGFUSE_PUBLIC_KEY')
    langfuse_sk = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key='LANGFUSE_SECRET_KEY')

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, SOURCE, datalake_bucket
    )
    database_name = datalake_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    langfuse = Langfuse(
        secret_key=langfuse_sk,
        public_key=langfuse_pk,
        host=langfuse_host
    )

    json_data = get_langfuse_data(langfuse, execution_date, table_name)
    rdd = spark.sparkContext.parallelize(json_data)
    df = spark.read.json(rdd)

    # Check if DataFrame is empty before proceeding
    if df.isEmpty():
        logger.info(f"No data found for table {table_name} on execution date {execution_date_str}. Skipping processing.")
    else:
        logger.info(f"Found records for table {table_name} on execution date {execution_date_str}")
        
        # Check if metadata column exists and drop it if present
        if "metadata" in df.columns:
            # logger.info("Dropping 'metadata' column from DataFrame")
            df = df.drop("metadata")
        
        df = (
            df.withColumn("year", lit(execution_date.year))
            .withColumn("month", lit(execution_date.month))
            .withColumn("day", lit(execution_date.day))
            .withColumn("hour", lit(execution_date.hour))
        )

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
            partitions=partition_cols,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=partition_cols,
        )

        full_raw_table_name = f"datalake_{SOURCE}_raw.{table_name}"
        table_privileges = TablePrivileges.from_environment_default(full_raw_table_name)
        if (
            table_privileges
            and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
        ):
            table_privileges.apply()
