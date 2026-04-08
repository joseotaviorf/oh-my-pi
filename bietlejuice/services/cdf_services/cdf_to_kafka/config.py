"""Configuration for CDF to Kafka service."""

import os
from typing import Optional


class CDFToKafkaConfig:
    """Configuration class for CDF to Kafka streaming service."""

    @property
    def use_schema_registry(self) -> bool:
        """Feature flag to control schema registry usage.

        When False, sends plain JSON to Kafka without wire format.
        When True, uses Confluent Schema Registry with wire format.

        Can be controlled via CDF_TO_KAFKA_USE_SCHEMA_REGISTRY environment variable.
        """
        env_value = os.getenv("CDF_TO_KAFKA_USE_SCHEMA_REGISTRY", "").lower()
        return env_value == "true"

    @property
    def schema_registry_url(self) -> Optional[str]:
        """Schema Registry URL. Required when use_schema_registry is True."""
        return os.getenv("SCHEMA_REGISTRY_URL")

    @property
    def schema_registry_api_key(self) -> Optional[str]:
        """Schema Registry API key. Required when use_schema_registry is True."""
        return os.getenv("CDF_TO_KAFKA_SCHEMA_REGISTRY_KEY")

    @property
    def schema_registry_api_secret(self) -> Optional[str]:
        """Schema Registry API secret. Required when use_schema_registry is True."""
        return os.getenv("CDF_TO_KAFKA_SCHEMA_REGISTRY_SECRET")

    @property
    def environment(self) -> str:
        """Current runtime environment. Defaults to 'dev' when not set."""
        return os.getenv("ENVIRONMENT", "dev")


config = CDFToKafkaConfig()
