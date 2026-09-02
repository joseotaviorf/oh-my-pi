"""Unit tests for load_idactum_scrapy_raw skip/bootstrap behavior."""

import importlib.util
import sys
import types
from datetime import date
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest


# Minimal PySpark type stubs so unit-tests-dags can import the job without a cluster.
class _StringType:
    pass


class _LongType:
    pass


class _ArrayType:
    def __init__(self, elementType, containsNull=True):
        self.elementType = elementType
        self.containsNull = containsNull


class _StructField:
    def __init__(self, name, dataType, nullable=True):
        self.name = name
        self.dataType = dataType
        self.nullable = nullable


class _StructType:
    def __init__(self, fields):
        self.fields = fields


class _AnalysisException(Exception):
    pass


_pyspark_sql_types = types.ModuleType("pyspark.sql.types")
for _type_name, _type_cls in (
    ("ArrayType", _ArrayType),
    ("LongType", _LongType),
    ("StringType", _StringType),
    ("StructField", _StructField),
    ("StructType", _StructType),
):
    setattr(_pyspark_sql_types, _type_name, _type_cls)

_pyspark_sql_utils = types.ModuleType("pyspark.sql.utils")
setattr(_pyspark_sql_utils, "AnalysisException", _AnalysisException)

sys.modules.setdefault("pyspark", MagicMock())
sys.modules.setdefault("pyspark.sql", MagicMock())
sys.modules.setdefault("pyspark.sql.functions", MagicMock())
sys.modules.setdefault("pyspark.sql.types", _pyspark_sql_types)
sys.modules.setdefault("pyspark.sql.utils", _pyspark_sql_utils)

_SPARK_JOB_PATH = (
    Path(__file__).resolve().parents[7]
    / "dags/growth/crawled_idactum_houses/spark_jobs/load_idactum_scrapy_raw.py"
)

_IMPORT_TIME_MOCKS = {
    "bietlejuice.base.databricks.table_privileges": MagicMock(),
    "bietlejuice.base.db": MagicMock(),
    "bietlejuice.base.spark": MagicMock(),
    "bietlejuice.base.spark.unity_catalog_helper": MagicMock(),
    "bietlejuice.clients.db_clients": MagicMock(),
    "bietlejuice.consumers.s3_consumer": MagicMock(),
    "bietlejuice.loaders": MagicMock(),
    "bietlejuice.loaders.s3_loader": MagicMock(),
    "bietlejuice.services.configuration_service": MagicMock(),
    "bietlejuice.services.metastore_services": MagicMock(),
    "quintoandar_logger": MagicMock(),
}


def _load_job_module():
    with patch.dict("sys.modules", _IMPORT_TIME_MOCKS):
        spec = importlib.util.spec_from_file_location(
            "load_idactum_scrapy_raw", _SPARK_JOB_PATH
        )
        if spec is None or spec.loader is None:
            raise RuntimeError(f"Failed to load spec for {_SPARK_JOB_PATH}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


@pytest.fixture(scope="module")
def job():
    return _load_job_module()


def test_is_missing_feed_error_matches_path_not_found(job):
    exc = Exception("Path does not exist: s3://bucket/missing")
    assert job._is_missing_feed_error(exc) is True


def test_is_missing_feed_error_does_not_match_unrelated(job):
    assert job._is_missing_feed_error(Exception("table not found")) is False


def test_empty_raw_schema_defaults_to_response_struct(job):
    schema = job._empty_raw_schema("rj_itbi_main")
    field_names = {field.name for field in schema.fields}
    assert field_names == {"response", "metadata"}


def test_empty_raw_schema_osasco_pesquisa_cdc_uses_array_response(job):
    schema = job._empty_raw_schema("sp_osasco_pesquisa_cdc")
    response_field = next(field for field in schema.fields if field.name == "response")
    assert isinstance(response_field.dataType, _ArrayType)


def test_empty_raw_schema_informacoes_cadastrais_has_top_level_fields(job):
    schema = job._empty_raw_schema("go_goiania_informacoes_cadastrais")
    field_names = {field.name for field in schema.fields}
    assert field_names == {
        "registration_number",
        "cadastral_info",
        "total_records",
        "metadata",
    }


def test_empty_raw_schema_am_manaus_bci_has_matricula(job):
    schema = job._empty_raw_schema("am_manaus_bci")
    response_field = next(field for field in schema.fields if field.name == "response")
    response_field_names = {field.name for field in response_field.dataType.fields}
    assert "matricula" in response_field_names


def test_empty_raw_schema_rj_niteroi_e_cidade_has_nested_response_fields(job):
    schema = job._empty_raw_schema("rj_niteroi_e_cidade")
    response_field = next(field for field in schema.fields if field.name == "response")
    response_field_names = {field.name for field in response_field.dataType.fields}
    assert response_field_names == {"dados_cadastrais", "proprietario"}

    dados_cadastrais = next(
        field
        for field in response_field.dataType.fields
        if field.name == "dados_cadastrais"
    )
    proprietario = next(
        field
        for field in response_field.dataType.fields
        if field.name == "proprietario"
    )
    assert isinstance(dados_cadastrais.dataType, _StructType)
    assert isinstance(proprietario.dataType, _StructType)
    assert {field.name for field in dados_cadastrais.dataType.fields} == {
        "matricula",
        "referencia_anterior",
    }
    assert {field.name for field in proprietario.dataType.fields} == {
        "bairro",
        "nomepri",
        "j39_numero",
        "j39_compl",
        "enderecoimovel",
    }


def test_empty_raw_schema_osasco_pesquisa_cep_uses_array_response(job):
    schema = job._empty_raw_schema("sp_osasco_pesquisa_cep")
    response_field = next(field for field in schema.fields if field.name == "response")
    assert isinstance(response_field.dataType, _ArrayType)


def test_empty_raw_schema_osasco_compromissarios_uses_array_response(job):
    schema = job._empty_raw_schema("sp_osasco_compromissarios")
    response_field = next(field for field in schema.fields if field.name == "response")
    assert isinstance(response_field.dataType, _ArrayType)
    item_field_names = {
        field.name for field in response_field.dataType.elementType.fields
    }
    assert item_field_names == {"cpf_cnpj", "nome"}


def test_empty_raw_schema_osasco_proprietarios_uses_array_response(job):
    schema = job._empty_raw_schema("sp_osasco_proprietarios")
    response_field = next(field for field in schema.fields if field.name == "response")
    assert isinstance(response_field.dataType, _ArrayType)
    item_field_names = {
        field.name for field in response_field.dataType.elementType.fields
    }
    assert item_field_names == {"cpf_cnpj", "nome", "percentual_posse"}


def test_empty_raw_schema_sp_santo_andre_itbi_uses_array_response(job):
    schema = job._empty_raw_schema("sp_santo_andre_itbi")
    response_field = next(field for field in schema.fields if field.name == "response")
    assert isinstance(response_field.dataType, _ArrayType)
    item_field_names = {
        field.name for field in response_field.dataType.elementType.fields
    }
    assert item_field_names == {
        "matricula",
        "endereco",
        "cartorio",
        "valor_pago",
        "valor_venal",
        "area_terreno",
        "area_construcao",
    }


def test_empty_raw_schema_pa_belem_certidao_cadastro_bairros_has_top_level_fields(job):
    schema = job._empty_raw_schema("pa_belem_certidao_cadastro_bairros")
    field_names = {field.name for field in schema.fields}
    assert field_names == {
        "neighborhood_code",
        "neighborhood_name",
        "registrations",
        "total_registrations",
        "metadata",
    }


def test_empty_raw_schema_pa_belem_certidao_cadastro_has_inscricao(job):
    schema = job._empty_raw_schema("pa_belem_certidao_cadastro")
    response_field = next(field for field in schema.fields if field.name == "response")
    response_field_names = {field.name for field in response_field.dataType.fields}
    assert "inscricao" in response_field_names


def test_empty_raw_schema_sp_santo_andre_iptu_uses_array_response(job):
    schema = job._empty_raw_schema("sp_santo_andre_iptu")
    field_names = {field.name for field in schema.fields}
    assert field_names == {"sql", "response", "metadata"}
    response_field = next(field for field in schema.fields if field.name == "response")
    assert isinstance(response_field.dataType, _ArrayType)
    item_field_names = {
        field.name for field in response_field.dataType.elementType.fields
    }
    assert "classificacao_fiscal" in item_field_names
    assert "lancamento" in item_field_names


def test_empty_raw_schema_sp_sao_paulo_itbi_has_cadastro_imovel(job):
    schema = job._empty_raw_schema("sp_sao_paulo_itbi")
    response_field = next(field for field in schema.fields if field.name == "response")
    response_field_names = {field.name for field in response_field.dataType.fields}
    assert "cadastro_imovel" in response_field_names
    assert "numero_transacao" in response_field_names


def test_response_schema_type_mismatch_detects_generic_vs_nested(job):
    metastore_service = MagicMock()
    metastore_service.get_table_names.return_value = ["rj_niteroi_e_cidade"]
    metastore_service.get_table_schema.return_value = {
        "response": "struct<_inscricao:string,inscricao:string>",
        "metadata": "struct<source:string,url:string>",
    }

    dataframe = MagicMock()
    dataframe.schema.fields = [
        MagicMock(
            simpleString=lambda: (
                "response:struct<dados_cadastrais:struct<matricula:string>,"
                "proprietario:struct<bairro:string>>"
            )
        )
    ]

    assert (
        job._response_schema_type_mismatch(
            metastore_service,
            "datalake_crawled_idactum_houses_raw",
            "rj_niteroi_e_cidade",
            dataframe,
        )
        is True
    )


def test_response_schema_type_mismatch_ignores_missing_table(job):
    metastore_service = MagicMock()
    metastore_service.get_table_names.return_value = []

    assert (
        job._response_schema_type_mismatch(
            metastore_service,
            "datalake_crawled_idactum_houses_raw",
            "rj_niteroi_e_cidade",
            MagicMock(),
        )
        is False
    )


def test_sanitize_raw_dataframe_is_noop_for_unregistered_tables(job):
    dataframe = MagicMock(name="dataframe")
    assert job._sanitize_raw_dataframe("rj_itbi_main", dataframe) is dataframe


def test_sanitize_raw_dataframe_rj_niteroi_projects_known_response_fields(job):
    dataframe = MagicMock(name="dataframe")
    projected = MagicMock(name="projected")
    dataframe.withColumn.return_value = projected

    result = job._sanitize_raw_dataframe("rj_niteroi_e_cidade", dataframe)

    assert result is projected
    dataframe.withColumn.assert_called_once()
    assert dataframe.withColumn.call_args.args[0] == "response"


def test_sanitize_raw_dataframe_sp_osasco_proprietarios_casts_percentual_posse(job):
    dataframe = MagicMock(name="dataframe")
    projected = MagicMock(name="projected")
    dataframe.withColumn.return_value = projected

    result = job._sanitize_raw_dataframe("sp_osasco_proprietarios", dataframe)

    assert result is projected
    dataframe.withColumn.assert_called_once()
    assert dataframe.withColumn.call_args.args[0] == "response"


def test_bootstrap_empty_raw_table_persists_empty_table(job):
    logger = MagicMock()
    empty_df = MagicMock(name="empty_df")
    transformed_df = MagicMock(name="transformed_df")

    with (
        patch.object(job, "_empty_raw_dataframe", return_value=empty_df) as empty_raw,
        patch.object(job, "transform_data", return_value=transformed_df) as transform,
        patch.object(job, "save_to_datalake") as save_to_datalake,
    ):
        job.bootstrap_empty_raw_table(
            logger,
            environment="forno",
            datalake_bucket="s3://bucket",
            table_name="sp_osasco_pesquisa_cdc",
            source="crawled_idactum_houses",
            spider="sp_osasco_pesquisa_cdc",
            execution_date=date(2026, 8, 1),
            ingestion_path="s3://crawler-scrapy-forno/sp_osasco_pesquisa_cdc/2026-08-01/*/batch_*.jsonl",
            reason="missing_feed_path",
            error=Exception("Path does not exist"),
        )

    empty_raw.assert_called_once_with("sp_osasco_pesquisa_cdc")
    transform.assert_called_once_with(
        empty_df,
        crawler_name="sp_osasco_pesquisa_cdc",
        execution_date=date(2026, 8, 1),
    )
    save_to_datalake.assert_called_once_with(
        dataframe=transformed_df,
        environment="forno",
        datalake_bucket="s3://bucket",
        table_name="sp_osasco_pesquisa_cdc",
        source="crawled_idactum_houses",
        force_recreate=True,
    )
