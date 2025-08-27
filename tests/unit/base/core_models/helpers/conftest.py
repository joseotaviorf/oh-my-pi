import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, IntegerType


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("test_surrogate_keys")
        .master("local[*]")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .getOrCreate()
    )

    yield spark

    spark.stop()


@pytest.fixture
def sample_dataframe(spark_session):
    """Create a sample DataFrame for testing."""
    schema = StructType(
        [
            StructField("id_entity", StringType(), True),
            StructField("name", StringType(), True),
            StructField("value", IntegerType(), True),
        ]
    )

    data = [
        ("123", "test_name_1", 100),
        ("456", "test_name_2", 200),
        ("789", "test_name_3", 300),
    ]

    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def empty_dataframe(spark_session):
    """Create an empty DataFrame for testing."""
    schema = StructType(
        [
            StructField("id_entity", StringType(), True),
            StructField("name", StringType(), True),
        ]
    )

    return spark_session.createDataFrame([], schema)
