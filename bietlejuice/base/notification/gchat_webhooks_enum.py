from typing import Optional


class GchatWebhooksEnum:
    """
    Mapping of human-readable channel names to their corresponding secret keys in Databricks Secrets.
    The value of each attribute is the 'key' within the 'quintoandar' scope.
    This class also handles legacy or alternative keywords.
    """

    # --- Standard Channel Mappings ---
    AE_ALERTS_PROD = "GCHAT_AE_ALERTS_PROD_WEBHOOK"
    AE_ALERTS_FORNO = "GCHAT_AE_ALERTS_FORNO_WEBHOOK"
    DATA_QUALITY_DEFAULT = "GCHAT_DATA_QUALITY_WEBHOOK"
    DATA_ALERTS = "GCHAT_DATA_ALERTS_WEBHOOK"
    DATA_QUALITY_PROD = "GCHAT_DATA_QUALITY_PROD_WEBHOOK"
    DATA_QUALITY_FORNO = "GCHAT_DATA_QUALITY_FORNO_WEBHOOK"
    GCHAT_SCHEMA_CHANGES = "GCHAT_SCHEMA_CHANGES_WEBHOOK"
    GCHAT_CDC_METRICS = "GCHAT_CDC_METRICS_WEBHOOK"
    GCHAT_CDC_EBDB_ALERTS = "GCHAT_EBDB_ALERTS_WEBHOOK"
    FINTECH_ALERTS_PROD = "GCHAT_FINTECH_ALERTS_PROD_WEBHOOK"
    GCHAT_CORE_MODEL_SCHEMA_VALIDATION = "CORE_MODEL_WEBHOOK"
    PEOPLE_ALERTS = "GCHAT_PEOPLE_ALERTS_WEBHOOK"
    DATA_ALARMS = "GCHAT_DATA_ALARMS_WEBHOOK"
    DATA_AGENTS_ALERTS = "GCHAT_DATA_AGENTS_ALARMS_WEBHOOK"

    # --- Alias mapping for legacy or alternative names ---
    _ALIAS_MAP = {
        "#alerts-de-airflow-dags": DATA_QUALITY_DEFAULT,
        "#alerts-data-quality": DATA_QUALITY_DEFAULT,
        "#data-alarms": DATA_ALARMS,
        "#alerts-data-quality-agents": DATA_AGENTS_ALERTS,
    }

    @classmethod
    def get_secret_key(cls, channel_keyword: str) -> Optional[str]:
        """
        Safely gets the secret key for a given channel keyword. It checks for aliases first,
        then for direct attributes.

        Args:
            channel_keyword (str): The human-readable name of the channel from the YAML file.

        Returns:
            str | None: The corresponding secret key to be used with Databricks Secrets,
                        or None if the keyword is not found, empty or invalid.
        """
        if not channel_keyword:
            return None

        # 1. Check if the keyword is an alias (e.g., for legacy values)
        if channel_keyword in cls._ALIAS_MAP:
            return cls._ALIAS_MAP[channel_keyword]

        # 2. Check if the keyword corresponds to a class attribute
        return getattr(cls, channel_keyword.upper(), None)
