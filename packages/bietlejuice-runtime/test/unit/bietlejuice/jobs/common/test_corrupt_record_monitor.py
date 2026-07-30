import json
from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.jobs.common import corrupt_record_monitor
from bietlejuice.jobs.common.corrupt_record_monitor import alert_on_corrupt_records

MODULE = "bietlejuice.jobs.common.corrupt_record_monitor"

AUTHX_SECRET_KEY = GchatWebhooksEnum.AUTHX_ALERTS
DEFAULT_SECRET_KEY = GchatWebhooksEnum.DATA_QUALITY_DEFAULT


def _valid_message(ts_field: str) -> str:
    return json.dumps({ts_field: "2026-06-16T12:00:00Z", "extra": "x"})


def _make_df(spark_session, good: int, corrupt: int, *, app: str = "monopoly"):
    """Build a raw-envelope DataFrame: `good` parseable rows + `corrupt` rows
    whose `message` is invalid JSON (so the inner timestamp probe returns null)."""
    rows = [(_valid_message("timestamp"), app) for _ in range(good)]
    rows += [("{not-json", app) for _ in range(corrupt)]
    return spark_session.createDataFrame(rows, ["message", "app"])


# Istio-proxy sidecar operational logs: plain text, not JSON objects. These are
# not access logs and must never be counted as corrupt/dropped records.
_NOISE_MESSAGES = [
    "2026-07-23T16:42:48.692369Z\tdebug\tenvoy wasm\twasm log ... finished",
    "2026-07-23T17:17:11.197518Z\tinfo\txdsproxy\tconnected to delta upstream XDS",
    "info\tcache\tRoot cert has changed, start rotating root cert",
]


# OPA logs its own server and bundle-plugin activity to the same stream as the
# decision logs: valid JSON objects carrying `msg`/`level` and no `timestamp`.
# They are not access logs, so they must not count as corrupt/dropped records.
_OPA_OPERATIONAL_MESSAGES = [
    json.dumps(
        {
            "level": "info",
            "msg": "Bundle loaded and activated successfully.",
            "plugin": "bundle",
            "time": "2026-06-16T12:00:00Z",
        }
    ),
    json.dumps(
        {
            "client_addr": "10.0.0.1",
            "level": "info",
            "msg": "Sent response.",
            "req_id": 7,
            "resp_status": 200,
            "time": "2026-06-16T12:00:00Z",
        }
    ),
]


def _make_operational_df(spark_session, operational: int, corrupt: int, *, app: str):
    """Build a raw-envelope DataFrame with `operational` OPA server/plugin rows
    (valid JSON, no timestamp) plus `corrupt` rows whose `message` is JSON-shaped
    but fails to parse (a truncated access log)."""
    rows = [
        (_OPA_OPERATIONAL_MESSAGES[i % len(_OPA_OPERATIONAL_MESSAGES)], app)
        for i in range(operational)
    ]
    rows += [("{not-json", app) for _ in range(corrupt)]
    return spark_session.createDataFrame(rows, ["message", "app"])


def _make_noisy_df(spark_session, noise: int, corrupt: int, *, app: str):
    """Build a raw-envelope DataFrame with `noise` plain-text sidecar rows (not
    JSON objects) plus `corrupt` rows whose `message` is JSON-shaped but fails to
    parse (a truncated/broken access log)."""
    rows = [(_NOISE_MESSAGES[i % len(_NOISE_MESSAGES)], app) for i in range(noise)]
    rows += [("{not-json", app) for _ in range(corrupt)]
    return spark_session.createDataFrame(rows, ["message", "app"])


@pytest.fixture
def fake_dbutils():
    dbutils = MagicMock()
    dbutils.secrets.get.return_value = "https://chat.googleapis.com/fake-webhook"
    return dbutils


@patch(f"{MODULE}.GChatService.send_message")
def test_no_alert_when_below_ratio_threshold(mock_send, spark_session, fake_dbutils):
    """Many good rows, few corrupt -> ratio under threshold -> no alert."""
    df = _make_df(spark_session, good=1000, corrupt=10)

    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="forno",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
    )

    mock_send.assert_not_called()
    fake_dbutils.secrets.get.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_no_alert_when_below_absolute_floor(mock_send, spark_session, fake_dbutils):
    """High ratio but tiny absolute count (< min_dropped) -> no alert."""
    df = _make_df(spark_session, good=5, corrupt=10)

    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="forno",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
    )

    mock_send.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_alert_uses_data_quality_channel_by_default(
    mock_send, spark_session, fake_dbutils
):
    """As a generic helper, the default channel is the shared data-quality channel
    (not a team channel) when no `channel` is passed."""
    df = _make_df(spark_session, good=100, corrupt=200)

    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
    )

    fake_dbutils.secrets.get.assert_called_once_with(
        scope="quintoandar", key=DEFAULT_SECRET_KEY
    )
    mock_send.assert_called_once()
    sent_message = mock_send.call_args.args[0]
    assert sent_message.destination == "https://chat.googleapis.com/fake-webhook"
    assert "datalake_access_logs_clean.opa" in sent_message.content
    assert "monopoly" in sent_message.content


@patch(f"{MODULE}.GChatService.send_message")
def test_alert_routes_to_team_channel_when_passed(
    mock_send, spark_session, fake_dbutils
):
    """A caller that owns the table (e.g. opa/istio loads) passes its own channel,
    which is used to resolve the webhook."""
    df = _make_df(spark_session, good=100, corrupt=200)

    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
        channel="AUTHX_ALERTS",
    )

    fake_dbutils.secrets.get.assert_called_once_with(
        scope="quintoandar", key=AUTHX_SECRET_KEY
    )
    mock_send.assert_called_once()


@patch(f"{MODULE}.GChatService.send_message")
def test_per_app_subset_trigger(mock_send, spark_session, fake_dbutils):
    """A small subset corruption on one app fires even when the GLOBAL ratio is
    well under the threshold (the exact gap from the postmortem)."""
    rows = [(_valid_message("timestamp"), "customer") for _ in range(10000)]
    rows += [(_valid_message("timestamp"), "monopoly") for _ in range(50)]
    rows += [("{not-json", "monopoly") for _ in range(200)]
    df = spark_session.createDataFrame(rows, ["message", "app"])

    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
    )

    mock_send.assert_called_once()
    sent_message = mock_send.call_args.args[0]
    assert "monopoly" in sent_message.content
    assert "customer" not in sent_message.content


@patch(f"{MODULE}.GChatService.send_message")
def test_falls_back_to_default_channel_when_primary_secret_missing(
    mock_send, spark_session, fake_dbutils
):
    """If the AUTHX secret is not provisioned, the alert must fall back to the
    data-quality default channel instead of being silently dropped."""

    def secret_side_effect(scope, key):
        if key == AUTHX_SECRET_KEY:
            raise KeyError("secret not found")
        return "https://chat.googleapis.com/fallback-webhook"

    fake_dbutils.secrets.get.side_effect = secret_side_effect
    df = _make_df(spark_session, good=100, corrupt=200)

    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
        channel="AUTHX_ALERTS",
    )

    fake_dbutils.secrets.get.assert_any_call(scope="quintoandar", key=AUTHX_SECRET_KEY)
    fake_dbutils.secrets.get.assert_any_call(
        scope="quintoandar", key=DEFAULT_SECRET_KEY
    )
    mock_send.assert_called_once()
    sent_message = mock_send.call_args.args[0]
    assert sent_message.destination == "https://chat.googleapis.com/fallback-webhook"


@patch(f"{MODULE}.GChatService.send_message")
def test_null_app_grouped_into_unknown_bucket(mock_send, spark_session, fake_dbutils):
    """Corrupt payloads on rows with no app label must still trigger, attributed to
    the (unknown) bucket."""
    rows = [(_valid_message("timestamp"), None) for _ in range(50)]
    rows += [("{not-json", None) for _ in range(200)]
    df = spark_session.createDataFrame(rows, "message STRING, app STRING")

    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
    )

    mock_send.assert_called_once()
    sent_message = mock_send.call_args.args[0]
    assert corrupt_record_monitor.UNKNOWN_APP in sent_message.content


@patch(f"{MODULE}.GChatService.send_message")
def test_uses_start_time_probe_for_istio(mock_send, spark_session, fake_dbutils):
    """Istio rows keyed on start_time still parse correctly with ts_field override."""
    rows = [(_valid_message("start_time"), "core") for _ in range(100)]
    rows += [("{broken", "core") for _ in range(200)]
    df = spark_session.createDataFrame(rows, ["message", "app"])

    alert_on_corrupt_records(
        df,
        ts_field="start_time",
        env="prod",
        table_name="datalake_access_logs_clean.istio",
        dbutils=fake_dbutils,
    )

    mock_send.assert_called_once()


@patch(f"{MODULE}.GChatService.send_message")
def test_no_alert_on_empty_dataframe(mock_send, spark_session, fake_dbutils):
    """Empty source partition -> nothing to evaluate, no alert, no raise."""
    df = spark_session.createDataFrame([], "message STRING, app STRING")

    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="forno",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
    )

    mock_send.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message", side_effect=RuntimeError("boom"))
def test_alerting_failure_never_raises(mock_send, spark_session, fake_dbutils):
    """A failure while sending must be swallowed so the load is never broken."""
    df = _make_df(spark_session, good=100, corrupt=200)

    # Should not raise despite send_message blowing up.
    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
    )

    mock_send.assert_called_once()


@patch(f"{MODULE}.LOGGER")
@patch(f"{MODULE}.GChatService.send_message", return_value=False)
def test_failed_delivery_logged_as_warning_not_success(
    mock_send, mock_logger, spark_session, fake_dbutils
):
    """GChatService.send_message swallows HTTP errors and returns False; a False
    return must be logged as a delivery failure, never as a successful send."""
    # arrange
    df = _make_df(spark_session, good=100, corrupt=200)

    # act
    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
    )

    # assert
    mock_send.assert_called_once()
    warnings = [call.args[0] for call in mock_logger.warning.call_args_list]
    assert any("delivery failed" in msg for msg in warnings)
    infos = [call.args[0] for call in mock_logger.info.call_args_list]
    assert not any("alert sent" in msg for msg in infos)


@patch(f"{MODULE}.GChatService.send_message")
def test_plain_text_sidecar_noise_never_alerts(mock_send, spark_session, fake_dbutils):
    """Sidecar operational lines (plain text, not JSON objects) are not access-log
    candidates: they must be excluded even when they dominate the volume."""
    # arrange
    rows = [
        (_NOISE_MESSAGES[i % len(_NOISE_MESSAGES)], "backoffice-bff")
        for i in range(5000)
    ]
    df = spark_session.createDataFrame(rows, ["message", "app"])

    # act
    alert_on_corrupt_records(
        df,
        ts_field="start_time",
        env="forno",
        table_name="datalake_access_logs_clean.istio",
        dbutils=fake_dbutils,
    )

    # assert
    mock_send.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_app_that_is_100_percent_sidecar_noise_never_alerts(
    mock_send, spark_session, fake_dbutils
):
    """An app whose entire stream is sidecar noise (the reported kodak-worker /
    seubarriga-worker-sqs shape) has zero access-log candidates -> no alert."""
    # arrange
    df = _make_noisy_df(spark_session, noise=400, corrupt=0, app="kodak-worker")

    # act
    alert_on_corrupt_records(
        df,
        ts_field="start_time",
        env="forno",
        table_name="datalake_access_logs_clean.istio",
        dbutils=fake_dbutils,
    )

    # assert
    mock_send.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_noise_excluded_from_ratio_denominator(mock_send, spark_session, fake_dbutils):
    """Only JSON-object candidates count toward total/dropped. A large volume of
    sidecar noise must not dilute the drop ratio of the real (broken) access logs:
    200 broken candidates out of 200 candidates -> 100% -> alert fires despite
    thousands of noise rows that would otherwise push the ratio well under 5%."""
    # arrange
    df = _make_noisy_df(spark_session, noise=10000, corrupt=200, app="monopoly")

    # act
    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.istio",
        dbutils=fake_dbutils,
    )

    # assert
    mock_send.assert_called_once()
    sent_message = mock_send.call_args.args[0]
    # 200 of 200 candidates (noise is neither numerator nor denominator).
    assert "200 of 200" in sent_message.content


@patch(f"{MODULE}.GChatService.send_message")
def test_noise_alongside_valid_access_logs_no_false_alert(
    mock_send, spark_session, fake_dbutils
):
    """Noise mixed with healthy access logs and only a handful of broken ones:
    the broken count stays under the absolute floor once noise is excluded, so no
    alert -- the noise neither triggers nor masks."""
    # arrange
    rows = [(_valid_message("start_time"), "backoffice-bff") for _ in range(2000)]
    rows += [("{broken", "backoffice-bff") for _ in range(10)]
    rows += [
        (_NOISE_MESSAGES[i % len(_NOISE_MESSAGES)], "backoffice-bff")
        for i in range(5000)
    ]
    df = spark_session.createDataFrame(rows, ["message", "app"])

    # act
    alert_on_corrupt_records(
        df,
        ts_field="start_time",
        env="forno",
        table_name="datalake_access_logs_clean.istio",
        dbutils=fake_dbutils,
    )

    # assert
    mock_send.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_opa_operational_json_logs_never_alert(mock_send, spark_session, fake_dbutils):
    """OPA server/bundle log lines are valid JSON without a `timestamp`, so the drop
    predicate alone would count them as corrupt. With `operational_log_field` they are
    excluded, even when they dominate an app's volume."""
    # arrange
    df = _make_operational_df(
        spark_session, operational=5000, corrupt=0, app="monopoly"
    )

    # act
    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
        operational_log_field="msg",
    )

    # assert
    mock_send.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_operational_logs_excluded_from_ratio_but_truncation_still_alerts(
    mock_send, spark_session, fake_dbutils
):
    """Truncation nulls every probe field, so a broken record has no `msg` and is
    still counted; the operational lines are excluded from both the numerator and the
    denominator, so they neither trigger nor mask."""
    # arrange
    df = _make_operational_df(
        spark_session, operational=5000, corrupt=200, app="monopoly"
    )

    # act
    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
        operational_log_field="msg",
    )

    # assert
    mock_send.assert_called_once()
    sent_message = mock_send.call_args.args[0]
    assert "200 of 200 dropped" in sent_message.content


@patch(f"{MODULE}.GChatService.send_message")
def test_operational_logs_counted_when_field_not_configured(
    mock_send, spark_session, fake_dbutils
):
    """Without `operational_log_field` the old behaviour is kept: valid JSON with no
    timestamp counts as dropped. Istio relies on this (its noise is plain text and is
    already excluded by the JSON-shape filter)."""
    # arrange
    df = _make_operational_df(
        spark_session, operational=5000, corrupt=0, app="monopoly"
    )

    # act
    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
    )

    # assert
    mock_send.assert_called_once()


@patch(f"{MODULE}._resolve_dbutils")
@patch(f"{MODULE}.GChatService.send_message")
def test_dbutils_resolved_on_demand_when_not_provided(
    mock_send, mock_resolve, spark_session
):
    """Callers do not have to resolve dbutils: it is fetched only when an alert is
    about to be sent, from inside the error boundary."""
    # arrange
    dbutils = MagicMock()
    dbutils.secrets.get.return_value = "https://chat.googleapis.com/lazy-webhook"
    mock_resolve.return_value = dbutils
    df = _make_df(spark_session, good=100, corrupt=200)

    # act
    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        channel="AUTHX_ALERTS",
    )

    # assert
    mock_resolve.assert_called_once()
    mock_send.assert_called_once()
    assert (
        mock_send.call_args.args[0].destination
        == "https://chat.googleapis.com/lazy-webhook"
    )


@patch(f"{MODULE}._resolve_dbutils")
@patch(f"{MODULE}.GChatService.send_message")
def test_dbutils_resolution_is_lazy_when_nothing_to_alert(
    mock_send, mock_resolve, spark_session
):
    """No alert, no dbutils: the happy path must not touch secrets at all."""
    # arrange
    df = _make_df(spark_session, good=1000, corrupt=10)

    # act
    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
    )

    # assert
    mock_resolve.assert_not_called()
    mock_send.assert_not_called()


@patch(f"{MODULE}._resolve_dbutils", side_effect=RuntimeError("no dbutils here"))
@patch(f"{MODULE}.GChatService.send_message")
def test_dbutils_resolution_failure_never_raises(
    mock_send, mock_resolve, spark_session
):
    """A runtime without dbutils must lose the alert, not the load."""
    # arrange
    df = _make_df(spark_session, good=100, corrupt=200)

    # act
    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
    )

    # assert
    mock_resolve.assert_called_once()
    mock_send.assert_not_called()


@patch(f"{MODULE}.GChatService.send_message")
def test_message_flags_apps_beyond_the_listed_limit(
    mock_send, spark_session, fake_dbutils
):
    """More offending apps than the message lists: the count and the omission must be
    explicit, and the combined figure must be labelled as such."""
    # arrange
    app_count = corrupt_record_monitor.TOP_APPS_LIMIT + 2
    rows = []
    for index in range(app_count):
        rows += [("{not-json", f"app-{index:02d}")] * 150
    df = spark_session.createDataFrame(rows, ["message", "app"])

    # act
    alert_on_corrupt_records(
        df,
        ts_field="timestamp",
        env="prod",
        table_name="datalake_access_logs_clean.opa",
        dbutils=fake_dbutils,
    )

    # assert
    mock_send.assert_called_once()
    content = mock_send.call_args.args[0].content
    assert f"*Apps over threshold:* {app_count} " in content
    assert "... and 2 more app(s)" in content
    assert "*All apps combined:*" in content
