"""Unit tests for AlertChannelService webhook resolution."""

from unittest.mock import MagicMock

import pytest

from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.services.messaging_services.alert_channel_service import (
    AlertChannelService,
)


class TestAlertChannelService:
    def test_resolves_primary_keyword_from_secrets(self):
        dbutils = MagicMock()
        dbutils.secrets.get.return_value = " https://hooks.example/primary "

        service = AlertChannelService(dbutils=dbutils)
        url = service.get_gchat_webhook_url(
            channel_keyword="PEOPLE_ALERTS",
            default_keyword="AE_ALERTS_PROD",
        )

        assert url == "https://hooks.example/primary"
        dbutils.secrets.get.assert_called_once_with(
            scope="quintoandar",
            key=GchatWebhooksEnum.PEOPLE_ALERTS,
        )

    def test_falls_back_to_default_keyword_when_primary_secret_missing(self):
        dbutils = MagicMock()

        def _get_secret(scope, key):
            if key == GchatWebhooksEnum.PEOPLE_ALERTS:
                raise Exception("secret not found")
            if key == GchatWebhooksEnum.AE_ALERTS_PROD:
                return "https://hooks.example/ae-alerts"
            raise AssertionError(f"unexpected key: {key}")

        dbutils.secrets.get.side_effect = _get_secret

        service = AlertChannelService(dbutils=dbutils)
        url = service.get_gchat_webhook_url(
            channel_keyword="PEOPLE_ALERTS",
            default_keyword="AE_ALERTS_PROD",
        )

        assert url == "https://hooks.example/ae-alerts"

    def test_uses_default_when_primary_keyword_is_none(self):
        dbutils = MagicMock()
        dbutils.secrets.get.return_value = "https://hooks.example/ae-forno"

        service = AlertChannelService(dbutils=dbutils)
        url = service.get_gchat_webhook_url(
            channel_keyword=None,
            default_keyword="AE_ALERTS_FORNO",
        )

        assert url == "https://hooks.example/ae-forno"
        dbutils.secrets.get.assert_called_once_with(
            scope="quintoandar",
            key=GchatWebhooksEnum.AE_ALERTS_FORNO,
        )

    def test_raises_when_all_keywords_fail(self):
        dbutils = MagicMock()
        dbutils.secrets.get.side_effect = Exception("secret missing")

        service = AlertChannelService(dbutils=dbutils)
        with pytest.raises(Exception, match="Failed to retrieve webhook URL"):
            service.get_gchat_webhook_url(
                channel_keyword="PEOPLE_ALERTS",
                default_keyword="AE_ALERTS_PROD",
            )


class TestGsheetsFailureWebhookResolution:
    def test_default_keyword_prod(self):
        assert (
            AlertChannelService.default_gsheets_alert_keyword("prod")
            == "AE_ALERTS_PROD"
        )

    def test_default_keyword_forno(self):
        assert (
            AlertChannelService.default_gsheets_alert_keyword("forno")
            == "AE_ALERTS_FORNO"
        )

    def test_prefers_declared_alert_channel(self):
        dbutils = MagicMock()
        dbutils.secrets.get.return_value = "https://hooks.example/people"

        service = AlertChannelService(dbutils=dbutils)
        url = service.get_gsheets_failure_webhook_url(
            environment="prod",
            alert_channel="PEOPLE_ALERTS",
        )

        assert url == "https://hooks.example/people"
        dbutils.secrets.get.assert_called_once_with(
            scope="quintoandar",
            key=GchatWebhooksEnum.PEOPLE_ALERTS,
        )

    def test_falls_back_to_ae_alerts_when_channel_omitted(self):
        dbutils = MagicMock()
        dbutils.secrets.get.return_value = "https://hooks.example/ae-forno"

        service = AlertChannelService(dbutils=dbutils)
        url = service.get_gsheets_failure_webhook_url(
            environment="forno",
            alert_channel=None,
        )

        assert url == "https://hooks.example/ae-forno"
        dbutils.secrets.get.assert_called_once_with(
            scope="quintoandar",
            key=GchatWebhooksEnum.AE_ALERTS_FORNO,
        )
