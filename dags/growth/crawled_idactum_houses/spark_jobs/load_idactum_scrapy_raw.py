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
) -> None:
    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

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
        force_recreate=False,
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

    dataframe_to_save = transform_data(
        raw_dataframe, crawler_name=spider, execution_date=execution_date
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
