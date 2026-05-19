"""Unit tests for platform notify_stale_dags DAG logic and structure."""

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest import mock

import pytest

from dags.platform.notify_stale_dags.notify_stale_dags import (
    STALE_THRESHOLD_MONTHS,
    _build_card,
    _environment_suffix_for_card,
    _should_notify,
    dag,
    notify_stale_dags,
)

_MOCK_NOTIFICATION_WEBHOOK_KEYS = {
    "data_quality": "GCHAT_DATA_QUALITY_FORNO_WEBHOOK",
    "stale_dag": "GCHAT_STALE_DAG_WEBHOOK",
}


class TestShouldNotify:
    @pytest.mark.parametrize(
        "schedule_interval,dag_id,expected",
        [
            ("0 0 * * *", "domain.some_dag", True),
            ("Dataset", "domain.some_dag", False),
            (None, "domain.some_dag", False),
            ("null", "domain.some_dag", False),
            ("30 2 * * *", "quintoml.training", False),
        ],
    )
    def test_should_notify_rules(self, schedule_interval, dag_id, expected):
        row = SimpleNamespace(
            schedule_interval=schedule_interval,
            dag_id=dag_id,
        )
        assert _should_notify(row) is expected


class TestBuildCard:
    def test_build_card_contains_dag_and_cards_v2(self):
        ts = datetime(2024, 6, 15, 12, 0, 0, tzinfo=timezone.utc)
        rows = [
            SimpleNamespace(
                dag_id="acme.sample_dag",
                owners="data-team",
                schedule_interval="0 * * * *",
                ts_last_success=ts,
            )
        ]
        card = _build_card(rows)
        assert "cardsV2" in card
        assert len(card["cardsV2"]) == 1
        inner = card["cardsV2"][0]["card"]["sections"][0]
        assert "acme.sample_dag" in str(inner)
        assert str(STALE_THRESHOLD_MONTHS) in str(card)


class TestEnvironmentSuffixForCard:
    def test_forno_and_prod_suffix(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "forno")
        assert _environment_suffix_for_card() == " · FORNO"
        monkeypatch.setenv("ENVIRONMENT", "prod")
        assert _environment_suffix_for_card() == " · PROD"

    def test_empty_when_other_or_unset(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "local")
        assert _environment_suffix_for_card() == ""
        monkeypatch.delenv("ENVIRONMENT", raising=False)
        assert _environment_suffix_for_card() == ""

    def test_build_card_subtitle_includes_env_on_forno(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "forno")
        rows = [
            SimpleNamespace(
                dag_id="x",
                owners="o",
                schedule_interval="0 * * * *",
                ts_last_success=None,
            )
        ]
        card = _build_card(rows)
        subtitle = card["cardsV2"][0]["card"]["header"]["subtitle"]
        assert " · FORNO" in subtitle
        assert str(STALE_THRESHOLD_MONTHS) in subtitle


class TestNotifyStaleDagsCallable:
    @mock.patch("dags.platform.notify_stale_dags.notify_stale_dags.requests.post")
    @mock.patch("dags.platform.notify_stale_dags.notify_stale_dags.Variable.get")
    @mock.patch("dags.platform.notify_stale_dags.notify_stale_dags.ConfigurationService")
    def test_exits_early_when_no_notifiable_rows(
        self, mock_cfg_cls, mock_var_get, mock_post
    ):
        mock_cfg_cls.return_value.get_config.return_value = _MOCK_NOTIFICATION_WEBHOOK_KEYS
        mock_var_get.return_value = "https://chat.example.com/hook"
        mock_session = mock.MagicMock()
        mock_session.execute.return_value.fetchall.return_value = []

        notify_stale_dags(session=mock_session)

        mock_post.assert_not_called()

    @mock.patch("dags.platform.notify_stale_dags.notify_stale_dags.requests.post")
    @mock.patch("dags.platform.notify_stale_dags.notify_stale_dags.Variable.get")
    @mock.patch("dags.platform.notify_stale_dags.notify_stale_dags.ConfigurationService")
    def test_skips_post_when_webhook_missing_but_stale_rows_exist(
        self, mock_cfg_cls, mock_var_get, mock_post
    ):
        mock_cfg_cls.return_value.get_config.return_value = _MOCK_NOTIFICATION_WEBHOOK_KEYS
        mock_var_get.return_value = None
        mock_session = mock.MagicMock()
        stale = SimpleNamespace(
            dag_id="acme.stale_cron",
            owners="x",
            schedule_interval="0 0 * * *",
            fileloc="/p",
            ts_last_success=datetime(2019, 1, 1, tzinfo=timezone.utc),
        )
        mock_session.execute.return_value.fetchall.return_value = [stale]

        notify_stale_dags(session=mock_session)

        mock_post.assert_not_called()

    @mock.patch("dags.platform.notify_stale_dags.notify_stale_dags.requests.post")
    @mock.patch("dags.platform.notify_stale_dags.notify_stale_dags.Variable.get")
    @mock.patch("dags.platform.notify_stale_dags.notify_stale_dags.ConfigurationService")
    def test_posts_cards_payload_when_stale_and_webhook_configured(
        self, mock_cfg_cls, mock_var_get, mock_post
    ):
        mock_cfg_cls.return_value.get_config.return_value = _MOCK_NOTIFICATION_WEBHOOK_KEYS
        mock_var_get.return_value = "https://chat.example.com/hook"
        mock_resp = mock.MagicMock()
        mock_resp.raise_for_status = mock.MagicMock()
        mock_post.return_value = mock_resp

        mock_session = mock.MagicMock()
        stale = SimpleNamespace(
            dag_id="acme.stale_cron",
            owners="x",
            schedule_interval="0 0 * * *",
            fileloc="/p",
            ts_last_success=datetime(2019, 1, 1, tzinfo=timezone.utc),
        )
        mock_session.execute.return_value.fetchall.return_value = [stale]

        notify_stale_dags(session=mock_session)

        mock_post.assert_called_once()
        args, kwargs = mock_post.call_args
        assert args[0] == "https://chat.example.com/hook"
        assert "cardsV2" in kwargs["json"]
        mock_resp.raise_for_status.assert_called_once()


class TestNotifyStaleDagsDAG:
    def test_dag_identity_and_tasks(self):
        assert dag.dag_id == "airflow.notify_stale_dags"
        assert set(dag.task_ids) == {"notify_stale_dags"}
        assert "monitoring" in dag.tags
