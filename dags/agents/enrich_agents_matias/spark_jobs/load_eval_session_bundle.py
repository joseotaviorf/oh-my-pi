# load_eval_session_bundle — writes datalake_agents_matias.eval_session_bundle
# (merge id_session; partitions year/month/day). Cohort → transcript → Langfuse →
# user-turn anchors → conversation[] → evals → Delta merge.
#
# Sources
# -------
# - datalake_chatbot.sessions           session cohort (bot=dominic)
# - datalake_chatbot.messages           transcript messages
# - datalake_langfuse_clean.traces      LLM trace data
# - datalake_langfuse_clean.observations observation spans
# - datalake_chatbot.evals              per-session evaluations
#
# Conversation model
# ------------------
# Each row contains a `conversation` array (one item per message).
# Each item embeds the Langfuse `traces` that occurred between that message
# and the next user message (user-turn anchor logic).

from __future__ import annotations

import re
from argparse import ArgumentParser, Namespace
from datetime import date, datetime, timedelta
from typing import Optional

from pyspark.sql import DataFrame, SparkSession, Window
from pyspark.sql import functions as F
from pyspark.sql.functions import broadcast, col, explode, lit, size
from pyspark.sql.types import (
    ArrayType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import MetastoreServiceFactory

# Setup & Constants
JOB_NAME = "load_eval_session_bundle"
logger = QuintoAndarLogger(JOB_NAME)

# Observation names kept in the conversation bundle. Fixed (version-less) entries.
OBS_WHITELIST_NAMES: tuple[str, ...] = (
    "Moderator",
    "interrupt",
    "AnswerProcessor",
    "HostGraph",
    "Host - HostPlanner",
    "transfer_to_agent",
    "BrokerHumanEscalationAgent",
)

# Version-agnostic observation names: {version} matches any integer (V1, V2, ...),
# so new agent versions flow through without editing this list.
OBS_WHITELIST_VERSIONED_TEMPLATES: tuple[str, ...] = (
    "search_broker_documents_v{version}",
    "BrokerInformationalAssistantAgentV{version}",
    "BrokerInformationalAssistantAgentV{version}Input",
    "BrokerInformationalAssistantAgentV{version} - ReactPlanner",
    "BrokerKnowledgeBaseTaskAgentV{version}",
    "BrokerKnowledgeBaseTaskAgentV{version}Input",
    "BrokerKnowledgeBaseTaskAgentV{version} - ReactPlanner",
    "BrokerHumanEscalationAgentV{version}",
)


def _versioned_template_to_regex(template: str) -> str:
    """Turn a `...V{version}...` template into a regex where {version} is any integer."""
    return r"\d+".join(re.escape(part) for part in template.split("{version}"))


OBS_WHITELIST_VERSIONED_REGEX = "^(?:{})$".format(
    "|".join(
        _versioned_template_to_regex(template)
        for template in OBS_WHITELIST_VERSIONED_TEMPLATES
    )
)


def _obs_name_in_whitelist(name_col):
    """Match an observation name against fixed + version-agnostic whitelist entries."""
    return name_col.isin(list(OBS_WHITELIST_NAMES)) | name_col.rlike(
        OBS_WHITELIST_VERSIONED_REGEX
    )


OBSERVATION_STRUCT = StructType(
    [
        StructField("started_at", TimestampType()),
        StructField("ended_at", TimestampType()),
        StructField("id", StringType()),
        StructField("name", StringType()),
        StructField("type", StringType()),
        StructField("output", StringType()),
    ]
)
OBSERVATIONS_ARRAY = ArrayType(OBSERVATION_STRUCT, containsNull=True)

TRACE_STRUCT = StructType(
    [
        StructField("started_at", TimestampType()),
        StructField("id", StringType()),
        StructField("name", StringType()),
        StructField("input", StringType()),
        StructField("output", StringType()),
        StructField("tags", StringType()),
        StructField("observations", OBSERVATIONS_ARRAY),
    ]
)
TRACES_ARRAY = ArrayType(TRACE_STRUCT, containsNull=True)

CONVERSATION_ITEM_STRUCT = StructType(
    [
        StructField("message_ts", TimestampType()),
        StructField("message_id", StringType()),
        StructField("message_sender", StringType()),
        StructField("message", StringType()),
        StructField("traces", TRACES_ARRAY),
    ]
)
CONVERSATION_ARRAY = ArrayType(CONVERSATION_ITEM_STRUCT, containsNull=True)

EMPTY_OBSERVATIONS = F.array().cast(OBSERVATIONS_ARRAY)
EMPTY_TRACES = F.array().cast(TRACES_ARRAY)
EMPTY_CONVERSATION = F.array().cast(CONVERSATION_ARRAY)

# Langfuse traces/observations can start slightly before session ts_created.
LANGFUSE_LOOKBACK_DAYS = 7
LANGFUSE_BUFFER_DAYS_AFTER = 1
# Messages may continue after session start beyond the session cohort window.
MESSAGES_BUFFER_DAYS_AFTER = 7

# Argument Parsing (single source of truth: add new args here only)
ARG_SPEC = [
    ("env", str, "forno", "Environment: forno/prod"),
    ("datalake_bucket", str, "5a-datalake-prod", "Datalake bucket"),
    (
        "database_base_name",
        str,
        "agents_matias",
        "Base name for database (schema)",
    ),
    ("dag_name", str, "enrich_agents_matias", "DAG name (for alignment with Airflow)"),
    ("table_name", str, "eval_session_bundle", "Target enrich table name"),
    (
        "load_start_date",
        str,
        lambda: (date.today() - timedelta(days=90)).isoformat(),
        "Inclusive session window start, format %Y-%m-%d",
    ),
    (
        "load_end_date",
        str,
        lambda: date.today().isoformat(),
        "Inclusive session window end, format %Y-%m-%d",
    ),
    ("run_mode", str, "dev", "Run mode: prod/dev"),
]


def parse_args() -> Namespace:
    """Parse CLI args. Uses parse_known_args() so Databricks kernel flags are ignored."""
    parser = ArgumentParser(description=JOB_NAME)
    default_values = [d() if callable(d) else d for _, _, d, _ in ARG_SPEC]
    for (name, type_, _default, help_text), default_val in zip(
        ARG_SPEC, default_values
    ):
        parser.add_argument(
            name, nargs="?", type=type_, default=default_val, help=help_text
        )
    add_validation_target_args(parser)
    namespace, _ = parser.parse_known_args()
    return namespace


# Helper functions
def _session_window(
    load_start_date: str, load_end_date: str
) -> tuple[datetime, datetime]:
    start = datetime.fromisoformat(load_start_date)
    end_exclusive = datetime.fromisoformat(load_end_date) + timedelta(days=1)
    return start, end_exclusive


def _load_windowed_table(
    spark: SparkSession,
    table_name: str,
    ts_column: str,
    window_start: datetime,
    window_end_exclusive: datetime,
    *,
    partition_prune: bool = False,
) -> DataFrame:
    ts_pred = (col(ts_column) >= lit(window_start)) & (
        col(ts_column) < lit(window_end_exclusive)
    )
    if partition_prune:
        partition_day = F.make_date(col("year"), col("month"), col("day"))
        last_day = (window_end_exclusive - timedelta(days=1)).date()
        pred = (
            (partition_day >= lit(window_start.date()))
            & (partition_day <= lit(last_day))
            & ts_pred
        )
    else:
        pred = ts_pred
    return spark.table(table_name).filter(pred)


def _transcript_id_session():
    return F.coalesce(
        col("id_sauron_session").cast("string"),
        col("id_sss_session"),
    )


def _cohort_langfuse_trace_keys(sessions: DataFrame) -> DataFrame:
    """Keys Langfuse uses in traces.id_session → cohort id_langfuse_session."""
    by_external = sessions.select(
        col("id_langfuse_session").alias("lf_key"),
        col("id_langfuse_session"),
    )
    by_copilot = sessions.select(
        col("id_copilot_session").alias("lf_key"),
        col("id_langfuse_session"),
    )
    return (
        by_external.unionByName(by_copilot)
        .filter(col("lf_key").isNotNull())
        .dropDuplicates(["lf_key", "id_langfuse_session"])
    )


def _log_bundle_stage_counts(
    *,
    n_sessions: int,
    n_sessions_null_transcript_key: int,
    n_messages: int,
    n_conversation_sessions: int,
    n_bundle: int,
    n_traces_raw: int,
    n_sessions_without_messages: int,
) -> None:
    logger.info(
        "m=build_eval_session_bundle, stage_counts, "
        f"n_sessions={n_sessions:,}, "
        f"n_sessions_null_transcript_key={n_sessions_null_transcript_key:,}, "
        f"n_messages={n_messages:,}, "
        f"n_conversation_sessions={n_conversation_sessions:,}, "
        f"n_bundle={n_bundle:,}, "
        f"n_traces_raw={n_traces_raw:,}, "
        f"n_sessions_without_messages={n_sessions_without_messages:,}"
    )
    if n_sessions > 0 and n_bundle == 0:
        logger.warning(
            "m=build_eval_session_bundle, msg=bundle row count is 0 while cohort is "
            "non-empty; verify bundle uses left join on conversation and a single "
            "contiguous run (not a stale dev_eval_session_bundle temp view)"
        )
    if n_sessions > 0 and n_messages == 0:
        logger.warning(
            "m=build_eval_session_bundle, msg=messages inner join returned 0 rows; "
            "check transcript key alignment between datalake_chatbot.sessions and "
            "datalake_chatbot.messages"
        )


def _collect_chronological_list(sort_ts_col, payload_col):
    return F.sort_array(
        F.collect_list(
            F.struct(sort_ts_col.alias("_sort_ts"), payload_col.alias("_payload"))
        ),
        asc=True,
    )


def _extract_sorted_payloads(sorted_array_col):
    return F.transform(sorted_array_col, lambda item: item["_payload"])


# Build eval session bundle
def build_eval_session_bundle(
    spark: SparkSession,
    load_start_date: str,
    load_end_date: str,
    *,
    log_stages: bool = False,
) -> DataFrame:
    """Assemble one row per session in [load_start_date, load_end_date] (inclusive)."""
    session_start_dt, session_end_exclusive_dt = _session_window(
        load_start_date, load_end_date
    )
    langfuse_start_dt = session_start_dt - timedelta(days=LANGFUSE_LOOKBACK_DAYS)
    langfuse_end_exclusive_dt = session_end_exclusive_dt + timedelta(
        days=LANGFUSE_BUFFER_DAYS_AFTER
    )
    messages_end_exclusive_dt = session_end_exclusive_dt + timedelta(
        days=MESSAGES_BUFFER_DAYS_AFTER
    )

    sessions_all = (
        _load_windowed_table(
            spark,
            "datalake_chatbot.sessions",
            "ts_created",
            session_start_dt,
            session_end_exclusive_dt,
        )
        .filter(col("bot") == "dominic")
        .filter(col("id_langfuse_session").isNotNull())
        .select(
            col("id_session").cast("string").alias("id_copilot_session"),
            _transcript_id_session().alias("id_session"),
            col("id_langfuse_session"),
            col("bot"),
            col("ts_created").alias("session_start_ts"),
            col("is_escalated"),
            col("channel"),
            col("active_feature_flags"),
            F.to_date(col("ts_created")).alias("session_date"),
            F.year(col("ts_created")).alias("year"),
            F.month(col("ts_created")).alias("month"),
            F.dayofmonth(col("ts_created")).alias("day"),
        )
    )
    sessions = sessions_all.filter(col("id_session").isNotNull()).cache()

    cohort = broadcast(
        sessions.select("id_session", "id_langfuse_session").dropDuplicates()
    )
    langfuse_trace_keys = broadcast(_cohort_langfuse_trace_keys(sessions))

    message_seq_window = Window.partitionBy("id_session").orderBy(
        col("message_ts").asc(),
        col("message_sender").asc(),
    )

    messages = (
        _load_windowed_table(
            spark,
            "datalake_chatbot.messages",
            "ts_created",
            session_start_dt,
            messages_end_exclusive_dt,
        )
        .join(
            cohort.select("id_session"),
            _transcript_id_session() == col("id_session"),
            "inner",
        )
        .select(
            col("id_session"),
            col("ts_created").alias("message_ts"),
            F.when(col("role") == "HUMAN", "user")
            .when(col("role") == "AI", "bot")
            .when(col("role") == "ANALYST", "analyst")
            .when(col("role") == "SYSTEM", "system")
            .otherwise(F.lower(col("role")))
            .alias("message_sender"),
            col("message"),
        )
        .withColumn("message_seq", F.row_number().over(message_seq_window))
        .withColumn(
            "message_id",
            F.concat(col("id_session"), lit("-m"), col("message_seq").cast("string")),
        )
    )

    user_window = Window.partitionBy("id_session").orderBy(col("message_ts").asc())
    user_anchors = (
        messages.filter(col("message_sender") == "user")
        .select(
            col("id_session"),
            col("message_id").alias("anchor_message_id"),
            col("message_ts").alias("anchor_message_ts"),
            F.lead("message_ts").over(user_window).alias("next_user_message_ts"),
        )
        .withColumnRenamed("id_session", "id_session_anchored")
    )

    traces_raw = (
        _load_windowed_table(
            spark,
            "datalake_langfuse_clean.traces",
            "ts_created",
            langfuse_start_dt,
            langfuse_end_exclusive_dt,
        )
        .filter(F.array_contains(col("tags"), "ian"))
        .withColumnRenamed("id_session", "lf_key")
        .join(langfuse_trace_keys, "lf_key", "inner")
        .join(cohort, "id_langfuse_session", "inner")
        .select(
            col("id_session"),
            col("id_trace"),
            col("name"),
            col("ts_created"),
            col("input"),
            col("output"),
            col("tags").cast("string").alias("tags"),
        )
    )

    trace_ids = broadcast(traces_raw.select("id_trace").dropDuplicates())

    observations_ids = (
        _load_windowed_table(
            spark,
            "datalake_langfuse_clean.observations",
            "ts_started",
            langfuse_start_dt,
            langfuse_end_exclusive_dt,
        )
        .join(trace_ids, "id_trace", "inner")
        .select(
            F.col("id_observation"),
            F.col("name"),
        )
        .filter(_obs_name_in_whitelist(col("name")))
        .drop(F.col("name"))
    ).localCheckpoint()

    observations = (
        _load_windowed_table(
            spark,
            "datalake_langfuse_clean.observations",
            "ts_started",
            langfuse_start_dt,
            langfuse_end_exclusive_dt,
        )
        .filter(_obs_name_in_whitelist(col("name")))
        .join(broadcast(observations_ids), "id_observation", "inner")
        .select(
            col("id_trace"),
            col("id_observation"),
            col("name"),
            col("type"),
            col("output"),
            col("ts_started").alias("ts_start"),
            col("ts_ended").alias("ts_end"),
        )
    )

    obs_by_trace = observations.groupBy("id_trace").agg(
        _extract_sorted_payloads(
            _collect_chronological_list(
                col("ts_start"),
                F.struct(
                    col("ts_start").alias("started_at"),
                    col("ts_end").alias("ended_at"),
                    col("id_observation").alias("id"),
                    col("name"),
                    col("type"),
                    col("output"),
                ),
            )
        )
        .cast(OBSERVATIONS_ARRAY)
        .alias("observations")
    )

    traces_with_anchors = (
        traces_raw.join(obs_by_trace, "id_trace", "left")
        .withColumn("observations", F.coalesce(col("observations"), EMPTY_OBSERVATIONS))
        .withColumnRenamed("ts_created", "trace_started_at")
        .join(
            user_anchors,
            (col("id_session") == user_anchors["id_session_anchored"])
            & (col("trace_started_at") >= user_anchors["anchor_message_ts"])
            & (
                user_anchors["next_user_message_ts"].isNull()
                | (col("trace_started_at") < user_anchors["next_user_message_ts"])
            ),
            "left",
        )
        .drop(F.col("id_session_anchored"))
    )

    trace_payload = F.struct(
        col("trace_started_at").alias("started_at"),
        col("id_trace").alias("id"),
        col("name"),
        col("input"),
        col("output"),
        col("tags"),
        col("observations"),
    )

    traces_by_message = (
        traces_with_anchors.filter(col("anchor_message_id").isNotNull())
        .groupBy("id_session", "anchor_message_id")
        .agg(
            _extract_sorted_payloads(
                _collect_chronological_list(col("trace_started_at"), trace_payload)
            )
            .cast(TRACES_ARRAY)
            .alias("traces")
        )
    )

    messages_with_traces = (
        messages.alias("m")
        .join(
            traces_by_message.alias("t"),
            (col("m.id_session") == col("t.id_session"))
            & (col("m.message_id") == col("t.anchor_message_id")),
            "left",
        )
        .select(
            col("m.id_session").alias("id_session"),
            col("m.message_ts").alias("message_ts"),
            col("m.message_id").alias("message_id"),
            col("m.message_sender").alias("message_sender"),
            col("m.message").alias("message"),
            F.coalesce(col("t.traces"), EMPTY_TRACES).alias("traces"),
        )
    )

    conversation_item = F.struct(
        col("message_ts"),
        col("message_id"),
        col("message_sender"),
        col("message"),
        col("traces"),
    )

    conversation_by_session = messages_with_traces.groupBy("id_session").agg(
        _extract_sorted_payloads(
            _collect_chronological_list(col("message_ts"), conversation_item)
        )
        .cast(CONVERSATION_ARRAY)
        .alias("conversation")
    )

    bundle = (
        sessions.join(conversation_by_session, "id_session", "left")
        .withColumn("conversation", F.coalesce(col("conversation"), EMPTY_CONVERSATION))
        .withColumn("ts_load", F.current_timestamp())
    )

    if log_stages:
        n_sessions_null_transcript_key = sessions_all.filter(
            col("id_session").isNull()
        ).count()
        n_sessions = sessions.count()
        n_traces_raw = traces_raw.count()
        n_messages = messages.count()
        n_conversation_sessions = conversation_by_session.count()
        n_bundle = bundle.count()
        message_keys = messages.select("id_session").dropDuplicates()
        n_sessions_without_messages = (
            sessions.select("id_session")
            .join(message_keys, "id_session", "left_anti")
            .count()
        )
        _log_bundle_stage_counts(
            n_sessions=n_sessions,
            n_sessions_null_transcript_key=n_sessions_null_transcript_key,
            n_messages=n_messages,
            n_conversation_sessions=n_conversation_sessions,
            n_bundle=n_bundle,
            n_traces_raw=n_traces_raw,
            n_sessions_without_messages=n_sessions_without_messages,
        )

    evals = (
        spark.table("datalake_chatbot.evals")
        .join(cohort, "id_langfuse_session", "inner")
        .select(col("id_langfuse_session"), col("evals"))
    )
    return bundle.join(evals, "id_langfuse_session", "left")


# Persistence
def _save_to_enrich(
    spark_client: SparkClient, result_df: DataFrame, args: Namespace, row_count: int
) -> None:
    db_info = DatalakeMetastoreService.get_db_info(
        args.env, args.database_base_name, args.datalake_bucket
    )
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=args.table_name,
            prod_location=database_location,
            bucket=args.datalake_bucket,
            target_database=getattr(args, "target_database_name", None),
            target_table=getattr(args, "target_table_name", None),
        )
    )
    full_table_name = f"{write_database_name}.{write_table_name}"
    s3_path = f"{write_location}{write_table_name}"

    MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    ).create_database(write_database_name)
    # Pass the live job session: DeltaLoader() defaults to the import-time
    # BaseSparkContext.spark global, whose default catalog on EMR is not Glue —
    # so the Delta files land in S3 but the table never registers in the catalog.
    DeltaLoader(spark_client.conn).load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=result_df,
        partition_by=["year", "month", "day"],
        merge_schema=True,
        merge_on=["id_session"],
    )
    MetastoreServiceFactory.create_loader_metastore_service(spark_client).refresh_table(
        write_database_name, write_table_name
    )
    priv = TablePrivileges.from_environment_default(full_table_name)
    if priv and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        priv.apply()
    logger.info(f"m=save_df, table={full_table_name}, rows={row_count:,}")


def save_df(spark_client: SparkClient, result_df: DataFrame, args: Namespace) -> None:
    run_mode = args.run_mode
    if run_mode == "dev":
        view_name = f"dev_{args.table_name}"
        result_df.cache()
        dev_row_count = result_df.count()
        if dev_row_count:
            conv = result_df.select(explode(col("conversation")).alias("item"))
            with_traces = conv.filter(size(col("item.traces")) > 0).count()
            logger.info(
                f"Dev stats: conversation_rows_with_traces={with_traces:,} "
                f"(messages that carry Langfuse traces)"
            )
        result_df.createOrReplaceTempView(view_name)
        logger.info(
            f"Dev mode: registered temp view '{view_name}' ({dev_row_count:,} rows). "
            f"Query with: SELECT * FROM {view_name}"
        )
        return
    if run_mode == "prod":
        row_count = result_df.count()
        if row_count == 0:
            logger.warning("m=save_df, msg=no rows in window; skip Delta write")
            return
        _save_to_enrich(spark_client, result_df, args, row_count)
        return
    raise ValueError(f"Invalid run mode: {run_mode}")


# main
def main(args: Optional[Namespace] = None) -> None:
    """Orchestrate ETL: build → write."""
    if args is None:
        args = parse_args()
    logger.info(
        f"m=main, run_mode={args.run_mode}, env={args.env}, "
        f"database_base_name={args.database_base_name}, table_name={args.table_name}, "
        f"data_interval=[{args.load_start_date}, {args.load_end_date}], "
        f"msg=Starting Spark job"
    )

    log_stages = args.run_mode == "dev"
    spark_client = SparkClient(app_name=JOB_NAME)
    output_df = build_eval_session_bundle(
        spark_client.conn,
        args.load_start_date,
        args.load_end_date,
        log_stages=log_stages,
    )
    save_df(spark_client, output_df, args)
    logger.info("m=main, msg=Job finished successfully")


if __name__ == "__main__":
    main()
