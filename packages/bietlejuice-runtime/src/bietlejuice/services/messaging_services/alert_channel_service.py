import logging

from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum


class AlertChannelService:
    """
    Service to resolve an alert channel keyword into a webhook URL
    by fetching it from Databricks Secrets.
    """

    def __init__(self, dbutils, scope="quintoandar"):
        if not dbutils:
            raise ValueError("DBUtils instance is required to fetch secrets.")
        self.dbutils = dbutils
        self.scope = scope

    def get_gchat_webhook_url(
        self, channel_keyword: str, default_keyword: str = None
    ) -> str:
        """
        Gets the Google Chat webhook URL based on a keyword, with a configurable fallback.

        This method attempts to resolve the primary `channel_keyword`. If it fails
        (either the keyword is invalid or the secret cannot be fetched), it will
        then attempt to use the `default_keyword`.

        Args:
            channel_keyword (str): The primary keyword for the channel.
            default_keyword (str, optional): The fallback keyword to use if the
                                             primary one fails. Defaults to None.

        Returns:
            str: The full webhook URL fetched from Databricks Secrets.

        Raises:
            Exception: If both the primary and default keywords fail to resolve
                       to a valid, fetchable secret.
        """
        keywords_to_try = [channel_keyword, default_keyword]
        last_exception = None

        for keyword in keywords_to_try:
            if not keyword:
                continue

            secret_key = GchatWebhooksEnum.get_secret_key(keyword)
            if not secret_key:
                logging.warning(
                    f"Keyword '{keyword}' is not a valid channel. Skipping."
                )
                continue

            try:
                webhook_url = self.dbutils.secrets.get(scope=self.scope, key=secret_key)
                logging.info(
                    f"Successfully fetched secret for keyword '{keyword}' (key: '{secret_key}')."
                )
                return webhook_url.strip()
            except Exception as e:
                last_exception = e
                logging.warning(
                    f"Could not fetch secret for keyword '{keyword}' (key: '{secret_key}'). "
                    f"Reason: {e}."
                )

        # If the loop finishes without returning, all attempts have failed.
        error_message = "Failed to retrieve webhook URL for all provided keywords."
        logging.error(error_message)
        if last_exception:
            raise Exception(error_message) from last_exception
        else:
            raise ValueError(
                error_message + " No valid keywords were provided or found."
            )

    @staticmethod
    def default_gsheets_alert_keyword(environment: str) -> str:
        """
        Return the AE alerts keyword used as fallback for gsheet ingestion failures.

        Args:
            environment: Pipeline environment name (``prod`` or forno-like).

        Returns:
            GchatWebhooksEnum attribute name for AE alerts in that environment.
        """
        return "AE_ALERTS_PROD" if environment == "prod" else "AE_ALERTS_FORNO"

    def get_gsheets_failure_webhook_url(
        self, environment: str, alert_channel: str = None
    ) -> str:
        """
        Resolve the Google Chat webhook for gsheet ingestion failure alerts.

        Prefers an optional DAG-declared ``alert_channel`` keyword and falls back
        to AE_ALERTS_PROD / AE_ALERTS_FORNO (ae-alerts-opsgenie) so existing
        behavior is preserved when the channel is omitted.

        Args:
            environment: Pipeline environment name (``prod`` or forno-like).
            alert_channel: Optional GchatWebhooksEnum keyword from the DAG declaration.

        Returns:
            Webhook URL string fetched from Databricks Secrets.
        """
        return self.get_gchat_webhook_url(
            channel_keyword=alert_channel or None,
            default_keyword=self.default_gsheets_alert_keyword(environment),
        )
