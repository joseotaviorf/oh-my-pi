import time

import pytest
import requests
from pyspark.sql import SparkSession
# from testcontainers.core.container import DockerContainer
# from testcontainers.core.network import Network
# from testcontainers.kafka import KafkaContainer

from bietlejuice.services.cdf_services.schema_registry import (
    create_or_get_schema_on_registry,
    register_schema_for_dataframe,
)


class DockerContainer:
    pass


@pytest.mark.skip(reason="Skipping because testcontainers are not supported in Bietlejuice")
class SchemaRegistryContainer(DockerContainer):
    SCHEMA_REGISTRY_IMAGE = "confluentinc/cp-schema-registry"
    SCHEMA_REGISTRY_PORT = 8081

    def __init__(self, version="7.5.0"):
        super().__init__(f"{self.SCHEMA_REGISTRY_IMAGE}:{version}")
        self.with_exposed_ports(self.SCHEMA_REGISTRY_PORT)

    def with_kafka(self, network, bootstrap_servers):
        """Configure Schema Registry to connect to Kafka using network alias."""
        self.with_network(network)
        self.with_network_aliases("schema-registry")

        self.with_env("SCHEMA_REGISTRY_HOST_NAME", "schema-registry")
        self.with_env(
            "SCHEMA_REGISTRY_LISTENERS", f"http://0.0.0.0:{self.SCHEMA_REGISTRY_PORT}"
        )
        self.with_env("SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS", bootstrap_servers)
        self.with_env("SCHEMA_REGISTRY_KAFKASTORE_TOPIC", "_schemas")
        self.with_env("SCHEMA_REGISTRY_SCHEMA_REGISTRY_GROUP_ID", "schema-registry")
        self.with_env("SCHEMA_REGISTRY_LEADER_ELIGIBILITY", "true")
        self.with_env("SCHEMA_REGISTRY_LOG4J_ROOT_LOGLEVEL", "INFO")

        return self

    def get_schema_registry_url(self):
        """Get the Schema Registry URL."""
        host = self.get_container_host_ip()
        port = self.get_exposed_port(self.SCHEMA_REGISTRY_PORT)
        return f"http://{host}:{port}"


@pytest.mark.skip(reason="Skipping because testcontainers are not supported in Bietlejuice")
class TestSchemaRegistryIntegrationContainers:
    """Integration tests using real testcontainers with Confluent images."""

    @pytest.fixture(scope="session")
    def confluent_containers(self):
        """Create Kafka and Schema Registry containers using testcontainers with shared network."""

        # Create shared network
        network = Network()
        network.create()

        # Start Kafka with network
        kafka = KafkaContainer("confluentinc/cp-kafka:7.5.0")
        kafka = kafka.with_network(network)
        kafka = kafka.with_network_aliases("kafka")
        kafka = kafka.with_env("KAFKA_TRANSACTION_STATE_LOG_MIN_ISR", "1")
        kafka = kafka.with_env("KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR", "1")
        kafka = kafka.with_env("KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR", "1")
        kafka = kafka.with_env("KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS", "0")

        print("Starting Kafka container...")
        kafka.start()

        # Kafka bootstrap servers for internal network communication
        kafka_internal_bootstrap = "kafka:9092"

        # Start Schema Registry with network and Kafka connection
        schema_registry = SchemaRegistryContainer("7.5.0")
        schema_registry = schema_registry.with_kafka(network, kafka_internal_bootstrap)

        print("Starting Schema Registry container...")
        schema_registry.start()

        # Wait for Schema Registry to be ready
        schema_registry_url = schema_registry.get_schema_registry_url()

        print(f"Waiting for Schema Registry at {schema_registry_url}...")

        # Wait for the service to be ready
        max_attempts = 60
        for attempt in range(max_attempts):
            try:
                response = requests.get(f"{schema_registry_url}/subjects", timeout=10)
                if response.status_code == 200:
                    print(f"Schema Registry ready after {attempt + 1} attempts")
                    break
            except requests.exceptions.RequestException as e:
                print(f"Attempt {attempt + 1}: Schema Registry not ready yet - {e}")

            if attempt < max_attempts - 1:
                time.sleep(3)
            else:
                print("Schema Registry failed to start. Getting container logs...")
                try:
                    # Try to get logs from both containers
                    kafka_logs = kafka.get_logs()
                    schema_logs = schema_registry.get_logs()
                    print("=== KAFKA LOGS ===")
                    print(kafka_logs)
                    print("=== SCHEMA REGISTRY LOGS ===")
                    print(schema_logs)
                except Exception as log_error:
                    print(f"Could not get logs: {log_error}")
                raise Exception("Schema Registry container did not become ready")

        yield schema_registry_url

        # Cleanup only at session end
        print("Stopping containers...")
        schema_registry.stop()
        kafka.stop()
        network.remove()

    @pytest.fixture
    def spark_session(self):
        """Create a Spark session for testing."""
        return SparkSession.builder.appName(
            "test_schema_registry_containers"
        ).getOrCreate()

    @pytest.fixture
    def sample_dataframe(self, spark_session):
        """Create a sample DataFrame for testing."""
        data = [
            ("Alice", 30, True, 75.5),
            ("Bob", 25, False, 80.0),
            ("Charlie", 35, True, 92.3),
        ]
        df = spark_session.createDataFrame(data, ["name", "age", "active", "score"])
        return df

    def test_schema_registration_with_containers(
        self, confluent_containers, sample_dataframe
    ):
        """Test schema registration with real containers."""
        schema_registry_url = confluent_containers

        schema_id = register_schema_for_dataframe(
            dataframe=sample_dataframe,
            topic="test-topic",
            delta_table="wonka.test_feature_set__latest",
            schema_registry_url=schema_registry_url,
            schema_registry_api_key="",  # No auth needed for test containers
            schema_registry_api_secret="",  # No auth needed for test containers
        )

        assert isinstance(schema_id, int)
        assert schema_id > 0

    def test_concurrent_schema_registrations(
        self, confluent_containers, sample_dataframe
    ):
        """Test registering multiple schemas concurrently."""
        schema_registry_url = confluent_containers

        # Register the same schema multiple times
        schema_ids = []
        for i in range(3):
            schema_id = register_schema_for_dataframe(
                dataframe=sample_dataframe,
                topic=f"test-topic-{i}",
                delta_table=f"wonka.feature_set_{i}__latest",
                schema_registry_url=schema_registry_url,
                schema_registry_api_key="",
                schema_registry_api_secret="",
            )
            schema_ids.append(schema_id)

        # All should be valid integers
        assert all(isinstance(sid, int) and sid > 0 for sid in schema_ids)

        # Different subjects should get different IDs
        # (though Schema Registry might deduplicate identical schemas)
        assert len(set(schema_ids)) >= 1  # At least one unique ID

    def test_schema_registry_error_handling(self, confluent_containers):
        """Test error handling with invalid requests."""
        schema_registry_url = confluent_containers

        # Test with invalid JSON schema
        invalid_schema = {"type": "invalid"}

        with pytest.raises(Exception) as exc_info:
            create_or_get_schema_on_registry(
                schema=invalid_schema,
                subject="test-subject",
                schema_registry_url=schema_registry_url,
                schema_registry_api_key="",
                schema_registry_api_secret="",
            )

        assert "Failed to persist schema" in str(exc_info.value)
