# load_matias_session_summary — writes datalake_agents_matias.matias_session_summary
# (merge id_session; partitions year/month/day).
#
# One flattened row per Matias (ian) chatbot session, derived from
# datalake_agents_matias.eval_session_bundle (enrich → enrich). Pre-computes every
# deterministic session-level signal used for analytics/reporting so downstream code
# never has to parse the nested conversation/traces/observations/evals structures.
#
# Source
# ------
# - datalake_agents_matias.eval_session_bundle   (per-session bundle w/ nested conversation & evals)
#
# Groups of signals (see metadata for the full column list)
# ---------------------------------------------------------
# - identity/time: user_id, session_start_ts, session_end_ts, hour_brt, weekday, is_weekend, is_partial_day
# - volume: message counts by sender (user/bot/analyst), first-user-message size, word/char totals
# - effort/cost: LLM calls, tokens (prompt/completion/total), tokens_per_user_msg
# - timing: bot_duration_sec (bot conversation only), full duration_sec, first_response_latency_sec
# - capability: tool/agent observation counts, doc-search calls, agent-usage flags
# - outcome: human_handoff (analyst turn = canonical), escalation_node_engaged, first_msg_escalation,
#   is_escalated_raw, the seven Ian evaluators + convenience flags (is_resolved/is_frustrated/has_evals)
# - quality/engagement: is_low_value (few messages AND short input — low-signal session)

from __future__ import annotations

from argparse import ArgumentParser, Namespace
from datetime import date, timedelta
from typing import Optional

from pyspark.sql import Column, DataFrame, SparkSession
from pyspark.sql.functions import col, current_timestamp, expr, lit, struct
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
from bietlejuice.services.metastore_services import SparkMetastoreService

# Setup & Constants
JOB_NAME = "load_matias_session_summary"
SOURCE_TABLE_NAME = "eval_session_bundle"
logger = QuintoAndarLogger(JOB_NAME)

# `conversation` is already chronologically ordered by the bundle job, so the first user
# turn is element_at(filter(...user), 1) — no re-sort needed. `all_obs` = every observation.
# `\\s+` reaches Spark as the regex \s+ (word split).
_FIRST_USER = "element_at(filter(conversation, x -> x.message_sender='user'), 1)"


def _sql(expression: str, alias: str) -> Column:
    """Wrap a Spark SQL expression string as an aliased Column.

    The heavy hitters below are higher-order functions (transform/filter/aggregate
    with lambdas) that have no readable Column-API equivalent, so we keep the SQL and
    just promote it to a real Column — expression and output name split cleanly instead
    of an `... AS name` tail buried at the end of a long string.
    """
    return expr(expression).alias(alias)


# Passthrough columns: raw bundle fields carried straight into the summary (plus the one
# rename). These need no computation, so they stay plain `col(...)` and out of the SQL block.
PASSTHROUGH_COLUMNS = [
    col("id_session"),
    col("id_langfuse_session"),
    col("id_copilot_session"),
    col("bot"),
    col("channel"),
    col("session_start_ts"),
    col("session_date"),
    col("year"),
    col("month"),
    col("day"),
    col("is_escalated").alias("is_escalated_raw"),
]

# Computed columns: session-level signals derived over eval_session_bundle (+ all_traces/
# all_obs helpers). All are Spark SQL expressions — mostly higher-order functions
# (transform/filter/aggregate) with no readable Column-API equivalent — so they live here
# together, wrapped by `_sql`.
COMPUTED_COLUMNS = [
    _sql("array_max(transform(conversation, x -> x.message_ts))", "session_end_ts"),
    _sql("date_format(session_date,'EEE')", "weekday"),
    _sql("dayofweek(session_date) IN (1,7)", "is_weekend"),
    _sql("dayofweek(session_date)=1", "is_partial_day"),
    _sql("hour(from_utc_timestamp(session_start_ts,'America/Sao_Paulo'))", "hour_brt"),
    _sql(
        "element_at(filter(transform(all_traces, t -> get_json_object(t.input,'$.user_id')), x -> x IS NOT NULL), 1)",
        "user_id",
    ),
    _sql("size(conversation)", "n_msgs"),
    _sql("size(filter(conversation, x -> x.message_sender='user'))", "n_user_msgs"),
    _sql("size(filter(conversation, x -> x.message_sender='bot'))", "n_bot_msgs"),
    _sql(
        "size(filter(conversation, x -> x.message_sender='analyst'))", "n_analyst_msgs"
    ),
    _sql("size(all_traces)", "n_llm_calls"),
    _sql(
        f"CASE WHEN trim(coalesce({_FIRST_USER}.message,''))='' THEN 0 ELSE size(split(trim({_FIRST_USER}.message),'\\\\s+')) END",
        "first_user_msg_words",
    ),
    _sql(f"length(coalesce({_FIRST_USER}.message,''))", "first_user_msg_chars"),
    _sql(
        "aggregate(filter(conversation, x -> x.message_sender='user'), 0, (a,x) -> a + CASE WHEN trim(coalesce(x.message,''))='' THEN 0 ELSE size(split(trim(x.message),'\\\\s+')) END)",
        "user_words_total",
    ),
    _sql(
        "aggregate(filter(conversation, x -> x.message_sender='user'), 0, (a,x) -> a + length(coalesce(x.message,'')))",
        "user_chars_total",
    ),
    _sql(
        "aggregate(filter(conversation, x -> x.message_sender='bot'),  0, (a,x) -> a + CASE WHEN trim(coalesce(x.message,''))='' THEN 0 ELSE size(split(trim(x.message),'\\\\s+')) END)",
        "bot_words_total",
    ),
    _sql(
        "aggregate(filter(conversation, x -> x.message_sender='analyst'), 0, (a,x) -> a + CASE WHEN trim(coalesce(x.message,''))='' THEN 0 ELSE size(split(trim(x.message),'\\\\s+')) END)",
        "analyst_words_total",
    ),
    _sql(
        "(unix_timestamp(array_max(transform(conversation, x -> x.message_ts))) - unix_timestamp(array_min(transform(conversation, x -> x.message_ts))))",
        "duration_sec",
    ),
    _sql(
        "(unix_timestamp(array_max(transform(filter(conversation, x -> x.message_sender IN ('user','bot')), x -> x.message_ts))) - unix_timestamp(array_min(transform(conversation, x -> x.message_ts))))",
        "bot_duration_sec",
    ),
    _sql(
        "(unix_timestamp(array_min(transform(filter(conversation, x -> x.message_sender='bot'),  x -> x.message_ts))) - unix_timestamp(array_min(transform(filter(conversation, x -> x.message_sender='user'), x -> x.message_ts))))",
        "first_response_latency_sec",
    ),
    _sql(
        "size(filter(all_obs, o -> o.name='search_broker_documents_v2' AND o.type='TOOL'))",
        "n_docsearch_calls",
    ),
    _sql("size(filter(all_obs, o -> o.type='TOOL'))", "n_tool_calls"),
    _sql("size(filter(all_obs, o -> o.type='AGENT'))", "n_agent_obs"),
    _sql("size(all_obs)", "n_observations"),
    _sql(
        "size(filter(all_obs, o -> o.name LIKE 'BrokerInformationalAssistantAgent%'))",
        "n_informational_obs",
    ),
    _sql(
        "size(filter(all_obs, o -> o.name LIKE 'BrokerKnowledgeBaseTaskAgent%'))",
        "n_knowledgebase_obs",
    ),
    _sql(
        "size(filter(all_obs, o -> o.name LIKE 'BrokerHumanEscalationAgent%'))",
        "n_escalation_obs",
    ),
    _sql(
        "exists(all_obs, o -> o.name LIKE 'BrokerInformationalAssistantAgent%')",
        "used_informational",
    ),
    _sql(
        "exists(all_obs, o -> o.name LIKE 'BrokerKnowledgeBaseTaskAgent%')",
        "used_knowledgebase",
    ),
    _sql(
        "exists(all_obs, o -> o.name LIKE 'BrokerHumanEscalationAgent%')",
        "escalation_node_engaged",
    ),
    _sql("exists(conversation, x -> x.message_sender='analyst')", "human_handoff"),
    _sql(
        f"exists(flatten(transform({_FIRST_USER}.traces, t -> t.observations)), o -> o.name LIKE 'BrokerHumanEscalationAgent%')",
        "first_msg_escalation",
    ),
    # agent_flow: collapsed ordered agent path (consecutive repeats merged) e.g. "Info > KB > Info > Esc".
    # NULL when the session ran no agents. Backs the agent-flow-sequence chart via GROUP BY.
    _sql(
        "nullif(array_join(aggregate("
        "  transform(array_sort(filter(all_obs, o -> o.type='AGENT' AND o.name LIKE 'Broker%Agent%'),"
        "    (a,b) -> CASE WHEN a.started_at<b.started_at THEN -1 WHEN a.started_at>b.started_at THEN 1 ELSE 0 END),"
        "    o -> CASE WHEN o.name LIKE 'BrokerInformationalAssistantAgent%' THEN 'Info'"
        "             WHEN o.name LIKE 'BrokerKnowledgeBaseTaskAgent%' THEN 'KB'"
        "             WHEN o.name LIKE 'BrokerHumanEscalationAgent%' THEN 'Esc' END),"
        "  CAST(array() AS array<string>),"
        "  (acc,x) -> CASE WHEN size(acc)=0 OR element_at(acc,-1) <> x THEN concat(acc, array(x)) ELSE acc END"
        "), ' > '), '')",
        "agent_flow",
    ),
    # response_latencies: seconds from each user turn to its first bot reply (reset after each reply
    # so bot bubbles don't double-count). Backs the per-turn latency distribution via explode().
    _sql(
        "aggregate("
        "  array_sort(filter(conversation, x -> x.message_sender IN ('user','bot')),"
        "    (a,b) -> CASE WHEN a.message_ts<b.message_ts THEN -1 WHEN a.message_ts>b.message_ts THEN 1 ELSE 0 END),"
        "  named_struct('last_user', CAST(NULL AS timestamp), 'lats', CAST(array() AS array<bigint>)),"
        "  (acc,x) -> CASE"
        "    WHEN x.message_sender='user' THEN named_struct('last_user', x.message_ts, 'lats', acc.lats)"
        "    WHEN x.message_sender='bot' AND acc.last_user IS NOT NULL"
        "      THEN named_struct('last_user', CAST(NULL AS timestamp), 'lats',"
        "           concat(acc.lats, array(unix_timestamp(x.message_ts)-unix_timestamp(acc.last_user))))"
        "    ELSE acc END,"
        "  acc -> acc.lats)",
        "response_latencies",
    ),
    # token_usage is at the LEAF LLM generation only (root path). A recursive/$.values[*]
    # search would re-read state-wrapper echoes and inflate totals ~2.4x — do not change.
    _sql(
        "aggregate(all_obs, CAST(0 AS double), (acc,o) -> acc + coalesce("
        "cast(get_json_object(o.output,'$.response_metadata.token_usage.total_tokens') AS double),"
        "cast(get_json_object(o.output,'$.response_metadata.token_usage.prompt_tokens') AS double)"
        "+cast(get_json_object(o.output,'$.response_metadata.token_usage.completion_tokens') AS double),"
        "CAST(0 AS double)))",
        "total_tokens",
    ),
    _sql(
        "aggregate(all_obs, CAST(0 AS double), (acc,o) -> acc + coalesce(cast(get_json_object(o.output,'$.response_metadata.token_usage.prompt_tokens') AS double), CAST(0 AS double)))",
        "prompt_tokens",
    ),
    _sql(
        "aggregate(all_obs, CAST(0 AS double), (acc,o) -> acc + coalesce(cast(get_json_object(o.output,'$.response_metadata.token_usage.completion_tokens') AS double), CAST(0 AS double)))",
        "completion_tokens",
    ),
    _sql("evals['IanResolutionEvaluator'].value", "eval_resolution"),
    _sql("evals['IanNaturalnessEvaluator'].value", "eval_naturalness"),
    _sql("evals['IanFrustrationEvaluator'].value", "eval_frustration"),
    _sql("evals['IanAIResistanceEvaluator'].value", "eval_ai_resistance"),
    _sql("evals['IanLaborLitigationRiskEvaluator'].value", "eval_legal_risk"),
    _sql("evals['ResolutionQualityEvaluator'].value", "eval_resolution_quality"),
    _sql("evals['EscalationReasonEvaluator'].value", "eval_escalation_reason"),
]

# Convenience columns derived from the base columns (referenced by name).
DERIVED_COLUMNS = [
    _sql("round(user_words_total / nullif(n_user_msgs,0), 2)", "avg_user_words"),
    _sql("round(bot_words_total / nullif(n_bot_msgs,0), 2)", "avg_bot_words"),
    _sql("round(total_tokens / nullif(n_user_msgs,0), 1)", "tokens_per_user_msg"),
    _sql(
        "round(aggregate(response_latencies, CAST(0 AS bigint), (a,x) -> a + x) / nullif(size(response_latencies),0), 1)",
        "avg_response_latency_sec",
    ),
    _sql("array_max(response_latencies)", "max_response_latency_sec"),
    _sql("eval_resolution = 1", "is_resolved"),
    _sql("eval_frustration >= 1", "is_frustrated"),
    _sql("eval_resolution IS NOT NULL", "has_evals"),
    # low engagement (few user turns) AND low input quality (short messages) => low-signal session
    _sql(
        "n_user_msgs <= 2 AND (user_words_total / nullif(n_user_msgs,0)) < 3",
        "is_low_value",
    ),
]

# Final projection: identity/time/partition keys stay flat (filtering, partitioning, DQ);
# metric families collapse into structs so the table stays narrow without losing anything.
# Access downstream as e.g. cost.total_tokens, evals.resolution, timing.response_latencies.
FINAL_COLUMNS = [
    col("id_session"),
    col("id_langfuse_session"),
    col("id_copilot_session"),
    col("user_id"),
    col("bot"),
    col("channel"),
    col("session_start_ts"),
    col("session_end_ts"),
    col("session_date"),
    col("weekday"),
    col("is_weekend"),
    col("is_partial_day"),
    col("hour_brt"),
    struct(
        "n_msgs",
        "n_user_msgs",
        "n_bot_msgs",
        "n_analyst_msgs",
        "first_user_msg_words",
        "first_user_msg_chars",
        "user_words_total",
        "user_chars_total",
        "bot_words_total",
        "analyst_words_total",
        "avg_user_words",
        "avg_bot_words",
    ).alias("volume"),
    struct(
        "duration_sec",
        "bot_duration_sec",
        "first_response_latency_sec",
        "avg_response_latency_sec",
        "max_response_latency_sec",
        "response_latencies",
    ).alias("timing"),
    struct(
        "n_llm_calls",
        "total_tokens",
        "prompt_tokens",
        "completion_tokens",
        "tokens_per_user_msg",
    ).alias("cost"),
    struct(
        "n_docsearch_calls",
        "n_tool_calls",
        "n_agent_obs",
        "n_observations",
        "n_informational_obs",
        "n_knowledgebase_obs",
        "n_escalation_obs",
        "used_informational",
        "used_knowledgebase",
        "agent_flow",
    ).alias("capability"),
    struct(
        "human_handoff",
        "escalation_node_engaged",
        "first_msg_escalation",
        "is_escalated_raw",
        "is_low_value",
    ).alias("outcome"),
    struct(
        col("eval_resolution").alias("resolution"),
        col("eval_naturalness").alias("naturalness"),
        col("eval_frustration").alias("frustration"),
        col("eval_ai_resistance").alias("ai_resistance"),
        col("eval_legal_risk").alias("legal_risk"),
        col("eval_resolution_quality").alias("resolution_quality"),
        col("eval_escalation_reason").alias("escalation_reason"),
        col("is_resolved"),
        col("is_frustrated"),
        col("has_evals"),
    ).alias("evals"),
    current_timestamp().alias("ts_load"),
    col("year"),
    col("month"),
    col("day"),
]

# Argument Parsing (single source of truth: add new args here only)
ARG_SPEC = [
    ("env", str, "forno", "Environment: forno/prod"),
    ("datalake_bucket", str, "5a-datalake-prod", "Datalake bucket"),
    ("database_base_name", str, "agents_matias", "Base name for database (schema)"),
    ("dag_name", str, "enrich_agents_matias", "DAG name (for alignment with Airflow)"),
    ("table_name", str, "matias_session_summary", "Target enrich table name"),
    (
        "load_start_date",
        str,
        lambda: (date.today() - timedelta(days=90)).isoformat(),
        "Inclusive session_date window start, format %Y-%m-%d",
    ),
    (
        "load_end_date",
        str,
        lambda: date.today().isoformat(),
        "Inclusive session_date window end, format %Y-%m-%d",
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


# Build matias session summary
def build_matias_session_summary(
    spark: SparkSession, source_table: str, load_start_date: str, load_end_date: str
) -> DataFrame:
    """One flattened row per session in [load_start_date, load_end_date] (inclusive)."""
    start = date.fromisoformat(load_start_date)
    end = date.fromisoformat(load_end_date)
    windowed = spark.table(source_table).filter(
        (col("session_date") >= lit(start)) & (col("session_date") <= lit(end))
    )
    with_helpers = windowed.withColumn(
        "all_traces", expr("flatten(transform(conversation, m -> m.traces))")
    ).withColumn(
        "all_obs",
        expr(
            "flatten(transform(conversation, m -> flatten(transform(m.traces, t -> t.observations))))"
        ),
    )
    return (
        with_helpers.select(*PASSTHROUGH_COLUMNS, *COMPUTED_COLUMNS)
        .select("*", *DERIVED_COLUMNS)
        .select(*FINAL_COLUMNS)
    )


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

    SparkMetastoreService(spark_client).create_database(write_database_name)
    DeltaLoader().load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=result_df,
        partition_by=["year", "month", "day"],
        merge_schema=True,
        merge_on=["id_session"],
    )
    SparkMetastoreService(spark_client).refresh_table(
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
    """Orchestrate ETL: read bundle → flatten → write summary."""
    if args is None:
        args = parse_args()
    logger.info(
        f"m=main, run_mode={args.run_mode}, env={args.env}, "
        f"database_base_name={args.database_base_name}, table_name={args.table_name}, "
        f"data_interval=[{args.load_start_date}, {args.load_end_date}], "
        f"msg=Starting Spark job"
    )

    spark_client = SparkClient(app_name=JOB_NAME)
    source_db = DatalakeMetastoreService.get_db_info(
        args.env, args.database_base_name, args.datalake_bucket
    )["db_enrich_databricks"]
    source_table = f"{source_db}.{SOURCE_TABLE_NAME}"
    logger.info(f"m=main, source_table={source_table}")

    output_df = build_matias_session_summary(
        spark_client.conn, source_table, args.load_start_date, args.load_end_date
    )
    save_df(spark_client, output_df, args)
    logger.info("m=main, msg=Job finished successfully")


if __name__ == "__main__":
    main()
