"""
Pytest fixtures for contract_history Spark job tests.
"""

import pytest
from unittest.mock import patch
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    TimestampType,
    DoubleType,
)
from datetime import datetime


@pytest.fixture(scope="session")
def spark_session():
    """Create a Spark session for testing."""
    spark = (
        SparkSession.builder.appName("CoreContractHistoryTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


HISTORICAL_EVENT_CONFIGS = [
    {
        "tracked_col": "imovel_id",
        "target_col": "id_house",
        "target_type": "bigint",
    },
    {
        "tracked_col": "usuario_id",
        "target_col": "id_tenant",
        "target_type": "bigint",
    },
    {
        "tracked_col": "proposta_id",
        "target_col": "id_proposal",
        "target_type": "bigint",
    },
    {
        "tracked_col": "status",
        "target_col": "status",
        "target_type": "string",
    },
    {
        "tracked_col": "contractRentModel",
        "target_col": "contract_rent_model",
        "target_type": "string",
    },
    {
        "tracked_col": "paganteCondominio",
        "target_col": "paying_condo",
        "target_type": "string",
    },
    {
        "tracked_col": "responsavelCondominio",
        "target_col": "responsible_for_condo",
        "target_type": "string",
    },
    {
        "tracked_col": "paganteIptu",
        "target_col": "paying_iptu",
        "target_type": "string",
    },
    {
        "tracked_col": "responsavelIptu",
        "target_col": "responsible_for_iptu",
        "target_type": "string",
    },
    {
        "tracked_col": "tipoAssinatura",
        "target_col": "signature_type",
        "target_type": "string",
    },
    {
        "tracked_col": "statusClosing",
        "target_col": "status_closing",
        "target_type": "string",
    },
    {
        "tracked_col": "relistingEnabled",
        "target_col": "is_relisting_enabled",
        "target_type": "boolean",
    },
    {
        "tracked_col": "valorAluguel",
        "target_col": "rent",
        "target_type": "double",
    },
    {
        "tracked_col": "iptu_valor",
        "target_col": "iptu",
        "target_type": "double",
    },
    {
        "tracked_col": "seguroFianca_parcelas",
        "target_col": "rental_guarantee_installment",
        "target_type": "int",
    },
    {
        "tracked_col": "seguroFianca_valor",
        "target_col": "rental_guarantee_value",
        "target_type": "double",
    },
    {
        "tracked_col": "seguroResidencial_parcelas",
        "target_col": "home_insurance_installment",
        "target_type": "int",
    },
    {
        "tracked_col": "seguroResidencial_valor",
        "target_col": "home_insurance_value",
        "target_type": "double",
    },
    {
        "tracked_col": "taxaComissaoPrimeiroAluguel",
        "target_col": "first_rent_comission_fee",
        "target_type": "double",
    },
    {
        "tracked_col": "tenantServiceFee",
        "target_col": "tenant_service_fee",
        "target_type": "double",
    },
    {
        "tracked_col": "estateAgentBrokerageShare",
        "target_col": "agent_brokerage_share",
        "target_type": "double",
    },
    {
        "tracked_col": "dataInicio",
        "target_col": "dt_started",
        "target_type": "date",
    },
    {
        "tracked_col": "dataEntrada",
        "target_col": "dt_entered",
        "target_type": "date",
    },
    {
        "tracked_col": "dataRescisao",
        "target_col": "dt_termination",
        "target_type": "date",
    },
    {
        "tracked_col": "dataFimContratoPrevisto",
        "target_col": "ts_contract_expected_end",
        "target_type": "date",
    },
    {
        "tracked_col": "dataAssinado",
        "target_col": "ts_signed",
        "target_type": "timestamp",
    },
    {
        "tracked_col": "dataRescisaoPrevista",
        "target_col": "ts_expected_termination",
        "target_type": "date",
    },
    {
        "tracked_col": "dataMinutaAprovada",
        "target_col": "ts_minuta_approved",
        "target_type": "timestamp",
    },
    {
        "tracked_col": "criadoEm",
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
    "ENTITY_TYPE": "CONTRACT",
    "CONTRACT_TRANSACTIONAL_TABLE": "test.transactional_contrato",
    "merge_on_historical": ["id_event"],
    "when_matched_update_condition_historical": None,
    "event_configs": HISTORICAL_EVENT_CONFIGS,
}


def _config_side_effect(key, required=False, default=None):
    if key in CONFIG_MAP:
        return CONFIG_MAP[key]
    if required:
        raise KeyError(f"Missing required config key: {key}")
    return default


@pytest.fixture
def mock_configuration_service_history():
    """Mock get_config for CoreContractHistorySparkJob."""
    with patch(
        "dags.core.core_contract_history.spark_jobs.load_core_contract_history"
        ".CoreContractHistorySparkJob.get_config"
    ) as mock_get_config:
        mock_get_config.side_effect = _config_side_effect
        yield mock_get_config


@pytest.fixture
def transactional_contract_df(spark_session):
    """Sample transactional CDC data for contract history tests."""
    schema = StructType(
        [
            StructField("id", StringType(), True),
            StructField("imovel_id", StringType(), True),
            StructField("usuario_id", StringType(), True),
            StructField("proposta_id", StringType(), True),
            StructField("status", StringType(), True),
            StructField("contractRentModel", StringType(), True),
            StructField("paganteCondominio", StringType(), True),
            StructField("responsavelCondominio", StringType(), True),
            StructField("paganteIptu", StringType(), True),
            StructField("responsavelIptu", StringType(), True),
            StructField("tipoAssinatura", StringType(), True),
            StructField("statusClosing", StringType(), True),
            StructField("relistingEnabled", StringType(), True),
            StructField("valorAluguel", DoubleType(), True),
            StructField("iptu_valor", DoubleType(), True),
            StructField("seguroFianca_parcelas", StringType(), True),
            StructField("seguroFianca_valor", DoubleType(), True),
            StructField("seguroResidencial_parcelas", StringType(), True),
            StructField("seguroResidencial_valor", DoubleType(), True),
            StructField("taxaComissaoPrimeiroAluguel", DoubleType(), True),
            StructField("tenantServiceFee", DoubleType(), True),
            StructField("estateAgentBrokerageShare", DoubleType(), True),
            StructField("dataInicio", StringType(), True),
            StructField("dataEntrada", StringType(), True),
            StructField("dataRescisao", StringType(), True),
            StructField("dataFimContratoPrevisto", StringType(), True),
            StructField("dataAssinado", StringType(), True),
            StructField("dataRescisaoPrevista", StringType(), True),
            StructField("dataMinutaAprovada", StringType(), True),
            StructField("criadoEm", StringType(), True),
            StructField("atualizadoEm", StringType(), True),
            StructField("op_cdc", StringType(), True),
            StructField("ts_database_transaction", TimestampType(), True),
            StructField("ts_cdc_transaction", TimestampType(), True),
        ]
    )
    data = [
        (
            "100",
            "1001",
            "2001",
            "3001",
            "Ativo",
            '{"rentalAdministrator": "QUINTOANDAR"}',
            "QuintoAndar",
            "Inquilino",
            "QuintoAndar",
            "Inquilino",
            "Eletronica",
            None,
            "false",
            2500.0,
            100.0,
            "1",
            None,
            "1",
            None,
            1.0,
            None,
            None,
            "2026-01-10",
            "2026-01-10",
            None,
            "2029-01-10",
            "2026-01-10",
            None,
            "2026-01-09",
            "2026-01-09",
            "2026-01-10",
            "c",
            datetime(2026, 1, 10, 8, 0, 0),
            datetime(2026, 1, 10, 8, 0, 1),
        ),
        (
            "100",
            "1001",
            "2001",
            "3001",
            "Finalizado",
            '{"rentalAdministrator": "QUINTOANDAR"}',
            "QuintoAndar",
            "Inquilino",
            "QuintoAndar",
            "Inquilino",
            "Eletronica",
            None,
            "false",
            2500.0,
            100.0,
            "1",
            None,
            "1",
            None,
            1.0,
            None,
            None,
            "2026-01-10",
            "2026-01-10",
            None,
            "2029-01-10",
            "2026-01-10",
            None,
            "2026-01-09",
            "2026-01-09",
            "2026-01-11",
            "u",
            datetime(2026, 1, 11, 9, 0, 0),
            datetime(2026, 1, 11, 9, 0, 1),
        ),
    ]
    return spark_session.createDataFrame(data, schema)
