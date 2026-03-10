"""
Pytest fixtures for core_region Spark job tests.
"""

import pytest
from unittest.mock import patch
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    TimestampType,
    LongType,
)
from datetime import datetime

from dags.core.core_region.spark_jobs.load_core_region import CoreRegionSparkJob


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreRegionTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def region_df(spark_session):
    """Create a sample region DataFrame for testing.

    Hierarchy:
      Cidade (id=5, id_state=10) ← root, ts_updated=2025-01-01
        MacroRegiao (id=3, id_parent_region=5) — ts_updated=2025-01-01
          SubRegiao  (id=1, id_parent_region=3) — ts_updated=2025-01-15 (recent)
          SubRegiao  (id=2, id_parent_region=3) — ts_updated=2025-01-20 (recent)
          SubRegiao  (id=4, id_parent_region=3) — ts_updated=2022-12-25 (old, for date-filter test)

    Parent rows (ids 3 and 5) must stay within the same date window as the SubRegiao rows
    so that the self-join can resolve the hierarchy even during incremental (date-filtered) loads.
    """
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_parent_region", LongType(), True),
            StructField("name", StringType(), True),
            StructField("level", StringType(), True),
            StructField("id_state", LongType(), True),
            StructField("ts_created", TimestampType(), True),
            StructField("ts_updated", TimestampType(), True),
        ]
    )

    data = [
        # Cidade — root of the hierarchy, carries id_state
        # ts_updated set to 2025-01-01 so it survives incremental date-filter tests
        (
            5,
            None,
            "São Paulo",
            "Cidade",
            10,
            datetime(2025, 1, 1, 0, 0),
            datetime(2025, 1, 1, 0, 0),
        ),
        # MacroRegiao — parent of the subregions
        # ts_updated set to 2025-01-01 so it survives incremental date-filter tests
        (
            3,
            5,
            "Zona Sul",
            "MacroRegiao",
            None,
            datetime(2025, 1, 1, 0, 0),
            datetime(2025, 1, 1, 0, 0),
        ),
        # SubRegiao — recent ts_updated (within typical date-filter window)
        (
            1,
            3,
            "Moema",
            "SubRegiao",
            None,
            datetime(2025, 1, 1, 10, 0),
            datetime(2025, 1, 15, 11, 0),
        ),
        # SubRegiao — recent ts_updated, has both RENT and SALE business contexts
        (
            2,
            3,
            "Ibirapuera",
            "SubRegiao",
            None,
            datetime(2025, 1, 2, 10, 0),
            datetime(2025, 1, 20, 11, 0),
        ),
        # SubRegiao — old ts_updated, used to assert date-filter exclusion
        (
            4,
            3,
            "Old Region",
            "SubRegiao",
            None,
            datetime(2022, 12, 25, 9, 0),
            datetime(2022, 12, 25, 10, 0),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def region_business_contexts_df(spark_session):
    """Create a sample region_business_context_served DataFrame for testing.

    - Region 1 (Moema): RENT only → has_rent_operation=True, has_sale_operation=False
    - Region 2 (Ibirapuera): both RENT and SALE → has_rent_operation=True, has_sale_operation=True
    """
    schema = StructType(
        [
            StructField("id_region", LongType(), True),
            StructField("business_context", StringType(), True),
        ]
    )

    data = [
        (1, "RENT"),
        (2, "RENT"),
        (2, "SALE"),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def state_df(spark_session):
    """Create a sample state DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("name", StringType(), True),
            StructField("abbreviation", StringType(), True),
            StructField("id_country", LongType(), True),
        ]
    )

    data = [
        (10, "São Paulo", "SP", 100),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def country_df(spark_session):
    """Create a sample country DataFrame for testing.

    Includes both 'code' (used in SELECT) and 'country_code' (used in the IS NOT NULL filter).
    """
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("code", StringType(), True),
            StructField("country_code", StringType(), True),
            StructField("name", StringType(), True),
            StructField("default_timezone", StringType(), True),
        ]
    )

    data = [
        (100, "BR", "BR", "Brasil", "America/Sao_Paulo"),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def country_df_with_null_code(spark_session):
    """Country DataFrame that includes a row with null country_code.

    Used to test that the IS NOT NULL filter removes unresolvable regions.
    """
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("code", StringType(), True),
            StructField("country_code", StringType(), True),
            StructField("name", StringType(), True),
            StructField("default_timezone", StringType(), True),
        ]
    )

    data = [
        (100, "BR", "BR", "Brasil", "America/Sao_Paulo"),
        (200, None, None, "Unknown", "UTC"),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def state_df_with_unknown(spark_session):
    """State DataFrame that includes a state pointing to the null-country row."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("name", StringType(), True),
            StructField("abbreviation", StringType(), True),
            StructField("id_country", LongType(), True),
        ]
    )

    data = [
        (10, "São Paulo", "SP", 100),
        (20, "Unknown State", "XX", 200),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def region_df_with_unknown_state(spark_session):
    """Region DataFrame that includes a Cidade linked to the unknown state.

    The 'unknown city' row should be filtered out by the country_code IS NOT NULL check.
    """
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("id_parent_region", LongType(), True),
            StructField("name", StringType(), True),
            StructField("level", StringType(), True),
            StructField("id_state", LongType(), True),
            StructField("ts_created", TimestampType(), True),
            StructField("ts_updated", TimestampType(), True),
        ]
    )

    data = [
        # Normal hierarchy
        (
            5,
            None,
            "São Paulo",
            "Cidade",
            10,
            datetime(2020, 1, 1),
            datetime(2020, 1, 1),
        ),
        (
            3,
            5,
            "Zona Sul",
            "MacroRegiao",
            None,
            datetime(2020, 6, 1),
            datetime(2020, 6, 1),
        ),
        (1, 3, "Moema", "SubRegiao", None, datetime(2025, 1, 1), datetime(2025, 1, 15)),
        # Cidade pointing to a state with null country_code → should be filtered out
        (
            9,
            None,
            "Unknown City",
            "Cidade",
            20,
            datetime(2020, 1, 1),
            datetime(2020, 1, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def business_unit_region_df(spark_session):
    """Create a sample business_unit_region DataFrame for testing.

    Region 1 (Moema) is linked to business unit 1000 → hub_name='Hub SP'.
    Region 2 (Ibirapuera) has no hub assignment → hub_name=null.
    """
    schema = StructType(
        [
            StructField("id_region", LongType(), True),
            StructField("id_business_unit", LongType(), True),
        ]
    )

    data = [
        (1, 1000),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def business_unit_df(spark_session):
    """Create a sample business_unit DataFrame for testing."""
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("hub_name", StringType(), True),
        ]
    )

    data = [
        (1000, "Hub SP"),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def mock_configuration_service():
    """Mock BaseCoreModelSparkJob.get_config to return core_region config values."""
    with patch(
        "bietlejuice.base.spark.base_core_model_spark_job.BaseCoreModelSparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = lambda key: {
            "ENTITY_TYPE": "REGION",
            "REGION_TABLE": "test.region",
            "REGION_BUSINESS_CONTEXTS_TABLE": "test.region_business_context_served",
            "STATE_TABLE": "test.state",
            "COUNTRY_TABLE": "test.country",
            "BUSINESS_UNIT_REGION_TABLE": "test.business_unit_region",
            "BUSINESS_UNIT_TABLE": "test.business_unit",
            "merge_on": ["id_region"],
            "when_matched_update_condition": "source.ts_updated > target.ts_updated",
            "z_order_by": ["id_region"],
            "partitions": ["year", "month", "day"],
        }.get(key)
        yield mock_get_config


@pytest.fixture
def mock_surrogate_keys_helper():
    """Mock SurrogateKeysHelper to add a deterministic surrogate_key column."""
    with patch(
        "dags.core.core_region.spark_jobs.load_core_region.SurrogateKeysHelper"
    ) as mock_helper:

        def generate_surrogate_key(df, entity_type, id_column="id_entity"):
            return df.withColumn("surrogate_key", df["id_region"].cast(StringType()))

        mock_helper.generate_surrogate_key.side_effect = generate_surrogate_key
        yield mock_helper


@pytest.fixture
def table_side_effect(
    region_df,
    region_business_contexts_df,
    state_df,
    country_df,
    business_unit_region_df,
    business_unit_df,
):
    """Return a callable that maps table names to their test DataFrames."""

    def side_effect(table_name):
        mapping = {
            "test.region": region_df,
            "test.region_business_context_served": region_business_contexts_df,
            "test.state": state_df,
            "test.country": country_df,
            "test.business_unit_region": business_unit_region_df,
            "test.business_unit": business_unit_df,
        }
        if table_name not in mapping:
            raise ValueError(f"Unknown table requested in test: {table_name}")
        return mapping[table_name]

    return side_effect


@pytest.fixture
def core_region_job(mock_configuration_service):
    """Create a CoreRegionSparkJob instance with mocked configuration."""
    return CoreRegionSparkJob()


@pytest.fixture
def core_model_df(
    spark_session,
    core_region_job,
    table_side_effect,
    mock_surrogate_keys_helper,
):
    """Execute create_core_model with a full load (no date filter) and return the result."""
    from argparse import Namespace

    with patch.object(spark_session, "table", side_effect=table_side_effect):
        return core_region_job.create_core_model(
            spark_session, Namespace(load_start_date=None, load_end_date=None)
        )
