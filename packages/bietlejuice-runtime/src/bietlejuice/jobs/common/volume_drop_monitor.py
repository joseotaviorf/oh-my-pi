from datetime import datetime, timedelta, timezone
from functools import reduce
from operator import or_
from typing import Dict, Iterable, List, Tuple

from pyspark.sql.functions import coalesce, col, count, lit
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.messaging_services.alert_channel_service import (
    AlertChannelService,
)
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

LOGGER = QuintoAndarLogger("volume_drop_monitor")

DEFAULT_BASELINE_WEEKS = 2
DEFAULT_MIN_REFERENCE_WEEKS = 2
DEFAULT_MIN_BASELINE = 1000
DEFAULT_DROP_RATIO = 0.5
TOP_APPS_LIMIT = 10
UNKNOWN_APP = "(unknown)"
# AlertChannelService resolves channel *keywords* (the GchatWebhooksEnum attribute
# names), not their secret-key values, so these are the attribute names. This is a
# generic helper, so the default channel is the shared data-quality channel; teams
# that own a table pass their own channel (e.g. "AUTHX_ALERTS") explicitly.
DEFAULT_CHANNEL_KEYWORD = "DATA_QUALITY_DEFAULT"
FALLBACK_CHANNEL_KEYWORD = "DATA_QUALITY_DEFAULT"
PARTITION_COLUMNS = ("year", "month", "day", "hour")


def alert_on_volume_drop(
    spark,
    *,
    table_name: str,
    loaded_hour: datetime,
    env: str,
    dbutils=None,
    channel: str = DEFAULT_CHANNEL_KEYWORD,
    baseline_weeks: int = DEFAULT_BASELINE_WEEKS,
    min_reference_weeks: int = DEFAULT_MIN_REFERENCE_WEEKS,
    min_baseline: int = DEFAULT_MIN_BASELINE,
    drop_ratio: float = DEFAULT_DROP_RATIO,
) -> None:
    """
    Detect a per-``app`` collapse in access-log volume for the hour this run just
    loaded, and post a non-blocking GChat warning naming the affected apps.

    Anchored on ``loaded_hour`` -- the run's own data interval -- not on wall-clock
    time. A rerun of an old interval therefore reports on *that* interval, and a
    DAG running behind schedule reports on the hours it is actually loading instead
    of warning about hours it has not reached yet.

    **Baseline.** An app's expected volume for an hour is the *minimum* of its
    count in the same hour on each of the previous ``baseline_weeks`` weeks. Same
    hour, same weekday, so weekday/weekend and time-of-day shape are held constant
    and no weekday gate is needed. Taking the minimum makes the baseline immune to
    a spiked reference week -- the dominant source of false positives for this
    signal -- which matters because with only two reference weeks a median would
    simply average the spike in. The bias is conservative: the baseline follows
    the *quietest* recent week, so it can only under-alert, never flap. Weeks in
    which the app is absent are treated as absent, not as zero, and at least
    ``min_reference_weeks`` of them must be present -- a newly-launched app cannot
    fire, and neither can a gap in history.

    **Thresholds.** An app is unhealthy in an hour when its baseline is at least
    ``min_baseline`` records and its count is below ``drop_ratio`` of that baseline.
    The volume floor exists because below it normal hour-to-hour variance routinely
    exceeds the ratio; apps that quiet cannot be watched here and rely on the
    corrupt-record monitor instead.

    The floor is kept low deliberately. Variance is what it defends against, and the
    minimum baseline and the edge trigger below already attack variance directly -- so
    raising the floor a third time would buy quiet mostly by dropping coverage. The
    incident this monitor was written for was a service running at ~1.9k records/hour,
    which any higher floor would have excluded from the watched set entirely.

    **Edge-triggered.** An alert is raised only when an app is unhealthy in the
    loaded hour *and was healthy in the hour before it*. A sustained condition --
    a decommissioned service, a permanent traffic shift, a renamed deployment --
    is reported once, when it starts, instead of every hour until the baseline
    catches up. This is the property the check exists to have: a single retired app
    must not be able to keep the alarm ringing for weeks.

    The total-volume guard is deliberately *not* edge-triggered: when an hour loads
    no records at all, that is severe enough to repeat for as long as it lasts. It is
    suppressed in exactly one case -- when *every* hour read comes back empty, the
    reference weeks included. Simultaneous silence across every reference week is a
    failed read, not an outage, and alerting on it means any wiring error pages on
    every single run.

    Apps whose ``app`` label is null are grouped into an explicit ``(unknown)``
    bucket so they are still watched. The alert is routed through
    ``AlertChannelService`` using the ``channel`` keyword (default: the shared
    data-quality channel), falling back to the data-quality channel when the
    channel's secret is missing. ``dbutils`` is optional: when omitted it is
    resolved on demand, only once an alert is about to be sent.

    It never raises: any failure to compute or send the alert is logged and
    swallowed, so volume monitoring can never break the load itself.
    """
    try:
        current_hour = _to_naive_utc(loaded_hour).replace(
            minute=0, second=0, microsecond=0
        )
        previous_hour = current_hour - timedelta(hours=1)

        # Partition values are written from each record's own timestamp, so a run
        # for hour H can spill a few rows into H+/-1. The counts are dominated by H
        # and every comparison is like-for-like across weeks, so the spill does not
        # bias the ratio.
        wanted_hours = _hours_to_read(
            current_hour, previous_hour, baseline_weeks=baseline_weeks
        )
        counts = _per_app_hour_counts(spark, table_name, wanted_hours)

        if not any(counts.get(hour) for hour in wanted_hours):
            LOGGER.warning(
                f"m=alert_on_volume_drop, table={table_name}, env={env}, "
                f"hour={current_hour.isoformat()}, msg=None of the "
                f"{len(wanted_hours)} requested hour partitions returned any rows; "
                f"treating this as a failed read rather than a stream outage and "
                f"skipping the alert."
            )
            return

        current_counts = counts.get(current_hour, {})
        total_current = sum(current_counts.values())

        unhealthy_now = _unhealthy_apps(
            counts,
            hour=current_hour,
            baseline_weeks=baseline_weeks,
            min_reference_weeks=min_reference_weeks,
            min_baseline=min_baseline,
            drop_ratio=drop_ratio,
        )
        unhealthy_before = _unhealthy_apps(
            counts,
            hour=previous_hour,
            baseline_weeks=baseline_weeks,
            min_reference_weeks=min_reference_weeks,
            min_baseline=min_baseline,
            drop_ratio=drop_ratio,
        )
        newly_unhealthy = [
            entry for app, entry in unhealthy_now.items() if app not in unhealthy_before
        ]
        newly_unhealthy.sort(key=lambda entry: entry[2] - entry[1], reverse=True)

        dropped = [entry for entry in newly_unhealthy if entry[1] > 0]
        silent = [entry for entry in newly_unhealthy if entry[1] == 0]

        LOGGER.info(
            f"m=alert_on_volume_drop, table={table_name}, env={env}, "
            f"hour={current_hour.isoformat()}, total={total_current}, "
            f"apps={len(current_counts)}, dropped={len(dropped)}, "
            f"stopped={len(silent)}"
        )

        if total_current > 0 and not newly_unhealthy:
            return

        content = _build_message(
            env=env,
            table_name=table_name,
            hour=current_hour,
            total_current=total_current,
            baseline_weeks=baseline_weeks,
            min_baseline=min_baseline,
            drop_ratio=drop_ratio,
            dropped=dropped,
            silent=silent,
        )

        resolved_dbutils = dbutils if dbutils is not None else _resolve_dbutils()
        webhook = AlertChannelService(dbutils=resolved_dbutils).get_gchat_webhook_url(
            channel_keyword=channel,
            default_keyword=FALLBACK_CHANNEL_KEYWORD,
        )
        sent = GChatService.send_message(Message(content=content, destination=webhook))
        if sent:
            LOGGER.info(
                f"m=alert_on_volume_drop, table={table_name}, "
                f"msg=Volume-drop alert sent for {len(newly_unhealthy)} app(s)."
            )
        else:
            LOGGER.warning(
                f"m=alert_on_volume_drop, table={table_name}, "
                f"msg=Volume-drop alert delivery failed for "
                f"{len(newly_unhealthy)} app(s)."
            )
    except Exception as error:  # noqa: BLE001 - alerting must never break the load
        LOGGER.warning(
            f"m=alert_on_volume_drop, table={table_name}, "
            f"msg=Failed to evaluate or send volume-drop alert: {error}"
        )


def _resolve_dbutils():
    """
    Resolve dbutils on demand. Imported lazily because importing the module builds
    a Spark context, and called from inside the caller's ``try`` so a resolution
    failure degrades to a missed alert instead of breaking the load.
    """
    from bietlejuice.base.spark.base_spark import BaseDBUtils

    return BaseDBUtils().get_dbutils()


def _to_naive_utc(moment: datetime) -> datetime:
    """
    Every hour in this module is a naive UTC wall clock, because that is what the
    ``year``/``month``/``day``/``hour`` partition columns store -- integers with no
    zone attached. ``loaded_hour`` is the one value that arrives from outside: the
    spark jobs pass Airflow's ``{{ ts }}``, which renders as
    ``2026-08-04T17:00:00+00:00`` and parses to a *tz-aware* datetime.

    Normalising it here is load-bearing rather than cosmetic. An aware datetime is
    never equal to a naive one and hashes differently, so an un-normalised anchor
    matches none of the hour keys rebuilt from the partition columns: every count
    reads as zero and the monitor reports a total stream loss on every run.
    """
    if moment.tzinfo is None:
        return moment
    return moment.astimezone(timezone.utc).replace(tzinfo=None)


def _hours_to_read(
    current_hour: datetime, previous_hour: datetime, *, baseline_weeks: int
) -> List[datetime]:
    """
    The two evaluated hours plus the reference hour for each of them on every one of
    the previous ``baseline_weeks`` weeks. Every entry is a whole hour, so the read
    below prunes to exactly this many partitions.
    """
    hours = []
    for anchor in (current_hour, previous_hour):
        hours.append(anchor)
        hours.extend(
            anchor - timedelta(weeks=week) for week in range(1, baseline_weeks + 1)
        )
    return sorted(set(hours))


def _hour_predicate(hour: datetime):
    return (
        (col("year") == hour.year)
        & (col("month") == hour.month)
        & (col("day") == hour.day)
        & (col("hour") == hour.hour)
    )


def _per_app_hour_counts(
    spark, table_name: str, hours: Iterable[datetime]
) -> Dict[datetime, Dict[str, int]]:
    """
    Per-``app`` row counts for each requested hour, in a single aggregation.

    The filter is expressed directly on the partition columns and compared against
    Python-side literals, so it is a pure partition filter: Delta resolves it from
    the transaction log and only the requested hours are opened. The result is at
    most ``#apps x #hours`` rows, so collecting it to the driver is cheap.
    """
    hours = list(hours)
    df = spark.table(table_name)
    app_bucket = (
        coalesce(col("app"), lit(UNKNOWN_APP))
        if "app" in df.columns
        else lit(UNKNOWN_APP)
    )

    rows = (
        df.where(reduce(or_, (_hour_predicate(hour) for hour in hours)))
        .groupBy(
            app_bucket.alias("_app_bucket"),
            *(col(column) for column in PARTITION_COLUMNS),
        )
        .agg(count(lit(1)).alias("records"))
        .collect()
    )

    per_hour: Dict[datetime, Dict[str, int]] = {hour: {} for hour in hours}
    for row in rows:
        hour = datetime(row["year"], row["month"], row["day"], row["hour"])
        per_hour.setdefault(hour, {})[row["_app_bucket"]] = row["records"]
    return per_hour


def _unhealthy_apps(
    counts: Dict[datetime, Dict[str, int]],
    *,
    hour: datetime,
    baseline_weeks: int,
    min_reference_weeks: int,
    min_baseline: int,
    drop_ratio: float,
) -> Dict[str, Tuple[str, int, float]]:
    """
    Apps whose volume in ``hour`` sits below ``drop_ratio`` of their baseline for
    that hour. Keyed by app; each value is ``(app, current, baseline)``.

    The baseline is the *minimum* across the reference weeks: with two samples a
    median is just their average, so a single spiked week would inflate it, while
    the minimum ignores the spike and biases toward under-alerting.

    Only apps with history are considered -- an app absent from every reference
    week has no baseline and is skipped rather than treated as a drop.
    """
    reference_hours = [
        hour - timedelta(weeks=week) for week in range(1, baseline_weeks + 1)
    ]
    current_counts = counts.get(hour, {})

    candidates = set()
    for reference_hour in reference_hours:
        candidates.update(counts.get(reference_hour, {}))

    unhealthy: Dict[str, Tuple[str, int, float]] = {}
    for app in candidates:
        references = [
            counts[reference_hour][app]
            for reference_hour in reference_hours
            if app in counts.get(reference_hour, {})
        ]
        if len(references) < min_reference_weeks:
            continue

        baseline = min(references)
        if baseline < min_baseline:
            continue

        current = current_counts.get(app, 0)
        if current < drop_ratio * baseline:
            unhealthy[app] = (app, current, baseline)

    return unhealthy


def _format_entry(app: str, current: int, baseline: float) -> str:
    change = (current - baseline) / baseline
    return f"  • {app}: {current:,} vs baseline {baseline:,.0f} ({change:.0%})"


def _build_message(
    *,
    env: str,
    table_name: str,
    hour: datetime,
    total_current: int,
    baseline_weeks: int,
    min_baseline: int,
    drop_ratio: float,
    dropped: List[Tuple[str, int, float]],
    silent: List[Tuple[str, int, float]],
) -> str:
    lines = [
        "⚠️ *Access-log volume drop detected*",
        f"*Table:* `{table_name}`",
        f"*Environment:* {env}",
        f"*Hour loaded:* {hour:%Y-%m-%d %H:00} UTC",
    ]

    if total_current == 0:
        lines.append(
            "🚨 *No records at all were loaded for this hour.* The access-log "
            "stream for this source has stopped."
        )

    if silent:
        lines.append(f"*Apps that stopped emitting entirely:* {len(silent)}")
        lines.extend(_render_entries(silent))

    if dropped:
        lines.append(
            f"*Apps below {drop_ratio:.0%} of their {baseline_weeks}-week baseline:* "
            f"{len(dropped)} (baseline >= {min_baseline:,} records)"
        )
        lines.extend(_render_entries(dropped))

    lines.append(
        f"Baseline is the lowest count for the same hour on the previous "
        f"{baseline_weeks} weeks. Only apps that were healthy in the previous hour "
        "are listed, so an ongoing drop is reported once rather than every hour."
    )
    return "\n".join(lines)


def _render_entries(entries: List[Tuple[str, int, float]]) -> List[str]:
    shown = entries[:TOP_APPS_LIMIT]
    rendered = [_format_entry(*entry) for entry in shown]
    if len(entries) > len(shown):
        rendered.append(
            f"  • ... and {len(entries) - len(shown)} more app(s); "
            f"the {len(shown)} with the largest absolute loss are listed above"
        )
    return rendered


__all__ = ["alert_on_volume_drop"]
