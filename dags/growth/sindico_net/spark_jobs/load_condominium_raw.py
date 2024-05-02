import json
import requests
from datetime import datetime

from argparse import ArgumentParser
from pyspark.sql import DataFrame
import pyspark.sql.functions as SF
from functools import reduce

import logging
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_entity_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("SindicoNet")

def _fetch_auth_token(login_url:str, credentials:dict) -> DataFrame:
    """
    Make a POST request to fetch auth token from SindicoNet plataform.
    """
    session = requests.Session()
    try:
        auth_response = session.post(
            login_url,
            json = credentials,
        )
        token = json.loads(auth_response.text)["token"]

        return f"Bearer {token}"

    except Exception as exception:
        logging.error(f"Fail to fetch auth token from SindicoNet plataform. error:{exception}")

        raise exception

def _fetch_condominium_data(auth_token:str, condominium_url:str, execution_date:str) -> DataFrame:
    """
    Fetch raw data from all condominiums.
    """
    headers = {
        "Accept": "application/json",
        "Authorization": auth_token
    }

    page = 1
    result = []

    while True:
        try:
            response = requests.get(f"{condominium_url}?page={page}", headers=headers)
            if response.status_code == 200:
                try:
                    data = json.loads(response.text)

                    if data['total'] > 0:
                        page += 1

                        api_page_df = spark.createDataFrame([
                        {
                            "id": str(row['id']),
                            "keyword": str(row['keyWord']),
                            "date_updated": str(row['dateUpdated']),
                            "data_construcao": str(row['dataConstrucao']),
                            "cnpj": str(row['cnpj']),
                            "condominio": str(row['condominio']),
                            "cep": str(row['cep']),
                            "rua": str(row['rua']),
                            "numero": str(row['numero']),
                            "bairro": str(row['bairro']),
                            "estado": str(row['estado']),
                            "cidade": str(row['cidade']),
                            "latitude": str(row['latitude']),
                            "longitude": str(row['longitude']),
                            "total_unidades": str(row['totalUnidades']),
                            "elevador": int(row['elevador']),
                            "total_elevadores": int(row['totalElevadores']),
                            "portaria": int(row['portaria']),
                            "total_portarias": str(row['totalPortarias']),
                            "piscina": int(row['piscina']),
                            "churrasqueira": int(row['churrasqueira']),
                            "quadra_esportiva": int(row['quadraEsportiva']),
                            "piscina": int(row['piscina']),
                            "academia": int(row['academia']),
                            "salao_festa": int(row['salaoFesta']),
                            "sauna": int(row['sauna']),
                            "salao_festa": int(row['salaoFesta']),
                            "lavanderia": int(row['lavanderia']),
                            "gas_encanado": int(row['gasEncanado']),
                            "total_blocos": str(row['totalBlocos']),
                            "areaGourmet": str(row['areaGourmet']),
                            "caracteristicas_condominio": str(row['caracteristicasCondominio']),
                            "quantidade_funcionarios": str(row['quantidadeFuncionarios']),
                            "arrecadacao_mensal": str(row['arrecadacaoMensal']),
                            "indice_inadimplencia": str(row['indiceInadimplencia']),
                            "quantidade_vagas_garagem": str(row['quantidadeVagasGaragem']),
                            "quantidade_pavimentos_garagem": str(row['quantidadePavimentosGaragem']),
                            "quantidade_andares": str(row['quantidadeAndares']),
                            "quantidade_portoes_garagem": str(row['quantidadePortoesGaragem']),
                            "possui_sindico_morador_ou_profissional": str(row['possuiSindicoMoradorOuProfissional']),
                            "possui_conta_corrente_ou_conta_pool": str(row['possuiContaCorrenteOuContaPool']),
                            "administraco_propria_ou_terceirizada": str(row['administracoPropriaOuTerceirizada']),
                            "quantidade_caixas_agua": str(row['quantidadeCaixasAgua']),
                            "funcionarios_terceirizados": str(row['funcionariosTerceirizados']),
                            "realizam_reuso_agua": str(row['realizamReusoAgua']),
                            "origem": str(row['origem']),
                            } for row in data['items']
                        ])

                        result.append(api_page_df)
                    else:
                        break
                except Exception as exception:
                    logging.error(f"Fail to extract data. Schema error:{exception}")
                    raise exception
            else:
                logging.error(f"Unsuccessful request to fetch campaign data from {condominium_url}. Status code: {response.status_code}")
                raise Exception(f"Network error. status code response: {response.status_code}")

        except Exception as exception:
            logging.error(f"Fail to fetch campaign data from Thribee plataform. error:{exception}")
            raise exception

    if len(result) > 0:
        return reduce(DataFrame.unionAll, result)

    logging.error(f"No data found for account to date {execution_date}.")

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="entity to load data")
    parser.add_argument("execution_date", help="time to load data")

    args = parser.parse_args()
    env = args.env
    source = args.source
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    execution_date = args.execution_date

    config_service = ConfigurationService(source)
    login_url = config_service.get_config("login_url")
    condominium_url = config_service.get_config("condominium_url")

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials = json.loads(dbutils.secrets.get(scope="quintoandar", key=APIEnum.SINDICONET))

    logger.info(
        f"""m=__main__, env={env}, source={source}, datalake_bucket={datalake_bucket},
        execution_date={execution_date}, table_name={table_name},
        msg=Starting spark job..."""
    )

    """
    Fetch condominiums data.
    """
    auth_token = _fetch_auth_token(login_url, credentials)
    df = _fetch_condominium_data(auth_token, condominium_url, execution_date)
    if df:
        """
        Adding load_date columns
        """
        df = df.withColumn('load_date',SF.lit(execution_date))

        """
        Load data to datalake.
        """
        spark_client = SparkClient()
        spark_context = spark_client.conn.sparkContext
        dataframe_service = SparkDataFrameService()

        db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_service.create_database(database_name)

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader = S3Loader()

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            compression="gzip",
        )

        """
        Update metastore.
        """
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
        )
    else:
        logger
