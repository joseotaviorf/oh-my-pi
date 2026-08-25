from unittest import mock

import pytest

from bietlejuice.observability.monitoring import gchat_notify


class TestGchatNotify:
    @pytest.fixture
    def sample_finding(self):
        return {
            "signal_type": "empty_partition",
            "database": "datalake_enrich",
            "table": "fact_orders",
            "partition_fingerprint": "year=2026|month=8|day=4",
            "environment": "prod",
            "table_owner": "owner@example.com",
            "team_owner": "growth",
        }

    def test_notify_skips_send_on_dry_run(self, sample_finding):
        with mock.patch.object(
            gchat_notify.GChatService, "send_message"
        ) as send_message:
            gchat_notify.notify_empty_partition_findings(
                [sample_finding],
                environment="prod",
                gchat_webhook_url="https://webhook",
                dry_run=True,
            )

        send_message.assert_not_called()

    def test_notify_skips_send_on_forno_without_force_send(self, sample_finding):
        with mock.patch.object(
            gchat_notify.GChatService, "send_message"
        ) as send_message:
            gchat_notify.notify_empty_partition_findings(
                [sample_finding],
                environment="forno",
                gchat_webhook_url="https://webhook",
            )

        send_message.assert_not_called()

    def test_notify_sends_on_prod(self, sample_finding):
        with mock.patch.object(
            gchat_notify.GChatService, "send_message"
        ) as send_message:
            gchat_notify.notify_empty_partition_findings(
                [sample_finding],
                environment="prod",
                gchat_webhook_url="https://webhook",
            )

        send_message.assert_called_once()
        message = send_message.call_args.args[0]
        assert message.destination == "https://webhook"
        assert "empty_partition" in message.thread_key

    def test_notify_force_send_on_forno(self, sample_finding):
        with mock.patch.object(
            gchat_notify.GChatService, "send_message"
        ) as send_message:
            gchat_notify.notify_empty_partition_findings(
                [sample_finding],
                environment="forno",
                gchat_webhook_url="https://webhook",
                force_send="true",
            )

        send_message.assert_called_once()

    def test_notify_sends_stale_data_on_prod(self):
        finding = {
            "signal_type": "stale_data",
            "database": "datalake_example",
            "table": "example",
            "column": "ts_load",
            "max_age_hours": 36,
            "latest_data_at": None,
            "age_hours": None,
            "environment": "prod",
            "table_owner": "owner@example.com",
            "team_owner": "growth",
        }
        with mock.patch.object(
            gchat_notify.GChatService, "send_message"
        ) as send_message:
            gchat_notify.notify_observability_findings(
                [finding],
                environment="prod",
                gchat_webhook_url="https://webhook",
            )

        send_message.assert_called_once()
        message = send_message.call_args.args[0]
        assert "stale_data" in message.thread_key
        assert "ts_load" in message.thread_key

    def test_notify_skips_when_webhook_empty(self, sample_finding):
        with mock.patch.object(
            gchat_notify.GChatService, "send_message"
        ) as send_message:
            gchat_notify.notify_empty_partition_findings(
                [sample_finding],
                environment="prod",
                gchat_webhook_url="",
            )

        send_message.assert_not_called()
