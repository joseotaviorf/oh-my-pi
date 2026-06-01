# Databricks notebook source
# MAGIC %run "/Workspace/Data Engineering/Agents/Utils/local_config"

# COMMAND ----------

# DBTITLE 1,Imports
import json as _json
import re as _re
from argparse import ArgumentParser, Namespace
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Callable, Optional

from pyspark.sql import DataFrame, SparkSession, Window
from pyspark.sql import functions as F
from pyspark.sql.types import (
    ArrayType,
    DataType,
    DoubleType,
    IntegerType,
    MapType,
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
from bietlejuice.services.metastore_services import SparkMetastoreService

# COMMAND ----------

# DBTITLE 1,Setup & Constants
JOB_NAME = "planner_emlio_logs"
SOURCE_TABLE = "datalake_emlio_clean.emlio_logs"
SERVICE_ID = "planner-ml-service"

logger = QuintoAndarLogger(JOB_NAME)

# COMMAND ----------

# DBTITLE 1,Developer Notes
print(
    "\n"
    "┌─────────────────────────────────────────────────────────────────┐\n"
    "│  ⚠  Run unit tests before deploying any change to this job.     │\n"
    "│                                                                 │\n"
    "│  From the repo root (requires Java + Python 3.9):               │\n"
    "│                                                                 │\n"
    "│    export JAVA_HOME=<path-to-jdk-11>                            │\n"
    "│    PYTHONPATH=. /path/to/python3.9 -m pytest \\                 │\n"
    "│  packages/bietlejuice-runtime/test/dags/agents/enrich_planner_emlio_logs/ -v │\n"
    "│                                                                 │\n"
    "└─────────────────────────────────────────────────────────────────┘\n"
)

# COMMAND ----------

# DBTITLE 1,Argument Parsing
_SAFE_IDENTIFIER_RE = _re.compile(r"^[a-zA-Z0-9_.]+$")


def _sql_identifier(value: str) -> str:
    """Argparse type validator that rejects unsafe SQL identifiers.

    Returns the value unchanged so the sanitized string propagates as the
    argparse attribute value — enabling static-analysis tools to recognise
    that args.table_name / args.database_base_name are safe after parsing.
    """
    if not value or not _SAFE_IDENTIFIER_RE.match(value):
        raise ValueError(f"Invalid SQL identifier: {value!r}")
    return value


ARG_SPEC = [
    ("env", str, "forno", "Environment: forno/prod"),
    ("datalake_bucket", str, "5a-datalake-prod", "Datalake bucket"),
    (
        "database_base_name",
        _sql_identifier,
        "curated_agents_planner",
        "Base name for the target schema",
    ),
    (
        "dag_name",
        str,
        "enrich_planner_emlio_logs",
        "DAG name (for alignment with Airflow)",
    ),
    ("table_name", _sql_identifier, "planner_emlio_logs", "Target enrich table name"),
    (
        "load_start_date",
        str,
        lambda: (date.today() - timedelta(days=1)).isoformat(),
        "Inclusive start date, format %Y-%m-%d",
    ),
    (
        "load_end_date",
        str,
        lambda: date.today().isoformat(),
        "Inclusive end date, format %Y-%m-%d",
    ),
    ("run_mode", str, "dev", "Run mode: prod/dev"),
]


def _defaults():
    return [d() if callable(d) else d for _, _, d, _ in ARG_SPEC]


def parse_args() -> Namespace:
    """Parse CLI args with notebook-safe defaults (parse_known_args ignores kernel flags)."""
    parser = ArgumentParser(description=JOB_NAME)
    for (name, type_, _default, help_text), default_val in zip(ARG_SPEC, _defaults()):
        parser.add_argument(
            name, nargs="?", type=type_, default=default_val, help=help_text
        )
    add_validation_target_args(parser)
    namespace, _ = parser.parse_known_args()
    return namespace


# COMMAND ----------

# DBTITLE 1,JSON Extraction Helpers


# get_json_object only accepts a literal string as the path argument — it cannot
# accept a Column expression. We therefore extract each envelope JSON string once
# (via this UDF) so all subsequent field-level calls can use literal paths.
@F.udf(StringType())
def _envelope_json(json_str: Optional[str], key: Optional[str]) -> Optional[str]:
    """Return the JSON string of the value at `key` inside `json_str`."""
    if not json_str or not key:
        return None
    try:
        value = _json.loads(json_str).get(key)
        return _json.dumps(value) if value is not None else None
    except Exception:
        return None


def _json_input_field(field_path: str) -> F.Column:
    """Extract a named field from the pre-extracted input envelope JSON."""
    return F.get_json_object(F.col("_input_envelope_json"), f"$.{field_path}")


def _json_output_field(field_path: str) -> F.Column:
    """Extract a named field from the pre-extracted response envelope JSON."""
    return F.get_json_object(F.col("_response_envelope_json"), f"$.{field_path}")


def _json_observability_field(field_path: str) -> F.Column:
    """Extract a field from the pre-extracted observability envelope JSON."""
    return F.get_json_object(F.col("_observability_envelope_json"), f"$.{field_path}")


def _nested_response_observability_json_path(relative_path: str) -> F.Column:
    """Scalar field under ``$.{response_type}.observability_data.<relative_path>`` in ``outputs``.

    Matches planner notebooks (``get_json_object(outputs, $.<response>.observability_data...)``).
    Used together with sibling-key envelope extracts via :func:`F.coalesce`.

    PySpark's :func:`get_json_object` requires a **string** path, not a Column (see note above).
    Dynamic paths are expressed via SQL ``concat`` inside :func:`F.expr`.
    """
    if not relative_path or not _SAFE_IDENTIFIER_RE.match(relative_path):
        raise ValueError(f"Invalid observability JSON relative_path: {relative_path!r}")
    escaped = relative_path.replace("'", "''")
    return F.expr(
        f"get_json_object(outputs, concat('$.', response_type, '.observability_data.', '{escaped}'))"
    )


def _build_payload_envelope(df: DataFrame) -> DataFrame:
    """Detect envelope keys and materialise the envelope JSON strings.

    outputs has two distinct top-level keys (besides request_id):
      - response key      → e.g. shadow_mode_response          (payload data)
      - observability key → e.g. shadow_mode_observability_data (monitoring data)
    They are siblings, NOT nested. We identify them by their suffix.

    Three *_type columns carry the envelope key names; three *_envelope_json columns
    carry the pre-extracted JSON strings so downstream helpers can use literal paths
    with get_json_object (which does not accept Column expressions as the path).
    """
    payload_map_input = F.map_filter(
        F.from_json(F.col("inputs"), "map<string, string>"),
        lambda k, v: k != "request_id",
    )
    outputs_map = F.from_json(F.col("outputs"), "map<string, string>")
    payload_map_response = F.map_filter(
        outputs_map,
        lambda k, v: (k != "request_id") & ~k.endswith("_observability_data"),
    )
    payload_map_observability = F.map_filter(
        outputs_map,
        lambda k, v: k.endswith("_observability_data"),
    )
    return (
        df.withColumn("payload_type", F.element_at(F.map_keys(payload_map_input), 1))
        .withColumn("response_type", F.element_at(F.map_keys(payload_map_response), 1))
        .withColumn(
            "observability_type", F.element_at(F.map_keys(payload_map_observability), 1)
        )
        .withColumn(
            "_input_envelope_json",
            _envelope_json(F.col("inputs"), F.col("payload_type")),
        )
        .withColumn(
            "_response_envelope_json",
            _envelope_json(F.col("outputs"), F.col("response_type")),
        )
        .withColumn(
            "_observability_envelope_json",
            _envelope_json(F.col("outputs"), F.col("observability_type")),
        )
    )


# COMMAND ----------


# DBTITLE 1,Field Specs
@dataclass(frozen=True)
class FieldSpec:
    """Declares one output column extracted from the JSON payload.

    Attributes:
        name:         Output column name.
        source:       JSON envelope to read from: "input" | "response" | "observability".
        path:         Dot-separated JSON path relative to the envelope key.
        dtype:        If set, parse the extracted JSON string with from_json using this schema
                      (use for arrays and structs). If None, get_json_object is used (scalars).
        cast:         If set, cast the resulting column to this type (e.g. IntegerType()).
        post_process: Optional column-level transform applied after extraction/cast.
                      Useful for upper-casing, exploding, or remapping values.
    """

    name: str
    source: str
    path: str
    dtype: Optional[DataType] = None
    cast: Optional[DataType] = None
    post_process: Optional[Callable] = field(default=None, hash=False, compare=False)


_AGENT_INPUT_SCHEMA = ArrayType(StructType([StructField("id_agent", IntegerType())]))

# fmt: off
INPUT_SPECS: tuple = (
    FieldSpec("business_context",            "input", "business_context",  post_process=F.upper),
    FieldSpec("id_house",                    "input", "id_house"),
    FieldSpec("id_prospect",                 "input", "id_prospect"),
    FieldSpec("id_region",                   "input", "id_region"),
    FieldSpec("list_agent_service_available","input", "agents",            dtype=_AGENT_INPUT_SCHEMA,
              post_process=lambda col: F.transform(col, lambda x: x["id_agent"])),
    FieldSpec("force_group",                 "input", "force_group"),
    FieldSpec("override_groups",             "input", "override_groups"),
    FieldSpec("debug_mode",                  "input", "debug_mode"),
)

OUTPUT_SPECS: tuple = (
    FieldSpec("list_agent_ml_ranking", "response",      "agents",               dtype=ArrayType(IntegerType())),
    FieldSpec("group",                 "response",      "group"),
    FieldSpec(
        "strategy_type_used",
        "observability",
        "strategy_type_used",
        post_process=lambda c: F.coalesce(
            _nested_response_observability_json_path("strategy_type_used"),
            c,
        ),
    ),
    FieldSpec(
        "ranked_agents_count",
        "observability",
        "ranked_agents_count",
        cast=IntegerType(),
        post_process=lambda c: F.coalesce(
            _nested_response_observability_json_path("ranked_agents_count").cast(IntegerType()),
            c,
        ),
    ),
    # evaluation_cache_clean_json and first_agent_ml_ranking are derived from the above
    # and handled separately in _extract_observability_derived below.
)
# fmt: on

_EXTRACTORS = {
    "input": _json_input_field,
    "response": _json_output_field,
    "observability": _json_observability_field,
}


def _apply_specs(df: DataFrame, specs: tuple) -> DataFrame:
    """Apply a sequence of FieldSpecs to df, adding one column per spec."""
    for spec in specs:
        col_expr = _EXTRACTORS[spec.source](spec.path)
        if spec.dtype is not None:
            col_expr = F.from_json(col_expr, spec.dtype)
        if spec.cast is not None:
            col_expr = col_expr.cast(spec.cast)
        if spec.post_process is not None:
            col_expr = spec.post_process(col_expr)
        df = df.withColumn(spec.name, col_expr)
    return df


# COMMAND ----------

# DBTITLE 1,Observability Derived Features
_EVALUATION_CACHE_SCHEMA = MapType(
    StringType(),
    StructType(
        [
            StructField("scores", ArrayType(DoubleType())),
            StructField("strategy_class_name", StringType()),
            StructField("strategy_repr", StringType()),
        ]
    ),
)


def _clean_evaluation_cache(df: DataFrame) -> DataFrame:
    """Parse the evaluation_cache JSON, strip internal strategy classes, and flatten to a
    clean map of strategy_class__key -> scores. Drops intermediate parse columns."""
    parsed = F.from_json(F.col("evaluation_cache"), _EVALUATION_CACHE_SCHEMA)
    public_entries = F.filter(
        F.map_entries(parsed),
        lambda entry: ~entry["value"]["strategy_class_name"].startswith("_"),
    )
    clean_map = F.map_from_entries(
        F.transform(
            public_entries,
            lambda entry: F.struct(
                F.concat_ws(
                    "__", entry["value"]["strategy_class_name"], entry["key"]
                ).alias("key"),
                entry["value"]["scores"].alias("value"),
            ),
        )
    )
    return df.withColumn("evaluation_cache_clean_json", F.to_json(clean_map))


def _nested_ranking_evaluation_cache() -> F.Column:
    """Path used by planner notebooks: ranking metadata nested under the response payload.

    Some log rows only expose ``ranking_info.evaluation_cache`` at
    ``$.{response_type}.observability_data`` inside ``outputs`` (not as a separate
    ``*_observability_data`` sibling string). We coalesce this with the sibling-envelope
    extract so ``metrics_calculate_ranking`` matches both layouts.
    """
    return _nested_response_observability_json_path("ranking_info.evaluation_cache")


def _extract_observability_derived(df: DataFrame) -> DataFrame:
    """Compute columns derived from already-extracted output fields.
    - evaluation_cache_clean_json: parsed and cleaned scoring map (→ metrics_calculate_ranking)
    - first_agent_ml_ranking:      first element of the ML-ranked agent list
    """
    df = df.withColumn(
        "evaluation_cache",
        F.coalesce(
            _nested_ranking_evaluation_cache(),
            _json_observability_field("ranking_info.evaluation_cache"),
        ),
    )
    df = _clean_evaluation_cache(df)
    return df.drop("evaluation_cache").withColumn(
        "first_agent_ml_ranking", F.col("list_agent_ml_ranking")[0]
    )


# COMMAND ----------


# DBTITLE 1,Deduplication & Build
def _deduplicate(df: DataFrame) -> DataFrame:
    """Keep one row per (uuid, ts_log). When a log appears in multiple partitions,
    the row from the earliest partition (month/day ascending) is retained."""
    dedup_window = Window.partitionBy("uuid", "ts_log").orderBy(
        F.col("month").asc(), F.col("day").asc()
    )
    return (
        df.withColumn("_row_number", F.row_number().over(dedup_window))
        .filter(F.col("_row_number") == 1)
        .drop("_row_number")
    )


def _final_columns() -> list:
    """Build the ordered output column list from INPUT_SPECS + OUTPUT_SPECS.
    Source metadata and partition columns are added as fixed bookends."""
    spec_columns = [spec.name for spec in INPUT_SPECS + OUTPUT_SPECS]
    derived_columns = [
        F.col("evaluation_cache_clean_json").alias("metrics_calculate_ranking"),
        "first_agent_ml_ranking",
    ]
    return (
        ["uuid", "service_version", "ts_log", "response_type"]
        + spec_columns
        + derived_columns
        + ["year", "month", "day"]
    )


def build_planner_emlio_logs(load_start_date: str, load_end_date: str) -> DataFrame:
    """Build the planner_emlio_logs enriched dataset.

    Reads planner-ml-service logs from the emlio clean layer for the window
    [load_start_date, load_end_date], extracts structured fields from JSON
    inputs/outputs driven by INPUT_SPECS / OUTPUT_SPECS, computes derived
    observability columns, deduplicates, and returns the final DataFrame.
    """
    date_filter = (
        (F.col("id_service") == SERVICE_ID)
        & (F.to_date("ts_log") >= load_start_date)
        & (F.to_date("ts_log") <= load_end_date)
    )

    df = spark.table(SOURCE_TABLE).filter(date_filter)  # noqa: F821
    df = _build_payload_envelope(df)
    df = _apply_specs(df, INPUT_SPECS + OUTPUT_SPECS)
    df = _extract_observability_derived(df)
    df = df.select(_final_columns())
    return _deduplicate(df)


# COMMAND ----------

# DBTITLE 1,Schema Validation
# Keep in sync with INPUT_SPECS + OUTPUT_SPECS: one StructField per spec entry,
# plus the fixed source/derived/partition columns.
EXPECTED_SCHEMA = StructType(
    [
        StructField("uuid", StringType(), True),
        StructField("service_version", StringType(), True),
        StructField("ts_log", TimestampType(), True),
        StructField("response_type", StringType(), True),
        # --- input fields (INPUT_SPECS order) ---
        StructField("business_context", StringType(), True),
        StructField("id_house", StringType(), True),
        StructField("id_prospect", StringType(), True),
        StructField("id_region", StringType(), True),
        StructField("list_agent_service_available", ArrayType(IntegerType()), True),
        StructField("force_group", StringType(), True),
        StructField("override_groups", StringType(), True),
        StructField("debug_mode", StringType(), True),
        # --- output fields (OUTPUT_SPECS order) ---
        StructField("list_agent_ml_ranking", ArrayType(IntegerType()), True),
        StructField("group", StringType(), True),
        StructField("strategy_type_used", StringType(), True),
        StructField("ranked_agents_count", IntegerType(), True),
        # --- derived observability ---
        StructField("metrics_calculate_ranking", StringType(), True),
        StructField("first_agent_ml_ranking", IntegerType(), True),
        # --- partitions ---
        StructField("year", IntegerType(), True),
        StructField("month", IntegerType(), True),
        StructField("day", IntegerType(), True),
    ]
)


def _schema_mismatches(actual: StructType, expected: StructType) -> list:
    """Return mismatch messages between actual and expected schemas (single pass)."""
    actual_by_name = {f.name: f for f in actual.fields}
    expected_by_name = {f.name: f for f in expected.fields}

    def _msg(name: str) -> Optional[str]:
        if name not in actual_by_name:
            return f"missing column '{name}' (expected {expected_by_name[name].dataType.simpleString()})"
        if name not in expected_by_name:
            return f"unexpected column '{name}'"
        actual_type = actual_by_name[name].dataType.simpleString()
        expected_type = expected_by_name[name].dataType.simpleString()
        if actual_type != expected_type:
            return f"column '{name}': expected {expected_type}, got {actual_type}"
        return None

    return list(
        filter(None, (_msg(n) for n in actual_by_name.keys() | expected_by_name.keys()))
    )


def validate_before_write(df: DataFrame) -> int:
    """Assert the DataFrame is non-empty and matches EXPECTED_SCHEMA. Returns row count."""
    row_count = df.count()
    if row_count == 0:
        raise ValueError("Dataset is empty; aborting write.")
    mismatches = _schema_mismatches(df.schema, EXPECTED_SCHEMA)
    if mismatches:
        raise ValueError(f"Schema mismatch — {'; '.join(mismatches)}.")
    logger.info(
        f"m=validate_before_write, rows={row_count:,}, msg=Pre-write checks passed"
    )
    return row_count


# COMMAND ----------


# DBTITLE 1,Persistence
def _save_to_enrich(
    spark_client: SparkClient, result_df: DataFrame, args: Namespace, row_count: int
) -> None:
    """Write DataFrame to the enrich layer via Delta merge, refresh metastore, apply ACLs.

    Schema evolution is enabled so that new columns added to INPUT_SPECS / OUTPUT_SPECS
    are automatically appended to the Delta table. Previous partitions will have null
    for the new columns, which is the expected behaviour when the payload schema grows.
    """
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

    SparkSession.builder.getOrCreate().conf.set(
        "spark.databricks.delta.schema.autoMerge.enabled", "true"
    )

    SparkMetastoreService(spark_client).create_database(write_database_name)
    DeltaLoader().load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=result_df,
        partition_by=["year", "month", "day"],
        merge_on=["uuid"],
    )
    SparkMetastoreService(spark_client).refresh_table(
        write_database_name, write_table_name
    )
    priv = TablePrivileges.from_environment_default(full_table_name)
    if priv and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        priv.apply()
    logger.info(f"m=save_to_enrich, table={full_table_name}, rows={row_count:,}")


def save_df(
    spark_client: SparkClient,
    result_df: DataFrame,
    args: Namespace,
    row_count: Optional[int] = None,
) -> None:
    """Dispatch write to dev (temp view for inspection) or prod (Delta merge to enrich)."""
    run_mode = getattr(args, "run_mode", "dev")
    if run_mode == "dev":
        view_name = f"dev_{args.table_name}"
        result_df.cache()
        dev_row_count = result_df.count()
        result_df.createOrReplaceTempView(view_name)
        logger.info(
            f"m=save_df, mode=dev, view={view_name}, rows={dev_row_count:,} — "
            f"query with: SELECT * FROM {view_name}"
        )
        return
    if run_mode == "prod":
        _save_to_enrich(
            spark_client,
            result_df,
            args,
            row_count if row_count is not None else result_df.count(),
        )
        return
    raise ValueError(f"Invalid run_mode: {run_mode!r}. Expected 'dev' or 'prod'.")


# COMMAND ----------


# DBTITLE 1,Entry Point
def main(args: Optional[Namespace] = None) -> None:
    """Orchestrate ETL: build → validate → write."""
    if args is None:
        args = parse_args()
    logger.info(
        f"m=main, run_mode={args.run_mode}, env={args.env}, "
        f"database_base_name={args.database_base_name}, "
        f"table_name={args.table_name}, "
        f"interval=[{args.load_start_date}, {args.load_end_date}]"
    )
    output_df = build_planner_emlio_logs(args.load_start_date, args.load_end_date)
    row_count = validate_before_write(output_df)
    save_df(SparkClient(), output_df, args, row_count=row_count)
    logger.info("m=main, msg=Job finished successfully")


# COMMAND ----------

if __name__ == "__main__":
    main()
