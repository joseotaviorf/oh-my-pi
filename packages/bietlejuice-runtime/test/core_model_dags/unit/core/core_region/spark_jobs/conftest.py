"""
Pytest fixtures for core_region Spark job tests.
"""

from datetime import datetime
from unittest.mock import patch

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

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

    Incremental window uses **ts_updated** (fallback ts_created). Hierarchy:
      Cidade (id=5) → MacroRegiao (id=3) → SubRegiao (ids 1, 2, 4).

    Rows 1,2,3,5 have ts_updated in Jan 2025; row 4 has ts_updated in 2022 (excluded from Jan window).
    ts_database_transaction may differ (e.g. row 6 in extended tests).
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
            StructField("ts_database_transaction", TimestampType(), True),
        ]
    )

    data = [
        # Cidade — root of the hierarchy, carries id_state
        # ts_database_transaction set to 2025-01-01 so it survives incremental date-filter tests
        (
            5,
            None,
            "São Paulo",
            "Cidade",
            10,
            datetime(2025, 1, 1, 0, 0),
            datetime(2025, 1, 1, 0, 0),
            datetime(2025, 1, 1, 0, 0),
        ),
        # MacroRegiao — parent of the subregions
        # ts_database_transaction set to 2025-01-01 so it survives incremental date-filter tests
        (
            3,
            5,
            "Zona Sul",
            "MacroRegiao",
            None,
            datetime(2025, 1, 1, 0, 0),
            datetime(2025, 1, 1, 0, 0),
            datetime(2025, 1, 1, 0, 0),
        ),
        # SubRegiao — recent ts_database_transaction (within typical date-filter window)
        (
            1,
            3,
            "Moema",
            "SubRegiao",
            None,
            datetime(2025, 1, 1, 10, 0),
            datetime(2025, 1, 15, 11, 0),
            datetime(2025, 1, 15, 11, 0),
        ),
        # SubRegiao — recent ts_database_transaction, has both RENT and SALE business contexts
        (
            2,
            3,
            "Ibirapuera",
            "SubRegiao",
            None,
            datetime(2025, 1, 2, 10, 0),
            datetime(2025, 1, 20, 11, 0),
            datetime(2025, 1, 20, 11, 0),
        ),
        # SubRegiao — old ts_updated, excluded from Jan 2025 incremental window
        (
            4,
            3,
            "Old Region",
            "SubRegiao",
            None,
            datetime(2022, 12, 25, 9, 0),
            datetime(2022, 12, 25, 10, 0),
            datetime(2022, 12, 25, 10, 0),
        ),
        # SubRegiao — ts_updated in window, ts_database_transaction outside (CDC lag / reorder)
        (
            6,
            3,
            "Vila Nova",
            "SubRegiao",
            None,
            datetime(2025, 1, 5, 8, 0),
            datetime(2025, 1, 10, 12, 0),
            datetime(2019, 1, 1, 0, 0),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def region_df_skewed_incremental(spark_session):
    """Same hierarchy as region_df but only SubRegiao id=1 has ts_updated in Jan 2025.

    Parents (5, 3) have old ts_updated; incremental must still resolve city/macro via full table.
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
            StructField("ts_database_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            5,
            None,
            "São Paulo",
            "Cidade",
            10,
            datetime(2010, 1, 1, 0, 0),
            datetime(2010, 1, 1, 0, 0),
            datetime(2025, 1, 1, 0, 0),
        ),
        (
            3,
            5,
            "Zona Sul",
            "MacroRegiao",
            None,
            datetime(2010, 1, 1, 0, 0),
            datetime(2010, 1, 1, 0, 0),
            datetime(2025, 1, 1, 0, 0),
        ),
        (
            1,
            3,
            "Moema",
            "SubRegiao",
            None,
            datetime(2025, 1, 1, 10, 0),
            datetime(2025, 1, 15, 11, 0),
            datetime(2025, 1, 15, 11, 0),
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
        # id_country matches EBDB country.id (1=Brazil, 2=Mexico).
        (10, "São Paulo", "SP", 1),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def region_config_df(spark_session):
    """region_config rows: phone_ddd keyed by id_region (matches datalake_ebdb_clean.region_config)."""
    schema = StructType(
        [
            StructField("id_region", LongType(), True),
            StructField("phone_ddd", StringType(), True),
        ]
    )
    # Production shape: region_config rows exist only for Cidade id_region; sub/macro inherit via join
    data = [
        (5, "11"),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def country_df(spark_session):
    """Create a sample country DataFrame for testing.

    Matches datalake_ebdb_clean.country: has 'code' only. The job filters on c.code IS NOT NULL
    and selects c.code AS country_code.
    """
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("code", StringType(), True),
            StructField("name", StringType(), True),
            StructField("default_timezone", StringType(), True),
        ]
    )

    data = [
        (1, "BR", "Brasil", "America/Sao_Paulo"),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def country_df_with_null_code(spark_session):
    """Country DataFrame that includes a row with null code.

    Used to test that the c.code IS NOT NULL filter removes unresolvable regions.
    """
    schema = StructType(
        [
            StructField("id", LongType(), True),
            StructField("code", StringType(), True),
            StructField("name", StringType(), True),
            StructField("default_timezone", StringType(), True),
        ]
    )

    data = [
        (1, "BR", "Brasil", "America/Sao_Paulo"),
        (200, None, "Unknown", "UTC"),
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
        (10, "São Paulo", "SP", 1),
        (20, "Unknown State", "XX", 200),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def region_df_with_unknown_state(spark_session):
    """Region DataFrame that includes a Cidade linked to the unknown state.

    The 'unknown city' row should be filtered out by the c.code IS NOT NULL check.
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
            StructField("ts_database_transaction", TimestampType(), True),
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
            datetime(2020, 6, 1),
        ),
        (
            1,
            3,
            "Moema",
            "SubRegiao",
            None,
            datetime(2025, 1, 1),
            datetime(2025, 1, 15),
            datetime(2025, 1, 15),
        ),
        # Cidade pointing to a state with null country_code → should be filtered out
        (
            9,
            None,
            "Unknown City",
            "Cidade",
            20,
            datetime(2020, 1, 1),
            datetime(2020, 1, 1),
            datetime(2020, 1, 1),
        ),
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
            "REGION_CONFIG_TABLE": "test.region_config",
            "STATE_TABLE": "test.state",
            "COUNTRY_TABLE": "test.country",
            "merge_on": ["id_region"],
            "when_matched_update_condition": (
                "source.ts_region_updated > target.ts_region_updated"
            ),
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
    region_config_df,
    state_df,
    country_df,
):
    """Return a callable that maps table names to their test DataFrames."""

    def side_effect(table_name):
        mapping = {
            "test.region": region_df,
            "test.region_business_context_served": region_business_contexts_df,
            "test.region_config": region_config_df,
            "test.state": state_df,
            "test.country": country_df,
        }
        if table_name not in mapping:
            raise ValueError(f"Unknown table requested in test: {table_name}")
        return mapping[table_name]

    return side_effect


@pytest.fixture
def table_side_effect_skewed(
    region_df_skewed_incremental,
    region_business_contexts_df,
    region_config_df,
    state_df,
    country_df,
):
    """table() mapping using region_df_skewed_incremental for test.region."""

    def side_effect(table_name):
        mapping = {
            "test.region": region_df_skewed_incremental,
            "test.region_business_context_served": region_business_contexts_df,
            "test.region_config": region_config_df,
            "test.state": state_df,
            "test.country": country_df,
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
