import json
import logging
import ast
from datetime import datetime
from argparse import ArgumentParser
from functools import reduce

import pandas as pd
from pyspark.sql.types import StructType
from pyspark.sql import functions as F
from pyspark.sql import DataFrame

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

from quintoandar_sap_4hana_api_client.clients import Sap4HanaClient
from quintoandar_sap_4hana_api_client.consumers.sap_4hana_consumer import (
    Sap4HanaConsumer,
)


JOB_NAME = "load_raw_sap_4hana"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _get_conn_config(dbutils, dbutils_secret_key):
    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=dbutils_secret_key)

    return json.loads(conn_config_json)


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
    table_api_path = extra_args["table_api_path"]

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name},load_start_date={load_start_date}, load_end_date={load_end_date},
                partitions={partitions}, table_api_path={table_api_path}, msg=Starting spark job...
        """
    )

    config_service = ConfigurationService(source)
    table_schema = config_service.get_config("tables")[table_name]["table_schema"]
    table_schema = StructType.fromJson(json.loads(table_schema))

    spark_client = SparkClient()
    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()

    conn_config = _get_conn_config(dbutils, APIEnum.SAP_4HANA)

    sap_client = Sap4HanaClient(conn_config, attempts=3)
    consumer = Sap4HanaConsumer(
        path=table_api_path,
        records_key="value",
        client=sap_client,
    )

    load_start_dt = datetime.strptime(load_start_date, "%Y-%m-%d")
    load_end_dt = datetime.strptime(load_end_date, "%Y-%m-%d")

    date_range = (
        pd.date_range(start=load_start_dt, end=load_end_date).to_pydatetime().tolist()
    )

    dfs = []
    for load_dt in date_range:
        try:
            data = consumer.sync(ingest_date=load_dt)
            df = spark_client.create_dataframe(data, table_schema, verify_schema=False)
            df = df.withColumn(
                "cpudt_dt",
                F.to_date(
                    F.expr("COALESCE(NULLIF(aedat, '00000000'), cpudt)"), "yyyyMMdd"
                ),
            )
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column("cpudt_dt")
                .output()
            )
            df = df.drop("cpudt_dt")
            dfs.append(df)
        except Exception as e:
            logger.info(f"{e}, m=Error loading data for {load_dt}")
    if dfs:
        df = reduce(DataFrame.unionAll, dfs)
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
