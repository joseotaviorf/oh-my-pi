import ast
import json
import logging
from argparse import ArgumentParser
from datetime import datetime
from urllib.parse import urlsplit

import boto3
import requests
from botocore.exceptions import ClientError
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
from bietlejuice.pipeline import FullTableLoaderPipeline
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_raw_sap_analytics_cloud"

REQUEST_TIMEOUT_SECONDS = 300

PARTITION_OVERWRITE_MODE_KEY = "spark.sql.sources.partitionOverwriteMode"

REQUIRED_SECRET_KEYS = frozenset(
    {"token_url", "client_id", "client_secret", "odata_url"}
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

spark_client = SparkClient(app_name=JOB_NAME)
metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
    spark_client
)


def _get_credentials(secret_id, secret_region):
    secrets_manager = boto3.client("secretsmanager", region_name=secret_region)

    try:
        secret_string = secrets_manager.get_secret_value(SecretId=secret_id)[
            "SecretString"
        ]
    except ClientError as error:
        raise RuntimeError(
            f"Could not read the SAC credentials from AWS Secrets Manager: "
            f"secret_id={secret_id}, region={secret_region}, "
            f"error={error.response['Error']['Code']}. ResourceNotFoundException "
            "means the secret does not exist in the account running this step; "
            "AccessDeniedException means the EMR JobFlowRole lacks "
            "secretsmanager:GetSecretValue on it."
        ) from error

    credentials = json.loads(secret_string)
    missing_keys = sorted(REQUIRED_SECRET_KEYS.difference(credentials))
    if missing_keys:
        raise RuntimeError(
            f"The SAC credentials secret is missing required keys: {missing_keys}, "
            f"secret_id={secret_id}, region={secret_region}."
        )

    return credentials


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


def _tenant_base_url(odata_url):
    """Return only ``scheme://host`` from the ``odata_url`` kept in the secret.

    The stored value is a complete FactData endpoint — provider id and query
    string included — so the export path coming from the configuration cannot
    simply be appended to it.
    """
    parts = urlsplit(odata_url)
    if not parts.scheme or not parts.netloc:
        raise RuntimeError(
            f"The odata_url in the secret is not an absolute URL: {odata_url!r}."
        )

    return f"{parts.scheme}://{parts.netloc}"


def _fetch_records(*, odata_url, table_api_path, access_token):
    """Read the whole fact data export, following OData server-driven paging."""
    url = f"{_tenant_base_url(odata_url)}/{table_api_path.lstrip('/')}"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json",
    }

    records = []
    while url:
        response = requests.get(url, headers=headers, timeout=REQUEST_TIMEOUT_SECONDS)
        if response.status_code != 200:
            raise RuntimeError(
                f"SAC OData request failed: {response.status_code}, "
                f"url={url}, msg={response.text}"
            )

        payload = response.json()
        records.extend(payload.get("value", []))
        # Every page must be followed before the export is considered complete:
        # a partially read export silently yields an incomplete snapshot.
        url = payload.get("@odata.nextLink")

    return records


def _raise_if_schema_diverges(records, table_schema):
    """Fail when the export does not carry every configured column.

    The export is addressed by an opaque provider id, so pointing the DAG at the
    wrong SAC model is easy to do and would otherwise load a table of nulls,
    because the dataframe is built without schema verification.
    """
    expected = {field.name for field in table_schema.fields}
    exported = set().union(*(record.keys() for record in records))
    missing = sorted(expected - exported)

    if missing:
        raise RuntimeError(
            f"The SAP Analytics Cloud export does not carry {len(missing)} of the "
            f"configured columns: {missing}. Check that table_api_path points at "
            "the intended model."
        )


def _raise_if_export_is_empty(records):
    """Refuse to publish an empty export.

    The load overwrites the table, so writing an empty export would replace a
    good snapshot with nothing.
    """
    if not records:
        raise RuntimeError(
            "The SAP Analytics Cloud export returned no rows. Refusing to "
            "overwrite the existing snapshot with an empty full load."
        )


def _raise_unless_partition_overwrite_is_static(spark):
    """Refuse to write unless overwrite replaces every partition.

    The run writes the whole model into the current year/month/day partition.
    Under the EMR preset default (dynamic) that leaves each earlier run's full
    copy in place, so an unfiltered read returns one duplicate snapshot per run
    day. The cluster pins static (see sap_analytics_cloud_cluster.yml); this
    check keeps the load from silently degrading if that override is dropped.
    """
    mode = spark.conf.get(PARTITION_OVERWRITE_MODE_KEY, None)

    if mode is None or str(mode).strip().lower() != "static":
        raise RuntimeError(
            f"{PARTITION_OVERWRITE_MODE_KEY}={mode!r}. This full load needs "
            "'static' so the overwrite replaces every partition instead of "
            "accumulating one full snapshot per run day; refusing to write. "
            "See sap_analytics_cloud_cluster.yml."
        )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="name of the output table")
    parser.add_argument("load_end_date")
    parser.add_argument("partitions")
    parser.add_argument("extra_args")

    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    load_end_date = args.load_end_date
    partitions = ast.literal_eval(args.partitions)
    extra_args = json.loads(args.extra_args)
    table_api_path = extra_args["table_api_path"]

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source},
                datalake_bucket={datalake_bucket}, table_name={table_name},
                load_end_date={load_end_date},
                partitions={partitions}, table_api_path={table_api_path},
                msg=Starting spark job...
        """
    )

    config_service = ConfigurationService(source)
    table_schema = config_service.get_config("tables")[table_name]["table_schema"]
    table_schema = StructType.fromJson(json.loads(table_schema))

    credentials = _get_credentials(
        secret_id=config_service.get_config("secret_id"),
        secret_region=config_service.get_config("secret_region"),
    )
    access_token = _get_access_token(credentials)
    odata_url = credentials["odata_url"]

    snapshot_dt = datetime.strptime(load_end_date, "%Y-%m-%d")

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

    _raise_unless_partition_overwrite_is_static(spark_client.conn)

    records = _fetch_records(
        odata_url=odata_url,
        table_api_path=table_api_path,
        access_token=access_token,
    )
    _raise_if_export_is_empty(records)
    _raise_if_schema_diverges(records, table_schema)

    df = spark_client.create_dataframe(records, table_schema, verify_schema=False)
    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_date(snapshot_dt)
        .output()
    )

    FullTableLoaderPipeline(
        database_name=write_database_name,
        table_name=write_table_name,
        database_location=write_location,
        layer=LayerEnum.RAW,
        query=None,
        partitions=partitions,
    ).load_and_register(df, format_options)

    logger.info(
        "m=load_raw, snapshot_dt=%s, rows=%s, msg=SAP Analytics Cloud raw full load "
        "completed successfully.",
        load_end_date,
        len(records),
    )
