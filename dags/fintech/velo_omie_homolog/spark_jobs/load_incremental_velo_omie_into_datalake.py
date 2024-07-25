import ast
from datetime import datetime
import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_omie_api_client.clients.omie_client import OmieClient
from quintoandar_omie_api_client.consumers import CONSUMERS

from pyspark.sql.types import StructType, StructField, StringType, ArrayType

JOB_NAME = "load_incremental_velo_omie_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def dict_flatner(dic: dict):
    final_result = {}
    for key, val in dic.items():
        if isinstance(val, dict):
            final_result = {**final_result, **val}
        else:
            final_result[key] = val
    return final_result


def get_cash_flows_missing_cols():
    all_columns_from_api = [
        "nCodTitulo",
        "cCodIntTitulo",
        "cNumTitulo",
        "dDtEmissao",
        "dDtVenc",
        "dDtPrevisao",
        "dDtPagamento",
        "nCodCliente",
        "cCPFCNPJCliente",
        "nCodCtr",
        "cNumCtr",
        "nCodOS",
        "cNumOS",
        "nCodCC",
        "cStatus",
        "cNatureza",
        "cTipo",
        "cOperacao",
        "cNumDocFiscal",
        "cCodCateg",
        "cNumParcela",
        "nValorTitulo",
        "nValorPIS",
        "cRetPIS",
        "nValorCOFINS",
        "cRetCOFINS",
        "nValorCSLL",
        "cRetCSLL",
        "nValorIR",
        "cRetIR",
        "nValorISS",
        "cRetISS",
        "nValorINSS",
        "cRetINSS",
        "cCodProjeto",
        "observacao",
        "cCodVendedor",
        "nCodComprador",
        "cCodigoBarras",
        "cNSU",
        "nCodNF",
        "dDtRegistro",
        "cNumBoleto",
        "cChaveNFe",
        "cOrigem",
        "nCodTitRepet",
        "cGrupo",
        "nCodMovCC",
        "nValorMovCC",
        "nCodMovCCRepet",
        "nDesconto",
        "nJuros",
        "nMulta",
        "nCodBaixa",
        "dDtCredito",
        "dDtConcilia",
        "cHrConcilia",
        "cUsConcilia",
        "dDtInc",
        "cHrInc",
        "cUsInc",
        "dDtAlt",
        "cHrAlt",
        "cUsAlt",
        "categorias",
        "nValAberto",
        "nValLiquido",
        "nValPago",
        "cLiquidado",
    ]
    return {k: None for k in all_columns_from_api}


def create_schema(json_list: list):
    cols = set()
    for row in json_list:
        [cols.add(key) for key in row.keys()]

    schema = []
    for col in cols:
        if col != "categorias":
            schema.append(StructField(col, StringType(), True))
        else:
            schema.append(
                StructField(
                    "categorias",
                    ArrayType(
                        StructType(
                            [
                                StructField(subcol, StringType(), True)
                                for subcol in [
                                    "cCodCateg",
                                    "nDistrPercentual",
                                    "nDistrValor",
                                    "nValorFixo",
                                ]
                            ]
                        )
                    ),
                    True,
                )
            )
    return StructType(schema)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument(
        "api_consumer_id", type=str, help="The consumer that will be used to load data"
    )
    parser.add_argument(
        "consumer_args",
        type=str,
        help="Dict in string with arguments for the consumer function",
    )
    parser.add_argument("partition_cols", type=str, help="DAG execution date")
    parser.add_argument("execution_date", type=str, help="DAG execution date")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    api_consumer_id = args.api_consumer_id
    consumer_args = args.consumer_args
    partition_cols = ast.literal_eval(args.partition_cols)
    execution_date = args.execution_date

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name}, api_consumer_id={api_consumer_id}
                execution_date={execution_date}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=APIEnum.VELO_OMIE_API
    )
    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    metastore_service = SparkMetastoreService(spark_client)

    # create database if it doesn't exists
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    client = OmieClient(conn_config["app_key"], conn_config["app_secret"], attempts=0)
    consumer_instance = CONSUMERS[api_consumer_id](client)

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    consumer_args = consumer_args.replace(
        "execution_date", dt_execution.strftime("%d/%m/%Y")
    )
    consumer_args = json.loads(consumer_args)

    json_list = consumer_instance.sync(**consumer_args)
    json_list = [dict_flatner(record) for record in json_list]
    if api_consumer_id == "CashFlow":
        # this API does not bring columns with null values, so we add then to be sure
        json_list.append(get_cash_flows_missing_cols())

    df = spark_client.create_dataframe(json_list, create_schema(json_list))
    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_date(dt_execution)
        .output()
    )

    if df:
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            database_location=database_location,
            partitions=partition_cols,
            max_records_per_file=100000,
        )
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            partitions=partition_cols,
        )
    else:
        logger.warning(
            f"""m=__main__, table_name={table_name}, execution_date={execution_date},
            msg=No data returned from API database."""
        )
