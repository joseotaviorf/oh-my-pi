import os
from unittest.mock import patch

import pytest

from bietlejuice.services.cdf_services.cdf_to_kafka_config import CDFToKafkaConfig


class TestCDFToKafkaConfig:
    """Unit tests for CDFToKafkaConfig class."""

    def test_use_schema_registry_default_false(self):
        """Test that use_schema_registry defaults to False when env var not set."""
        config = CDFToKafkaConfig()

        assert config.use_schema_registry is False

    @pytest.mark.parametrize(
        "env_value,expected",
        [
            ("true", True),
            ("True", True),
            ("TRUE", True),
            ("false", False),
            ("1", False),
            ("0", False),
            ("yes", False),
            ("no", False),
            ("on", False),
            ("off", False),
            ("invalid", False),
            ("", False),
        ],
    )
    def test_use_schema_registry_with_env_var(self, env_value, expected, monkeypatch):
        """Test use_schema_registry with various environment variable values."""
        monkeypatch.setenv("CDF_TO_KAFKA_USE_SCHEMA_REGISTRY", env_value)
        config = CDFToKafkaConfig()
        assert config.use_schema_registry is expected

    @pytest.mark.parametrize(
        "env_var,attr_name,value,expected",
        [
            (
                "SCHEMA_REGISTRY_URL",
                "schema_registry_url",
                "http://test-registry:8081",
                "http://test-registry:8081",
            ),
            ("SCHEMA_REGISTRY_URL", "schema_registry_url", None, None),
            (
                "CDF_TO_KAFKA_SCHEMA_REGISTRY_KEY",
                "schema_registry_api_key",
                "test-api-key",
                "test-api-key",
            ),
            ("CDF_TO_KAFKA_SCHEMA_REGISTRY_KEY", "schema_registry_api_key", None, None),
            (
                "CDF_TO_KAFKA_SCHEMA_REGISTRY_SECRET",
                "schema_registry_api_secret",
                "test-api-secret",
                "test-api-secret",
            ),
            (
                "CDF_TO_KAFKA_SCHEMA_REGISTRY_SECRET",
                "schema_registry_api_secret",
                None,
                None,
            ),
        ],
    )
    def test_schema_registry_properties(
        self, env_var, attr_name, value, expected, monkeypatch
    ):
        """Test schema registry URL, API key, and secret properties."""
        if value is not None:
            monkeypatch.setenv(env_var, value)

        config = CDFToKafkaConfig()
        assert getattr(config, attr_name) == expected

    @patch.dict(
        os.environ,
        {
            "CDF_TO_KAFKA_USE_SCHEMA_REGISTRY": "true",
            "SCHEMA_REGISTRY_URL": "http://test-registry:8081",
            "CDF_TO_KAFKA_SCHEMA_REGISTRY_KEY": "test-key",
            "CDF_TO_KAFKA_SCHEMA_REGISTRY_SECRET": "test-secret",
        },
    )
    def test_complete_config_with_schema_registry_enabled(self):
        """Test complete configuration when schema registry is enabled."""
        config = CDFToKafkaConfig()

        assert config.use_schema_registry is True
        assert config.schema_registry_url == "http://test-registry:8081"
        assert config.schema_registry_api_key == "test-key"
        assert config.schema_registry_api_secret == "test-secret"

    @patch.dict(os.environ, {"CDF_TO_KAFKA_USE_SCHEMA_REGISTRY": "false"})
    def test_complete_config_with_schema_registry_disabled(self):
        """Test complete configuration when schema registry is disabled."""
        config = CDFToKafkaConfig()

        assert config.use_schema_registry is False
        # Even when disabled, the properties still return env var values or None
        assert config.schema_registry_url is None
        assert config.schema_registry_api_key is None
        assert config.schema_registry_api_secret is None
