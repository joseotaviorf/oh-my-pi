import mock
import pytest

from bietlejuice.services.configuration_service import ConfigurationService
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
@mock.patch.object(ConfigurationService, "_load_configurations_from_files")
@mock.patch.object(ConfigurationService, "_get_configuration_files")
@mock.patch.object(ConfigurationService, "_get_environment")
def configuration_service(
    mock__get_environment,
    mock__get_configuration_files,
    mock__load_configurations_from_files,
):
    configuration_service = ConfigurationService()

    return configuration_service


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
