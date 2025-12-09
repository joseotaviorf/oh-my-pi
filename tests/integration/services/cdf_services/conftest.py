import os
import tempfile
from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest
from delta.tables import DeltaTable


from pyspark.sql import SparkSession


# Required Spark configuration for Wonka tests
spark_configs = {
    "spark.app.name": "pytest-spark",
    "spark.sql.session.timeZone": "UTC",
    "spark.sql.autoBroadcastJoinThreshold": "-1",
    "spark.executor.memory": "4g",
    "spark.executor.instances": "1",
    "spark.driver.memory": "4g",
    "spark.ui.enabled": "false",
    "spark.default.parallelism": "1",
    "spark.ui.showConsoleProgress": "false",
    "spark.driver.cores": "2",
    "spark.executor.cores": "2",
    "spark.debug.maxToStringFields": "100",
    "spark.sql.jsonGenerator.ignoreNullFields": "false",
    "spark.dynamicAllocation.enabled": "false",
    "spark.io.compression.codec": "lz4",
    "spark.rdd.compress": "false",
    "spark.shuffle.compress": "false",
    "spark.sql.shuffle.partitions": "1",
    "spark.sql.sources.partitionOverwriteMode": "dynamic",
    "spark.jars.packages": "io.delta:delta-spark_2.12:3.0.0,org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.1",
    "spark.sql.extensions": "io.delta.sql.DeltaSparkSessionExtension",
    "spark.sql.catalog.spark_catalog": "org.apache.spark.sql.delta.catalog.DeltaCatalog",
    "spark.sql.legacy.createHiveTableByDefault": "false",
}

@pytest.fixture
def kafka_container():
    """Kafka container for integration tests."""
    with KafkaContainer() as kafka_container:
        yield kafka_container


@pytest.fixture
def temp_delta_table_path():
    """Create a temporary directory for Delta table."""
    with tempfile.TemporaryDirectory() as temp_dir:
        yield temp_dir


@pytest.fixture
def temp_checkpoint_path(request):
    """Create a temporary directory for checkpoint location."""
    test_name = request.node.name
    with tempfile.TemporaryDirectory(suffix=f"_{test_name}") as temp_dir:
        yield temp_dir


@pytest.fixture
def table(spark_session, temp_delta_table_path, request):
    """Create sample data for testing."""
    table_name = f"test_table_{request.node.name}"

    print(f"Table name: {table_name}")

    spark_session.sql(f"DROP TABLE IF EXISTS {table_name}")

    data = [
        (1, "Alice", "alice@example.com", datetime.now()),
        (2, "Bob", "bob@example.com", datetime.now()),
        (3, "Charlie", "charlie@example.com", datetime.now()),
    ]

    df = spark_session.createDataFrame(data, ["id", "name", "email", "created_at"])
    table_path = os.path.join(temp_delta_table_path, table_name)
    df.write.format("delta").option("delta.enableChangeDataFeed", "true").save(
        table_path
    )

    spark_session.sql(f"CREATE TABLE {table_name} USING DELTA LOCATION '{table_path}'")

    yield table_name

    spark_session.sql(f"DROP TABLE IF EXISTS {table_name}")


@pytest.fixture
def updated_table(spark_session, table):
    """Update a record in the table."""
    source = spark_session.createDataFrame(
        [(1, "john", "john@example.com", datetime.now())],
        ["id", "name", "email", "created_at"],
    )

    DeltaTable.forName(spark_session, table).alias("target").merge(
        source.alias("source"), "target.id = source.id"
    ).whenMatchedUpdateAll().execute()

    return source


@pytest.fixture
def deleted_table(spark_session, table, updated_table):
    """Delete a record from the table."""
    DeltaTable.forName(spark_session, table).alias("target").merge(
        spark_session.createDataFrame([(2,)], ["id"]).alias("source"),
        "target.id = source.id",
    ).whenMatchedDelete().execute()

    return table


@pytest.fixture
def kafka_options(kafka_container, request):
    """Kafka options for testing."""
    test_name = request.node.name
    return {
        "topic": f"test-cdf-topic-{test_name}",
        "kafka.bootstrap.servers": kafka_container.get_bootstrap_server(),
    }


@pytest.fixture
def schema_registry_config():
    """Schema Registry configuration for testing."""
    return {
        "url": "http://mock-schema-registry:8081",
        "api_key": "test-key",
        "api_secret": "test-secret",
    }


@pytest.fixture
def mock_schema_registry():
    """Mock schema registry session for wire format tests."""
    with patch(
        "quintoandar.wonka.services.schema_registry._create_session_with_retry"
    ) as mock_session_factory:
        mock_session = MagicMock()
        mock_session.post.return_value = MagicMock(
            status_code=201, json=lambda: {"id": 1}
        )
        mock_session_factory.return_value = mock_session
        yield mock_session_factory


@pytest.fixture(scope="session")
def spark_context(request):
    """
    Fixture that provides a configured SparkContext using the configurations
    specified in the user's request.
    """

    builder = SparkSession.builder
    for key, value in spark_configs.items():
        builder.config(key=key, value=value)

    session = builder.getOrCreate()

    sc = session.sparkContext

    yield sc

    session.stop()


@pytest.fixture(scope="session")
def spark_session(request):
    """
    Fixture that provides a configured SparkSession using the configurations
    specified in the user's request.
    """

    builder = SparkSession.builder
    for key, value in spark_configs.items():
        builder.config(key=key, value=value)

    session = builder.getOrCreate()

    yield session

    session.stop()
