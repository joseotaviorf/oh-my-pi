import json
import logging
import re
import time
import random
import threading
from argparse import ArgumentParser
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed

import boto3
from langfuse import Langfuse
from pyspark.sql.functions import lit, col

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
from bietlejuice.services.storage_services import S3Service


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "fetch_data"
SOURCE = "langfuse"

# retry and performance constants for API fetching
MAX_WORKERS = 5
MAX_RETRIES = 5
EXPONENTIAL_BACKOFF_BASE = 2
JITTER_MIN = 0.15
JITTER_MAX = 0.6
BATCH_SIZE = 100  # Number of score IDs to fetch per API call
LOG_INTERVAL_SECONDS = 30  # Log progress every N seconds


logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s:%(name)s:%(asctime)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = logging.getLogger(JOB_NAME)


def fetch_page_with_retry(langfuse, score_ids_str, page, max_retries=MAX_RETRIES):
    """Fetch a single page with retry logic."""
    for attempt in range(max_retries + 1):
        try:
            resp = langfuse.api.score_v_2.get(score_ids=score_ids_str, page=page)
            return resp
        except Exception as e:
            if attempt == max_retries:
                logger.error(f"Page {page}: All {max_retries} retries exhausted. Final error: {str(e)}")
                raise e
            base_delay = EXPONENTIAL_BACKOFF_BASE ** attempt
            jitter = random.uniform(JITTER_MIN, JITTER_MAX)
            delay = base_delay + jitter
            logger.warning(
                f"Page {page}: Retry {attempt + 1}/{max_retries} after error: {type(e).__name__}. "
                f"Waiting {delay:.2f}s"
            )
            time.sleep(delay)
    return None


def extract_score_data(score):
    """Extract id, session_id and metadata from a score object."""
    metadata = None
    if hasattr(score, 'metadata') and score.metadata:
        try:
            if isinstance(score.metadata, dict):
                metadata = json.dumps(score.metadata, default=str)
            elif hasattr(score.metadata, 'dict'):
                metadata = json.dumps(score.metadata.dict(), default=str)
            else:
                metadata = json.dumps(score.metadata, default=str)
        except Exception as e:
            logger.warning(f"Failed to serialize metadata for score {getattr(score, 'id', 'unknown')}: {str(e)}")
            metadata = None
    
    return {
        'id': getattr(score, 'id', None),
        'session_id': getattr(score, 'session_id', None),
        'metadata': metadata
    }


def fetch_scores_batch_with_retry(langfuse, score_ids, batch_num, total_batches, log_state):
    """Fetch all pages for a batch of score IDs."""
    start_time = time.time()
    try:
        score_ids_str = ",".join(score_ids)

        first_resp = fetch_page_with_retry(langfuse, score_ids_str, 1)
        if not first_resp or not hasattr(first_resp, 'data'):
            raise ValueError("Invalid response from API")
        
        results = [extract_score_data(score) for score in first_resp.data]
        total_pages = first_resp.meta.total_pages if hasattr(first_resp, 'meta') else 1

        if total_pages > 1:
            for page in range(2, total_pages + 1):
                resp = fetch_page_with_retry(langfuse, score_ids_str, page)
                results.extend([extract_score_data(score) for score in resp.data])
        
        elapsed = time.time() - start_time
        # count how many scores have actual data vs null placeholders
        valid_count = sum(1 for r in results if r.get('session_id') or r.get('metadata'))
        
        # log based on time interval or if it's the last batch
        current_time = time.time()
        should_log = False
        batches_completed = 0
        
        with log_state['lock']:
            log_state['batches_completed'] += 1
            batches_completed = log_state['batches_completed']
            time_since_last_log = current_time - log_state['last_log_time']
            is_last_batch = (batches_completed == total_batches)
            
            if time_since_last_log >= LOG_INTERVAL_SECONDS or is_last_batch:
                should_log = True
                log_state['last_log_time'] = current_time
        
        if should_log:
            logger.info(
                f"Progress: {batches_completed}/{total_batches} batches completed. "
                f"Latest batch ({batch_num}): {len(results)} scores ({valid_count} with data) in {elapsed:.2f}s"
            )
        
        return results
        
    except Exception as e:
        elapsed = time.time() - start_time
        logger.error(
            f"Batch {batch_num}/{total_batches}: Failed after {elapsed:.2f}s. "
            f"{len(score_ids)} scores affected. Error: {str(e)}"
        )
        return [{'id': sid, 'session_id': None, 'metadata': None} for sid in score_ids]


def enrich_scores_from_api(df, langfuse):
    """Enrich scores dataframe with session_id and metadata from API."""
    start_time = time.time()
    logger.info("=" * 60)
    logger.info("Starting API enrichment for scores table")
    logger.info(f"Config: {MAX_WORKERS} workers, batch size {BATCH_SIZE}")

    score_ids = [row.id for row in df.select("id").distinct().collect()]
    logger.info(f"Total scores: {len(score_ids)}")
    
    if not score_ids:
        logger.warning("No score IDs found, skipping enrichment")
        return df

    # split score IDs into batches
    batches = [score_ids[i:i + BATCH_SIZE] for i in range(0, len(score_ids), BATCH_SIZE)]
    logger.info(f"Processing {len(batches)} batches (logging every {LOG_INTERVAL_SECONDS}s)")

    api_data = []
    failed_batches = 0
    successful_batches = 0
    
    # thread-safe state for time-based logging
    log_state = {
        'last_log_time': time.time(),
        'batches_completed': 0,
        'lock': threading.Lock()
    }
    
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_batch = {
            executor.submit(fetch_scores_batch_with_retry, langfuse, batch, batch_num + 1, len(batches), log_state): (batch_num + 1, len(batch))
            for batch_num, batch in enumerate(batches)
        }
        
        for future in as_completed(future_to_batch):
            batch_num, batch_size = future_to_batch[future]
            try:
                results = future.result()
                if results:
                    # Check if batch returned valid data or null placeholders
                    valid_results = [r for r in results if r.get('session_id') is not None or r.get('metadata') is not None]
                    if valid_results:
                        successful_batches += 1
                    else:
                        failed_batches += 1
                        logger.warning(f"Batch {batch_num}/{len(batches)}: No valid data returned")
                    api_data.extend(results)
            except Exception as e:
                failed_batches += 1
                logger.error(f"Batch {batch_num}/{len(batches)}: Unexpected error - {str(e)}")
    
    elapsed = time.time() - start_time
    success_rate = (successful_batches / len(batches) * 100) if batches else 0
    
    logger.info("=" * 60)
    logger.info(f"API enrichment completed in {elapsed:.2f}s")
    logger.info(f"Summary: {successful_batches}/{len(batches)} batches successful ({success_rate:.1f}%)")
    logger.info(f"Total API records retrieved: {len(api_data)}")
    if failed_batches > 0:
        logger.warning(f"Failed batches: {failed_batches} (scores will have null session_id/metadata)")
    logger.info("=" * 60)
    
    if api_data:
        api_df = spark.createDataFrame(api_data)
        
        api_df = api_df.withColumnRenamed("session_id", "api_session_id") \
                       .withColumnRenamed("metadata", "api_metadata")
        
        # join with original dataframe on score_id
        enriched_df = df.join(api_df, df.id == api_df.id, "left") \
                        .drop(api_df.id)
        
        # coalesce to prefer API values, fall back to S3
        enriched_df = enriched_df.withColumn(
            "session_id",
            col("api_session_id")
        ).withColumn(
            "metadata",
            col("api_metadata")
        ).drop("api_session_id", "api_metadata")
        
        logger.info("Successfully enriched dataframe with API data")
        return enriched_df
    else:
        logger.warning("No API data found")
        return df


def fetch_from_s3(s3_service, proxy_path, start_timestamp, end_timestamp, table_name):
    """Fetch data from S3 for all tables."""
    logger.info(f"Fetching data from S3 for table: {table_name}")
    logger.info(f"S3 path: {proxy_path}")

    hours_diff = int((end_timestamp - start_timestamp) / timedelta(hours=1)) + 1
    timestamp_strs = [
        (start_timestamp + timedelta(hours=i)).strftime("%Y-%m-%dT%H*") for i in range(hours_diff)
    ]

    objs = s3_service.list_objects(proxy_path)
    timestamp_patterns = [re.compile(ts_str.replace('*', '.*')) for ts_str in timestamp_strs]
    valid_files = [
        filename for filename in objs if any(
            pattern.search(filename) for pattern in timestamp_patterns
        )
    ]
    
    logger.info(f"Found {len(valid_files)} files")
    
    if not valid_files:
        logger.warning(f"No files found between {start_timestamp} and {end_timestamp}")
        return None

    df = spark.read.json(valid_files)

    if df.isEmpty():
        logger.warning(f"Dataframe is empty for table {table_name} between {start_timestamp} and {end_timestamp}. Skipping data loading operations.")
        return None
    
    if "metadata" in df.columns:
        df = df.withColumn("metadata", col("metadata").cast("string"))
    
    return df

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

    logger.info(f"dag_name={dag_name}, environment={environment}, datalake_bucket={datalake_bucket}")
    logger.info(f"table_name={table_name}")
    logger.info(f"start_timestamp={start_timestamp_str}, end_timestamp={end_timestamp_str}")

    # Parse timestamps
    end_timestamp = datetime.fromisoformat(end_timestamp_str).replace(tzinfo=None)
    start_timestamp = datetime.fromisoformat(start_timestamp_str).replace(tzinfo=None)
    partition_cols = ["year", "month", "day", "hour"]

    # Initialize services
    config_service = ConfigurationService(dag_name)
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    # Setup database
    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, SOURCE, datalake_bucket
    )
    database_name = datalake_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    langfuse_integration_bucket_path = config_service.get_config("langfuse_integration_bucket_path")
    proxy_path = f"{langfuse_integration_bucket_path}{table_name}"
    
    s3_service = S3Service(boto3.resource("s3"))
    df = fetch_from_s3(s3_service, proxy_path, start_timestamp, end_timestamp, table_name)

    # for scores table, enrich with API data (session_id and metadata)
    if table_name == "scores" and df is not None:
        logger.info("Enriching scores table with API data")
        
        langfuse_host = config_service.get_config("langfuse_host")
        
        base_dbutils = BaseDBUtils()
        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        langfuse_pk = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key='LANGFUSE_PUBLIC_KEY')
        langfuse_sk = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key='LANGFUSE_SECRET_KEY')

        langfuse = Langfuse(
            secret_key=langfuse_sk,
            public_key=langfuse_pk,
            host=langfuse_host
        )

        df = enrich_scores_from_api(df, langfuse)

    if df is None:
        logger.warning(f"No data to process for table {table_name}")
    else:
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
            optimize_dataframe=False,
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

        full_raw_table_name = f"datalake_{SOURCE}_raw.{table_name}"
        table_privileges = TablePrivileges.from_environment_default(full_raw_table_name)
        if (
            table_privileges
            and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
        ):
            table_privileges.apply()

        logger.info(f"Successfully processed and loaded data for table {table_name}")
