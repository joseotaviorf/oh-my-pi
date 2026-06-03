import ast
import json
import logging
from argparse import ArgumentParser
from datetime import datetime

import pandas as pd
from pyspark.sql import functions as F
from pyspark.sql.types import StructType
from quintoandar_logger import QuintoAndarLogger
from quintoandar_sap_4hana_api_client.clients import Sap4HanaClient
from quintoandar_sap_4hana_api_client.consumers.sap_4hana_consumer import (
    Sap4HanaConsumer,
)

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.pipeline import IncrementalTableLoaderPipeline
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_raw_sap_4hana"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _get_conn_config(dbutils, dbutils_secret_key):
    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=dbutils_secret_key)

    return json.loads(conn_config_json)


def _format_day_errors(failed_days):
    return "\n".join(
        f"  - {day.strftime('%Y-%m-%d')}: {error}" for day, error in failed_days
    )


def _format_empty_days(empty_days):
    return "\n".join(f"  - {day.strftime('%Y-%m-%d')}" for day in empty_days)


def _warn_empty_days(*, empty_days, load_start_date, load_end_date):
    if not empty_days:
        return

    logger.warning(
        "m=load_raw, empty_days=%s, msg=SAP 4HANA raw load returned no data for "
        "%s day(s) in [%s, %s]. Check SAP API token, QueryDatasphere availability, "
        "and ingest_date filter.\n%s",
        [day.strftime("%Y-%m-%d") for day in empty_days],
        len(empty_days),
        load_start_date,
        load_end_date,
        _format_empty_days(empty_days),
    )


def _raise_if_load_failed(
    *,
    failed_days,
    loaded_days,
    load_start_date,
    load_end_date,
):
    if failed_days:
        raise RuntimeError(
            f"SAP 4HANA raw load failed for {len(failed_days)} day(s) "
            f"in [{load_start_date}, {load_end_date}]:\n"
            f"{_format_day_errors(failed_days)}"
        )

    if not loaded_days:
        raise RuntimeError(
            f"SAP 4HANA raw load ingested no data for [{load_start_date}, {load_end_date}]. "
            "No days were processed successfully."
        )


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

    add_validation_target_args(parser)
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

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(SparkClient())
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )
    spark_metastore_service.create_database(write_database_name)

    failed_days = []
    empty_days = []
    loaded_days = []

    for load_dt in date_range:
        try:
            data = consumer.sync(ingest_date=load_dt)
            if not data:
                empty_days.append(load_dt)
                logger.warning(
                    "m=load_raw, load_dt=%s, msg=No data returned by SAP API for this day.",
                    load_dt.strftime("%Y-%m-%d"),
                )
                continue

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

            IncrementalTableLoaderPipeline(
                database_name=write_database_name,
                table_name=write_table_name,
                database_location=write_location,
                layer=LayerEnum.RAW,
                query=None,
                partitions=partitions,
            ).load_and_register(df, format_options)

            loaded_days.append(load_dt)
            logger.info(
                "m=load_raw, load_dt=%s, rows=%s, msg=Successfully loaded SAP 4HANA raw data.",
                load_dt.strftime("%Y-%m-%d"),
                len(data),
            )
        except Exception as e:
            logger.error(
                "m=load_raw, load_dt=%s, error=%s, msg=Failed to load SAP 4HANA raw data.",
                load_dt.strftime("%Y-%m-%d"),
                e,
                exc_info=True,
            )
            failed_days.append((load_dt, str(e)))

    _warn_empty_days(
        empty_days=empty_days,
        load_start_date=load_start_date,
        load_end_date=load_end_date,
    )
    _raise_if_load_failed(
        failed_days=failed_days,
        loaded_days=loaded_days,
        load_start_date=load_start_date,
        load_end_date=load_end_date,
    )

    logger.info(
        "m=load_raw, loaded_days=%s, msg=SAP 4HANA raw load completed successfully.",
        [day.strftime("%Y-%m-%d") for day in loaded_days],
    )
