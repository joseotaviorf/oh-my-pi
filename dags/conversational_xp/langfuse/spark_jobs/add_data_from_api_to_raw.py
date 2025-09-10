import json
import logging
import os
import time
import random
from argparse import ArgumentParser
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed


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
PAGE_SIZE = 100

# retry and performance constants
MAX_RETRIES = 5
EXPONENTIAL_BACKOFF_BASE = 2
JITTER_MIN = 0.1
JITTER_MAX = 0.5
ERROR_SAMPLE_LIMIT = 5
MINUTES_INTERVAL = 30
CPU_USAGE_PERCENTAGE = 0.5

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(
    name=JOB_NAME,
    fmt='%(levelname)s:%(name)s:%(asctime)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
)

def fetch_page_with_retry(langfuse, table_name, start_timestamp, end_timestamp, page, limit=PAGE_SIZE, max_retries=MAX_RETRIES):
    """Fetch a single page with exponential backoff retry."""
    interval_str = f"{start_timestamp.strftime('%Y-%m-%d %H:%M')}-{end_timestamp.strftime('%H:%M')}"
    for attempt in range(max_retries + 1):
        try:
            result = fetch_page(langfuse, table_name, start_timestamp, end_timestamp, page, limit)

            if attempt > 0:
                logger.info(f"Interval {interval_str}: Request succeeded for page {page} after {attempt} retries")
            
            return result
        except Exception as e:
            if attempt == max_retries:
                raise e
            
            base_delay = EXPONENTIAL_BACKOFF_BASE ** attempt  # 1s, 2s, 4s
            jitter = random.uniform(JITTER_MIN, JITTER_MAX)  # add 10-50% jitter
            delay = base_delay + jitter
            
            logger.warning(
                f"Interval {interval_str}: Error on page {page} "
                f"attempt {attempt + 1}/{max_retries + 1}. Retrying in {delay:.2f}s. Error: {str(e)}"
            )
            time.sleep(delay)
    
    # this should never be reached, but just in case
    raise RuntimeError(f"Interval {interval_str}: Unexpected error in retry logic for page {page}")


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


def generate_time_intervals(start_timestamp, end_timestamp):
    """Generate time intervals between start and end timestamps based on MINUTES_INTERVAL."""
    intervals = []
    current_start = start_timestamp
    
    while current_start < end_timestamp:
        current_end = min(current_start + timedelta(minutes=MINUTES_INTERVAL), end_timestamp)
        intervals.append((current_start, current_end))
        current_start = current_end
    
    return intervals


def get_langfuse_data(langfuse, start_timestamp, end_timestamp, table_name, max_workers):
    """Retrieves data from Langfuse API using parallel requests for better performance."""

    first_page_result = fetch_page_with_retry(langfuse, table_name, start_timestamp, end_timestamp, 1, PAGE_SIZE)
    all_json_data = first_page_result['data']
    
    # according to Langfuse API docs, meta.totalPages should always be present
    total_pages = first_page_result['meta']['totalPages']
    logger.info(f"Pages to fetch: {total_pages}")

    if total_pages == 1:
        return all_json_data

    pages_to_fetch = list(range(2, total_pages + 1))

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_page = {
            executor.submit(fetch_page_with_retry, langfuse, table_name, start_timestamp, end_timestamp, page, PAGE_SIZE): page
            for page in pages_to_fetch
        }
        
        # collect results as they complete; aggregate errors and raise after fetch
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
            sample = ", ".join([f"page={p}: {str(e)}" for p, e in errors[:ERROR_SAMPLE_LIMIT]])
            raise RuntimeError(f"{len(errors)} page request(s) failed: {sample}")

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

    # fetch the last 1.5 hours of data, 30min + 1hr from airflow schedule
    end_timestamp = datetime.fromisoformat(end_timestamp_str).replace(tzinfo=None)
    start_timestamp = datetime.fromisoformat(start_timestamp_str).replace(tzinfo=None) - timedelta(minutes=MINUTES_INTERVAL)
    partition_cols = ["year", "month", "day", "hour"]

    config_service = ConfigurationService(dag_name)
    langfuse_host = config_service.get_config("langfuse_host")

    logger.info(f"m=dag_name={dag_name}, environment={environment}, datalake_bucket={datalake_bucket}")
    logger.info(f"m=table_name={table_name}")
 

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

    max_workers = max(1, int((os.cpu_count() or 1) * CPU_USAGE_PERCENTAGE))
    logger.info(f"Using {max_workers} workers")
    logger.info(f"Using {PAGE_SIZE} page size")

    intervals = generate_time_intervals(start_timestamp, end_timestamp)
    logger.info(f"Fetching from {start_timestamp.strftime('%Y-%m-%d %H:%M')} to {end_timestamp.strftime('%Y-%m-%d %H:%M')}")
    logger.info(f"{len(intervals)} {MINUTES_INTERVAL}min intervals")

    langfuse = Langfuse(
        secret_key=langfuse_sk,
        public_key=langfuse_pk,
        host=langfuse_host
    )

    all_json_data = []
    for i, (interval_start, interval_end) in enumerate(intervals, 1):
        interval_str = f"{interval_start.strftime('%Y-%m-%d %H:%M')}-{interval_end.strftime('%H:%M')}"
        logger.info(f"Interval {i}/{len(intervals)}: {interval_start.strftime('%Y-%m-%d %H:%M')} to {interval_end.strftime('%Y-%m-%d %H:%M')}")
        try:
            interval_data = get_langfuse_data(langfuse, interval_start, interval_end, table_name, max_workers)
            if interval_data:
                all_json_data.extend(interval_data)
                logger.info(f"Found {len(interval_data)} records for interval {interval_str}")
            else:
                logger.info(f"No data found for interval {interval_str}")
        except Exception as e:
            logger.error(f"Failed to fetch data for interval {interval_str}: {str(e)}")
            raise
    
    logger.info(f"Total records: {len(all_json_data)}")

    if not all_json_data:
        logger.warning(f"No data found, skipping processing...")
    else:

        rdd = spark.sparkContext.parallelize(all_json_data)
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
