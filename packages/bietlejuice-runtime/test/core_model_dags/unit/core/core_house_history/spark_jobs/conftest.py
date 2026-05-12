"""
Pytest fixtures for core_house_history Spark job tests.
"""

from datetime import datetime
from unittest.mock import patch

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    DoubleType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

HOUSE_HISTORY_EVENT_CONFIGS = [
    {"tracked_col": "externalId", "target_col": "id_external", "target_type": "string"},
    {"tracked_col": "regiao_id", "target_col": "id_region", "target_type": "bigint"},
    {
        "tracked_col": "id_user_registrant",
        "target_col": "id_user_registrant",
        "target_type": "bigint",
    },
    {"tracked_col": "endereco", "target_col": "address", "target_type": "string"},
    {"tracked_col": "numero", "target_col": "number", "target_type": "string"},
    {"tracked_col": "bairro", "target_col": "neighborhood", "target_type": "string"},
    {"tracked_col": "complemento", "target_col": "complement", "target_type": "string"},
    {"tracked_col": "cep", "target_col": "zipcode", "target_type": "string"},
    {"tracked_col": "cidade", "target_col": "city", "target_type": "string"},
    {"tracked_col": "tipo", "target_col": "type", "target_type": "string"},
    {"tracked_col": "areaTotal", "target_col": "total_area", "target_type": "int"},
    {"tracked_col": "lat", "target_col": "lat", "target_type": "decimal"},
    {"tracked_col": "lng", "target_col": "lng", "target_type": "decimal"},
    {
        "tracked_col": "numeroBanheiros",
        "target_col": "total_bathrooms",
        "target_type": "int",
    },
    {
        "tracked_col": "numeroQuartos",
        "target_col": "total_bedrooms",
        "target_type": "int",
    },
    {"tracked_col": "numeroSuites", "target_col": "total_suites", "target_type": "int"},
    {"tracked_col": "andar", "target_col": "floor", "target_type": "int"},
    {
        "tracked_col": "dataCriacao",
        "target_col": "ts_created",
        "target_type": "timestamp",
    },
    {
        "tracked_col": "atualizadoEm",
        "target_col": "ts_updated",
        "target_type": "timestamp",
    },
]

CONFIG_MAP = {
    "ENTITY_TYPE": "HOUSE",
    "HOUSE_TRANSACTIONAL_TABLE": "test_transactional_imovel",
    "HLR_TRANSACTIONAL_TABLE": "test_hlr",
    "USER_TRANSACTIONAL_TABLE": "test_usuario",
    "merge_on_historical": [
        "id_house",
        "event_name",
        "ts_transaction",
        "year",
        "month",
        "day",
    ],
    "when_matched_update_condition_historical": "FALSE",
    "event_configs": HOUSE_HISTORY_EVENT_CONFIGS,
}


def _config_side_effect(key, required=False, default=None):
    if key in CONFIG_MAP:
        return CONFIG_MAP[key]
    if required:
        raise KeyError(f"Missing required config key: {key}")
    return default


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreHouseHistoryTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


@pytest.fixture
def mock_configuration_service():
    """Mock get_config for CoreHouseHistorySparkJob."""
    with patch(
        "dags.core.core_house_history.spark_jobs.load_core_house_history"
        ".CoreHouseHistorySparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = _config_side_effect
        yield mock_get_config


@pytest.fixture
def transactional_imovel_df(spark_session):
    """Sample transactional CDC data for house (imovel)."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("externalId", StringType(), True),
            StructField("regiao_id", StringType(), True),
            StructField("usuario_id", StringType(), True),
            StructField("originalUsuarioQueCadastrou_id", StringType(), True),
            StructField("usuarioQueCadastrou_id", StringType(), True),
            StructField("endereco", StringType(), True),
            StructField("numero", StringType(), True),
            StructField("bairro", StringType(), True),
            StructField("complemento", StringType(), True),
            StructField("cep", StringType(), True),
            StructField("cidade", StringType(), True),
            StructField("tipo", StringType(), True),
            StructField("areaTotal", DoubleType(), True),
            StructField("lat", DoubleType(), True),
            StructField("lng", DoubleType(), True),
            StructField("numeroBanheiros", StringType(), True),
            StructField("numeroQuartos", StringType(), True),
            StructField("numeroSuites", StringType(), True),
            StructField("andar", StringType(), True),
            StructField("dataCriacao", StringType(), True),
            StructField("atualizadoEm", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "42",
            "EXT-42",
            "10",
            "100",
            "50",
            None,
            "Rua A",
            "123",
            "Centro",
            "Apto 1",
            "01000-000",
            "São Paulo",
            "APARTMENT",
            80.0,
            -23.55,
            -46.63,
            "2",
            "3",
            "1",
            "5",
            "2026-01-10",
            "2026-01-10",
            "c",
            datetime(2026, 1, 10, 8, 0, 0),
            datetime(2026, 1, 10, 8, 0, 1),
        ),
        (
            "42",
            "EXT-42",
            "10",
            "150",
            "50",
            None,
            "Rua A",
            "123",
            "Centro",
            "Apto 1",
            "01000-000",
            "São Paulo",
            "APARTMENT",
            80.0,
            -23.55,
            -46.63,
            "2",
            "3",
            "1",
            "5",
            "2026-01-10",
            "2026-01-15",
            "u",
            datetime(2026, 1, 15, 9, 0, 0),
            datetime(2026, 1, 15, 9, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_hlr_df(spark_session):
    """Sample transactional CDC data for ImovelListingRelation (HLR)."""
    schema = StructType(
        [
            StructField("imovelId", StringType(), True),
            StructField("relatedId", StringType(), True),
            StructField("relatedAs", StringType(), True),
            StructField("sourceType", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "42",
            "200",
            "PROPERTY_OWNER",
            "MAIN_USER",
            "c",
            datetime(2026, 1, 12, 10, 0, 0),
            datetime(2026, 1, 12, 10, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_hlr_with_delete_df(spark_session):
    """HLR with a create followed by a delete."""
    schema = StructType(
        [
            StructField("imovelId", StringType(), True),
            StructField("relatedId", StringType(), True),
            StructField("relatedAs", StringType(), True),
            StructField("sourceType", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "42",
            "200",
            "PROPERTY_OWNER",
            "MAIN_USER",
            "c",
            datetime(2026, 1, 12, 10, 0, 0),
            datetime(2026, 1, 12, 10, 0, 1),
        ),
        (
            "42",
            "200",
            "PROPERTY_OWNER",
            "MAIN_USER",
            "d",
            datetime(2026, 1, 14, 11, 0, 0),
            datetime(2026, 1, 14, 11, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_hlr_empty_df(spark_session):
    """Empty HLR — no ownership records."""
    schema = StructType(
        [
            StructField("imovelId", StringType(), True),
            StructField("relatedId", StringType(), True),
            StructField("relatedAs", StringType(), True),
            StructField("sourceType", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    return spark_session.createDataFrame([], schema)


@pytest.fixture
def transactional_usuario_df(spark_session):
    """Sample transactional CDC data for usuario. User 200 created on day 12."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("personuuid", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "100",
            "uuid-aaa",
            "c",
            datetime(2026, 1, 1, 0, 0, 0),
            datetime(2026, 1, 1, 0, 0, 1),
        ),
        (
            "150",
            "uuid-bbb",
            "c",
            datetime(2026, 1, 1, 0, 0, 0),
            datetime(2026, 1, 1, 0, 0, 1),
        ),
        (
            "200",
            "uuid-ccc",
            "c",
            datetime(2026, 1, 12, 9, 0, 0),
            datetime(2026, 1, 12, 9, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)


@pytest.fixture
def transactional_usuario_late_df(spark_session):
    """User 200 created AFTER the events — to test as-of join temporal correctness."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("personuuid", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "100",
            "uuid-aaa",
            "c",
            datetime(2026, 1, 1, 0, 0, 0),
            datetime(2026, 1, 1, 0, 0, 1),
        ),
        (
            "150",
            "uuid-bbb",
            "c",
            datetime(2026, 1, 1, 0, 0, 0),
            datetime(2026, 1, 1, 0, 0, 1),
        ),
        (
            "200",
            "uuid-ccc",
            "c",
            datetime(2026, 2, 1, 0, 0, 0),
            datetime(2026, 2, 1, 0, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)
