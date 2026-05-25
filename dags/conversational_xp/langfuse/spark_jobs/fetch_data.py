import json
import logging
import random
import re
import threading
import time
from argparse import ArgumentParser
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta

import boto3
from langfuse import Langfuse
from pyspark.sql import functions as F
from pyspark.sql.types import FloatType, StringType, StructField, StructType

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

MAX_WORKERS = 5
MIN_WORKERS = 1
HEALTH_WINDOW_SIZE = 20
RATE_LIMIT_PENALTY = 2
MAX_RETRIES = 3
EXPONENTIAL_BACKOFF_BASE = 2
JITTER_MIN = 0.5
JITTER_MAX = 2
BATCH_SIZE = 100

# ordered from highest threshold to lowest — evaluate top-down,
# first match wins (score >= min_score)
HEALTH_LEVELS = [
    {"name": "HEALTHY", "min_score": 0.8, "workers": MAX_WORKERS, "delay": 0.0},
    {"name": "DEGRADED", "min_score": 0.5, "workers": 3, "delay": 5.0},
    {"name": "STRESSED", "min_score": 0.2, "workers": 2, "delay": 15.0},
    {"name": "CRITICAL", "min_score": 0.0, "workers": MIN_WORKERS, "delay": 30.0},
]


logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s:%(name)s:%(asctime)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = logging.getLogger(JOB_NAME)


class ApiHealthMonitor:
    """Tracks API health via rolling window and exposes adaptive control signals."""

    def __init__(self, window_size=HEALTH_WINDOW_SIZE):
        self._window = deque([1.0] * window_size, maxlen=window_size)
        self._lock = threading.RLock()
        self._critical_entered_at = None
        self._previous_level_name = "HEALTHY"
        self._transitions = []

    @property
    def health_score(self):
        with self._lock:
            return sum(self._window) / len(self._window)

    def _resolve_level(self, score):
        for level in HEALTH_LEVELS:
            if score >= level["min_score"]:
                return level
        return HEALTH_LEVELS[-1]

    @property
    def health_level(self):
        return self._resolve_level(self.health_score)

    @property
    def health_level_name(self):
        return self.health_level["name"]

    @property
    def current_workers(self):
        return self.health_level["workers"]

    @property
    def inter_wave_delay(self):
        return self.health_level["delay"]

    def record(self, succeeded, status_code=None):
        with self._lock:
            if succeeded:
                self._window.append(1.0)
            else:
                # count rate limiting as a heavier signal than other failures
                penalty = RATE_LIMIT_PENALTY if status_code == 429 else 1
                for _ in range(penalty):
                    self._window.append(0.0)
            self._handle_level_transition()

    def _level_index(self, name):
        return next(
            (
                index
                for index, level in enumerate(HEALTH_LEVELS)
                if level["name"] == name
            ),
            -1,
        )

    def _handle_level_transition(self):
        current_name = self.health_level_name
        if current_name == self._previous_level_name:
            return

        old_name = self._previous_level_name
        old_level_data = HEALTH_LEVELS[self._level_index(old_name)]
        self._transitions.append((old_name, current_name))

        if current_name == "CRITICAL":
            self._critical_entered_at = time.time()
        elif old_name == "CRITICAL":
            self._critical_entered_at = None

        current_level = self.health_level
        score = self.health_score
        is_downgrade = self._level_index(current_name) > self._level_index(old_name)

        if is_downgrade:
            logger.warning(
                f"Health downgrade: {old_name} → {current_name} "
                f"(score: {score:.2f}, workers: {old_level_data['workers']}→{current_level['workers']}, "
                f"delay: {old_level_data['delay']:.1f}→{current_level['delay']:.1f}s)"
            )
        else:
            logger.info(
                f"Health recovered: {old_name} → {current_name} "
                f"(score: {score:.2f}, workers: {old_level_data['workers']}→{current_level['workers']}, "
                f"delay: {old_level_data['delay']:.1f}→{current_level['delay']:.1f}s)"
            )

        self._previous_level_name = current_name

    def critical_duration(self):
        if self._critical_entered_at is None:
            return 0.0
        return time.time() - self._critical_entered_at


def fetch_page_with_retry(langfuse, score_ids_str, page, max_retries=MAX_RETRIES):
    for attempt in range(max_retries + 1):
        try:
            resp = langfuse.api.score_v_2.get(score_ids=score_ids_str, page=page)
            return resp, None
        except Exception as e:
            status_code = getattr(e, "status_code", None)
            if attempt == max_retries:
                raise

            base_delay = EXPONENTIAL_BACKOFF_BASE**attempt
            jitter = random.uniform(JITTER_MIN, JITTER_MAX)
            delay = base_delay + jitter

            if status_code == 429:
                retry_after = getattr(e, "retry_after", None)
                if retry_after:
                    delay = max(delay, float(retry_after))

            time.sleep(delay)


def extract_score_data(score):
    metadata = None
    if hasattr(score, "metadata") and score.metadata:
        try:
            if hasattr(score.metadata, "dict"):
                metadata = json.dumps(score.metadata.dict(), default=str)
            else:
                metadata = json.dumps(score.metadata, default=str)
        except Exception as e:
            logger.warning(
                f"Failed to serialize metadata for score {getattr(score, 'id', 'unknown')}: {str(e)}"
            )
            metadata = None

    return {
        "id": getattr(score, "id", None),
        "session_id": getattr(score, "session_id", None),
        "metadata": metadata,
        "value": getattr(score, "value", None),
    }


def fetch_scores_batch_with_retry(langfuse, score_ids, batch_num, total_batches):
    try:
        score_ids_str = ",".join(score_ids)

        first_resp, _ = fetch_page_with_retry(langfuse, score_ids_str, 1)
        if not first_resp or not hasattr(first_resp, "data"):
            raise ValueError("Invalid response from API")

        results = [extract_score_data(score) for score in first_resp.data]
        total_pages = first_resp.meta.total_pages if hasattr(first_resp, "meta") else 1

        if total_pages > 1:
            for page in range(2, total_pages + 1):
                resp, _ = fetch_page_with_retry(langfuse, score_ids_str, page)
                results.extend([extract_score_data(score) for score in resp.data])

        return results, None, True, None

    except Exception as e:
        status_code = getattr(e, "status_code", None)
        error_msg = str(e).split("\n")[0][:200]
        return (
            [
                {"id": sid, "session_id": None, "metadata": None, "value": None}
                for sid in score_ids
            ],
            status_code,
            False,
            error_msg,
        )


def enrich_scores_from_api(df, langfuse, spark):
    start_time = time.time()

    total_rows = df.count()
    df = df.dropDuplicates(subset=["id"])
    deduplicated_rows = df.count()

    if total_rows > deduplicated_rows:
        logger.warning(
            f"Removed {total_rows - deduplicated_rows} duplicate IDs. "
            f"Original: {total_rows}, After: {deduplicated_rows}"
        )

    score_ids = [row.id for row in df.select("id").collect()]

    if not score_ids:
        logger.warning("No score IDs found, skipping enrichment")
        return df

    batches = [
        score_ids[i : i + BATCH_SIZE] for i in range(0, len(score_ids), BATCH_SIZE)
    ]
    monitor = ApiHealthMonitor()

    logger.info(
        f"Starting API enrichment: {len(batches)} batches, "
        f"{monitor.current_workers} workers"
    )

    api_data = []
    total_succeeded = 0
    total_failed = 0
    wave_num = 0
    remaining = list(enumerate(batches, 1))
    last_logged_error = None

    # single pool for the entire run - parallelism is controlled
    # by wave size, not by pool capacity
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        while remaining:
            delay = monitor.inter_wave_delay
            if delay > 0:
                logger.info(
                    f"Health={monitor.health_level_name}: pausing {delay:.1f}s between waves"
                )
                time.sleep(delay)

            # wave size == current_workers: if monitor says 2,
            # we only submit 2 concurrent batches even though
            # the pool could handle 5
            wave_size = max(monitor.current_workers, 1)
            wave, remaining = remaining[:wave_size], remaining[wave_size:]
            wave_num += 1

            futures = {
                executor.submit(
                    fetch_scores_batch_with_retry,
                    langfuse,
                    batch,
                    batch_num,
                    len(batches),
                ): batch_num
                for batch_num, batch in wave
            }

            wave_succeeded = 0
            wave_failed = 0
            wave_errors = {}

            # wait for ALL futures in this wave before starting the next -
            # this guarantees we never exceed wave_size concurrent requests
            for future in as_completed(futures):
                results, status_code, succeeded, error_msg = future.result()
                monitor.record(succeeded, status_code)
                if succeeded:
                    wave_succeeded += 1
                else:
                    wave_failed += 1
                    if error_msg:
                        wave_errors[error_msg] = wave_errors.get(error_msg, 0) + 1
                api_data.extend(results)

            total_succeeded += wave_succeeded
            total_failed += wave_failed

            estimated_total_waves = wave_num + len(remaining) // max(wave_size, 1)
            critical_secs = monitor.critical_duration()
            summary = (
                f"Wave {wave_num}/{estimated_total_waves}: "
                f"{wave_succeeded}/{len(wave)} ok | "
                f"Health: {monitor.health_level_name} ({monitor.health_score:.2f})"
            )
            if critical_secs > 0:
                summary += f" | CRITICAL for {critical_secs:.0f}s"

            if wave_errors:
                top_error = max(wave_errors, key=wave_errors.get)
                is_new_error = top_error != last_logged_error
                if is_new_error:
                    summary += f" | {top_error} (x{wave_errors[top_error]})"
                    last_logged_error = top_error
                else:
                    summary += f" | same error (x{wave_failed})"

            logger.info(summary)

    elapsed = time.time() - start_time
    logger.info(
        f"API enrichment completed in {elapsed:.1f}s | "
        f"{total_succeeded}/{len(batches)} batches ok"
        + (f", {total_failed} failed" if total_failed > 0 else "")
    )

    if api_data:
        api_schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("session_id", StringType(), True),
                StructField("metadata", StringType(), True),
                StructField("value", FloatType(), True),
            ]
        )
        api_df = spark.createDataFrame(api_data, schema=api_schema)

        api_df = (
            api_df.withColumnRenamed("session_id", "api_session_id")
            .withColumnRenamed("metadata", "api_metadata")
            .withColumnRenamed("value", "api_value")
            .select("id", "api_session_id", "api_metadata", "api_value")
        )

        enriched_df = df.join(api_df, df.id == api_df.id, "left").drop(api_df.id)

        for column_name in ("session_id", "metadata", "value"):
            api_column_name = f"api_{column_name}"
            if column_name in df.columns:
                enriched_df = enriched_df.withColumn(
                    column_name,
                    F.coalesce(F.col(api_column_name), F.col(column_name)),
                )
            else:
                enriched_df = enriched_df.withColumn(
                    column_name, F.col(api_column_name)
                )

        enriched_df = enriched_df.drop("api_session_id", "api_metadata", "api_value")
        return enriched_df
    else:
        logger.warning("No API data found")
        return df


def fetch_from_s3(
    spark, s3_service, proxy_path, start_timestamp, end_timestamp, table_name
):
    logger.info(f"Fetching data from S3 for table: {table_name}, path: {proxy_path}")

    hours_diff = int((end_timestamp - start_timestamp) / timedelta(hours=1)) + 1
    timestamp_strs = [
        (start_timestamp + timedelta(hours=i)).strftime("%Y-%m-%dT%H*")
        for i in range(hours_diff)
    ]

    objs = s3_service.list_objects(proxy_path)
    timestamp_patterns = [
        re.compile(ts_str.replace("*", ".*")) for ts_str in timestamp_strs
    ]
    valid_files = [
        filename
        for filename in objs
        if any(pattern.search(filename) for pattern in timestamp_patterns)
    ]

    logger.info(f"Found {len(valid_files)} files")

    if not valid_files:
        raise RuntimeError(
            "No data found in S3 bucket from Langfuse export. "
            "Access https://langfuse.apps.core-prd-green.habitat.zone/project/cma4b5v5l000f2n07551cc2v8/settings/integrations/blobstorage "
            "and click run now or contact the Conversational Platform Team"
        )

    df = spark.read.json(valid_files)

    if df.isEmpty():
        logger.warning(
            f"Dataframe is empty for table {table_name} between {start_timestamp} and {end_timestamp}. Skipping data loading operations."
        )
        return None

    if "metadata" in df.columns:
        df = df.withColumn("metadata", F.to_json(F.col("metadata")))

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

    logger.info(
        f"dag_name={dag_name}, environment={environment}, datalake_bucket={datalake_bucket}"
    )
    logger.info(f"table_name={table_name}")
    logger.info(
        f"start_timestamp={start_timestamp_str}, end_timestamp={end_timestamp_str}"
    )

    end_timestamp = datetime.fromisoformat(end_timestamp_str).replace(tzinfo=None)
    start_timestamp = datetime.fromisoformat(start_timestamp_str).replace(
        tzinfo=None
    ) - timedelta(hours=2)
    partition_cols = ["year", "month", "day", "hour"]

    config_service = ConfigurationService(dag_name)
    spark_client = SparkClient()
    spark = spark_client.conn
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

    langfuse_integration_bucket_path = config_service.get_config(
        "langfuse_integration_bucket_path"
    )
    proxy_path = f"{langfuse_integration_bucket_path}{table_name}"

    s3_service = S3Service(boto3.resource("s3"))
    df = fetch_from_s3(
        spark, s3_service, proxy_path, start_timestamp, end_timestamp, table_name
    )

    # for scores table, enrich with API data (session_id and metadata)
    if table_name == "scores" and df is not None:
        logger.info("Enriching scores table with API data")

        langfuse_host = config_service.get_config("langfuse_host")
        logger.info(f"Langfuse API host: {langfuse_host}")

        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()
        if dbutils is None:
            raise RuntimeError("Databricks dbutils is unavailable")

        langfuse_pk = dbutils.secrets.get(
            scope=DATABRICKS_SCOPE, key="LANGFUSE_PUBLIC_KEY"
        )
        langfuse_sk = dbutils.secrets.get(
            scope=DATABRICKS_SCOPE, key="LANGFUSE_SECRET_KEY"
        )

        langfuse = Langfuse(
            secret_key=langfuse_sk, public_key=langfuse_pk, host=langfuse_host
        )

        df = enrich_scores_from_api(df, langfuse, spark)

    if df is None:
        logger.warning(f"No data to process for table {table_name}")
    else:
        df = (
            df.withColumn("year", F.lit(start_timestamp.year))
            .withColumn("month", F.lit(start_timestamp.month))
            .withColumn("day", F.lit(start_timestamp.day))
            .withColumn("hour", F.lit(start_timestamp.hour))
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
        if table_privileges and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
            table_privileges.apply()

        logger.info(f"Successfully processed and loaded data for table {table_name}")
