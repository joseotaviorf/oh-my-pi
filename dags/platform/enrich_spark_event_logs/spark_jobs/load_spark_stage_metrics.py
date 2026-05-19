"""Ingest Spark event logs from S3 → Delta.

Source path layout (written by every bietlejuice cluster after PR 1):
    s3a://<databricks_bucket>/spark-event-logs/<dag_id>/eventlog…<spark_app_attempt>/
        JSONL shards (often zstd-compressed per ``spark.eventLog.compress``).

    Typical directory names include ``eventlog_v2_<id>/`` (underscore, Databricks
    local / driver apps) and ``eventlog-v2-<id>/`` (hyphen). Parsed with
    ``EVENTLOG_APP_ID_SEGMENT_PATTERN``.

The event log file format is JSONL (one JSON object per line), compressed on the
executor side when ``spark.eventLog.compress=true`` (often zstd in prod). Each line has an `Event`
discriminator string identifying the event type. We extract three event types
and join them at the (id_spark_app, id_stage, id_stage_attempt) grain:

  * `SparkListenerStageCompleted` — source of truth for stage existence;
    provides accumulator-driven metrics (shuffle, spill, executor time,
    peak execution memory).
  * `SparkListenerStageExecutorMetrics` — executor-level memory peaks and
    GC totals. Only emitted when `spark.eventLog.logStageExecutorMetrics=true`
    (enabled by PR #23078). Aggregated to per-stage MAX/SUM across executors.
  * `SparkListenerTaskEnd` — per-task wall-clock and GC time. Aggregated
    into approximate percentiles (p50/p95/max) for skew detection.

The latter two are LEFT-joined onto SparkListenerStageCompleted, so a stage
attempt with no executor-metrics or task-end events still produces a row
(with NULL in the corresponding columns). All other event types are ignored.

Cluster_id is intentionally NOT extracted here. It can be derived from the
`SparkListenerEnvironmentUpdate` event (Spark Properties .
`spark.databricks.clusterUsageTags.clusterId`), but that event can be missing
on short-lived apps and adds joining complexity. PR 5 will join
spark_app_id → cluster_id via system.lakeflow.job_run_timeline, which is more
authoritative and always populated.

Incremental loading uses Spark's `_metadata.file_modification_time` column
(DBR 16.1+) to skip files older than `load_start_date`. The 2-day lookback
window matches PR 2 (`enrich_databricks_health`) and accommodates late-
arriving logs from clusters that finish around midnight UTC.
"""

import argparse

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import (
    ArrayType,
    LongType,
    StringType,
    StructField,
    StructType,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.loaders.delta_loader import DeltaLoader

# Java regex for ``regexp_extract`` (capture group 1 = Spark application / attempt id).
# Databricks RollingEventLogFilesWriter uses ``eventlog_v2_<id>/``; hyphenated
# ``eventlog-v2-<id>/`` and legacy ``eventlog-<id>/`` also occur.
EVENTLOG_APP_ID_SEGMENT_PATTERN = r"eventlog(?:[_-]v\d+)?[_-]([^/]+)/"

JOB_NAME = "load_spark_stage_metrics"
logger = QuintoAndarLogger(JOB_NAME)


# Partial schema for the subset of fields we need from each Spark event line.
# Spark event logs have huge variable schema; we only declare what we read so
# `from_json` can skip everything else without inferring it.
ACCUMULABLE_SCHEMA = StructType(
    [
        StructField("ID", LongType(), nullable=True),
        StructField("Name", StringType(), nullable=True),
        StructField("Value", StringType(), nullable=True),
    ]
)
STAGE_INFO_SCHEMA = StructType(
    [
        StructField("Stage ID", LongType(), nullable=True),
        StructField("Stage Attempt ID", LongType(), nullable=True),
        StructField("Stage Name", StringType(), nullable=True),
        StructField("Number of Tasks", LongType(), nullable=True),
        StructField("Submission Time", LongType(), nullable=True),
        StructField("Completion Time", LongType(), nullable=True),
        StructField("Failure Reason", StringType(), nullable=True),
        StructField("Accumulables", ArrayType(ACCUMULABLE_SCHEMA), nullable=True),
    ]
)
# Subset of fields populated on `SparkListenerStageExecutorMetrics` events.
# The full struct has ~25 metric fields; we only declare the ones we aggregate.
EXECUTOR_METRICS_SCHEMA = StructType(
    [
        StructField("JVMHeapMemory", LongType(), nullable=True),
        StructField("OnHeapExecutionMemory", LongType(), nullable=True),
        StructField("OffHeapExecutionMemory", LongType(), nullable=True),
        StructField("MinorGCTime", LongType(), nullable=True),
        StructField("MajorGCTime", LongType(), nullable=True),
    ]
)
# Subset of fields populated on `SparkListenerTaskEnd` events.
TASK_INFO_SCHEMA = StructType(
    [
        StructField("Task ID", LongType(), nullable=True),
    ]
)
TASK_METRICS_SCHEMA = StructType(
    [
        StructField("Executor Run Time", LongType(), nullable=True),
        StructField("Executor CPU Time", LongType(), nullable=True),
        StructField("JVM GC Time", LongType(), nullable=True),
    ]
)
# Top-level event schema. Every field is nullable because each event line only
# populates the subset of fields relevant to its `Event` discriminator —
# StageCompleted populates `Stage Info`, StageExecutorMetrics populates
# `Executor ID` / `Executor Metrics` plus top-level `Stage ID` / `Stage Attempt ID`,
# and TaskEnd populates `Task Info` / `Task Metrics` plus the same top-level keys.
EVENT_SCHEMA = StructType(
    [
        StructField("Event", StringType(), nullable=True),
        StructField("Stage Info", STAGE_INFO_SCHEMA, nullable=True),
        StructField("Stage ID", LongType(), nullable=True),
        StructField("Stage Attempt ID", LongType(), nullable=True),
        StructField("Executor ID", StringType(), nullable=True),
        StructField("Executor Metrics", EXECUTOR_METRICS_SCHEMA, nullable=True),
        StructField("Task Info", TASK_INFO_SCHEMA, nullable=True),
        StructField("Task Metrics", TASK_METRICS_SCHEMA, nullable=True),
    ]
)

# Spark internal accumulator names → output column names.
# These names are stable across DBR versions (Spark 3.x onward) and live in
# org.apache.spark.executor.TaskMetrics.
STAGE_ACCUMULATORS = {
    "internal.metrics.executorRunTime": "executor_run_time_ms",
    "internal.metrics.executorCpuTime": "executor_cpu_time_ns",
    "internal.metrics.shuffle.read.localBytesRead": "shuffle_read_local_bytes",
    "internal.metrics.shuffle.read.remoteBytesRead": "shuffle_read_remote_bytes",
    "internal.metrics.shuffle.write.bytesWritten": "shuffle_write_bytes",
    "internal.metrics.input.bytesRead": "input_bytes_read",
    "internal.metrics.output.bytesWritten": "output_bytes_written",
    "internal.metrics.peakExecutionMemory": "peak_execution_memory_bytes",
    "internal.metrics.diskBytesSpilled": "disk_bytes_spilled",
    "internal.metrics.memoryBytesSpilled": "memory_bytes_spilled",
}


def main() -> None:
    args = parse_args()
    logger.info(
        f"m=main,msg='starting {JOB_NAME}',load_start_date={args.load_start_date},"
        f"load_end_date={args.load_end_date},databricks_bucket={args.databricks_bucket}"
    )

    df_stage_metrics = read_stage_metrics(
        databricks_bucket=args.databricks_bucket,
        load_start_date=args.load_start_date,
        load_end_date=args.load_end_date,
    )
    load_table(
        dataframe=df_stage_metrics,
        environment=args.env,
        datalake_bucket=args.bucket,
        schema=args.database_base_name,
        table_name=args.table_name,
    )
    logger.info(f"m=main,msg='finished {JOB_NAME}'")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod")
    parser.add_argument("bucket", type=str, help="datalake bucket name")
    parser.add_argument(
        "dag_name", type=str, help="Airflow DAG name without bietlejuice prefix"
    )
    parser.add_argument(
        "database_base_name", type=str, help="custom_schema (databricks_health)"
    )
    parser.add_argument(
        "table_name", type=str, help="target table name (spark_stage_metrics)"
    )
    parser.add_argument(
        "load_start_date", type=str, help="inclusive lower bound, ISO date"
    )
    parser.add_argument(
        "load_end_date", type=str, help="exclusive upper bound, ISO date"
    )
    parser.add_argument(
        "databricks_bucket", type=str, help="bucket where event logs are written"
    )
    return parser.parse_args()


def read_stage_metrics(
    databricks_bucket: str, load_start_date: str, load_end_date: str
) -> DataFrame:
    """Read Spark event logs from S3 and project per-stage-attempt metrics.

    Three event types contribute. SparkListenerStageCompleted is the source of
    truth for which stage attempts exist (and provides accumulator-driven
    metrics, dag_id, and the timestamp/date columns); SparkListenerStageExecutor
    Metrics and SparkListenerTaskEnd are LEFT-joined as enrichments on
    (id_spark_app, id_stage, id_stage_attempt). Stage attempts missing those
    events still produce a row with NULL in the corresponding columns.
    """
    source_path = f"s3a://{databricks_bucket}/spark-event-logs/"
    logger.info(f"m=read_stage_metrics,msg='reading event logs from {source_path}'")

    raw = (
        spark.read.option("recursiveFileLookup", "true")
        .text(source_path)
        .filter(
            F.col("_metadata.file_modification_time")
            >= F.lit(load_start_date).cast("date")
        )
        .filter(
            F.col("_metadata.file_modification_time")
            < F.lit(load_end_date).cast("date")
        )
        .withColumn("file_path", F.col("_metadata.file_path"))
        .withColumn(
            "dag_id", F.regexp_extract("file_path", r"spark-event-logs/([^/]+)/", 1)
        )
        .withColumn(
            "id_spark_app",
            F.regexp_extract("file_path", EVENTLOG_APP_ID_SEGMENT_PATTERN, 1),
        )
    )

    parsed = raw.withColumn("event", F.from_json(F.col("value"), EVENT_SCHEMA))

    metric_columns = [
        F.expr(
            f"CAST(filter(event.`Stage Info`.Accumulables, x -> x.Name = '{accum_name}')[0].Value AS BIGINT)"
        ).alias(out_name)
        for accum_name, out_name in STAGE_ACCUMULATORS.items()
    ]

    df_stage_completed = (
        parsed.filter(F.col("event.Event") == F.lit("SparkListenerStageCompleted"))
        .filter(F.col("event.`Stage Info`").isNotNull())
        .select(
            F.col("id_spark_app"),
            F.col("event.`Stage Info`.`Stage ID`").alias("id_stage"),
            F.col("event.`Stage Info`.`Stage Attempt ID`").alias("id_stage_attempt"),
            F.col("dag_id"),
            F.col("event.`Stage Info`.`Stage Name`").alias("stage_name"),
            F.col("event.`Stage Info`.`Failure Reason`").alias("stage_failure_reason"),
            F.col("event.`Stage Info`.`Number of Tasks`").alias("task_count"),
            *metric_columns,
            F.col("event.`Stage Info`.`Failure Reason`")
            .isNotNull()
            .alias("is_stage_failed"),
            F.to_date(
                F.from_unixtime(
                    F.col("event.`Stage Info`.`Completion Time`") / F.lit(1000)
                )
            ).alias("dt_stage_completed"),
            F.from_unixtime(F.col("event.`Stage Info`.`Submission Time`") / F.lit(1000))
            .cast("timestamp")
            .alias("ts_stage_submitted"),
            F.from_unixtime(F.col("event.`Stage Info`.`Completion Time`") / F.lit(1000))
            .cast("timestamp")
            .alias("ts_stage_completed"),
            F.current_timestamp().alias("ts_load"),
        )
    )

    # SparkListenerStageExecutorMetrics emits one event per (executor, stage
    # attempt) at stage completion. Aggregate to per-stage MAX of memory peaks
    # and SUM of GC times across executors. Requires
    # spark.eventLog.logStageExecutorMetrics=true on the cluster (PR #23078).
    df_executor_metrics = (
        parsed.filter(
            F.col("event.Event") == F.lit("SparkListenerStageExecutorMetrics")
        )
        .select(
            F.col("id_spark_app"),
            F.col("event.`Stage ID`").alias("id_stage"),
            F.col("event.`Stage Attempt ID`").alias("id_stage_attempt"),
            F.col("event.`Executor Metrics`.JVMHeapMemory").alias("jvm_heap_bytes"),
            F.col("event.`Executor Metrics`.OnHeapExecutionMemory").alias(
                "on_heap_execution_memory_bytes"
            ),
            F.col("event.`Executor Metrics`.OffHeapExecutionMemory").alias(
                "off_heap_execution_memory_bytes"
            ),
            F.col("event.`Executor Metrics`.MinorGCTime").alias("minor_gc_time_ms"),
            F.col("event.`Executor Metrics`.MajorGCTime").alias("major_gc_time_ms"),
        )
        .groupBy("id_spark_app", "id_stage", "id_stage_attempt")
        .agg(
            F.max("jvm_heap_bytes").alias("max_jvm_heap_bytes"),
            F.max("on_heap_execution_memory_bytes").alias(
                "max_on_heap_execution_memory_bytes"
            ),
            F.max("off_heap_execution_memory_bytes").alias(
                "max_off_heap_execution_memory_bytes"
            ),
            F.sum("minor_gc_time_ms").alias("total_minor_gc_time_ms"),
            F.sum("major_gc_time_ms").alias("total_major_gc_time_ms"),
        )
        .withColumn(
            "total_gc_time_ms",
            F.col("total_minor_gc_time_ms") + F.col("total_major_gc_time_ms"),
        )
    )

    # SparkListenerTaskEnd emits one event per task. Aggregate per stage attempt
    # into wall-clock percentiles (skew detection) and the worst single-task
    # GC pause. `task_skew_ratio` collapses to NULL when the median is 0/null
    # so we don't surface a misleading "infinite skew" on near-empty stages.
    df_task_metrics = (
        parsed.filter(F.col("event.Event") == F.lit("SparkListenerTaskEnd"))
        .select(
            F.col("id_spark_app"),
            F.col("event.`Stage ID`").alias("id_stage"),
            F.col("event.`Stage Attempt ID`").alias("id_stage_attempt"),
            F.col("event.`Task Metrics`.`Executor Run Time`").alias("task_run_time_ms"),
            F.col("event.`Task Metrics`.`JVM GC Time`").alias("task_gc_time_ms"),
        )
        .groupBy("id_spark_app", "id_stage", "id_stage_attempt")
        .agg(
            F.percentile_approx("task_run_time_ms", 0.5).alias("p50_task_run_time_ms"),
            F.percentile_approx("task_run_time_ms", 0.95).alias("p95_task_run_time_ms"),
            F.max("task_run_time_ms").alias("max_task_run_time_ms"),
            F.max("task_gc_time_ms").alias("max_task_gc_time_ms"),
        )
        .withColumn(
            "task_skew_ratio",
            F.when(
                F.col("p50_task_run_time_ms").isNull()
                | (F.col("p50_task_run_time_ms") == 0),
                F.lit(None).cast("double"),
            ).otherwise(
                F.greatest(
                    F.lit(0.0),
                    F.col("max_task_run_time_ms") / F.col("p50_task_run_time_ms"),
                )
            ),
        )
    )

    join_keys = ["id_spark_app", "id_stage", "id_stage_attempt"]
    return (
        df_stage_completed.join(df_executor_metrics, on=join_keys, how="left")
        .join(df_task_metrics, on=join_keys, how="left")
        .select(
            F.col("id_spark_app"),
            F.col("id_stage"),
            F.col("id_stage_attempt"),
            F.col("dag_id"),
            F.col("stage_name"),
            F.col("stage_failure_reason"),
            F.col("task_count"),
            *[F.col(out_name) for out_name in STAGE_ACCUMULATORS.values()],
            F.col("max_jvm_heap_bytes"),
            F.col("max_on_heap_execution_memory_bytes"),
            F.col("max_off_heap_execution_memory_bytes"),
            F.col("total_minor_gc_time_ms"),
            F.col("total_major_gc_time_ms"),
            F.col("total_gc_time_ms"),
            F.col("p50_task_run_time_ms"),
            F.col("p95_task_run_time_ms"),
            F.col("max_task_run_time_ms"),
            F.col("max_task_gc_time_ms"),
            F.col("task_skew_ratio"),
            F.col("is_stage_failed"),
            F.col("dt_stage_completed"),
            F.col("ts_stage_submitted"),
            F.col("ts_stage_completed"),
            F.col("ts_load"),
        )
    )


def load_table(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    schema: str,
    table_name: str,
) -> None:
    logger.info(f"m=load_table,msg='loading table {schema}.{table_name}'")

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]

    loader = DeltaLoader(spark)
    loader.load_table(
        table_name=f"{database_name}.{table_name}",
        path=f"{database_location}/{table_name}",
        source_df=dataframe,
        partition_by=["dt_stage_completed"],
    )


if __name__ == "__main__":
    main()
