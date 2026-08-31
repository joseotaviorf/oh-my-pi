from collections import defaultdict
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.jobs.common import volume_drop_monitor
from bietlejuice.jobs.common.volume_drop_monitor import alert_on_volume_drop

MODULE = "bietlejuice.jobs.common.volume_drop_monitor"

AUTHX_SECRET_KEY = GchatWebhooksEnum.AUTHX_ALERTS
DEFAULT_SECRET_KEY = GchatWebhooksEnum.DATA_QUALITY_DEFAULT

# Thursday 14:00 UTC. Reference hours are the same hour on the two preceding
# Thursdays, so weekday and time-of-day shape are held constant.
LOADED_HOUR = datetime(2026, 7, 30, 14)
SATURDAY_HOUR = datetime(2026, 8, 1, 14)

# Kept below the production default so the fixtures stay small: a test that used the
# real 1000-record floor would have to materialise several thousand rows per hour
# bucket, and every bucket is expanded row by row in _register_table.
TEST_MIN_BASELINE = 500

TABLE_SCHEMA = "app STRING, year INT, month INT, day INT, hour INT"


def _counts(apps, *, loaded_hour=LOADED_HOUR):
    """Expand a per-app spec into ``{hour: {app: row_count}}``.

    Each spec may set ``current`` (the loaded hour), ``previous`` (the hour before
    it), ``refs`` (the reference weeks for the loaded hour) and ``prev_refs``
    (the reference weeks for the previous hour, defaulting to ``refs``). A ``None``
    entry in a reference list means the app was absent that week.
    """
    previous_hour = loaded_hour - timedelta(hours=1)
    counts = defaultdict(dict)

    for app, spec in apps.items():
        for anchor, key in ((loaded_hour, "current"), (previous_hour, "previous")):
            value = spec.get(key)
            if value:
                counts[anchor][app] = value

        refs = spec.get("refs", [])
        prev_refs = spec.get("prev_refs", refs)
        for anchor, values in ((loaded_hour, refs), (previous_hour, prev_refs)):
            for week, value in enumerate(values, start=1):
                if value:
                    counts[anchor - timedelta(weeks=week)][app] = value

    return counts


def _register_table(spark_session, counts, name="clean_access_logs"):
    rows = []
    for hour, per_app in counts.items():
        for app, records in per_app.items():
            rows.extend([(app, hour.year, hour.month, hour.day, hour.hour)] * records)

    spark_session.createDataFrame(rows, TABLE_SCHEMA).createOrReplaceTempView(name)
    return name


def _run(spark_session, table, *, loaded_hour=LOADED_HOUR, **kwargs):
    kwargs.setdefault("min_baseline", TEST_MIN_BASELINE)
    alert_on_volume_drop(
        spark_session,
        table_name=table,
        loaded_hour=loaded_hour,
        env="prod",
        **kwargs,
    )


@pytest.fixture
def fake_dbutils():
    dbutils = MagicMock()
    dbutils.secrets.get.return_value = "https://chat.googleapis.com/fake-webhook"
    return dbutils


@patch(f"{MODULE}.GChatService.send_message")
def test_no_alert_on_healthy_hour(mock_send, spark_session, fake_dbutils):
    """Volume in line with the baseline -> nothing to report."""
    table = _register_table(
        spark_session,
        _counts(
            {
                "monopoly": {"current": 980, "previous": 1010, "refs": [1000] * 2},
                "customer": {"current": 700, "previous": 720, "refs": [740] * 2},
            }
        ),
    )

    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_not_called()
    fake_dbutils.secrets.get.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_alerts_when_app_drops_below_half_baseline(
    mock_send, spark_session, fake_dbutils
):
    """An app under 50% of its baseline is named, with its counts, while a healthy
    app sharing the hour is not."""
    table = _register_table(
        spark_session,
        _counts(
            {
                "monopoly": {"current": 100, "previous": 1000, "refs": [1000] * 2},
                "customer": {"current": 740, "previous": 740, "refs": [740] * 2},
            }
        ),
    )

    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_called_once()
    content = mock_send.call_args.args[0].content
    assert "monopoly" in content
    assert "customer" not in content
    assert "100" in content


@patch(f"{MODULE}.GChatService.send_message")
def test_no_alert_when_baseline_below_floor(mock_send, spark_session, fake_dbutils):
    """Below the volume floor, hour-to-hour variance routinely exceeds the ratio,
    so low-traffic apps must not be watched here."""
    table = _register_table(
        spark_session,
        _counts({"tiny": {"current": 10, "previous": 400, "refs": [400] * 2}}),
    )

    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_no_alert_when_history_is_too_sparse(mock_send, spark_session, fake_dbutils):
    """Fewer than min_reference_weeks present -> no baseline -> a newly launched
    app cannot fire."""
    table = _register_table(
        spark_session,
        _counts(
            {
                "newcomer": {
                    "current": 50,
                    "previous": 1000,
                    "refs": [None, 1000],
                }
            }
        ),
    )

    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_minimum_baseline_ignores_single_anomalous_reference_week(
    mock_send, spark_session, fake_dbutils
):
    """One spiked reference week must not drag the expectation up. This is the
    false-positive mode the previous single-week comparison suffered from, and
    with two samples a median would just average the spike in (baseline 10500,
    making the healthy 900 look like a 91% drop). The minimum ignores the spike
    entirely: baseline 1000, current 900, no alert."""
    table = _register_table(
        spark_session,
        _counts(
            {
                "monopoly": {
                    "current": 900,
                    "previous": 950,
                    "refs": [1000, 20000],
                }
            }
        ),
    )

    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_vanished_app_reported_in_stopped_section(
    mock_send, spark_session, fake_dbutils
):
    """An app that stops emitting outright is reported, but in its own section so
    a decommission reads as a decommission rather than as data loss."""
    table = _register_table(
        spark_session,
        _counts(
            {
                "monopoly": {"current": 0, "previous": 1000, "refs": [1000] * 2},
                "customer": {"current": 740, "previous": 740, "refs": [740] * 2},
            }
        ),
    )

    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_called_once()
    content = mock_send.call_args.args[0].content
    assert "stopped emitting entirely" in content
    assert "monopoly" in content


@patch(f"{MODULE}.GChatService.send_message")
def test_sustained_drop_is_reported_only_once(mock_send, spark_session, fake_dbutils):
    """Regression guard for the reason this monitor was rewritten: an app that is
    already unhealthy in the previous hour -- a retired service, a permanent
    traffic shift -- must not re-alert every hour until its baseline catches up."""
    table = _register_table(
        spark_session,
        _counts(
            {
                "retired": {
                    "current": 0,
                    "previous": 0,
                    "refs": [1000] * 2,
                    "prev_refs": [1000] * 2,
                },
                # Keeps the hour non-empty so this exercises the per-app rule and
                # not the (deliberately not edge-triggered) total-volume guard.
                "customer": {"current": 740, "previous": 740, "refs": [740] * 2},
            }
        ),
    )

    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_null_app_grouped_into_unknown_bucket(mock_send, spark_session, fake_dbutils):
    """Rows with no app label are still watched, under the (unknown) bucket."""
    table = _register_table(
        spark_session,
        _counts({None: {"current": 100, "previous": 1000, "refs": [1000] * 2}}),
    )

    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_called_once()
    content = mock_send.call_args.args[0].content
    assert volume_drop_monitor.UNKNOWN_APP in content


@patch(f"{MODULE}.GChatService.send_message")
def test_empty_hour_triggers_total_volume_line(mock_send, spark_session, fake_dbutils):
    """No records at all for the loaded hour is the total-loss case and must be
    called out explicitly, not just as a list of per-app drops."""
    table = _register_table(
        spark_session,
        _counts({"monopoly": {"current": 0, "previous": 1000, "refs": [1000] * 2}}),
    )

    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_called_once()
    content = mock_send.call_args.args[0].content
    assert "No records at all were loaded for this hour" in content


@patch(f"{MODULE}.GChatService.send_message")
def test_tz_aware_loaded_hour_is_normalised(mock_send, spark_session, fake_dbutils):
    """The spark jobs pass Airflow's `{{ ts }}`, which parses to a tz-aware datetime,
    while the partition columns rebuild a naive one. An un-normalised anchor is equal
    to no hour at all, so every count reads as zero and a perfectly healthy hour is
    reported as a total stream loss -- on every run. The fixture here is the one from
    test_no_alert_on_healthy_hour; only the anchor differs."""
    table = _register_table(
        spark_session,
        _counts({"monopoly": {"current": 980, "previous": 1010, "refs": [1000] * 2}}),
    )

    _run(
        spark_session,
        table,
        loaded_hour=LOADED_HOUR.replace(tzinfo=timezone.utc),
        dbutils=fake_dbutils,
    )

    mock_send.assert_not_called()


@patch(f"{MODULE}.LOGGER")
@patch(f"{MODULE}.GChatService.send_message")
def test_no_alert_when_every_requested_hour_is_empty(
    mock_send, mock_logger, spark_session, fake_dbutils
):
    """The loaded hour and every reference week coming back empty together is a
    failed read, not weeks of simultaneous outage. Alerting on it would let any
    wiring error page on every run, which is the one thing the total-volume guard must
    not do given it is deliberately not edge-triggered."""
    table = _register_table(spark_session, _counts({}), name="empty_access_logs")

    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_not_called()
    warnings = [call.args[0] for call in mock_logger.warning.call_args_list]
    assert any("failed read" in message for message in warnings)


@patch(f"{MODULE}.GChatService.send_message")
def test_weekend_hour_is_evaluated(mock_send, spark_session, fake_dbutils):
    """The previous check short-circuited to pass on weekends. Comparing against
    the same hour on preceding weeks keeps weekends comparable, so they are now
    covered."""
    table = _register_table(
        spark_session,
        _counts(
            {"monopoly": {"current": 100, "previous": 1000, "refs": [1000] * 2}},
            loaded_hour=SATURDAY_HOUR,
        ),
    )

    _run(spark_session, table, loaded_hour=SATURDAY_HOUR, dbutils=fake_dbutils)

    mock_send.assert_called_once()


@patch(f"{MODULE}.GChatService.send_message")
def test_routes_to_the_requested_channel(mock_send, spark_session, fake_dbutils):
    table = _register_table(
        spark_session,
        _counts({"monopoly": {"current": 100, "previous": 1000, "refs": [1000] * 2}}),
    )

    _run(spark_session, table, dbutils=fake_dbutils, channel="AUTHX_ALERTS")

    fake_dbutils.secrets.get.assert_called_once_with(
        scope="quintoandar", key=AUTHX_SECRET_KEY
    )
    mock_send.assert_called_once()


@patch(f"{MODULE}.GChatService.send_message")
def test_routes_to_the_default_channel_when_none_given(
    mock_send, spark_session, fake_dbutils
):
    table = _register_table(
        spark_session,
        _counts({"monopoly": {"current": 100, "previous": 1000, "refs": [1000] * 2}}),
    )

    _run(spark_session, table, dbutils=fake_dbutils)

    fake_dbutils.secrets.get.assert_called_once_with(
        scope="quintoandar", key=DEFAULT_SECRET_KEY
    )


@patch(f"{MODULE}.GChatService.send_message")
def test_falls_back_to_default_channel_when_primary_secret_missing(
    mock_send, spark_session, fake_dbutils
):
    """A missing team secret must degrade to the shared data-quality channel rather
    than dropping the alert."""

    def secret_side_effect(scope, key):
        if key == AUTHX_SECRET_KEY:
            raise KeyError("secret not found")
        return "https://chat.googleapis.com/fallback-webhook"

    fake_dbutils.secrets.get.side_effect = secret_side_effect
    table = _register_table(
        spark_session,
        _counts({"monopoly": {"current": 100, "previous": 1000, "refs": [1000] * 2}}),
    )

    _run(spark_session, table, dbutils=fake_dbutils, channel="AUTHX_ALERTS")

    fake_dbutils.secrets.get.assert_any_call(scope="quintoandar", key=AUTHX_SECRET_KEY)
    fake_dbutils.secrets.get.assert_any_call(
        scope="quintoandar", key=DEFAULT_SECRET_KEY
    )
    mock_send.assert_called_once()
    assert (
        mock_send.call_args.args[0].destination
        == "https://chat.googleapis.com/fallback-webhook"
    )


@patch(f"{MODULE}._resolve_dbutils")
@patch(f"{MODULE}.GChatService.send_message")
def test_dbutils_resolved_only_when_alerting(
    mock_send, mock_resolve, spark_session, fake_dbutils
):
    """Resolving dbutils builds a Spark context, so it must stay off the healthy
    path and only happen once an alert is about to be sent."""
    mock_resolve.return_value = fake_dbutils

    healthy = _register_table(
        spark_session,
        _counts({"monopoly": {"current": 980, "previous": 1000, "refs": [1000] * 2}}),
        name="healthy_access_logs",
    )
    _run(spark_session, healthy)
    mock_resolve.assert_not_called()

    dropped = _register_table(
        spark_session,
        _counts({"monopoly": {"current": 100, "previous": 1000, "refs": [1000] * 2}}),
        name="dropped_access_logs",
    )
    _run(spark_session, dropped)
    mock_resolve.assert_called_once()
    mock_send.assert_called_once()


@patch(f"{MODULE}.LOGGER")
@patch(f"{MODULE}.GChatService.send_message", return_value=False)
def test_failed_delivery_logged_as_warning_not_success(
    mock_send, mock_logger, spark_session, fake_dbutils
):
    """GChatService.send_message swallows HTTP errors and returns False; a False
    return must be logged as a delivery failure, never as a successful send."""
    table = _register_table(
        spark_session,
        _counts({"monopoly": {"current": 100, "previous": 1000, "refs": [1000] * 2}}),
    )

    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_called_once()
    warnings = [call.args[0] for call in mock_logger.warning.call_args_list]
    assert any("delivery failed" in message for message in warnings)
    infos = [call.args[0] for call in mock_logger.info.call_args_list]
    assert not any("alert sent" in message for message in infos)


@patch(f"{MODULE}.LOGGER")
@patch(f"{MODULE}.GChatService.send_message")
def test_never_raises_when_the_read_fails(
    mock_send, mock_logger, spark_session, fake_dbutils
):
    """Monitoring must never break the load: an unreadable table degrades to a
    logged warning."""
    _run(spark_session, "does_not_exist", dbutils=fake_dbutils)

    mock_send.assert_not_called()
    warnings = [call.args[0] for call in mock_logger.warning.call_args_list]
    assert any("Failed to evaluate or send" in message for message in warnings)


@patch(f"{MODULE}.GChatService.send_message", side_effect=RuntimeError("boom"))
def test_never_raises_when_sending_fails(mock_send, spark_session, fake_dbutils):
    table = _register_table(
        spark_session,
        _counts({"monopoly": {"current": 100, "previous": 1000, "refs": [1000] * 2}}),
    )

    # Should not raise despite send_message blowing up.
    _run(spark_session, table, dbutils=fake_dbutils)

    mock_send.assert_called_once()
