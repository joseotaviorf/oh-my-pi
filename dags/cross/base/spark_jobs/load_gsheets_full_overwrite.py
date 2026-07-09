"""Spark job: ingestão simples de Google Sheets em UMA etapa.

Lê a planilha na fonte e SOBRESCREVE (overwrite total) a tabela diretamente no
schema final (clean), sem camada raw, sem validação de clean-query e sem split
raw->clean. O overwrite + recriação da tabela (force_recreate) faz o schema da
tabela sempre acompanhar a planilha, evitando erros de merge de schema.

Usado pelo workflow `RawGsheetsIngestionWorkflow` (tipo de DAG `gsheets_ingestion`).
Diferente de `load_gsheets_into_datalake.py` (modelo antigo raw->clean), aqui NÃO há
`validate_clean_query_against_raw` — logo, sem o falso-positivo de "load-raw SUCCESS
sem gravar".
"""

import json
from argparse import ArgumentParser

from quintoandar_gsheets_api_client.clients import GoogleSheetsClient
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.api_consumers.gsheets_consumer import GsheetsConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.gsheets_service import GsheetsService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_gsheets_full_overwrite"
logger = QuintoAndarLogger(JOB_NAME)

TIMEOUT_LIMIT = 5 * 60


def __get_auth(dbutils, credentials_scope, credentials_key):
    """Lê as credenciais da API do Google Sheets do Databricks secret scope."""
    credentials = json.loads(
        dbutils.secrets.get(scope=credentials_scope, key=credentials_key)
    )
    scope = credentials.pop("scope")
    return credentials, scope


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod")
    parser.add_argument("datalake_bucket")
    parser.add_argument(
        "source", help="namespace do schema (ex.: gsheets -> datalake_gsheets_clean)"
    )
    parser.add_argument("table_name", help="nome da tabela final")
    parser.add_argument("sheet_id", help="ID da planilha do Google Sheets")
    parser.add_argument("sheet_name", help="nome da aba dentro da planilha")
    parser.add_argument(
        "credentials_key", help="key do secret com as credenciais da SA"
    )
    parser.add_argument("credentials_scope", help="scope do Databricks secret")
    parser.add_argument(
        "--target-database-name",
        required=False,
        default=None,
        help="validation: nome do database de destino isolado (ex.: cluster_validation)",
    )
    parser.add_argument(
        "--target-table-name",
        required=False,
        default=None,
        help="validation: nome da tabela de destino isolada",
    )
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name

    logger.info(
        f"m={JOB_NAME}, environment={environment}, source={source}, "
        f"table_name={table_name}, msg=Starting single-step gsheets overwrite..."
    )

    # Clients
    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()
    credentials, scope = __get_auth(
        dbutils, args.credentials_scope, args.credentials_key
    )
    gsheets_client = GoogleSheetsClient(credentials, scope, timeout=TIMEOUT_LIMIT)
    spark_client = SparkClient()
    gsheets_consumer = GsheetsConsumer(gsheets_client, spark_client)

    # Destino = schema FINAL (clean). Sem raw.
    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    database_name = datalake_info["db_clean_databricks"]
    database_location = datalake_info["db_clean_path"]

    if args.target_database_name and args.target_table_name:
        from bietlejuice.base.validation.target_resolver import (
            validation_database_location,
        )

        prod_database = database_name
        database_name = args.target_database_name
        table_name = args.target_table_name
        database_location = validation_database_location(
            datalake_bucket, prod_database
        ).replace("s3a://", "s3://")

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    # Lê a planilha como vem (sem CAST/tipagem). clean_table_name = table_name.
    df = gsheets_consumer.get_sheet_df(
        args.sheet_name, args.sheet_id, table_name, None, None
    )
    df = GsheetsService(schema=source).clean_unsupported_column_names(df)

    format_options = SparkTableStorageFormat.DEFAULT_CLEAN

    # Overwrite total dos dados...
    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
    )
    # ...e recria a tabela no metastore (force_recreate=True) p/ o schema acompanhar a planilha.
    spark_metastore_loader.update_metastore(
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        force_recreate=True,
    )

    logger.info(
        f"m={JOB_NAME}, table={database_name}.{table_name}, msg=Sheet fully overwritten!"
    )
