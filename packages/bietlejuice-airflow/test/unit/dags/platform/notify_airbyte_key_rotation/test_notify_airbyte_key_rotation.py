"""Unit tests for platform notify_airbyte_key_rotation DAG logic and structure."""

from unittest import mock

from dags.platform.notify_airbyte_key_rotation.notify_airbyte_key_rotation import (
    AIRBYTE_KEY_ROTATION_RUNBOOK_URL,
    GCHAT_AIRBYTE_KEY_ROTATION_WEBHOOK,
    _build_reminder_card,
    _environment_suffix_for_card,
    dag,
    notify_airbyte_key_rotation,
)


class TestBuildReminderCard:
    def test_build_reminder_card_contains_cards_v2_and_runbook(self):
        card = _build_reminder_card()
        assert "cardsV2" in card
        assert len(card["cardsV2"]) == 1
        inner_card = card["cardsV2"][0]["card"]
        assert "Airbyte Key Rotation Reminder" in inner_card["header"]["title"]
        assert "month-end" in inner_card["header"]["subtitle"]
        widgets = inner_card["sections"][0]["widgets"]
        assert AIRBYTE_KEY_ROTATION_RUNBOOK_URL in str(widgets)
        assert "Runbook: Rotate Airbyte Key" in str(widgets)


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

    def test_build_reminder_card_subtitle_includes_env_on_forno(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "forno")
        card = _build_reminder_card()
        subtitle = card["cardsV2"][0]["card"]["header"]["subtitle"]
        assert " · FORNO" in subtitle


class TestNotifyAirbyteKeyRotationCallable:
    @mock.patch(
        "dags.platform.notify_airbyte_key_rotation.notify_airbyte_key_rotation.requests.post"
    )
    @mock.patch(
        "dags.platform.notify_airbyte_key_rotation.notify_airbyte_key_rotation.Variable.get"
    )
    def test_skips_post_when_webhook_missing(self, mock_var_get, mock_post):
        mock_var_get.return_value = None

        notify_airbyte_key_rotation()

        mock_var_get.assert_called_once_with(
            GCHAT_AIRBYTE_KEY_ROTATION_WEBHOOK, default_var=None
        )
        mock_post.assert_not_called()

    @mock.patch(
        "dags.platform.notify_airbyte_key_rotation.notify_airbyte_key_rotation.requests.post"
    )
    @mock.patch(
        "dags.platform.notify_airbyte_key_rotation.notify_airbyte_key_rotation.Variable.get"
    )
    def test_posts_cards_payload_when_webhook_configured(self, mock_var_get, mock_post):
        mock_var_get.return_value = "https://chat.example.com/hook"
        mock_resp = mock.MagicMock()
        mock_resp.raise_for_status = mock.MagicMock()
        mock_post.return_value = mock_resp

        notify_airbyte_key_rotation()

        mock_var_get.assert_called_once_with(
            GCHAT_AIRBYTE_KEY_ROTATION_WEBHOOK, default_var=None
        )
        mock_post.assert_called_once()
        args, kwargs = mock_post.call_args
        assert args[0] == "https://chat.example.com/hook"
        assert "cardsV2" in kwargs["json"]
        mock_resp.raise_for_status.assert_called_once()


class TestNotifyAirbyteKeyRotationDAG:
    def test_dag_identity_and_tasks(self):
        assert dag.dag_id == "airflow.notify_airbyte_key_rotation"
        assert set(dag.task_ids) == {"notify_airbyte_key_rotation"}
        assert dag.schedule_interval == "0 10 20-30 * *"
        assert "monitoring" in dag.tags
        assert "airbyte" in dag.tags
