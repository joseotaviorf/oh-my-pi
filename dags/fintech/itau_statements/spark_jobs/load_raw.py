import json
import logging
import ast
from datetime import datetime, timedelta
from argparse import ArgumentParser
from functools import reduce
import requests
import tempfile
from time import sleep

import pandas as pd
from pyspark.sql.types import StructType, StringType
from pyspark.sql import DataFrame
from pyspark.sql.functions import lit

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.api import APIEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.pipeline import IncrementalTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

from quintoandar_logger import QuintoAndarLogger


JOB_NAME = "load_raw_sap_4hana"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def create_end_date(start_date):
    return (start_date + timedelta(days=1)).strftime("%Y-%m-%d")


def get_data(statement_id, credentials, start_date):
    page = 1
    data = []
    tries = 0
    while True:
        url = f"https://account-statement.api.itau.com/account-statement/v1/statements/{statement_id}"
        params = {
            "type": "current_account",
            "page_size": 50000,
            "start_date": start_date.strftime("%Y-%m-%d"),
            "end_date": create_end_date(start_date),
            "page": page,
        }
        response = requests.get(
            url,
            headers=credentials["headers"],
            params=params,
            cert=credentials["certs"],
        )
        if response.status_code != 200:
            credentials = reauth(credentials)
            tries += 1
            if tries > 3:
                print(
                    f"Error retriving data for statement_id={statement_id} and start_date={start_date}! Response: {response.text} - {response.status_code}"
                )
                response.raise_for_status()
            sleep(2)
            continue
        response = response.json()
        data.extend(response.get("data", [{}])[0].get("events", []))
        if response["pagination"]["total_pages"] != response["pagination"]["page"]:
            page = response["pagination"]["page"] + 1
            tries = 0
        else:
            break
    return pd.json_normalize(data, sep="_")


def get_token(credentials):
    token_url = "https://sts.itau.com.br/api/oauth/token"

    token_data = {
        "grant_type": "client_credentials",
        "client_id": credentials["client_id"],
        "client_secret": credentials["client_secret"],
    }

    response = requests.post(
        token_url,
        data=token_data,
        cert=credentials["certs"],
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    if response.status_code == 200:
        token_info = response.json()
        return token_info.get("access_token")
    else:
        raise Exception(
            f"Erro ao obter o token: {response.status_code}, msg={response.text}"
        )


def reauth(credentials):
    credentials["headers"] = {
        "x-itau-correlationid": credentials["correlation_id"],
        "Authorization": f"Bearer {get_token(credentials)}",
    }
    return credentials


def prepare_temp_file(file_text):
    fl = tempfile.NamedTemporaryFile(delete=False)
    fl.write(file_text.encode("utf-8"))
    fl.close()
    return fl.name


def _get_conn_config(dbutils, dbutils_secret_key):
    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=dbutils_secret_key)
    credentials = json.loads(conn_config_json)
    certs = (
        prepare_temp_file(credentials["cert"]),
        prepare_temp_file(credentials["cert_key"]),
    )
    credentials["certs"] = certs
    credentials["headers"] = {
        "x-itau-correlationid": credentials["correlation_id"],
        "Authorization": f"Bearer {get_token(credentials)}",
    }
    return credentials


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("partitions")
    parser.add_argument("extra_args")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    partitions = ast.literal_eval(args.partitions)
    extra_args = json.loads(args.extra_args)
    statement_id = extra_args["statement_id"]

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name},load_start_date={load_start_date}, load_end_date={load_end_date},
                partitions={partitions}, statement_id={statement_id}, msg=Starting spark job...
        """
    )

    config_service = ConfigurationService(source)
    table_schema = config_service.get_config("tables_details")[table_name][
        "table_schema"
    ]
    table_schema = StructType.fromJson(json.loads(table_schema))

    spark_client = SparkClient()
    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()

    conn_config = _get_conn_config(dbutils, APIEnum.ITAU.value)

    load_start_dt = datetime.strptime(load_start_date, "%Y-%m-%d")
    load_end_dt = datetime.strptime(load_end_date, "%Y-%m-%d")

    date_range = (
        pd.date_range(start=load_start_dt, end=load_end_date).to_pydatetime().tolist()
    )

    dfs = []
    for load_dt in date_range:
        try:
            data = get_data(statement_id, conn_config, load_dt)
            if data.empty:
                continue
            print(statement_id, load_dt)
            if "literal_complementary" in data.columns:
                data["literal_complementary"] = (
                    data["literal_complementary"].replace("", None).astype(str)
                )
            df = spark_client.create_dataframe(data)
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(load_dt)
                .output()
            )
            dfs.append(df)
        except Exception as e:

            logger.info(f"{e}, m=Error loading data for {load_dt}, msg={e}")
            raise e
    if dfs:
        all_columns = set()
        for df in dfs:
            all_columns.update(df.schema.names)

        merged_dfs = []
        for df in dfs:
            for col in all_columns:
                if col not in df.columns:
                    df = df.withColumn(col, lit(None).cast(StringType()))
            merged_dfs.append(df.select(*all_columns))

        df = reduce(DataFrame.unionAll, merged_dfs)
        db_info = DatalakeMetastoreService.get_db_info(
            environment, source, datalake_bucket
        )
        spark_metastore_service = SparkMetastoreService(SparkClient())
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

        # create database if it doesn't exists
        database_name = db_info["db_raw_databricks"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        database_location = db_info["db_raw_path"]
        spark_metastore_service.create_database(database_name)
        if df:
            IncrementalTableLoaderPipeline(
                database_name=database_name,
                table_name=table_name,
                database_location=database_location,
                layer=LayerEnum.RAW,
                query=None,
                partitions=partitions,
            ).load_and_register(df, format_options)
        else:
            logger.info(f"m=No data to load for this period!")

    else:
        logger.info(f"m=No data to load for this period!")
