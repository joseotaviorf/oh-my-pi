import ast
import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta

import boto3
import requests
from pyspark.sql import functions as F
from pyspark.sql.types import StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import (
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline import IncrementalTableLoaderPipeline
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_raw_sap_analytics_cloud"

# The SAC OData credentials live in AWS Secrets Manager rather than in the
# "quintoandar" secret scope most fintech jobs read. The EMR JobFlowRole running
# this step (emr-prod) must allow secretsmanager:GetSecretValue on this secret.
SECRET_ID = "odata_sap_analytics_cloud"
SECRET_REGION = "us-east-1"

REQUEST_TIMEOUT_SECONDS = 300

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

spark_client = SparkClient(app_name=JOB_NAME)
metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
    spark_client
)


def _get_credentials():
    secrets_manager = boto3.client("secretsmanager", region_name=SECRET_REGION)
    secret_string = secrets_manager.get_secret_value(SecretId=SECRET_ID)["SecretString"]

    return json.loads(secret_string)


def _get_access_token(credentials):
    response = requests.post(
        credentials["token_url"],
        data={
            "grant_type": "client_credentials",
            "client_id": credentials["client_id"],
            "client_secret": credentials["client_secret"],
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=REQUEST_TIMEOUT_SECONDS,
    )

    if response.status_code != 200:
        raise RuntimeError(
            f"Failed to obtain SAC access token: {response.status_code}, "
            f"msg={response.text}"
        )

    return response.json()["access_token"]


def _fetch_records(*, odata_url, table_api_path, access_token, ingest_date):
    """Read one day of the SAC OData export, following server-driven paging."""
    # TODO: confirm the SAC export exposes a Date field filterable this way. If it
    # does not, the DAG must switch to extraction_type: full in the declaration and
    # in both *_conf.yml.
    url = f"{odata_url.rstrip('/')}/{table_api_path.lstrip('/')}"
    params = {"$filter": f"Date eq '{ingest_date.strftime('%Y-%m-%d')}'"}
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json",
    }

    records = []
    while url:
        response = requests.get(
            url, params=params, headers=headers, timeout=REQUEST_TIMEOUT_SECONDS
        )
        if response.status_code != 200:
            raise RuntimeError(
                f"SAC OData request failed: {response.status_code}, "
                f"url={url}, msg={response.text}"
            )

        payload = response.json()
        records.extend(payload.get("value", []))
        # OData server-driven paging: the next link already carries the query
        # string, so params must not be sent again.
        url = payload.get("@odata.nextLink")
        params = None

    return records


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
        "m=load_raw, empty_days=%s, msg=SAP Analytics Cloud raw load returned no data "
        "for %s day(s) in [%s, %s]. Check the SAC OData credentials, the export "
        "availability, and the Date filter.\n%s",
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
            f"SAP Analytics Cloud raw load failed for {len(failed_days)} day(s) "
            f"in [{load_start_date}, {load_end_date}]:\n"
            f"{_format_day_errors(failed_days)}"
        )

    if not loaded_days:
        raise RuntimeError(
            "SAP Analytics Cloud raw load ingested no data for "
            f"[{load_start_date}, {load_end_date}]. No days were processed "
            "successfully."
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
                m=__main__, environment={environment}, source={source},
                datalake_bucket={datalake_bucket}, table_name={table_name},
                load_start_date={load_start_date}, load_end_date={load_end_date},
                partitions={partitions}, table_api_path={table_api_path},
                msg=Starting spark job...
        """
    )

    config_service = ConfigurationService(source)
    table_schema = config_service.get_config("tables")[table_name]["table_schema"]
    table_schema = StructType.fromJson(json.loads(table_schema))

    credentials = _get_credentials()
    access_token = _get_access_token(credentials)
    odata_url = credentials["odata_url"]

    load_start_dt = datetime.strptime(load_start_date, "%Y-%m-%d")
    load_end_dt = datetime.strptime(load_end_date, "%Y-%m-%d")

    date_range = [
        load_start_dt + timedelta(days=offset)
        for offset in range((load_end_dt - load_start_dt).days + 1)
    ]

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)

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
    metastore_service.create_database(write_database_name)

    failed_days = []
    empty_days = []
    loaded_days = []

    for load_dt in date_range:
        try:
            data = _fetch_records(
                odata_url=odata_url,
                table_api_path=table_api_path,
                access_token=access_token,
                ingest_date=load_dt,
            )
            if not data:
                empty_days.append(load_dt)
                logger.warning(
                    "m=load_raw, load_dt=%s, msg=No data returned by the SAC OData "
                    "export for this day.",
                    load_dt.strftime("%Y-%m-%d"),
                )
                continue

            df = spark_client.create_dataframe(data, table_schema, verify_schema=False)
            # TODO: if the SAC export carries its own event date, partition by that
            # column instead of the ingestion day.
            df = df.withColumn("ingest_dt", F.lit(load_dt.strftime("%Y-%m-%d")))
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column("ingest_dt")
                .output()
            )
            df = df.drop("ingest_dt")

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
                "m=load_raw, load_dt=%s, rows=%s, msg=Successfully loaded SAP "
                "Analytics Cloud raw data.",
                load_dt.strftime("%Y-%m-%d"),
                len(data),
            )
        except Exception as e:
            logger.error(
                "m=load_raw, load_dt=%s, error=%s, msg=Failed to load SAP Analytics "
                "Cloud raw data.",
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
        "m=load_raw, loaded_days=%s, msg=SAP Analytics Cloud raw load completed "
        "successfully.",
        [day.strftime("%Y-%m-%d") for day in loaded_days],
    )
