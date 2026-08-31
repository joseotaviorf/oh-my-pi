"""
This spark job reads quintoml's prompt manifest directly (the same source
Task A in ../vocs_machina_planning.py reads, to decide skip vs proceed) and
registers the resulting inference-status rows as
datalake_vocs_machina_planning_raw.vocs_machina_inference_status.

Runs as a step on the EMR job cluster this DAG creates right before this job
(execute-job-cluster task): that cluster's own instance profile reaches both
quintoml's manifest bucket and this repo's own datalake bucket directly, so
this job does its own read + transform + load in one shot instead of
receiving pre-built rows from Task A. Two earlier hand-off designs were
tried and abandoned:
  - Airflow (airflow-prod-role) staging the rows as a JSON blob to this
    repo's own datalake bucket: needs a PutObject grant Airflow doesn't have.
  - Task A pushing the rows to XCom and this job pulling them into a CLI
    parameter: worked mechanically, but the DAG submitted Spark work through
    Databricks' jobs/runs/submit back then, which caps the total parameters
    payload at 10,000 bytes, and a real production backfill window
    serializes to ~76KB -- see bi-etl-ejuice#27353 (reverted).
So this job re-derives the same rows Task A computes, via the
manifest-reading/row-building functions mirrored 1:1 from
../vocs_machina_planning.py (no cross-import between dags/ and spark_jobs/
exists elsewhere in this repo) -- keep the two copies in sync if that logic
ever changes.

Shape otherwise mirrors dags/platform/dag_inventory/spark_jobs/load_dag_inventory_raw.py:
build a Spark DataFrame, then S3Loader.load_df + SparkMetastoreLoader.update_metastore
+ SparkMetastoreService.create_new_partitions_from_df.

Partitioning: year/month/day are parsed from each row's own "day" field (the
backfill day whose inference status the row reports) and reused as BOTH the
partition columns and the only surviving representation of that day -- no
separate date column, matching load_dag_inventory_raw.py's
create_dag_dataframe (which also has no date column beyond year/month/day).
This is deliberately different from load_start_date (this DAG run's own
ingestion/load date, used only to compute "today" for the backfill window):
a single computed row set mixes many different backfill days across all
active prompts, so "the day this snapshot was taken" and "the day a given
row's status is about" are genuinely different things. Only the latter is
used for this table's partitions, so the raw table stays queryable per
backfill day (same idea as load_vocs_machina_raw.py, which partitions by the
day its content is about).
"""

import json
import logging
import re
from argparse import ArgumentParser
from datetime import datetime, timedelta

import boto3
from pyspark.sql import Row
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_vocs_machina_inference_status_raw"
DATE_FMT = "%Y-%m-%d"
INFERENCE_STATUS_SCHEMA = (
    "prompt_id:string, prompt_hash:string, inference_status:string, "
    "year:int, month:int, day:int"
)

# quintoml's vocs-machina S3 layout -- mirrored byte-for-byte from the
# module-level constants in ../vocs_machina_planning.py (Task A reads the
# same manifest/markers to compute its skip-vs-proceed decision).
DATA_SCIENCE_BUCKET = "data-science.s3.data.quintoandar.com.br"
VOCS_MACHINA_MANIFEST_KEY = (
    "post-contract/vocs-machina/_meta/latest_active_prompts.json"
)
VOCS_MACHINA_RAW_PREFIX = "post-contract/vocs-machina/raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def active_prompts(manifest):
    """Return only the prompts flagged active=True in quintoml's manifest.

    Mirrors active_prompts in ../vocs_machina_planning.py -- see that
    function's docstring for why identity against True (not bare
    truthiness) is checked.
    """
    return [
        prompt for prompt in manifest.get("prompts", []) if prompt.get("active") is True
    ]


def backfill_day_range(today, backfill_days):
    """Inclusive day range [today - backfill_days, today].

    Mirrors backfill_day_range in ../vocs_machina_planning.py.
    """
    if backfill_days < 0:
        raise ValueError(f"backfill_days must be >= 0, got {backfill_days}")
    start = today - timedelta(days=backfill_days)
    return [start + timedelta(days=offset) for offset in range(backfill_days + 1)]


def success_marker_key(prompt_id, prompt_hash, day):
    """Build the _SUCCESS marker key for one (day, prompt_id, prompt_hash) partition.

    Mirrors success_marker_key in ../vocs_machina_planning.py, which mirrors
    quintoml's vocs_machina/storage.py build_partition_prefix +
    build_success_marker_uri byte-for-byte (zero-padded month/day).
    """
    return (
        f"{VOCS_MACHINA_RAW_PREFIX}/"
        f"year={day.year}/month={day.month:02d}/day={day.day:02d}/"
        f"prompt_id={prompt_id}/prompt_hash={prompt_hash}/_SUCCESS"
    )


_UNSAFE_PARTITION_COMPONENT_RE = re.compile(r"[/\x00-\x1f]")


def _is_safe_partition_component(value):
    """True if value is safe to embed as a single S3 partition-key segment.

    Mirrors _is_safe_partition_component in ../vocs_machina_planning.py.
    """
    return isinstance(value, str) and not _UNSAFE_PARTITION_COMPONENT_RE.search(value)


def iter_partition_days(prompts, today):
    """Expand each active prompt into (day, prompt_id, prompt_hash) tuples, one
    per backfill day.

    Mirrors iter_partition_days in ../vocs_machina_planning.py -- see that
    function's docstring for the malformed-entry-skipping and
    de-duplication rules.
    """
    partition_days = []
    seen = set()
    for prompt in prompts:
        try:
            prompt_id = prompt["prompt_id"]
            prompt_hash = prompt["prompt_hash"]
            days = backfill_day_range(today, prompt["backfill_days"])
        except (KeyError, ValueError) as exc:
            logger.warning(
                f"m=iter_partition_days, prompt_id={prompt.get('prompt_id')}, "
                f"msg=Skipping prompt with missing/invalid required field: {exc}"
            )
            continue
        if not (
            _is_safe_partition_component(prompt_id)
            and _is_safe_partition_component(prompt_hash)
        ):
            logger.warning(
                f"m=iter_partition_days, prompt_id={prompt_id!r}, "
                f"msg=Skipping prompt with a prompt_id/prompt_hash unsafe for "
                f"S3 partition keys"
            )
            continue
        for day in days:
            key = (day, prompt_id, prompt_hash)
            if key in seen:
                continue
            seen.add(key)
            partition_days.append(key)
    return partition_days


def build_snapshot_rows(partition_days, existing_marker_keys):
    """Pure S3-key -> status mapping: "done" if the partition's _SUCCESS marker
    key is present in existing_marker_keys, "missing" otherwise.

    Mirrors build_snapshot_rows in ../vocs_machina_planning.py.
    """
    rows = []
    for day, prompt_id, prompt_hash in partition_days:
        marker_key = success_marker_key(prompt_id, prompt_hash, day)
        status = "done" if marker_key in existing_marker_keys else "missing"
        rows.append(
            {
                "day": day.strftime(DATE_FMT),
                "prompt_id": prompt_id,
                "prompt_hash": prompt_hash,
                "inference_status": status,
            }
        )
    return rows


def existing_marker_keys_for_days(s3_client, days):
    """Batch-list every _SUCCESS marker that exists for a set of backfill days.

    Same batching contract as existing_marker_keys_for_days in
    ../vocs_machina_planning.py (one list call per unique day, not one
    per-partition check) -- adapted to a raw boto3 client + paginator since
    this job has no Airflow S3Hook to hand it.
    """
    existing_keys = set()
    paginator = s3_client.get_paginator("list_objects_v2")
    for day in days:
        prefix = (
            f"{VOCS_MACHINA_RAW_PREFIX}/"
            f"year={day.year}/month={day.month:02d}/day={day.day:02d}/"
        )
        for page in paginator.paginate(Bucket=DATA_SCIENCE_BUCKET, Prefix=prefix):
            for obj in page.get("Contents", []):
                if obj["Key"].endswith("/_SUCCESS"):
                    existing_keys.add(obj["Key"])
    return existing_keys


def read_active_prompts_manifest(s3_client) -> dict:
    """Read and parse quintoml's prompt manifest (read-only, never written here)."""
    body = (
        s3_client.get_object(Bucket=DATA_SCIENCE_BUCKET, Key=VOCS_MACHINA_MANIFEST_KEY)[
            "Body"
        ]
        .read()
        .decode("utf-8")
    )
    return json.loads(body)


def build_inference_status_dataframe(rows: list, spark_client):
    """Transform the computed inference-status rows into a Spark DataFrame.

    Passes an explicit schema, since create_dataframe(records) with no schema
    raises "can not infer schema from empty dataset" when rows is empty --
    which happens whenever quintoml's active-prompt manifest has zero active
    prompts for a run.
    """
    records = []
    for row in rows:
        dt = datetime.strptime(row["day"], DATE_FMT)
        records.append(
            Row(
                prompt_id=row["prompt_id"],
                prompt_hash=row["prompt_hash"],
                inference_status=row["inference_status"],
                year=dt.year,
                month=dt.month,
                day=dt.day,
            )
        )
    return spark_client.create_dataframe(records, schema=INFERENCE_STATUS_SCHEMA)


def main() -> None:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod/staging values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source", help="DAG name (vocs_machina_planning)")
    parser.add_argument("table_name")
    parser.add_argument(
        "load_start_date",
        help="This DAG run's ingestion/load date (YYYY-MM-DD), used to compute the backfill window",
    )
    parser.add_argument(
        "partitions", help="list with partition cols, e.g. \"['year', 'month', 'day']\""
    )
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    load_start_date = args.load_start_date
    partition_cols = json.loads(args.partitions.replace("'", '"'))

    logger.info(
        f"""
        m=main, environment={environment}, source={source}, table_name={table_name},
        load_start_date={load_start_date}, raw_partition_cols={partition_cols},
        msg=Starting Spark job...
        """
    )

    spark_client = SparkClient()
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    )

    logger.info("m=main, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_loader = S3Loader()
    s3_client = boto3.client("s3")

    today = datetime.strptime(load_start_date, DATE_FMT).date()
    manifest = read_active_prompts_manifest(s3_client)
    partition_days = iter_partition_days(active_prompts(manifest), today)
    unique_days = {day for day, _, _ in partition_days}
    existing_marker_keys = existing_marker_keys_for_days(s3_client, unique_days)
    rows = build_snapshot_rows(partition_days, existing_marker_keys)

    df = build_inference_status_dataframe(rows, spark_client)

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader.update_metastore(
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
        force_recreate=False,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partition_cols,
    )


if __name__ == "__main__":
    main()
