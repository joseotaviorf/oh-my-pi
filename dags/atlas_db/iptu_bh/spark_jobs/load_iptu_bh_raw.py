import ast
import logging
import unicodedata
import re

from argparse import ArgumentParser
from datetime import datetime, date
from typing import List, Optional

from pyspark.sql import DataFrame, functions as F
from pyspark.sql.types import StructType, StructField, StringType, ArrayType

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.services import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader

from quintoandar_logger import QuintoAndarLogger


SOURCE = "iptu_bh"
JOB_NAME = f"load_{SOURCE}_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def load_from_s3(base_path: str, year: int) -> DataFrame:
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    return s3_consumer.get_data_from_file(
        options={"multiline": "false"},
        path=f"s3://{base_path}{year}/iptu_bh_raw_all.jsonl.gz",
        format="json",
    )


def save_to_datalake(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    table_name: str,
    partitions: List[str],
) -> None:
    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    s3_loader.load_df(
        df=dataframe,
        s3_path=f"{database_location}{table_name}",
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        partitions=partitions,
        compression="gzip",
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=dataframe,
        database_name=database_name,
        table_name=table_name,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=database_location,
        partitions=partitions,
        force_recreate=True,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=dataframe,
        database_name=database_name,
        table_name=table_name,
        partition_cols=partitions,
    )


def filter_data(dataframe: DataFrame) -> DataFrame:
    # When we have an error field it means that the taxpayer was not found for the year
    return dataframe.where(
        (F.col("response.Dados Cadastrais Gerais").getItem(0).getItem(0) != "Erro") &
        (F.col("response.Dados Cadastrais Gerais").getItem(0).getItem(1) != "")
    )


def transform_data(dataframe: DataFrame) -> DataFrame:
    def normalize_field_name(field: str) -> str:
        normalized_accents = "".join(
            character
            for character in unicodedata.normalize("NFKD", field)
            if not unicodedata.combining(character)
        )
        lowered_words = normalized_accents.lower()
        without_special_chars = re.sub(r"[^a-zA-Z0-9_]", "_", lowered_words)

        return re.sub(r"_+", "_", without_special_chars)

    def normalize_key_value_pair(data: Optional[list[str]]) -> dict[str, str]:
        if data is None:
            return {}

        return {normalize_field_name(field): value for field, value in data}

    def transform_into_table(data) -> list[dict[str, str]]:
        table_header = [normalize_field_name(field) for field in data[0]]
        table_items = data[1:]

        return [dict(zip(table_header, table_item)) for table_item in table_items]

    general_data_udf = F.udf(
        normalize_key_value_pair,
        StructType(
            [
                StructField("indice_cadastral", StringType(), True),
                StructField("exercicio", StringType(), True),
                StructField("situacao_atual", StringType(), True),
                StructField("endereco_do_imovel", StringType(), True),
                StructField("endereco_de_correspondencia", StringType(), True),
                StructField("matricula", StringType(), True),
                StructField("cartorio", StringType(), True),
            ]
        ),
    )
    property_data_udf = F.udf(
        normalize_key_value_pair,
        StructType(
            [
                StructField("patrimonio", StringType(), True),
                StructField("tipo_uso", StringType(), True),
                StructField("ap_transp_insc_rateio", StringType(), True),
                StructField("quantidade_de_insc_lote", StringType(), True),
                StructField("lote_ctm", StringType(), True),
                StructField("regional", StringType(), True),
                StructField("zona_uso_zona_homogenea", StringType(), True),
                StructField("frequencia_coleta", StringType(), True),
            ]
        ),
    )
    property_characteristics_udf = F.udf(
        normalize_key_value_pair,
        StructType(
            [
                StructField("area_do_terreno", StringType(), True),
                StructField("fracao_ideal", StringType(), True),
                StructField("area_do_terreno_fracionada", StringType(), True),
                StructField("quantidade_de_economias", StringType(), True),
                StructField("area_construida", StringType(), True),
                StructField("area_privativa_total", StringType(), True),
                StructField("padrao_de_acabamento_pontuacao", StringType(), True),
                StructField("ano_de_construcao", StringType(), True),
            ]
        ),
    )
    land_factors_udf = F.udf(
        normalize_key_value_pair,
        StructType(
            [
                StructField("posicao_lote", StringType(), True),
                StructField("pedologia", StringType(), True),
                StructField("topografia", StringType(), True),
                StructField("gleba", StringType(), True),
                StructField("melhorias", StringType(), True),
            ]
        ),
    )
    construction_factors_udf = F.udf(
        normalize_key_value_pair,
        StructType(
            [
                StructField("fator_comercializacao", StringType(), True),
                StructField("ft_local", StringType(), True),
                StructField("fator_tipologia", StringType(), True),
                StructField("fator_depreciacao", StringType(), True),
            ]
        ),
    )
    immunity_and_exemption_factors_udf = F.udf(
        normalize_key_value_pair,
        StructType(
            [
                StructField("construcao", StringType(), True),
                StructField("terreno", StringType(), True),
                StructField("zona_uso", StringType(), True),
                StructField("patrimonio", StringType(), True),
                StructField("imunidade", StringType(), True),
                StructField("taxa_de_aparelho", StringType(), True),
                StructField("taxa_de_iluminacao", StringType(), True),
                StructField("taxa_de_coleta", StringType(), True),
                StructField("imposto", StringType(), True),
                StructField("isencao_total", StringType(), True),
            ]
        ),
    )
    launch_elements_udf = F.udf(
        normalize_key_value_pair,
        StructType(
            [
                StructField("exercicio", StringType(), True),
                StructField("lancamento", StringType(), True),
                StructField("estado_lancamento", StringType(), True),
                StructField("valor_m2_terreno", StringType(), True),
                StructField("valor_venal_terreno", StringType(), True),
                StructField("valor_m2_construcao", StringType(), True),
                StructField("valor_venal_construcao", StringType(), True),
                StructField("venal_total", StringType(), True),
                StructField("redutor", StringType(), True),
                StructField("fator_venal_geral", StringType(), True),
                StructField("valor_aparelhos_de_transporte", StringType(), True),
                StructField("valor_coleta_de_residuos_solidos", StringType(), True),
                StructField("valor_taxa_de_incendio", StringType(), True),
                StructField("valor_da_taxa_de_iluminacao", StringType(), True),
                StructField("desconto_especial", StringType(), True),
                StructField("valor_imposto", StringType(), True),
            ]
        ),
    )
    building_characteristics_udf = F.udf(
        transform_into_table,
        ArrayType(
            StructType(
                [
                    StructField("grupo", StringType(), True),
                    StructField("subgrupo", StringType(), True),
                    StructField("item", StringType(), True),
                ]
            )
        ),
    )
    unities_udf = F.udf(
        transform_into_table,
        ArrayType(
            StructType(
                [
                    StructField("tipo_de_ocupacao", StringType(), True),
                    StructField("area_construida", StringType(), True),
                    StructField("tipo_construtivo", StringType(), True),
                    StructField("quantidade", StringType(), True),
                ]
            )
        ),
    )

    return (
        dataframe.select("response.*")
        .select(
            general_data_udf(F.col("Dados Cadastrais Gerais")).alias(
                "dados_cadastrais_gerais"
            ),
            property_data_udf(F.col("Dados do Imóvel")).alias("dados_do_imovel"),
            property_characteristics_udf(F.col("Características do Imóvel")).alias(
                "caracteristicas_do_imovel"
            ),
            land_factors_udf(F.col("Fatores Ligados ao Terreno")).alias(
                "fatores_ligados_ao_terreno"
            ),
            construction_factors_udf(F.col("Fatores Ligados à Construção")).alias(
                "fatores_ligados_a_construcao"
            ),
            immunity_and_exemption_factors_udf(
                F.col("Fatores de Imunidade e Isenção")
            ).alias("fatores_de_imunidade_e_isencao"),
            launch_elements_udf(F.col("Elementos do Lançamento")).alias(
                "elementos_do_lancamento"
            ),
            unities_udf(F.col("Unidades")).alias("unidades"),
            building_characteristics_udf(F.col("Características Construtivas")).alias(
                "caracteristicas_construtivas"
            ),
        )
        .withColumns(
            {
                "dt_load": F.lit(date.today()),
                "year": F.col("dados_cadastrais_gerais.exercicio"),
            }
        )
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", help="Forno/Prod values")
    parser.add_argument("datalake_bucket", help="Bucket value in forno/prod")
    parser.add_argument("table_name", help="Name of the table to store data into")
    parser.add_argument("partitions", help="Partition columns name")
    parser.add_argument("execution_date", help="DAG execution_date")

    args = parser.parse_args()

    config_service = ConfigurationService(SOURCE)
    base_s3_ingestion_path = config_service.get_config("base_s3_ingestion_path")

    partition_year = datetime.strptime(args.execution_date, "%Y-%m-%d").year
    dataframe_to_save = transform_data(
        filter_data(load_from_s3(base_path=base_s3_ingestion_path, year=partition_year))
    )

    save_to_datalake(
        dataframe=dataframe_to_save,
        environment=args.env,
        datalake_bucket=args.datalake_bucket,
        table_name=args.table_name,
        partitions=ast.literal_eval(args.partitions),
    )
