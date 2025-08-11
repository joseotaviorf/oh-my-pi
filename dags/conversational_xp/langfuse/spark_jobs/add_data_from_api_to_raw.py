import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed
import os

from langfuse import Langfuse
from pyspark.sql.functions import lit, to_json, col

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
JOB_NAME = "load_langfuse_raw"
SOURCE = "langfuse"
PAGE_SIZE = 50

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def fetch_page(langfuse, table_name, start_timestamp, end_timestamp, page, limit=PAGE_SIZE):
    """Fetch a single page of data from start_timestamp to end_timestamp. Raise on failure."""
    if table_name == "scores":
        resp = langfuse.api.score_v_2.get(
            from_timestamp=start_timestamp,
            to_timestamp=end_timestamp,
            page=page,
            limit=limit,
        )
    elif table_name == "traces":
        resp = langfuse.api.trace.list(
            from_timestamp=start_timestamp,
            to_timestamp=end_timestamp,
            page=page,
            limit=limit,
        )
    elif table_name == "observations":
        resp = langfuse.api.observations.get_many(
            from_start_time=start_timestamp,
            to_start_time=end_timestamp,
            page=page,
            limit=limit,
        )
    else:
        raise Exception(f"Table {table_name} not found")

    return {
        'page': page,
        'data': [json.dumps(x.dict(), default=str) for x in resp.data],
        'meta': resp.meta.dict() if hasattr(resp, 'meta') else {},
    }


def get_langfuse_data(langfuse, start_timestamp, end_timestamp, table_name):
    """Retrieves data from Langfuse API using parallel requests for better performance."""
    limit = PAGE_SIZE
    # use 80% of available CPU cores for the worker pool, minimum of 1
    max_workers = max(1, int((os.cpu_count() or 1) * 0.8))
    
    logger.info(f"Fetching data from start_timestamp {start_timestamp} to end_timestamp {end_timestamp}")
    logger.info(f"Using {max_workers} workers with page size {limit}")

    first_page_result = fetch_page(langfuse, table_name, start_timestamp, end_timestamp, 1, limit)
    
    all_json_data = first_page_result['data']
    
    # according to Langfuse API docs, meta.totalPages should always be present
    total_pages = first_page_result['meta']['totalPages']
    logger.info(f"Total pages to fetch: {total_pages}")

    if total_pages == 1:
        logger.info(f"Only one page of data for table {table_name}")
        return all_json_data

    pages_to_fetch = list(range(2, total_pages + 1))
    
    # use only as many workers as we have pages to fetch
    num_workers = min(max_workers, len(pages_to_fetch))

    
    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        future_to_page = {
            executor.submit(fetch_page, langfuse, table_name, start_timestamp, end_timestamp, page, limit): page
            for page in pages_to_fetch
        }
        
        # collect results as they complete; aggregate errors and raise after fetch phase
        errors = []
        for future in as_completed(future_to_page):
            page = future_to_page[future]
            try:
                result = future.result()
                if result.get('data'):
                    all_json_data.extend(result['data'])
            except Exception as e:
                errors.append((page, e))

        if errors:
            sample = ", ".join([f"page={p}: {str(e)}" for p, e in errors[:5]])
            raise RuntimeError(f"{len(errors)} page request(s) failed: {sample}")
    
    logger.info(f"Total records for table {table_name}: {len(all_json_data)}")
    return all_json_data

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name")
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("start_timestamp")
    parser.add_argument("end_timestamp")
    parser.add_argument("table_name")

    args = parser.parse_args()
    dag_name = args.dag_name
    environment = args.env
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    start_timestamp_str = args.start_timestamp
    end_timestamp_str = args.end_timestamp

    start_timestamp = datetime.fromisoformat(start_timestamp_str)  - timedelta(hours=2)
    end_timestamp = datetime.fromisoformat(end_timestamp_str)
    partition_cols = ["year", "month", "day", "hour"]

    config_service = ConfigurationService(dag_name)
    langfuse_host = config_service.get_config("langfuse_host")

    logger.info(f"m=dag_name={dag_name}, environment={environment}, datalake_bucket={datalake_bucket}")
    logger.info(f"m=table_name={table_name}, start_timestamp={start_timestamp}, end_timestamp={end_timestamp}")
 

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

    json_data = get_langfuse_data(langfuse, start_timestamp, end_timestamp, table_name)

    if not json_data:
        logger.warning(f"No data found, skipping processing.")
    else:

        rdd = spark.sparkContext.parallelize(json_data)
        df = spark.read.json(rdd)

        if "metadata" in df.columns:
            df = df.withColumn("metadata", to_json(col("metadata")))
        
        df = (
            df.withColumn("year", lit(start_timestamp.year))
            .withColumn("month", lit(start_timestamp.month))
            .withColumn("day", lit(start_timestamp.day))
            .withColumn("hour", lit(start_timestamp.hour))
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
