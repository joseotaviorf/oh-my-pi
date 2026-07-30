from typing import Optional

from pyspark.sql import DataFrame
from pyspark.sql.functions import coalesce, col, from_json, lit, trim, when
from pyspark.sql.functions import sum as spark_sum
from pyspark.sql.types import StringType, StructField, StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.messaging_services.alert_channel_service import (
    AlertChannelService,
)
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

LOGGER = QuintoAndarLogger("corrupt_record_monitor")

DEFAULT_MIN_DROPPED = 100
DEFAULT_RATIO_THRESHOLD = 0.05
TOP_APPS_LIMIT = 10
UNKNOWN_APP = "(unknown)"
# AlertChannelService resolves channel *keywords* (the GchatWebhooksEnum attribute
# names), not their secret-key values, so these are the attribute names. This is a
# generic helper, so the default channel is the shared data-quality channel; teams
# that own a table pass their own channel (e.g. "AUTHX_ALERTS") explicitly.
DEFAULT_CHANNEL_KEYWORD = "DATA_QUALITY_DEFAULT"
FALLBACK_CHANNEL_KEYWORD = "DATA_QUALITY_DEFAULT"


def alert_on_corrupt_records(
    raw_df: DataFrame,
    *,
    ts_field: str,
    env: str,
    table_name: str,
    dbutils=None,
    channel: str = DEFAULT_CHANNEL_KEYWORD,
    min_dropped: int = DEFAULT_MIN_DROPPED,
    ratio_threshold: float = DEFAULT_RATIO_THRESHOLD,
    message_col: str = "message",
    operational_log_field: Optional[str] = None,
) -> None:
    """
    Detect source log records that fail JSON parsing and are silently dropped by
    the clean-load filter, and post a non-blocking GChat warning when the drop
    rate is significant for any single ``app``.

    The clean-load jobs read with ``mode=PERMISSIVE`` and parse the inner payload
    with ``from_json(message, ...)``. A truncated or otherwise invalid inner
    payload yields a parsed struct whose fields are all null, so the downstream
    ``.where(col("data.<ts_field>").isNotNull())`` filter drops the row without
    raising. This approximates that drop predicate with a cheap probe schema,
    aggregates the dropped rows **per app** in a single pass and alerts when any
    app crosses both an absolute floor (``min_dropped``) and a ratio floor
    (``ratio_threshold``). Evaluating per app means a small-but-critical subset
    (e.g. internal back-office traffic on one app) is not masked by the overall
    volume of unaffected apps. Rows whose ``app`` label is null are grouped into an
    explicit ``(unknown)`` bucket so they still trigger.

    The probe declares only ``<ts_field>`` (plus ``operational_log_field``), so it is
    deliberately narrower than the full schema the clean load parses with and the
    counts are a **lower bound** on what the clean load actually drops:
    ``from_json`` nulls the whole struct whenever *any* value does not fit its
    declared type (a numeric field arriving as a string, an object where a scalar is
    expected), and such a record is dropped by the clean load while still parsing
    cleanly against the probe. Truncation and malformed JSON — the failure mode this
    monitor exists for — are detected; drops caused by upstream schema drift are
    not, and belong to the schema-change tooling instead.

    Only **access-log candidates** are evaluated: records whose ``message`` is a
    JSON object (the trimmed value starts with ``{``). The istio-proxy S3 stream
    interleaves real access logs with sidecar operational noise (plain-text lines
    such as ``... debug envoy wasm ...`` or ``info xdsproxy connected ...``); that
    noise is not audit data and is excluded from both the numerator and the
    denominator so it cannot inflate the drop rate or fire a false alarm. A
    tail-truncated access log still starts with ``{`` (Envoy truncates the end), so
    genuine corruption is still detected. Note that a record whose whole outer
    envelope failed to parse arrives with ``message`` null (the reader keeps the
    row and nulls every field); such rows are dropped by the clean load but are
    **not** evaluated here, because a null ``message`` cannot be attributed to an
    app or told apart from a legitimately absent payload.

    ``operational_log_field`` names a field carried only by non-access-log lines
    that are nevertheless valid JSON — OPA logs its own server and bundle-plugin
    activity as JSON objects with ``msg``/``level`` and no ``<ts_field>``. When a
    record parses, lacks ``<ts_field>`` and carries that field, it is counted as
    operational and excluded from both the numerator and the denominator; a
    truncated record nulls every probe field, so it is still counted as dropped.
    Leave it unset for sources whose operational noise is not JSON (istio).

    The alert is routed through ``AlertChannelService`` using the ``channel``
    keyword (default: the shared data-quality channel; callers that own a table
    pass their own channel). A missing channel secret falls back to the
    data-quality default channel instead of being silently dropped. ``dbutils`` is
    optional: when omitted it is resolved on demand, only once an alert is about to
    be sent.

    It never raises: any failure to compute or send the alert is logged and
    swallowed, so log-volume monitoring can never break the load itself.
    """
    try:
        probe_fields = [StructField(ts_field, StringType(), True)]
        if operational_log_field:
            probe_fields.append(StructField(operational_log_field, StringType(), True))
        probe = from_json(col(message_col), StructType(probe_fields))
        ts_missing = probe.getField(ts_field).isNull()

        # Only JSON-object-shaped messages are access-log candidates. Sidecar
        # operational noise (plain-text envoy/wasm/xds lines) is not audit data,
        # so it is excluded from both the total and the dropped counts.
        is_json_shaped = col(message_col).isNotNull() & trim(
            col(message_col)
        ).startswith("{")
        if operational_log_field:
            is_operational = (
                is_json_shaped
                & ts_missing
                & probe.getField(operational_log_field).isNotNull()
            )
        else:
            is_operational = lit(False)

        is_candidate = is_json_shaped & ~is_operational
        candidate_flag = when(is_candidate, lit(1)).otherwise(lit(0))
        dropped_flag = when(is_candidate & ts_missing, lit(1)).otherwise(lit(0))
        operational_flag = when(is_operational, lit(1)).otherwise(lit(0))

        if "app" in raw_df.columns:
            app_bucket = coalesce(col("app"), lit(UNKNOWN_APP))
        else:
            app_bucket = lit(UNKNOWN_APP)

        per_app = (
            raw_df.withColumn("_app_bucket", app_bucket)
            .groupBy("_app_bucket")
            .agg(
                spark_sum(candidate_flag).alias("total"),
                spark_sum(dropped_flag).alias("dropped"),
                spark_sum(operational_flag).alias("operational"),
            )
            .collect()
        )

        total = sum((row["total"] or 0) for row in per_app)
        dropped = sum((row["dropped"] or 0) for row in per_app)
        operational = sum((row["operational"] or 0) for row in per_app)

        if total == 0:
            LOGGER.info(
                f"m=alert_on_corrupt_records, table={table_name}, "
                f"operational={operational}, "
                f"msg=No access-log candidate rows to evaluate."
            )
            return

        ratio = dropped / total
        LOGGER.info(
            f"m=alert_on_corrupt_records, table={table_name}, env={env}, "
            f"total={total}, dropped={dropped}, ratio={ratio:.4f}, "
            f"operational={operational}"
        )

        offending = _offending_apps(per_app, min_dropped, ratio_threshold)
        if not offending:
            return

        content = _build_message(
            env=env,
            table_name=table_name,
            total=total,
            dropped=dropped,
            ratio=ratio,
            min_dropped=min_dropped,
            ratio_threshold=ratio_threshold,
            offending=offending,
        )

        resolved_dbutils = dbutils if dbutils is not None else _resolve_dbutils()
        webhook = AlertChannelService(dbutils=resolved_dbutils).get_gchat_webhook_url(
            channel_keyword=channel,
            default_keyword=FALLBACK_CHANNEL_KEYWORD,
        )
        sent = GChatService.send_message(Message(content=content, destination=webhook))
        if sent:
            LOGGER.info(
                f"m=alert_on_corrupt_records, table={table_name}, "
                f"msg=Corrupt-record alert sent for {len(offending)} app(s)."
            )
        else:
            LOGGER.warning(
                f"m=alert_on_corrupt_records, table={table_name}, "
                f"msg=Corrupt-record alert delivery failed for "
                f"{len(offending)} app(s)."
            )
    except Exception as error:  # noqa: BLE001 - alerting must never break the load
        LOGGER.warning(
            f"m=alert_on_corrupt_records, table={table_name}, "
            f"msg=Failed to evaluate or send corrupt-record alert: {error}"
        )


def _resolve_dbutils():
    """
    Resolve dbutils on demand. Imported lazily because importing the module builds
    a Spark context, and called from inside the caller's ``try`` so a resolution
    failure degrades to a missed alert instead of breaking the load.
    """
    from bietlejuice.base.spark.base_spark import BaseDBUtils

    return BaseDBUtils().get_dbutils()


def _offending_apps(per_app, min_dropped: int, ratio_threshold: float):
    """
    Keep only the apps that cross both the absolute and ratio floors, sorted by
    dropped count descending. Each entry is ``(app, total, dropped, ratio)``.
    """
    offending = []
    for row in per_app:
        app_total = row["total"] or 0
        app_dropped = row["dropped"] or 0
        if app_total <= 0:
            continue
        app_ratio = app_dropped / app_total
        if app_dropped >= min_dropped and app_ratio >= ratio_threshold:
            offending.append((row["_app_bucket"], app_total, app_dropped, app_ratio))

    offending.sort(key=lambda entry: entry[2], reverse=True)
    return offending


def _build_message(
    *,
    env: str,
    table_name: str,
    total: int,
    dropped: int,
    ratio: float,
    min_dropped: int,
    ratio_threshold: float,
    offending,
) -> str:
    shown = offending[:TOP_APPS_LIMIT]
    lines = [
        "⚠️ *Audit log corrupt-record drop detected*",
        f"*Table:* `{table_name}`",
        f"*Environment:* {env}",
        f"*Apps over threshold:* {len(offending)} "
        f"(>= {min_dropped} dropped and >= {ratio_threshold:.0%} of the app's source)",
    ]
    lines.extend(
        f"  • {app}: {app_dropped} of {app_total} dropped ({app_ratio:.1%})"
        for app, app_total, app_dropped, app_ratio in shown
    )
    if len(offending) > len(shown):
        lines.append(
            f"  • ... and {len(offending) - len(shown)} more app(s); "
            f"the {len(shown)} with the most dropped records are listed above"
        )
    lines.append(f"*All apps combined:* {dropped} of {total} records ({ratio:.1%})")
    lines.append(
        "These records failed JSON parsing and were filtered out of the clean table. "
        "Investigate upstream log truncation/format before the data is lost."
    )
    return "\n".join(lines)
