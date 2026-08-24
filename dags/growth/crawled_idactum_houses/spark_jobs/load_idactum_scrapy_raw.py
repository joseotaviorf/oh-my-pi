from argparse import ArgumentParser
from datetime import date, datetime
from typing import List, Optional

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import (
    ArrayType,
    LongType,
    StringType,
    StructField,
    StructType,
)
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.schema_service import SchemaService

PARTITION_COLS: List[str] = ["year", "month", "day"]

METADATA_STRUCT = StructType(
    [
        StructField("source", StringType(), True),
        StructField("url", StringType(), True),
        StructField("accessed_at", StringType(), True),
        StructField("referer_url", StringType(), True),
    ]
)

# Union of response.* fields referenced across Idactum scrapy clean SQL files.
_RESPONSE_STRUCT = StructType(
    [
        StructField(field_name, StringType(), True)
        for field_name in (
            "_inscricao",
            "inscricao",
            "inscricao_cadastral",
            "cdc",
            "endereco",
            "setor",
            "cpf_cnpj",
            "numero_certidao",
            "cartorio_de_registro",
            "valor_da_transacao",
            "valor_venal_do_imovel",
            "valor_venal_da_edificacao",
            "natureza_da_operacao",
            "proprietario",
            "adquirente",
            "situacao",
            "numero_guia",
            "numero_protocolo",
            "numero_autenticacao",
            "inscricao_imobiliaria",
            "endereco_imovel",
            "natureza_transacao",
            "parte_transferida",
            "parcela",
            "valor_declarado",
            "base_calculo",
            "valor_total_devido",
            "valor_total_pago",
            "data_vencimento",
            "data_pagamento",
            "transmitente",
            "folha_suplementar",
            "observacao",
        )
    ]
)

_OSASCO_PESQUISA_CDC_ITEM_STRUCT = StructType(
    [
        StructField("inscricao", StringType(), True),
        StructField("cdc", StringType(), True),
        StructField("endereco", StringType(), True),
        StructField("no_matricula", StringType(), True),
        StructField("proprietario_compromissario", StringType(), True),
        StructField("situacao", StringType(), True),
    ]
)

_CADASTRAL_INFO_ITEM_STRUCT = StructType(
    [
        StructField("nrinscr", StringType(), True),
        StructField("nmbairro", StringType(), True),
        StructField("nmlogradou", StringType(), True),
        StructField("nrimovel", StringType(), True),
        StructField("incompl", StringType(), True),
        StructField("areaterr", StringType(), True),
        StructField("areaedif", StringType(), True),
        StructField("areatest", StringType(), True),
        StructField("vlvenal", StringType(), True),
        StructField("uso", StringType(), True),
        StructField("formauso", StringType(), True),
        StructField("tpedif1", StringType(), True),
        StructField("tpedif2", StringType(), True),
        StructField("x_coord", StringType(), True),
        StructField("y_coord", StringType(), True),
        StructField("ci", StringType(), True),
        StructField("nmedificio", StringType(), True),
    ]
)

_REGISTRATION_ITEM_STRUCT = StructType(
    [
        StructField("registration_number", StringType(), True),
        StructField("ci", StringType(), True),
    ]
)

_OSASCO_PESQUISA_CEP_ITEM_STRUCT = StructType(
    [
        StructField("inscricao", StringType(), True),
        StructField("cdc", StringType(), True),
        StructField("endereco", StringType(), True),
        StructField("no_matricula", StringType(), True),
        StructField("situacao", StringType(), True),
    ]
)

_OSASCO_COMPROMISSARIOS_ITEM_STRUCT = StructType(
    [
        StructField("cpf_cnpj", StringType(), True),
        StructField("nome", StringType(), True),
    ]
)

_OSASCO_PROPRIETARIOS_ITEM_STRUCT = StructType(
    [
        StructField("cpf_cnpj", StringType(), True),
        StructField("nome", StringType(), True),
        StructField("percentual_posse", StringType(), True),
    ]
)

_AM_MANAUS_BCI_RESPONSE_STRUCT = StructType(
    [
        StructField(field_name, StringType(), True)
        for field_name in (
            "inscricao",
            "matricula",
            "bairro",
            "logradouro",
            "numero",
            "cep",
            "complemento",
            "ano_construcao",
            "area_terreno",
            "area_construcao_unidade",
            "area_edificada",
            "tipo_imovel",
        )
    ]
)

_BA_SALVADOR_CERTIDAO_CADASTRAL_RESPONSE_STRUCT = StructType(
    [
        StructField(field_name, StringType(), True)
        for field_name in (
            "incricao_imobiliaria",
            "bairro",
            "logradouro",
            "numero_porta",
            "numero_metrico",
            "cep",
            "complemento_endereco",
            "area_terreno",
            "area_construida",
            "utilizacao",
        )
    ]
)

_BSB_MAIN_FICHAS_RESPONSE_STRUCT = StructType(
    [
        StructField(field_name, StringType(), True)
        for field_name in (
            "inscricao",
            "cidade",
            "bairro_de_correspondencia",
            "endereco_do_imovel",
            "cep_do_imovel",
            "area_terreno",
            "area_da_construcao_do_alvara",
            "area_declarada",
            "natureza_do_imovel",
        )
    ]
)

_SP_DADOS_CADASTRAIS_RECADASTRAMENTO_RESPONSE_STRUCT = StructType(
    [
        StructField(field_name, StringType(), True)
        for field_name in (
            "NumIPTU",
            "Bairro",
            "Endereco",
            "Numero",
            "Complemento",
            "CepImovel",
        )
    ]
)

_RJ_DADOS_CADASTRAIS_RESPONSE_STRUCT = StructType(
    [
        StructField("inscription_sem_dv", StringType(), True),
    ]
)

_RJ_NITEROI_DADOS_CADASTRAIS_STRUCT = StructType(
    [
        StructField("matricula", StringType(), True),
        StructField("referencia_anterior", StringType(), True),
    ]
)

_RJ_NITEROI_PROPRIETARIO_STRUCT = StructType(
    [
        StructField("bairro", StringType(), True),
        StructField("nomepri", StringType(), True),
        StructField("j39_numero", StringType(), True),
        StructField("j39_compl", StringType(), True),
        StructField("enderecoimovel", StringType(), True),
    ]
)

_RJ_NITEROI_E_CIDADE_RESPONSE_STRUCT = StructType(
    [
        StructField("dados_cadastrais", _RJ_NITEROI_DADOS_CADASTRAIS_STRUCT, True),
        StructField("proprietario", _RJ_NITEROI_PROPRIETARIO_STRUCT, True),
    ]
)

_BSB_FEATURES_PROPERTIES_CADASTRAL_STRUCT = StructType(
    [
        StructField(field_name, StringType(), True)
        for field_name in (
            "objectid",
            "lt_nome",
            "lt_endereco",
            "lt_cep",
            "ac_area_ct",
            "ac_area_ce",
        )
    ]
)

_BSB_FEATURES_PROPERTIES_GEOMETRIA_STRUCT = StructType(
    [
        StructField(field_name, StringType(), True)
        for field_name in (
            "objectid",
            "iptu_imovel",
            "lt_nome",
            "iptu_endereco",
            "lt_cep",
            "iptu_area_terr",
            "iptu_areac_dec",
        )
    ]
)

_BSB_FEATURES_ITEM_STRUCT = StructType(
    [
        StructField("properties", _BSB_FEATURES_PROPERTIES_CADASTRAL_STRUCT, True),
    ]
)

_BSB_GEOMETRIA_FEATURES_ITEM_STRUCT = StructType(
    [
        StructField("properties", _BSB_FEATURES_PROPERTIES_GEOMETRIA_STRUCT, True),
    ]
)

_BSB_FEATURES_RESPONSE_STRUCT = StructType(
    [
        StructField("features", ArrayType(_BSB_FEATURES_ITEM_STRUCT), True),
    ]
)

_BSB_GEOMETRIA_RESPONSE_STRUCT = StructType(
    [
        StructField("features", ArrayType(_BSB_GEOMETRIA_FEATURES_ITEM_STRUCT), True),
    ]
)


def _response_metadata_schema(response_struct: StructType) -> StructType:
    return StructType(
        [
            StructField("response", response_struct, True),
            StructField("metadata", METADATA_STRUCT, True),
        ]
    )


_EMPTY_RAW_SCHEMAS = {
    "sp_osasco_pesquisa_cdc": StructType(
        [
            StructField(
                "response",
                ArrayType(_OSASCO_PESQUISA_CDC_ITEM_STRUCT),
                True,
            ),
            StructField("metadata", METADATA_STRUCT, True),
        ]
    ),
    "sp_osasco_pesquisa_cep": StructType(
        [
            StructField(
                "response",
                ArrayType(_OSASCO_PESQUISA_CEP_ITEM_STRUCT),
                True,
            ),
            StructField("metadata", METADATA_STRUCT, True),
        ]
    ),
    "sp_osasco_compromissarios": StructType(
        [
            StructField(
                "response",
                ArrayType(_OSASCO_COMPROMISSARIOS_ITEM_STRUCT),
                True,
            ),
            StructField("metadata", METADATA_STRUCT, True),
        ]
    ),
    "sp_osasco_proprietarios": StructType(
        [
            StructField(
                "response",
                ArrayType(_OSASCO_PROPRIETARIOS_ITEM_STRUCT),
                True,
            ),
            StructField("metadata", METADATA_STRUCT, True),
        ]
    ),
    "go_goiania_informacoes_cadastrais": StructType(
        [
            StructField("registration_number", StringType(), True),
            StructField(
                "cadastral_info",
                ArrayType(_CADASTRAL_INFO_ITEM_STRUCT),
                True,
            ),
            StructField("total_records", LongType(), True),
            StructField("metadata", METADATA_STRUCT, True),
        ]
    ),
    "go_goiania_cadastro_imobiliario": StructType(
        [
            StructField("neighborhood_id", LongType(), True),
            StructField(
                "registrations",
                ArrayType(_REGISTRATION_ITEM_STRUCT),
                True,
            ),
            StructField("total_registrations", LongType(), True),
            StructField("metadata", METADATA_STRUCT, True),
        ]
    ),
    "am_manaus_bci": _response_metadata_schema(_AM_MANAUS_BCI_RESPONSE_STRUCT),
    "ba_salvador_certidao_cadastral": _response_metadata_schema(
        _BA_SALVADOR_CERTIDAO_CADASTRAL_RESPONSE_STRUCT
    ),
    "bsb_main_fichas": _response_metadata_schema(_BSB_MAIN_FICHAS_RESPONSE_STRUCT),
    "sp_dados_cadastrais_recadastramento_main": _response_metadata_schema(
        _SP_DADOS_CADASTRAIS_RECADASTRAMENTO_RESPONSE_STRUCT
    ),
    "rj_dados_cadastrais_main_busca": _response_metadata_schema(
        _RJ_DADOS_CADASTRAIS_RESPONSE_STRUCT
    ),
    "rj_dados_cadastrais_main_nirf": _response_metadata_schema(
        _RJ_DADOS_CADASTRAIS_RESPONSE_STRUCT
    ),
    "rj_dados_cadastrais_main_predio": _response_metadata_schema(
        _RJ_DADOS_CADASTRAIS_RESPONSE_STRUCT
    ),
    "rj_niteroi_e_cidade": _response_metadata_schema(
        _RJ_NITEROI_E_CIDADE_RESPONSE_STRUCT
    ),
    "bsb_main_cadastro_territorial": _response_metadata_schema(
        _BSB_FEATURES_RESPONSE_STRUCT
    ),
    "bsb_main_certidao_geometria": _response_metadata_schema(
        _BSB_GEOMETRIA_RESPONSE_STRUCT
    ),
}


def _is_missing_feed_error(exc: Exception) -> bool:
    msg = str(exc)
    return "Path does not exist" in msg or "PATH_NOT_FOUND" in msg


def _empty_raw_schema(table_name: str) -> StructType:
    return _EMPTY_RAW_SCHEMAS.get(
        table_name,
        StructType(
            [
                StructField("response", _RESPONSE_STRUCT, True),
                StructField("metadata", METADATA_STRUCT, True),
            ]
        ),
    )


def _empty_raw_dataframe(table_name: str) -> DataFrame:
    spark_client = SparkClient()
    return spark_client.conn.createDataFrame([], _empty_raw_schema(table_name))


def _normalize_schema_type(schema_type: str) -> str:
    return schema_type.lower().replace(" ", "")


def _response_schema_type_mismatch(
    spark_metastore_service: SparkMetastoreService,
    database_name: str,
    table_name: str,
    dataframe: DataFrame,
) -> bool:
    if table_name not in spark_metastore_service.get_table_names(database_name):
        return False

    table_schema = spark_metastore_service.get_table_schema(database_name, table_name)
    dataframe_schema = SchemaService.get_schema_from_dataframe(dataframe)

    table_response_type = table_schema.get("response")
    dataframe_response_type = dataframe_schema.get("response")
    if table_response_type is None or dataframe_response_type is None:
        return False

    return _normalize_schema_type(table_response_type) != _normalize_schema_type(
        dataframe_response_type
    )


def bootstrap_empty_raw_table(
    logger: QuintoAndarLogger,
    *,
    environment: str,
    datalake_bucket: str,
    table_name: str,
    source: str,
    spider: str,
    execution_date: date,
    ingestion_path: str,
    reason: str,
    error: Optional[Exception] = None,
) -> None:
    error_suffix = f", error={error}" if error is not None else ""
    logger.warning(
        f"m=__main__, source={source}, spider={spider}, "
        f"execution_date={execution_date.isoformat()}, ingestion_path={ingestion_path}, "
        f"reason={reason}{error_suffix}, "
        f"msg=Bootstrapping empty raw table for downstream tasks"
    )

    dataframe_to_save = transform_data(
        _empty_raw_dataframe(table_name),
        crawler_name=spider,
        execution_date=execution_date,
    )
    save_to_datalake(
        dataframe=dataframe_to_save,
        environment=environment,
        datalake_bucket=datalake_bucket,
        table_name=table_name,
        source=source,
        force_recreate=True,
    )

    logger.info(
        f"m=__main__, source={source}, table_name={table_name}, "
        f"execution_date={execution_date.isoformat()}, partitions={PARTITION_COLS}, "
        f"msg=Bootstrapped empty scrapy raw table"
    )


def load_from_s3(path: str) -> DataFrame:
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    return s3_consumer.get_data_from_file(
        path=path,
        format="json",
        options={"multiline": "false"},
    )


def _sanitize_rj_niteroi_e_cidade_response(dataframe: DataFrame) -> DataFrame:
    """Project response to known fields so numeric JSON keys never reach metastore DDL."""
    return dataframe.withColumn(
        "response",
        F.struct(
            F.struct(
                F.col("response.dados_cadastrais.matricula")
                .cast(StringType())
                .alias("matricula"),
                F.col("response.dados_cadastrais.referencia_anterior")
                .cast(StringType())
                .alias("referencia_anterior"),
            ).alias("dados_cadastrais"),
            F.struct(
                F.col("response.proprietario.bairro")
                .cast(StringType())
                .alias("bairro"),
                F.col("response.proprietario.nomepri")
                .cast(StringType())
                .alias("nomepri"),
                F.col("response.proprietario.j39_numero")
                .cast(StringType())
                .alias("j39_numero"),
                F.col("response.proprietario.j39_compl")
                .cast(StringType())
                .alias("j39_compl"),
                F.col("response.proprietario.enderecoimovel")
                .cast(StringType())
                .alias("enderecoimovel"),
            ).alias("proprietario"),
        ),
    )


def _sanitize_sp_osasco_proprietarios_response(dataframe: DataFrame) -> DataFrame:
    """Cast array item fields to string so JSON inference cannot drift to long."""
    return dataframe.withColumn(
        "response",
        F.transform(
            F.col("response"),
            lambda item: F.struct(
                item.getField("cpf_cnpj").cast(StringType()).alias("cpf_cnpj"),
                item.getField("nome").cast(StringType()).alias("nome"),
                item.getField("percentual_posse")
                .cast(StringType())
                .alias("percentual_posse"),
            ),
        ),
    )


_RAW_RESPONSE_SANITIZERS = {
    "rj_niteroi_e_cidade": _sanitize_rj_niteroi_e_cidade_response,
    "sp_osasco_proprietarios": _sanitize_sp_osasco_proprietarios_response,
}


def _sanitize_raw_dataframe(table_name: str, dataframe: DataFrame) -> DataFrame:
    sanitizer = _RAW_RESPONSE_SANITIZERS.get(table_name)
    if sanitizer is None:
        return dataframe
    return sanitizer(dataframe)


def transform_data(
    dataframe: DataFrame, crawler_name: str, execution_date: date
) -> DataFrame:
    return (
        dataframe.withColumn("dt_load", F.lit(date.today()))
        .withColumn("crawler_name", F.lit(crawler_name))
        .withColumn("year", F.lit(execution_date.year))
        .withColumn("month", F.lit(execution_date.month))
        .withColumn("day", F.lit(execution_date.day))
    )


def save_to_datalake(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    table_name: str,
    source: str,
    *,
    force_recreate: bool = False,
) -> None:
    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    if not force_recreate and _response_schema_type_mismatch(
        spark_metastore_service,
        database_name,
        table_name,
        dataframe,
    ):
        logger.warning(
            f"m=save_to_datalake, db={database_name}, table={table_name}, "
            f"msg=Existing metastore response schema differs from incoming dataframe; "
            f"forcing table recreation"
        )
        force_recreate = True

    s3_loader = S3Loader()
    s3_loader.load_df(
        df=dataframe,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=PARTITION_COLS,
        compression="gzip",
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=dataframe,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partitions=PARTITION_COLS,
        force_recreate=force_recreate,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=dataframe,
        partition_cols=PARTITION_COLS,
    )

    full_raw_table_name = f"datalake_{source}_raw.{table_name}"
    table_privileges = TablePrivileges.from_environment_default(full_raw_table_name)
    if table_privileges and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        table_privileges.apply()

    spark_metastore_service.refresh_table(database_name, table_name)


if __name__ == "__main__":
    parser = ArgumentParser(
        description="Load Idactum Scrapy crawler JSONL data into the raw layer"
    )
    parser.add_argument("env", help="Forno/Prod values")
    parser.add_argument("datalake_bucket", help="Bucket value in forno/prod")
    parser.add_argument("table_name", help="Name of the table to store data into")
    parser.add_argument("execution_date", help="DAG execution_date (YYYY-MM-DD)")
    parser.add_argument(
        "source",
        help=(
            "Shared metastore source for crawled Idactum feeds "
            "(e.g., crawled_idactum_houses → datalake_crawled_idactum_houses_raw)"
        ),
    )
    parser.add_argument(
        "spider", help="Scrapy spider / crawler slug (e.g., rj_itbi_main)"
    )

    args = parser.parse_args()
    source = args.source
    spider = args.spider
    execution_date = datetime.strptime(args.execution_date, "%Y-%m-%d").date()

    JOB_NAME = f"load_{spider}_scrapy_raw"
    logger = QuintoAndarLogger(JOB_NAME)

    # Shared forno/prod feed_bucket conf under crawled_idactum_houses/spark_jobs/.
    config_service = ConfigurationService("crawled_idactum_houses")
    feed_bucket = config_service.get_config("feed_bucket").rstrip("/")
    ingestion_path = f"{feed_bucket}/{spider}/{args.execution_date}/*/batch_*.jsonl"

    logger.info(
        f"m=__main__, environment={args.env}, source={source}, spider={spider}, "
        f"execution_date={args.execution_date}, ingestion_path={ingestion_path}, "
        f"msg=Starting scrapy raw load"
    )

    try:
        raw_dataframe = load_from_s3(path=ingestion_path)
        if raw_dataframe.isEmpty():
            bootstrap_empty_raw_table(
                logger,
                environment=args.env,
                datalake_bucket=args.datalake_bucket,
                table_name=args.table_name,
                source=source,
                spider=spider,
                execution_date=execution_date,
                ingestion_path=ingestion_path,
                reason="empty_feed_dataframe",
            )
            raise SystemExit(0)
    except AnalysisException as exc:
        if _is_missing_feed_error(exc):
            bootstrap_empty_raw_table(
                logger,
                environment=args.env,
                datalake_bucket=args.datalake_bucket,
                table_name=args.table_name,
                source=source,
                spider=spider,
                execution_date=execution_date,
                ingestion_path=ingestion_path,
                reason="missing_feed_path",
                error=exc,
            )
            raise SystemExit(0) from None
        raise

    sanitized_dataframe = _sanitize_raw_dataframe(args.table_name, raw_dataframe)
    dataframe_to_save = transform_data(
        sanitized_dataframe, crawler_name=spider, execution_date=execution_date
    )

    save_to_datalake(
        dataframe=dataframe_to_save,
        environment=args.env,
        datalake_bucket=args.datalake_bucket,
        table_name=args.table_name,
        source=source,
    )

    logger.info(
        f"m=__main__, source={source}, table_name={args.table_name}, "
        f"execution_date={args.execution_date}, partitions={PARTITION_COLS}, "
        f"msg=Successfully saved scrapy raw data"
    )
