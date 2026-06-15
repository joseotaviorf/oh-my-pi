"""Unit tests for load_cdf_to_datazord._get_kafka_credentials."""

import json
import sys
import unittest
from unittest.mock import MagicMock, patch

# Mock deps that require Spark/Databricks before importing the job.
MOCKED_MODULES = [
    "quintoandar_logger",
    "pyspark",
    "pyspark.sql",
    "bietlejuice.base.spark",
    "bietlejuice.base.spark.base_spark",
    "bietlejuice.base.spark.cluster_utils",
    "bietlejuice.base.spark.cluster_utils.factory",
    "bietlejuice.base.spark.runtime_detector",
    "bietlejuice.services.cdf_services.cdf_to_kafka.service",
]
for module in MOCKED_MODULES:
    sys.modules[module] = MagicMock()

from dags.cross.base.spark_jobs import load_cdf_to_datazord as job  # noqa: E402


class TestGetKafkaCredentialsEmr(unittest.TestCase):
    """EMR branch fetches both creds directly from Secrets Manager via boto3."""

    def test_fetches_from_secrets_manager(self):
        # Arrange
        mock_client = MagicMock()
        mock_client.get_secret_value.return_value = {
            "SecretString": json.dumps({"key": "the-key", "secret": "the-secret"}),
        }
        env = {"ENVIRONMENT": "forno"}
        with (
            patch.object(job.RuntimeDetector, "is_emr", return_value=True),
            patch.object(job.boto3, "client", return_value=mock_client),
            patch.dict("os.environ", env, clear=False),
        ):
            # Act
            key, secret = job._get_kafka_credentials()

        # Assert
        self.assertEqual((key, secret), ("the-key", "the-secret"))
        mock_client.get_secret_value.assert_called_once_with(
            SecretId="WONKA_CONFLUENT_KAFKA_API_KEY_FORNO"
        )


class TestGetKafkaCredentialsDatabricks(unittest.TestCase):
    """Non-EMR branch keeps reading the Vault-populated env vars, untouched."""

    def test_reads_from_env(self):
        # Arrange
        env = {"KAFKA_API_KEY": "env-key", "KAFKA_API_SECRET": "env-secret"}
        with (
            patch.object(job.RuntimeDetector, "is_emr", return_value=False),
            patch.dict("os.environ", env, clear=False),
        ):
            # Act
            key, secret = job._get_kafka_credentials()

        # Assert
        self.assertEqual((key, secret), ("env-key", "env-secret"))
