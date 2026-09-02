"""Load vocs-machina's `_meta/` JSON artifacts into raw Delta tables.

Unlike the sibling `vocs_machina` DAG's `load_vocs_machina_raw.py`, these
artifacts are NOT day-partitioned in their S3 key layout (no
year=/month=/day= prefix): run summaries and backfill plans are one file per
run_id, throughput observations are MANY files per run under a flat prefix
(one per calibration sample, keyed `<observed_at>-<run_id>.json`), and the
prompt catalog snapshot is a single fixed-key JSON file
(latest_active_prompts.json). So this job does a full-prefix rescan of each
`_meta/` sub-prefix on every invocation (json glob, no load_start_date/
load_end_date range) and relies on a Delta MERGE keyed to the artifact's
grain: run_id for run_summaries/backfill_plans, [run_id, observed_at] for
throughput observations (multiple samples share a run_id), and
[run_id, prompt_id] for the prompt catalog snapshot. Matched keys are
never updated (`when_matched_update_condition="FALSE"`): `_meta/` artifacts
are immutable once written, so a rescan must not restamp `ts_load` or hop
year/month/day into today's partition. New keys still insert. This is
the opposite of the sibling's day-partition-overwrite pattern.

Dispatches on the positional `table_name` CLI arg to one of 4 parse paths --
run_summaries, throughput_observations, prompt_catalog_snapshots,
backfill_plans -- see TABLE_BUILDERS.

Every row gets `s3_key` (source object key), `ts_load` (ingestion timestamp),
and `year`/`month`/`day` derived from `ts_load` -- not from any field in the
source JSON, since no business-date field is guaranteed across all 4 artifact
shapes (backfill_plans in particular has none at all).
"""

import json
import logging
from argparse import ArgumentParser
from typing import Callable, Dict, List, Optional

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    ArrayType,
    BooleanType,
    DoubleType,
    IntegerType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_vocs_machina_meta_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
    spark_client
)

# Exceptions Spark raises for "no matching files" / "cannot infer schema from
# an empty/absent set of files". These `_meta/` artifacts are sparse by
# design (throughput_observations/backfill_plans can legitimately have zero
# files most runs; the prompt catalog snapshot file may not exist yet before
# vocs-machina's first run), so any of these markers is treated as
# legitimately-empty input rather than a failure -- mirroring
# load_vocs_machina_raw.py's day-partition skip pattern.
MISSING_DATA_MARKERS = (
    "Path does not exist",
    "PATH_NOT_FOUND",
    "UNABLE_TO_INFER_SCHEMA",
)

# Shared nested-struct shapes reused across run_summaries and backfill_plans.
THROUGHPUT_CALIBRATION_SCHEMA = StructType(
    [
        StructField("calls_per_second", DoubleType(), True),
        StructField("basis", StringType(), True),
        StructField("config_default", DoubleType(), True),
    ]
)

BACKFILL_BREAKER_SCHEMA = StructType(
    [
        StructField("tripped", BooleanType(), True),
        StructField("fingerprint", StringType(), True),
        StructField("reasons", ArrayType(StringType()), True),
        StructField("n_prompts", IntegerType(), True),
        StructField("n_partitions", IntegerType(), True),
        StructField("estimated_calls", IntegerType(), True),
        StructField("approved", BooleanType(), True),
        StructField("refused", BooleanType(), True),
        StructField(
            "approved_pairs",
            ArrayType(
                StructType(
                    [
                        StructField("prompt_id", StringType(), True),
                        StructField("prompt_hash", StringType(), True),
                    ]
                )
            ),
            True,
        ),
    ]
)

BACKFILL_ESCALATION_ATTRIBUTION_SCHEMA = StructType(
    [
        StructField("escalated_to_backfill", BooleanType(), True),
        StructField("forward_tasks", IntegerType(), True),
        StructField("backfill_tasks", IntegerType(), True),
        StructField("forward_plan_and_fetch_seconds", DoubleType(), True),
        StructField("backfill_plan_and_fetch_seconds", DoubleType(), True),
        StructField("backfill_share_estimated", BooleanType(), True),
        StructField("forward_classification_seconds_estimated", DoubleType(), True),
        StructField("backfill_classification_seconds_estimated", DoubleType(), True),
        StructField("forward_cost_usd_estimated", DoubleType(), True),
        StructField("backfill_cost_usd_estimated", DoubleType(), True),
    ]
)

RUN_SUMMARIES_SCHEMA = StructType(
    [
        StructField("run_id", StringType(), True),
        StructField(
            "window",
            StructType(
                [
                    StructField("start", StringType(), True),
                    StructField("end", StringType(), True),
                ]
            ),
            True,
        ),
        StructField("environment", StringType(), True),
        StructField("mode", StringType(), True),
        StructField("execution_backend", StringType(), True),
        StructField("model", StringType(), True),
        StructField("failed_sources", ArrayType(StringType()), True),
        StructField("forward_tasks", IntegerType(), True),
        StructField("backfill_tasks", IntegerType(), True),
        StructField("prompts_backfilling", ArrayType(StringType()), True),
        StructField(
            "metrics",
            StructType(
                [
                    StructField("planned_calls", IntegerType(), True),
                    StructField("completed_calls", IntegerType(), True),
                    StructField("failed_calls", IntegerType(), True),
                    StructField("calls_per_second", DoubleType(), True),
                    StructField("duration_seconds", DoubleType(), True),
                    StructField("classification_duration_seconds", DoubleType(), True),
                    StructField("retry_total", IntegerType(), True),
                    StructField("retry_429_total", IntegerType(), True),
                    StructField("prompt_tokens", IntegerType(), True),
                    StructField("completion_tokens", IntegerType(), True),
                    StructField("cached_tokens", IntegerType(), True),
                    StructField("cache_hit_rate", DoubleType(), True),
                    StructField("partitions_complete", IntegerType(), True),
                    StructField("partitions_incomplete", IntegerType(), True),
                    StructField("backfill_deferred_partitions", IntegerType(), True),
                    StructField("checkpoint_rows_written", IntegerType(), True),
                    StructField("source_fetch_failures", IntegerType(), True),
                    StructField("response_cost_usd", DoubleType(), True),
                ]
            ),
            True,
        ),
        StructField("throughput_calibration", THROUGHPUT_CALIBRATION_SCHEMA, True),
        StructField("backfill_breaker", BACKFILL_BREAKER_SCHEMA, True),
        StructField(
            "backfill_escalation_attribution",
            BACKFILL_ESCALATION_ATTRIBUTION_SCHEMA,
            True,
        ),
    ]
)

THROUGHPUT_OBSERVATIONS_SCHEMA = StructType(
    [
        StructField("run_id", StringType(), True),
        StructField("observed_at", StringType(), True),
        StructField("model", StringType(), True),
        StructField("mode", StringType(), True),
        StructField("completed_calls", IntegerType(), True),
        StructField("duration_seconds", DoubleType(), True),
        StructField("calls_per_second", DoubleType(), True),
    ]
)

PROMPT_CATALOG_SNAPSHOT_SCHEMA = StructType(
    [
        StructField("generated_at", StringType(), True),
        StructField("run_id", StringType(), True),
        StructField(
            "prompts",
            ArrayType(
                StructType(
                    [
                        StructField("prompt_id", StringType(), True),
                        StructField("prompt_hash", StringType(), True),
                        StructField(
                            "classifier_contract_fingerprint", StringType(), True
                        ),
                        # Kept as a raw JSON string, not a struct: unlike the
                        # named nested sections above (fixed schema), this
                        # applicability clause tree's shape varies per prompt
                        # and risks Spark struct schema-merge failures across
                        # rows. Declaring the field StringType in an explicit
                        # read schema makes Spark's JSON reader serialize the
                        # nested object/array back to its raw JSON text
                        # instead of attempting to parse it into a struct.
                        StructField("effective_applicability", StringType(), True),
                        StructField("active", BooleanType(), True),
                        StructField("collection", StringType(), True),
                        StructField("opportunity", StringType(), True),
                        StructField("backfill_days", IntegerType(), True),
                    ]
                )
            ),
            True,
        ),
    ]
)

BACKFILL_PLANS_SCHEMA = StructType(
    [
        StructField("partitions", IntegerType(), True),
        StructField("estimated_calls", IntegerType(), True),
        StructField("estimated_llm_seconds", DoubleType(), True),
        StructField("estimated_wall_clock_seconds", IntegerType(), True),
        StructField("estimated_runs_needed", IntegerType(), True),
        StructField(
            "estimate_basis_counts",
            StructType(
                [
                    StructField("measured_from_last_success", IntegerType(), True),
                    StructField("config_default", IntegerType(), True),
                ]
            ),
            True,
        ),
        StructField("caution", StringType(), True),
        StructField("throughput_calibration", THROUGHPUT_CALIBRATION_SCHEMA, True),
        StructField("backfill_breaker", BACKFILL_BREAKER_SCHEMA, True),
    ]
)

MERGE_KEYS: Dict[str, List[str]] = {
    "run_summaries": ["run_id"],
    # A run emits many throughput samples (one file per observation), so run_id
    # alone is not unique -- keying on it would collapse samples and, on the
    # next full rescan, abort the MERGE with multiple source/target matches.
    "throughput_observations": ["run_id", "observed_at"],
    "prompt_catalog_snapshots": ["run_id", "prompt_id"],
    "backfill_plans": ["run_id"],
}

# `_meta/` artifacts are immutable. Updating matched keys would only restamp
# ts_load and hop year/month/day into today's partition.
WHEN_MATCHED_UPDATE_CONDITION = "FALSE"

# Appended by _add_source_and_load_columns / _add_ts_load_partition_cols.
# Empty frames written on a missing sparse prefix must carry the same
# columns so DeltaLoader.load_table can create the raw table for the
# downstream clean LOAD_DELTA task (which always runs).
_LOAD_METADATA_FIELDS = [
    StructField("s3_key", StringType(), True),
    StructField("ts_load", TimestampType(), True),
    StructField("year", IntegerType(), True),
    StructField("month", IntegerType(), True),
    StructField("day", IntegerType(), True),
]


def _with_load_metadata(
    schema: StructType, extra_before_load: Optional[List[StructField]] = None
) -> StructType:
    fields = list(schema.fields)
    if extra_before_load:
        fields.extend(extra_before_load)
    fields.extend(_LOAD_METADATA_FIELDS)
    return StructType(fields)


# Exploded prompt-catalog row (one row per prompt), plus load metadata.
# Column order must match build_prompt_catalog_snapshots_df.
PROMPT_CATALOG_SNAPSHOTS_OUTPUT_SCHEMA = StructType(
    [
        StructField("generated_at", StringType(), True),
        StructField("run_id", StringType(), True),
        StructField("prompt_id", StringType(), True),
        StructField("prompt_hash", StringType(), True),
        StructField("classifier_contract_fingerprint", StringType(), True),
        StructField("effective_applicability", StringType(), True),
        StructField("active", BooleanType(), True),
        StructField("collection", StringType(), True),
        StructField("opportunity", StringType(), True),
        StructField("backfill_days", IntegerType(), True),
    ]
    + _LOAD_METADATA_FIELDS
)

OUTPUT_SCHEMAS: Dict[str, StructType] = {
    "run_summaries": _with_load_metadata(RUN_SUMMARIES_SCHEMA),
    "throughput_observations": _with_load_metadata(THROUGHPUT_OBSERVATIONS_SCHEMA),
    "prompt_catalog_snapshots": PROMPT_CATALOG_SNAPSHOTS_OUTPUT_SCHEMA,
    "backfill_plans": _with_load_metadata(
        BACKFILL_PLANS_SCHEMA,
        extra_before_load=[StructField("run_id", StringType(), True)],
    ),
}


def ensure_output_df(
    spark: SparkSession, table_name: str, df: Optional[DataFrame]
) -> DataFrame:
    """Return `df`, or an empty frame with the table's output schema.

    Sparse `_meta/` prefixes legitimately have zero files. Skipping the
    write would leave the raw Delta table uncreated, and the framework
    still runs the paired clean LOAD_DELTA task against it. An empty
    merge creates/keeps the table so clean can SELECT zero rows.
    """
    if df is None:
        logger.warning(
            f"m=ensure_output_df, table_name={table_name}, "
            f"msg=No source files found; writing empty frame so the raw "
            f"table exists for the downstream clean task."
        )
        return spark.createDataFrame([], OUTPUT_SCHEMAS[table_name])
    return df


# Extracts the run_id from a backfill_plans object key, e.g.
# ".../_meta/backfill_plans/<run_id>.json" -> "<run_id>". backfill_plans.json
# bodies carry no run_id field of their own -- it is only encoded in the
# filename.
BACKFILL_PLAN_RUN_ID_RE = r"backfill_plans/([^/]+)\.json$"


def get_forno_adjusted_data_science_path(
    environment: str, source_root_path: str
) -> str:
    """Resolve data-science bucket host for forno vs prod/staging."""
    if environment == "forno":
        return source_root_path.replace(
            "s3://data-science.s3.data", "s3://data-science.s3.forno.data"
        )
    return source_root_path


def _read_json_or_none(
    spark: SparkSession, path: str, schema: StructType
) -> Optional[DataFrame]:
    """Read a JSON glob/single-file path with an explicit schema.

    Returns None (never raises) when no files match `path` -- a legitimate
    "nothing to ingest this run" state for these sparse `_meta/` artifacts.
    Any other failure (auth, corruption) is a real error and is re-raised.
    """
    try:
        return spark.read.schema(schema).json(path)
    except Exception as exc:
        msg = str(exc)
        if any(marker in msg for marker in MISSING_DATA_MARKERS):
            logger.warning(
                f"m=_read_json_or_none, path={path}, "
                f"msg=No matching files (expected when this artifact is sparse "
                f"or not yet written); skipping. error={msg}"
            )
            return None
        raise


def _add_ts_load_partition_cols(df: DataFrame) -> DataFrame:
    """Add ts_load and ts_load-derived year/month/day columns."""
    out = df.withColumn("ts_load", F.current_timestamp())
    return (
        out.withColumn("year", F.year("ts_load"))
        .withColumn("month", F.month("ts_load"))
        .withColumn("day", F.dayofmonth("ts_load"))
    )


def _add_source_and_load_columns(df: DataFrame) -> DataFrame:
    """Add s3_key, ts_load, and ts_load-derived year/month/day columns."""
    with_key = df.withColumn("s3_key", F.input_file_name())
    return _add_ts_load_partition_cols(with_key)


def build_run_summaries_df(
    spark: SparkSession, source_root_path: str
) -> Optional[DataFrame]:
    path = f"{source_root_path}/_meta/runs/*/summary.json"
    df = _read_json_or_none(spark, path, RUN_SUMMARIES_SCHEMA)
    if df is None:
        return None
    return _add_source_and_load_columns(df)


def build_throughput_observations_df(
    spark: SparkSession, source_root_path: str
) -> Optional[DataFrame]:
    path = f"{source_root_path}/_meta/throughput/*.json"
    df = _read_json_or_none(spark, path, THROUGHPUT_OBSERVATIONS_SCHEMA)
    if df is None:
        return None
    # Capture s3_key before dropDuplicates. input_file_name() is empty after
    # a shuffle/aggregation, so stamping it afterwards would blank lineage
    # on every throughput row (the catalog path already materializes s3_key
    # before explode + dropDuplicates for the same reason).
    df = df.withColumn("s3_key", F.input_file_name())
    # The MERGE keys this table on [run_id, observed_at]. A run's samples each
    # carry a distinct observed_at, but collapse any exact duplicate defensively
    # so two identical source rows can't abort the MERGE on one target key.
    df = df.dropDuplicates(["run_id", "observed_at"])
    return _add_ts_load_partition_cols(df)


def build_prompt_catalog_snapshots_df(
    spark: SparkSession, source_root_path: str
) -> Optional[DataFrame]:
    path = f"{source_root_path}/_meta/latest_active_prompts.json"
    df = _read_json_or_none(spark, path, PROMPT_CATALOG_SNAPSHOT_SCHEMA)
    if df is None:
        return None

    # Capture s3_key before the explode so each exploded prompt row carries
    # the source file it came from.
    with_key = df.withColumn("s3_key", F.input_file_name())
    exploded = with_key.select(
        "generated_at",
        "run_id",
        "s3_key",
        F.explode("prompts").alias("prompt"),
    ).select(
        "generated_at",
        "run_id",
        F.col("prompt.prompt_id").alias("prompt_id"),
        F.col("prompt.prompt_hash").alias("prompt_hash"),
        F.col("prompt.classifier_contract_fingerprint").alias(
            "classifier_contract_fingerprint"
        ),
        F.col("prompt.effective_applicability").alias("effective_applicability"),
        F.col("prompt.active").alias("active"),
        F.col("prompt.collection").alias("collection"),
        F.col("prompt.opportunity").alias("opportunity"),
        F.col("prompt.backfill_days").alias("backfill_days"),
        "s3_key",
    )
    # The Delta MERGE keys this table on [run_id, prompt_id]. A single snapshot
    # is expected to list each prompt_id once, but a duplicate would make two
    # source rows match the same target key and abort the MERGE with
    # DeltaUnsupportedOperationException. Collapse duplicates defensively (rows
    # for a repeated prompt_id in one snapshot carry identical content).
    exploded = exploded.dropDuplicates(["run_id", "prompt_id"])
    return _add_ts_load_partition_cols(exploded)


def build_backfill_plans_df(
    spark: SparkSession, source_root_path: str
) -> Optional[DataFrame]:
    path = f"{source_root_path}/_meta/backfill_plans/*.json"
    df = _read_json_or_none(spark, path, BACKFILL_PLANS_SCHEMA)
    if df is None:
        return None
    with_run_id = df.withColumn(
        "run_id",
        F.regexp_extract(F.input_file_name(), BACKFILL_PLAN_RUN_ID_RE, 1),
    )
    return _add_source_and_load_columns(with_run_id)


TABLE_BUILDERS: Dict[str, Callable[[SparkSession, str], Optional[DataFrame]]] = {
    "run_summaries": build_run_summaries_df,
    "throughput_observations": build_throughput_observations_df,
    "prompt_catalog_snapshots": build_prompt_catalog_snapshots_df,
    "backfill_plans": build_backfill_plans_df,
}


def main() -> None:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod/staging values")
    parser.add_argument("bucket", help="bucket value in forno/prod")
    parser.add_argument("schema", help="datalake schema name")
    parser.add_argument(
        "source_root_path",
        help="S3 base path for vocs-machina output (no trailing slash)",
    )
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("partitions", help="list with partition cols")
    parser.add_argument("format", help="data format to load from S3 (json)")
    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    bucket = args.bucket
    schema = args.schema
    source_root_path = get_forno_adjusted_data_science_path(
        environment, args.source_root_path
    )
    table_name = args.table_name
    partition_cols = json.loads(args.partitions.replace("'", '"'))

    if table_name not in TABLE_BUILDERS:
        raise ValueError(
            f"m=main, msg=Unknown table_name {table_name!r}; expected one of "
            f"{sorted(TABLE_BUILDERS)}"
        )

    logger.info(
        f"m=main, environment={environment}, schema={schema}, table_name={table_name}, "
        f"source_root_path={source_root_path}, msg=Starting spark job..."
    )

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )

    metastore_service.create_database(write_database_name)

    df = ensure_output_df(
        spark, table_name, TABLE_BUILDERS[table_name](spark, source_root_path)
    )
    row_count = df.count()
    if row_count == 0:
        logger.warning(
            f"m=main, table_name={table_name}, "
            f"msg=Writing empty frame (no source rows) so the raw table "
            f"exists for the downstream clean task."
        )

    full_table_name = f"{write_database_name}.{write_table_name}"
    table_path = f"{write_location}{write_table_name}"

    # DeltaLoader.load_table is invoked directly here (not via the framework's
    # LOAD_DELTA clean-layer task creator) -- this is an established pattern
    # for custom raw-layer jobs, e.g.
    # dags/qcx/blip_messages/spark_jobs/load_blip_messages_raw.py.
    # Insert-only MERGE: `_meta/` JSON for a given run_id is immutable, so
    # updating matched rows would only restamp ts_load and move history into
    # today's year/month/day partition -- the anti-pattern the sibling
    # vocs_machina DAG documents for ts_load-based merge conditions. Same
    # FALSE-on-match pattern as load_blip_messages_raw.py.
    loader = DeltaLoader(spark)
    loader.load_table(
        table_name=full_table_name,
        path=table_path,
        source_df=df,
        partition_by=partition_cols,
        merge_on=MERGE_KEYS[table_name],
        when_matched_update_condition=WHEN_MATCHED_UPDATE_CONDITION,
    )

    logger.info(
        f"m=main, table_name={full_table_name}, row_count={row_count}, "
        f"msg=Successfully merged {table_name} into datalake"
    )


if __name__ == "__main__":
    main()
