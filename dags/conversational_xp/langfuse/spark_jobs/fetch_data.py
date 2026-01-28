import json
import logging
import time
import random
from argparse import ArgumentParser
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Callable, Dict, List

import boto3
from langfuse import Langfuse
from pyspark.sql.functions import lit, col, coalesce

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

MAX_WORKERS = 8 # maximum number of workers to use for API fetching
MAX_RETRIES = 5 # maximum number of times to retry a failed request
EXPONENTIAL_BACKOFF_BASE = 2 # base for exponential backoff, e.g. 2^0 = 1s, 2^1 = 2s, 2^2 = 4s, etc.
JITTER_MIN = 0.5 # min seconds of jitter added to delay API calls when retrying
JITTER_MAX = 2 # max seconds of jitter added to delay API calls when retrying
BATCH_SIZE = 100  # number IDs to fetch from API per batch
MAX_CONSECUTIVE_FAILURES = 10  # halt job after N consecutive batch failures


logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s:%(name)s:%(asctime)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = logging.getLogger(JOB_NAME)


class TooManyConsecutiveFailuresError(Exception):
    """Raised when too many consecutive batch failures occur, indicating persistent API issues."""
    pass


def call_with_retry(*, make_call, call_label, max_retries=MAX_RETRIES):
    for attempt in range(max_retries + 1):
        try:
            return make_call()
        except Exception as e:
            if attempt == max_retries:
                logger.error(f"{call_label}: all {max_retries} retries exhausted after {type(e).__name__}: {str(e)}")
                raise e
            base_delay = EXPONENTIAL_BACKOFF_BASE ** attempt
            jitter = random.uniform(JITTER_MIN, JITTER_MAX)
            delay = base_delay + jitter
            logger.warning(
                f"{call_label}: attempt {attempt + 1}/{max_retries + 1} failed with {type(e).__name__}"
                f"Retrying in {delay:.2f}s (base={base_delay}s, jitter={jitter:.2f}s)"
            )
            time.sleep(delay)


def iter_batches(id_iter, batch_size: int):
    batch: List[str] = []
    for item_id in id_iter:
        batch.append(item_id)
        if len(batch) >= batch_size:
            yield batch
            batch = []
    if batch:
        yield batch


def collect_batch_results(
    *,
    future_to_batch_num: Dict,
    is_valid_record: Callable[[Dict], bool],
    entity_label: str,
    total_batches: int,
):
    api_data: List[Dict] = []
    failed_batches = 0
    successful_batches = 0
    consecutive_failures = 0
    completed_batches = 0

    for future in as_completed(future_to_batch_num):
        batch_num = future_to_batch_num[future]
        try:
            results = future.result()
            consecutive_failures = 0
            if results:
                valid_results = [r for r in results if is_valid_record(r)]
                if valid_results:
                    successful_batches += 1
                else:
                    failed_batches += 1
                api_data.extend(results)
            else:
                failed_batches += 1
        except TooManyConsecutiveFailuresError:
            raise
        except Exception as e:
            consecutive_failures += 1
            failed_batches += 1
            if consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
                raise TooManyConsecutiveFailuresError(
                    f"Job halted after {consecutive_failures} consecutive batch failures "
                    f"while fetching {entity_label}. Last error: {type(e).__name__}: {str(e)}"
                ) from e

        completed_batches += 1
        if completed_batches % 10 == 0 or completed_batches == total_batches:
            logger.info(f"{entity_label}: processed {completed_batches}/{total_batches} batches")

    return api_data, successful_batches, failed_batches


def coalesce_columns(enriched_df, original_df, columns_map: Dict[str, str]):
    """Apply coalesce pattern for API enrichment columns.
    
    Args:
        enriched_df: DataFrame after join with API data
        original_df: Original DataFrame before join
        columns_map: Mapping of api_column -> target_column names
    """
    for api_col, target_col in columns_map.items():
        if target_col in original_df.columns:
            enriched_df = enriched_df.withColumn(target_col, coalesce(col(api_col), col(target_col)))
        else:
            enriched_df = enriched_df.withColumn(target_col, col(api_col))
        enriched_df = enriched_df.drop(api_col)
    return enriched_df


def validate_paginated_response(resp, batch_num: int, page: int):
    """Validate that API response has required pagination attributes."""
    if not hasattr(resp, 'data'):
        raise ValueError(f"Invalid API response: missing 'data' attribute (batch {batch_num}, page {page})")
    if not hasattr(resp, 'meta') or not hasattr(resp.meta, 'total_pages'):
        raise ValueError(f"Invalid API response: missing 'meta.total_pages' attribute (batch {batch_num}, page {page})")


def paginate_api_response(make_request: Callable, batch_num: int, extract_data: Callable[[List], List[Dict]]) -> List[Dict]:
    """Generic pagination handler for Langfuse API responses."""
    results = []
    page = 1
    while True:
        resp = call_with_retry(
            make_call=lambda p=page: make_request(page=p),
            call_label=f"batch {batch_num} page {page}",
        )
        validate_paginated_response(resp, batch_num, page)
        results.extend(extract_data(resp.data))
        if page >= resp.meta.total_pages:
            break
        page += 1
    return results


def fetch_and_collect_api_data(
    df,
    langfuse,
    fetch_batch_func: Callable,
    is_valid_record: Callable[[Dict], bool],
    entity_label: str,
) -> List[Dict]:
    start_time = time.time()
    logger.info(f"Starting API enrichment for {entity_label} (workers={MAX_WORKERS}, batch_size={BATCH_SIZE})")

    id_iter = (row.id for row in df.select("id").distinct().toLocalIterator())

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_batch_num = {
            executor.submit(fetch_batch_func, langfuse, batch, batch_num): batch_num
            for batch_num, batch in enumerate(iter_batches(id_iter, BATCH_SIZE), start=1)
        }
        batches_submitted = len(future_to_batch_num)

        if batches_submitted == 0:
            logger.info(f"No {entity_label} IDs found, skipping enrichment")
            return []

        api_data, successful_batches, failed_batches = collect_batch_results(
            future_to_batch_num=future_to_batch_num,
            is_valid_record=is_valid_record,
            entity_label=entity_label,
            total_batches=batches_submitted,
        )

    elapsed = time.time() - start_time
    success_rate = (successful_batches / batches_submitted * 100) if batches_submitted else 0

    logger.info(
        f"{entity_label.capitalize()} enrichment done in {elapsed:.2f}s "
        f"(batches={batches_submitted}, ok={successful_batches}, failed={failed_batches}, success_rate={success_rate:.1f}%, api_records={len(api_data)})"
    )
    return api_data


def enrich_df_from_api(
    df,
    langfuse,
    fetch_batch_func: Callable,
    is_valid_record: Callable[[Dict], bool],
    entity_label: str,
    columns_to_enrich: List[str],
):
    """Generic DataFrame enrichment from API data."""
    df = df.dropDuplicates(subset=["id"])

    api_data = fetch_and_collect_api_data(
        df=df,
        langfuse=langfuse,
        fetch_batch_func=fetch_batch_func,
        is_valid_record=is_valid_record,
        entity_label=entity_label,
    )

    if not api_data:
        return df

    api_df = spark.createDataFrame(api_data)  # type: ignore[name-defined]
    for col_name in columns_to_enrich:
        api_df = api_df.withColumnRenamed(col_name, f"api_{col_name}")
    api_df = api_df.select("id", *[f"api_{c}" for c in columns_to_enrich])

    enriched_df = df.join(api_df, df.id == api_df.id, "left").drop(api_df.id)

    columns_map = {f"api_{c}": c for c in columns_to_enrich}
    return coalesce_columns(enriched_df, df, columns_map)


def extract_score_data(score):
    """Extract id, session_id, metadata and value from a score object."""
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
        'metadata': metadata,
        'value': getattr(score, 'value', None)
    }


def fetch_scores_batch(langfuse, score_ids, batch_num):
    score_ids_str = ",".join(score_ids)
    return paginate_api_response(
        make_request=lambda page: langfuse.api.score_v_2.get(score_ids=score_ids_str, page=page),
        batch_num=batch_num,
        extract_data=lambda data: [extract_score_data(s) for s in data],
    )


def extract_observation_data(observation):
    return {
        "id": getattr(observation, "id", None),
        "latency": getattr(observation, "latency", None),
    }


def fetch_observations_batch(langfuse, observation_ids, batch_num):
    filter_json = json.dumps(
        [{"type": "stringOptions", "column": "id", "operator": "any of", "value": observation_ids}],
        separators=(",", ":"),
    )

    def extract_valid_observations(data):
        results = []
        for obs in data:
            extracted = extract_observation_data(obs)
            if extracted and extracted.get("id") is not None:
                results.append(extracted)
        return results

    return paginate_api_response(
        make_request=lambda page: langfuse.api.observations.get_many(filter=filter_json, limit=100, page=page),
        batch_num=batch_num,
        extract_data=extract_valid_observations,
    )


def enrich_from_langfuse_api(df, table_name, config_service, databricks_scope):
    """Enrich DataFrame with Langfuse API data for scores or observations tables."""
    langfuse_host = config_service.get_config("langfuse_host")

    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()
    if dbutils is None:
        logger.warning("dbutils is not available; skipping API enrichment")
        return df

    langfuse_pk = dbutils.secrets.get(scope=databricks_scope, key='LANGFUSE_PUBLIC_KEY')
    langfuse_sk = dbutils.secrets.get(scope=databricks_scope, key='LANGFUSE_SECRET_KEY')

    langfuse = Langfuse(
        secret_key=langfuse_sk,
        public_key=langfuse_pk,
        host=langfuse_host
    )

    logger.info(f"Enriching {table_name} table with API data")

    if table_name == "scores":
        return enrich_df_from_api(
            df=df,
            langfuse=langfuse,
            fetch_batch_func=fetch_scores_batch,
            is_valid_record=lambda r: r.get("session_id") is not None or r.get("metadata") is not None,
            entity_label="scores",
            columns_to_enrich=["session_id", "metadata", "value"],
        )

    if table_name == "observations":
        return enrich_df_from_api(
            df=df,
            langfuse=langfuse,
            fetch_batch_func=fetch_observations_batch,
            is_valid_record=lambda r: r.get("latency") is not None,
            entity_label="observations",
            columns_to_enrich=["latency"],
        )

    return df


def fetch_from_s3(s3_service, proxy_path, start_timestamp, end_timestamp, table_name):
    """Fetch data from S3 for all tables."""
    logger.info(f"Fetching data from S3 for table: {table_name}")
    logger.info(f"S3 path: {proxy_path}")

    base_path = proxy_path if proxy_path.endswith("/") else f"{proxy_path}/"
    hours_diff = int((end_timestamp - start_timestamp) / timedelta(hours=1)) + 1
    
    valid_files = []
    for i in range(hours_diff):
        # construct timestamp prefix for the hour: YYYY-MM-DDTHH
        ts_str = (start_timestamp + timedelta(hours=i)).strftime("%Y-%m-%dT%H")
        prefix = f"{base_path}{ts_str}"

        files = s3_service.list_objects_by_prefix(prefix)
        valid_files.extend(files)
    
    logger.info(f"Found {len(valid_files)} files")
    
    if not valid_files:
        logger.warning(f"No files found between {start_timestamp} and {end_timestamp}")
        return None

    df = spark.read.json(valid_files)  # type: ignore[name-defined]

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

    end_timestamp = datetime.fromisoformat(end_timestamp_str).replace(tzinfo=None)
    start_timestamp = datetime.fromisoformat(start_timestamp_str).replace(tzinfo=None) - timedelta(hours=2)
    partition_cols = ["year", "month", "day", "hour"]

    config_service = ConfigurationService(dag_name)
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

    langfuse_integration_bucket_path = config_service.get_config("langfuse_integration_bucket_path")
    proxy_path = f"{langfuse_integration_bucket_path}{table_name}"
    
    s3_service = S3Service(boto3.resource("s3"))
    df = fetch_from_s3(s3_service, proxy_path, start_timestamp, end_timestamp, table_name)

    if table_name in ("scores", "observations") and df is not None:
        df = enrich_from_langfuse_api(df, table_name, config_service, DATABRICKS_SCOPE)

    if df is None:
        logger.warning(f"No data to process for table {table_name}, skipping...")
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
