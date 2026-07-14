"""Config-driven Agents alert framework (Architecture B custom Spark job).

Per run: read the in-repo allowlisted alert registry, evaluate each alert whose
cron is DUE against ``data_interval_start``, MERGE one result row per violating
entity (key ``id_alert``) into ``datalake_{schema}.agent_alert_results``, and
POST to Notification Hub (inmetro route) on breach. One failing alert never
aborts the others; only a broken framework (registry unreadable/invalid or Delta
write failure) fails the job.

Uses Spark SQL + Delta Lake APIs only (EMR Spark 3.5 / Databricks DBR compatible).
No dbutils, Unity Catalog helpers, or ``spark.databricks.*`` job configs in this file.
"""

from __future__ import annotations

import hashlib
import logging
from argparse import ArgumentParser, Namespace
from datetime import date, datetime, timezone

import requests
import yaml
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    BooleanType,
    DateType,
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_agent_alerts"
REGISTRY_FILE_NAME = "alerts_registry.yml"
TABLE_NAME = "agent_alert_results"
REQUIRED_ALERT_KEYS = (
    "description",
    "channel",
    "cron",
    "threshold",
    "id_column",
    "criteria_sql",
)
NOTIFICATION_HUB_INMETRO_BASE_KEY = "notification_hub_inmetro_webhook_base"
CRITERIA_VERSION_LENGTH = 12
ALERT_ID_LENGTH = 16
CRON_FIELD_COUNT = 5
# Dedup/merge on the deterministic per-entity id. Insert-only (never update a
# matched row) so ts_check stays the FIRST time the entity was alerted.
MERGE_KEYS = ["id_alert"]
MERGE_INSERT_ONLY_CONDITION = "1 = 0"
PARTITION_COLS = ["alert_name", "year", "month", "day"]
# Cap the sample of new ids listed in the GChat message (full set lives in Delta).
NOTIFY_SAMPLE_SIZE = 10

RESULT_SCHEMA = StructType(
    [
        StructField("id_alert", StringType(), True),
        StructField("alert_name", StringType(), True),
        StructField("criteria_version", StringType(), True),
        StructField("id_column", StringType(), True),
        StructField("id_entity", StringType(), True),
        StructField("entity_value", StringType(), True),
        StructField("violation_count", LongType(), True),
        StructField("threshold", StringType(), True),
        StructField("is_breach", BooleanType(), True),
        StructField("dt_check", DateType(), True),
        StructField("ts_check", TimestampType(), True),
        StructField("year", IntegerType(), True),
        StructField("month", IntegerType(), True),
        StructField("day", IntegerType(), True),
    ]
)
RESULT_FIELDS = [field.name for field in RESULT_SCHEMA.fields]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark = SparkSession.getActiveSession() or SparkSession.builder.getOrCreate()
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")


def is_cron_due(cron_expr: str, dt) -> bool:
    """Return True when the 5-field ``cron_expr`` matches datetime ``dt``.

    Pure-Python 5-field matcher (minute hour dom month dow) with no external
    dependency. Inlined in this job because Databricks/EMR execute the job file
    directly, so co-located imports are not resolvable at runtime. Supported per
    field: ``*``, ``a``, ``a-b``, ``a,b,c``, ``*/step``, ``a-b/step``. DOW uses
    cron convention: Sunday = 0.

    :raises ValueError: when ``cron_expr`` does not split into 5 fields.
    """
    fields = cron_expr.split()
    if len(fields) != CRON_FIELD_COUNT:
        raise ValueError(
            f"Malformed cron expression, expected {CRON_FIELD_COUNT} fields: {cron_expr!r}"
        )

    minute, hour, dom, month, dow = fields
    cron_dow = dt.isoweekday() % 7  # Sunday = 0

    return (
        _field_matches(minute, dt.minute, 0, 59)
        and _field_matches(hour, dt.hour, 0, 23)
        and _field_matches(dom, dt.day, 1, 31)
        and _field_matches(month, dt.month, 1, 12)
        and _field_matches(dow, cron_dow, 0, 6)
    )


def _field_matches(field: str, value: int, lo: int, hi: int) -> bool:
    """Return True when ``value`` satisfies a single cron field."""
    for part in field.split(","):
        if part == "*":
            return True

        base, _, step_str = part.partition("/")
        step = int(step_str) if step_str else 1
        start, _, end = base.partition("-")

        if base == "*":
            rng_lo, rng_hi = lo, hi
        elif end:
            rng_lo, rng_hi = int(start), int(end)
        else:
            if step == 1 and value == int(start):
                return True
            rng_lo = rng_hi = int(start)

        if rng_lo <= value <= rng_hi and (value - rng_lo) % step == 0:
            return True

    return False


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("dag_name")
    parser.add_argument("schema")
    parser.add_argument("logical_ts")
    return parser.parse_args()


def load_registry(dag_name: str) -> dict:
    """Read, parse and validate the co-located alert registry.

    A malformed registry is a framework-level failure and propagates.
    """
    content = DAGPackagesPathService.get_config_file_content_in_spark_jobs(
        dag_name, REGISTRY_FILE_NAME
    )
    parsed = yaml.safe_load(content) or {}
    alerts = parsed.get("alerts")
    if not alerts:
        raise ValueError(
            f"m=load_registry, msg=Registry has no alerts, dag_name={dag_name}"
        )

    for alert_name, defn in alerts.items():
        missing = [key for key in REQUIRED_ALERT_KEYS if key not in defn]
        if missing:
            raise ValueError(
                f"m=load_registry, alert={alert_name}, msg=Missing required keys: {missing}"
            )
        # Fail fast on an unroutable alert: a channel that resolves to no Hub
        # space would otherwise raise mid-run, after results were merged.
        if not (defn.get("hub_space") or _hub_space_from_channel(defn["channel"])):
            raise ValueError(
                f"m=load_registry, alert={alert_name}, "
                f"msg=Cannot resolve Notification Hub space from channel={defn['channel']!r}"
            )

    return alerts


def _cron_gate_timestamp(logical_ts: datetime) -> datetime:
    """Minute used for cron matching — from ``data_interval_start``, not EMR execution time."""
    instant = logical_ts
    if instant.tzinfo is not None:
        instant = instant.astimezone(timezone.utc).replace(tzinfo=None)
    return instant.replace(second=0, microsecond=0)


def _due_alerts(registry: dict, logical_ts: datetime) -> dict:
    """Alerts to evaluate for this Airflow data interval.

    Cron gating uses ``logical_ts`` (``data_interval_start``), floored to the minute —
    not EMR step start time. ``ignore_cron`` skips the registry cron (Forno smoke only).
    """
    gate_ts = _cron_gate_timestamp(logical_ts)
    return {
        name: defn
        for name, defn in registry.items()
        if defn.get("ignore_cron") or is_cron_due(defn["cron"], gate_ts)
    }


def _criteria_version(criteria_sql: str) -> str:
    """Short sha256 (first 12 hex chars) of the normalized criteria SQL."""
    normalized = " ".join(criteria_sql.split())
    digest = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
    return digest[:CRITERIA_VERSION_LENGTH]


def _sql_literal(value: str) -> str:
    """Escape a string for safe embedding in Spark SQL string literals."""
    return value.replace("'", "''")


def _check_timestamps(logical_ts):
    """Stdlib date/timestamp for Spark literals (Spark rejects non-stdlib datetime types)."""
    dt_check = date(logical_ts.year, logical_ts.month, logical_ts.day)
    ts_check = datetime(
        logical_ts.year,
        logical_ts.month,
        logical_ts.day,
        logical_ts.hour,
        logical_ts.minute,
        logical_ts.second,
        logical_ts.microsecond,
    )
    return dt_check, ts_check


def _parse_logical_ts(raw: str) -> datetime:
    """Parse Airflow ``data_interval_start`` (ISO-8601 UTC) to a naive UTC datetime.

    Airflow emits ``data_interval_start`` in UTC; normalize to naive UTC (not the
    EMR host's local zone) so cron gating and the dedup check-day are deterministic
    regardless of the cluster clock.
    """
    text = raw.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed


def _render_criteria_sql(criteria_sql: str, logical_ts: datetime) -> str:
    """Replace bracket placeholders before Spark executes registry SQL."""
    return criteria_sql.replace(
        "{logical_yyyymmdd_hhmm}", logical_ts.strftime("%Y%m%d_%H%M")
    ).replace("{logical_date}", logical_ts.strftime("%Y-%m-%d"))


def evaluate_alert(alert_name: str, defn: dict, logical_ts) -> dict | None:
    """Run criteria SQL on the cluster; return metadata and a violations DataFrame.

    Counting, dedup, and Delta writes stay in Spark — no driver ``collect()`` on
    full violation sets. On SQL failure or invalid threshold the alert is logged
    and skipped (returns None).
    """
    id_column = defn["id_column"]
    value_column = defn.get("value_column")
    criteria_sql = _render_criteria_sql(defn["criteria_sql"], logical_ts)
    threshold_raw = defn["threshold"]
    try:
        threshold_num = _numeric_threshold(threshold_raw)
    except ValueError as error:
        logger.error(f"m=evaluate_alert, alert={alert_name}, error={error}")
        return None

    try:
        violations_df = _criteria_violations_dataframe(
            criteria_sql, id_column, value_column
        )
        violation_count = violations_df.count()
    except Exception as error:  # noqa: BLE001 — one bad alert must not abort others
        logger.error(f"m=evaluate_alert, alert={alert_name}, error={error}")
        return None

    return {
        "alert_name": alert_name,
        "criteria_version": _criteria_version(criteria_sql),
        "id_column": id_column,
        "violations_df": violations_df,
        "violation_count": violation_count,
        "threshold": _as_string(threshold_raw),
        "is_breach": violation_count > threshold_num,
    }


def _criteria_violations_dataframe(
    criteria_sql: str, id_column: str, value_column: str | None
) -> DataFrame:
    """Run registry SQL and normalize to ``id_entity`` / ``entity_value`` (cluster-side)."""
    columns = [id_column] + ([value_column] if value_column else [])
    violations_df = (
        spark.sql(criteria_sql)
        .select(*columns)
        .filter(F.col(id_column).isNotNull())
        .withColumnRenamed(id_column, "id_entity")
        .withColumn("id_entity", F.col("id_entity").cast("string"))
    )
    if value_column:
        violations_df = violations_df.withColumnRenamed(
            value_column, "entity_value"
        ).withColumn("entity_value", F.col("entity_value").cast("string"))
    else:
        violations_df = violations_df.withColumn(
            "entity_value", F.lit(None).cast(StringType())
        )
    return violations_df.dropDuplicates(["id_entity"])


def _as_string(value) -> str | None:
    """Stringify registry/SQL values so createDataFrame always matches StringType columns."""
    if value is None:
        return None
    return str(value)


def _numeric_threshold(value) -> int | float:
    """Parse registry threshold for count-based breach (stored as string in Delta)."""
    if isinstance(value, bool):
        raise ValueError(f"threshold must be numeric, got bool: {value!r}")
    if isinstance(value, (int, float)):
        return value
    text = str(value).strip()
    if "." in text:
        return float(text)
    return int(text)


def _spark_id_alert_column(alert_name: str, dt_check: date):
    """Deterministic per-entity dedup key, cluster-side.

    ``substring(sha256(alert_name|id_entity|day), 1, 16)`` — includes the check
    date so a still-breaching entity re-alerts on a new day but never twice
    within the same day (even across DAG re-runs). Both the fresh results and
    the already-stored ids are hashed by this same expression.
    """
    day = dt_check.isoformat()
    return F.substring(
        F.sha2(
            F.concat_ws("|", F.lit(alert_name), F.col("id_entity"), F.lit(day)),
            256,
        ),
        1,
        ALERT_ID_LENGTH,
    )


def _violations_to_results_df(evaluation: dict, logical_ts) -> DataFrame:
    """Expand violations into rows that match ``RESULT_SCHEMA`` (cluster-side)."""
    dt_check, ts_check = _check_timestamps(logical_ts)
    alert_name = evaluation["alert_name"]
    return (
        evaluation["violations_df"]
        .withColumn("id_alert", _spark_id_alert_column(alert_name, dt_check))
        .withColumn("alert_name", F.lit(alert_name))
        .withColumn("criteria_version", F.lit(evaluation["criteria_version"]))
        .withColumn("id_column", F.lit(evaluation["id_column"]))
        .withColumn(
            "violation_count", F.lit(evaluation["violation_count"]).cast(LongType())
        )
        .withColumn("threshold", F.lit(evaluation["threshold"]))
        .withColumn("is_breach", F.lit(evaluation["is_breach"]))
        .withColumn("dt_check", F.lit(dt_check).cast(DateType()))
        .withColumn("ts_check", F.lit(ts_check).cast(TimestampType()))
        .withColumn("year", F.lit(logical_ts.year))
        .withColumn("month", F.lit(logical_ts.month))
        .withColumn("day", F.lit(logical_ts.day))
        .select(*RESULT_FIELDS)
    )


def _empty_id_alert_dataframe() -> DataFrame:
    return spark.createDataFrame([], schema="id_alert string")


def _existing_alert_ids_df(schema: str, alert_name: str, logical_ts) -> DataFrame:
    """``id_alert`` rows already stored for this alert on this check day (partition-pruned)."""
    table_name = f"datalake_{schema}.{TABLE_NAME}"
    if not spark.catalog.tableExists(table_name):
        return _empty_id_alert_dataframe()

    safe_name = _sql_literal(alert_name)
    query = f"""
        SELECT id_alert
        FROM {table_name}
        WHERE alert_name = '{safe_name}'
          AND year = {logical_ts.year}
          AND month = {logical_ts.month}
          AND day = {logical_ts.day}
    """
    return spark.sql(query).select("id_alert")


def _notify_sample(new_results_df: DataFrame) -> tuple[int, list, dict]:
    """Count new entities on cluster; pull at most ``NOTIFY_SAMPLE_SIZE`` rows to the driver."""
    new_count = new_results_df.count()
    if new_count == 0:
        return 0, [], {}

    rows = (
        new_results_df.select("id_entity", "entity_value")
        .limit(NOTIFY_SAMPLE_SIZE)
        .collect()
    )
    sample_ids = [str(row["id_entity"]) for row in rows]
    entity_values = {
        str(row["id_entity"]): _as_string(row["entity_value"]) for row in rows
    }
    return new_count, sample_ids, entity_values


def _notification_hub_inmetro_base(dag_name: str, environment: str) -> str | None:
    """Resolve Hub base URL from co-located ``spark_jobs/{environment}_conf.yml`` (EMR/S3), then wheel config."""
    conf_file = f"{environment}_conf.yml"
    try:
        raw = DAGPackagesPathService.get_config_file_content_in_spark_jobs(
            dag_name, conf_file
        )
        value = (yaml.safe_load(raw) or {}).get(NOTIFICATION_HUB_INMETRO_BASE_KEY)
        if value:
            return str(value).strip()
    except FileNotFoundError:
        logger.warning(
            f"m={JOB_NAME}, dag_name={dag_name}, conf_file={conf_file}, "
            "msg=Spark jobs env conf not found; falling back to ConfigurationService"
        )
    except Exception as error:  # noqa: BLE001
        logger.warning(
            f"m={JOB_NAME}, dag_name={dag_name}, conf_file={conf_file}, error={error}"
        )

    try:
        return ConfigurationService(dag_name).get_config(
            NOTIFICATION_HUB_INMETRO_BASE_KEY
        )
    except (IndexError, KeyError, AttributeError):
        return None


def notify_on_breach(
    alert_name: str,
    defn: dict,
    evaluation: dict,
    new_count: int,
    sample_ids: list,
    sample_entity_values: dict,
    logical_ts,
    dag_name: str,
    environment: str,
) -> bool:
    """POST an inmetro-shaped breach payload to Notification Hub for this alert's space."""
    base_url = _notification_hub_inmetro_base(dag_name, environment)
    if not base_url:
        logger.warning(
            f"m=notify_on_breach, alert={alert_name}, "
            f"msg=Missing config key {NOTIFICATION_HUB_INMETRO_BASE_KEY!r}"
        )
        return False

    space = defn.get("hub_space") or _hub_space_from_channel(defn["channel"])
    if not space:
        raise ValueError(
            f"m=notify_on_breach, alert={alert_name}, "
            f"msg=Could not resolve Notification Hub space from channel={defn['channel']!r}"
        )

    webhook_url = _notification_hub_webhook_url(base_url, space)
    payload = _build_inmetro_payload(
        alert_name,
        defn,
        evaluation,
        new_count,
        sample_ids,
        sample_entity_values,
        logical_ts,
    )
    if not _post_notification_hub(webhook_url, payload):
        logger.warning(
            f"m=notify_on_breach, alert={alert_name}, space={space}, "
            "msg=Notification Hub message was not delivered"
        )
        return False
    return True


def _hub_space_from_channel(channel: str) -> str | None:
    """Map registry ``channel`` to Notification Hub ``?space=`` (GChat display name).

    Convention: ``#agents-data-alarms`` → ``agents-data-alarms``,
    ``#alerts_agent_accreditation`` → ``alerts_agent_accreditation``. Use ``hub_space`` in
    the registry when the display name does not match stripping ``#``.
    """
    if not channel:
        return None
    channel = channel.strip()
    if channel.startswith("#"):
        return channel[1:]
    return channel


def _notification_hub_webhook_url(base_url: str, space: str) -> str:
    separator = "&" if "?" in base_url else "?"
    return f"{base_url.rstrip('/')}{separator}space={space}"


def _post_notification_hub(webhook_url: str, payload: dict) -> bool:
    try:
        response = requests.post(webhook_url, json=payload, timeout=30)
        response.raise_for_status()
    except Exception as error:  # noqa: BLE001 — breach path must not abort other alerts
        logger.warning(
            f"m=_post_notification_hub, url={webhook_url}, payload={payload}, error={error}"
        )
        return False
    return True


def _build_inmetro_payload(
    alert_name: str,
    defn: dict,
    evaluation: dict,
    new_count: int,
    sample_ids: list,
    sample_entity_values: dict,
    logical_ts,
) -> dict:
    severity = str(defn.get("severity", "Error"))
    status = "ERROR" if severity.lower() in ("error", "critical") else severity.upper()
    return {
        "suite_name": alert_name,
        "status": status,
        "message": _format_breach_message(
            defn, evaluation, new_count, sample_ids, sample_entity_values, logical_ts
        ),
    }


def _format_breach_message(
    defn: dict,
    evaluation: dict,
    new_count: int,
    sample_ids: list,
    sample_entity_values: dict,
    logical_ts,
) -> str:
    """Single-line body: inmetro template turns ``\\n`` into ``<br>``, which GChat shows as text."""
    shown = [
        f"{i}={sample_entity_values[i]}"
        if sample_entity_values.get(i) is not None
        else i
        for i in sample_ids
    ]
    sample = ", ".join(shown)
    if new_count > len(sample_ids):
        sample += f" (+{new_count - len(sample_ids)} more)"
    ts = logical_ts.isoformat() if hasattr(logical_ts, "isoformat") else str(logical_ts)
    return (
        f"{defn['description']} — "
        f"New: {new_count} | Total violating: {evaluation['violation_count']} | "
        f"Threshold: {evaluation['threshold']} | "
        f"{evaluation['id_column']}: {sample} | Checked at: {ts}"
    )


def _union_result_dataframes(dataframes: list[DataFrame]) -> DataFrame:
    if not dataframes:
        return spark.createDataFrame([], schema=RESULT_SCHEMA)
    combined = dataframes[0]
    for frame in dataframes[1:]:
        combined = combined.unionByName(frame)
    return combined


def main() -> None:
    args = parse_arguments()
    datalake_bucket = args.datalake_bucket
    dag_name = args.dag_name
    schema = args.schema
    logical_ts = _parse_logical_ts(args.logical_ts)
    gate_ts = _cron_gate_timestamp(logical_ts)

    logger.info(
        f"m={JOB_NAME}, environment={args.environment}, datalake_bucket={datalake_bucket}, "
        f"dag_name={dag_name}, schema={schema}, logical_ts={logical_ts}, cron_gate_ts={gate_ts}, "
        "msg=Starting spark job (cron gate uses data_interval_start)"
    )

    registry = load_registry(dag_name)
    due = _due_alerts(registry, logical_ts)
    logger.info(f"m={JOB_NAME}, msg=Due alerts: {list(due)}")

    result_dfs: list[DataFrame] = []
    pending_notifications = []
    for name, defn in due.items():
        evaluation = evaluate_alert(name, defn, logical_ts)
        if evaluation is None or not evaluation["is_breach"]:
            continue

        results_df = _violations_to_results_df(evaluation, logical_ts)
        existing_df = _existing_alert_ids_df(schema, name, logical_ts)
        new_results_df = results_df.join(existing_df, on="id_alert", how="left_anti")
        new_count, sample_ids, sample_values = _notify_sample(new_results_df)

        result_dfs.append(results_df)
        if new_count > 0:
            pending_notifications.append(
                (name, defn, evaluation, new_count, sample_ids, sample_values)
            )
        logger.info(
            f"m={JOB_NAME}, alert={name}, violating={evaluation['violation_count']}, "
            f"new={new_count}"
        )

    combined_df = _union_result_dataframes(result_dfs)
    if not result_dfs:
        # Still write an empty result set: the downstream register-table task runs
        # every tick and needs the Delta table (and its _delta_log) to exist. An
        # empty MERGE bootstraps the table on the first run and is a no-op after.
        logger.info(
            f"m={JOB_NAME}, msg=No breaching alerts this tick; "
            "writing empty result set to keep the Delta table registered."
        )

    destination_table_name = f"datalake_{schema}.{TABLE_NAME}"
    destination_table_path = f"s3://{datalake_bucket}/enrich/{schema}/{TABLE_NAME}"
    DeltaLoader().load_table(
        table_name=destination_table_name,
        path=destination_table_path,
        source_df=combined_df,
        partition_by=PARTITION_COLS,
        merge_on=MERGE_KEYS,
        when_matched_update_condition=MERGE_INSERT_ONLY_CONDITION,
    )

    if not pending_notifications:
        return

    for (
        name,
        defn,
        evaluation,
        new_count,
        sample_ids,
        sample_values,
    ) in pending_notifications:
        notify_on_breach(
            name,
            defn,
            evaluation,
            new_count,
            sample_ids,
            sample_values,
            logical_ts,
            dag_name,
            args.environment,
        )


if __name__ == "__main__":
    main()
