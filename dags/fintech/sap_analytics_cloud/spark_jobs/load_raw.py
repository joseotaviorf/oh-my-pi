import ast
import json
import logging
import socket
import ssl
import time
from argparse import ArgumentParser
from datetime import datetime
from urllib.parse import urlencode, urlsplit

import boto3
import requests
from botocore.exceptions import ClientError
from pyspark.sql.functions import lit
from pyspark.sql.types import StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline import IncrementalTableLoaderPipeline
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import MetastoreServiceFactory
from bietlejuice.services.storage_services.s3_service import S3Service

JOB_NAME = "load_raw_sap_analytics_cloud"

REQUEST_TIMEOUT_SECONDS = 300

REQUEST_ATTEMPTS = 3
REQUEST_RETRY_BACKOFF_SECONDS = 10

# Scratch area for the raw export; cleared before staging and after the load.
STAGING_PREFIX = "tmp/api_ingestion"

# The model's date dimension, at monthly grain and formatted as YYYYMM. One
# month is one block of this load: the unfiltered export moves at roughly
# 0.9 MB/s, so pulling the whole model took over two hours and never finished,
# while a single month is about 1.2 GiB and lands in around 25 minutes.
DATE_DIMENSION = "Date"
DATE_DIMENSION_FORMAT = "%Y%m"

HTTPS_PORT = 443
EGRESS_PROBE_TIMEOUT_SECONDS = 10
# Any always-on host outside the VPC works; it only has to prove that the
# cluster can open a TLS connection to somewhere other than the tenant.
EGRESS_PROBE_CONTROL_HOST = "www.google.com"

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


def _tls_probe(address, sni):
    """Try to complete a TLS handshake, announcing ``sni`` as the server name.

    Trust is deliberately not enforced: the question is only whether the
    packets reach a TLS server, and a certificate coming back already answers
    it.
    """
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    try:
        with socket.create_connection(
            (address, HTTPS_PORT), timeout=EGRESS_PROBE_TIMEOUT_SECONDS
        ) as sock:
            with context.wrap_socket(sock, server_hostname=sni) as tls:
                return f"reached ({tls.version()})"
    except OSError as error:
        return f"blocked ({type(error).__name__})"


def _diagnose_egress(host):
    """Report which side is dropping the connection to ``host``.

    The step runs unattended and the cluster is torn down with it, so the only
    chance to collect this is while the failing run is still up. Sending a
    control server name to the tenant's own address is what separates the two
    causes: a handshake that succeeds only when the name changes means the name
    is being filtered on the way out, not the address being refused by SAP.
    """
    try:
        address = socket.gethostbyname(host)
    except OSError as error:
        return f"{host} does not resolve from the cluster ({error})."

    control = _tls_probe(EGRESS_PROBE_CONTROL_HOST, EGRESS_PROBE_CONTROL_HOST)
    with_real_sni = _tls_probe(address, host)
    with_control_sni = _tls_probe(address, EGRESS_PROBE_CONTROL_HOST)

    if control.startswith("blocked"):
        verdict = (
            "the cluster cannot reach the public internet at all, so this is "
            "not specific to the tenant."
        )
    elif with_control_sni.startswith("reached") and with_real_sni.startswith("blocked"):
        verdict = (
            "the tenant address accepts a handshake under another server name, "
            "so the name is being filtered on the way out: the egress path has "
            "to allow the tenant domains."
        )
    elif with_real_sni.startswith("blocked"):
        verdict = (
            "the tenant address refuses the handshake under any server name, "
            "so the source address is being filtered: the tenant has to accept "
            "this cluster's NAT address."
        )
    else:
        verdict = "the probe did reach the tenant, so the failure is intermittent."

    return (
        f"Egress probe: {EGRESS_PROBE_CONTROL_HOST}={control}; "
        f"{address} as {host}={with_real_sni}; "
        f"{address} as {EGRESS_PROBE_CONTROL_HOST}={with_control_sni}. "
        f"Reading: {verdict}"
    )


def _request(method, url, **kwargs):
    """Issue an HTTP request, retrying transient failures to reach the tenant.

    SAC is outside the VPC, so every run depends on the cluster's egress path.
    When that path drops the connection, requests raises a bare ConnectionError
    that surfaces in Airflow as "Unknown Error" and only becomes readable after
    pulling the step's stdout out of S3. Name the host and the likely cause
    instead: the credentials are already known-good by this point, so a
    connection that dies before any HTTP response points at the network, not at
    the secret.
    """
    host = urlsplit(url).netloc

    for attempt in range(1, REQUEST_ATTEMPTS + 1):
        try:
            return requests.request(method, url, **kwargs)
        except (requests.ConnectionError, requests.Timeout) as error:
            if attempt == REQUEST_ATTEMPTS:
                try:
                    diagnosis = _diagnose_egress(host)
                except Exception as probe_error:  # noqa: BLE001 - never mask the original failure
                    diagnosis = f"Egress probe failed to run: {probe_error}."

                raise RuntimeError(
                    f"Could not reach {host} after {REQUEST_ATTEMPTS} attempts: "
                    f"{error}. The request never got an HTTP response, so this is "
                    f"the egress path rather than the SAC credentials. {diagnosis}"
                ) from error

            wait_seconds = REQUEST_RETRY_BACKOFF_SECONDS * attempt
            logger.warning(
                f"m=_request, host={host}, attempt={attempt}/{REQUEST_ATTEMPTS}, "
                f"error={error}, msg=Retrying in {wait_seconds}s..."
            )
            time.sleep(wait_seconds)


def _get_access_token(credentials):
    response = _request(
        "post",
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


def _staging_path(*, datalake_bucket, source, table_name, month):
    """Where the raw export lands before Spark reads it.

    Keyed by month so two months staged at once cannot read each other's pages.
    """
    return f"s3://{datalake_bucket}/{STAGING_PREFIX}/{source}/{table_name}/{month}"


def _clear_staging(s3_resource, staging_path):
    """Drop anything left under ``staging_path``.

    The task is retried, and a retry that finds pages from the attempt that
    died would read them on top of the ones it writes and load the overlap
    twice. The prefix is scoped to one table and one month, so nothing else can
    live under it.
    """
    parts = urlsplit(staging_path)
    s3_resource.Bucket(parts.netloc).objects.filter(
        Prefix=parts.path.lstrip("/")
    ).delete()


def _stage_export(
    *,
    odata_url,
    table_api_path,
    access_token,
    target_month,
    staging_path,
    storage_service,
):
    """Stream one month of the export into ``staging_path``, one object per page.

    Collecting the whole export into a Python list is what killed an earlier
    run: the driver reached roughly 17 GB resident and the kernel took the
    process down with no traceback. Writing each page out and dropping it keeps
    driver memory bounded by a single page, and lets Spark read the result in
    parallel instead of materialising it on the driver.

    The month is filtered by the API rather than here, so the request only
    transfers the block being loaded.

    Returns the number of rows staged and every column seen across the export.
    """
    query = urlencode(
        {"$format": "JSON", "$filter": f"{DATE_DIMENSION} eq '{target_month}'"}
    )
    url = f"{_tenant_base_url(odata_url)}/{table_api_path.lstrip('/')}?{query}"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json",
    }

    row_count = 0
    pages = 0
    exported_columns = set()

    while url:
        response = _request(
            "get", url, headers=headers, timeout=REQUEST_TIMEOUT_SECONDS
        )
        if response.status_code != 200:
            raise RuntimeError(
                f"SAC OData request failed: {response.status_code}, "
                f"url={url}, msg={response.text}"
            )

        payload = response.json()
        rows = payload.get("value", [])

        if rows:
            pages += 1
            # Accumulated across every page, not sampled from the first one:
            # the export omits null properties, so a column that happens to be
            # null throughout the first page is absent there and present later.
            exported_columns.update(*(row.keys() for row in rows))
            # Checked per page, not once the export finishes. An unfiltered
            # export pages for many hours, so a check that waits for the last
            # page cannot report the wasted transfer until it is already spent.
            _raise_unless_month_is_isolated(
                {row.get(DATE_DIMENSION) for row in rows}, target_month
            )

            storage_service.upload_file(
                "\n".join(json.dumps(row) for row in rows),
                f"{staging_path}/page_{pages:06d}.json",
            )
            row_count += len(rows)
            # An earlier run spent 27 minutes paging without emitting a single
            # line, so a stuck export looked exactly like a slow one.
            logger.info(
                f"m=_stage_export, month={target_month}, pages={pages}, "
                f"rows={row_count}, msg=Staged a page of the SAC export."
            )

        # Every page must be followed before the export is considered complete:
        # a partially read export silently yields an incomplete snapshot.
        url = payload.get("@odata.nextLink")

    return row_count, exported_columns


def _raise_if_schema_diverges(exported_columns, table_schema):
    """Fail when the export does not carry every configured column.

    The export is addressed by an opaque provider id, so pointing the DAG at the
    wrong SAC model is easy to do and would otherwise load a table of nulls,
    because the dataframe is read without schema inference.
    """
    expected = {field.name for field in table_schema.fields}
    missing = sorted(expected - exported_columns)

    if missing:
        raise RuntimeError(
            f"The SAP Analytics Cloud export does not carry {len(missing)} of the "
            f"configured columns: {missing}. Check that table_api_path points at "
            "the intended model."
        )


def _raise_if_export_is_empty(row_count, target_month):
    """Refuse to publish an empty month.

    The load overwrites the month's partition, so writing an empty export would
    replace good data with nothing.
    """
    if not row_count:
        raise RuntimeError(
            f"The SAP Analytics Cloud export returned no rows for {target_month}. "
            "Refusing to overwrite that month's partition with an empty load."
        )


def _raise_unless_month_is_isolated(page_months, target_month):
    """Fail when a page carries any month other than the requested one.

    The month is filtered by the API and nothing downstream re-checks it. If
    that filter were ignored the run would pull the whole model and write every
    month of it into the target month's partition, which reads as a plausible
    month of data rather than as a failure.
    """
    unexpected = sorted(month for month in page_months if month != target_month)

    if unexpected:
        raise RuntimeError(
            f"The export for {target_month} also carries {len(unexpected)} other "
            f"month(s): {unexpected[:12]}. The API did not honour the "
            f"{DATE_DIMENSION} filter; stopping before the whole model is "
            f"transferred and written into the {target_month} partition."
        )


def _raise_unless_partition_overwrite_is_dynamic(spark):
    """Refuse to write unless overwrite is scoped to the month being loaded.

    The run writes a single month, partitioned by that month. Under 'static'
    the overwrite would replace the whole table, so each month block would
    erase the ones loaded before it and the table would only ever hold the
    month that ran last. The cluster pins dynamic (see
    sap_analytics_cloud_cluster.yml); this check keeps the load from silently
    destroying history if that override is dropped.
    """
    mode = spark.conf.get(PARTITION_OVERWRITE_MODE_KEY, None)

    if mode is None or str(mode).strip().lower() != "dynamic":
        raise RuntimeError(
            f"{PARTITION_OVERWRITE_MODE_KEY}={mode!r}. This monthly load needs "
            "'dynamic' so the overwrite replaces only the month being loaded "
            "instead of erasing every month already in the table; refusing to "
            "write. "
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

    # The month being loaded comes from the run's own date, so the daily
    # schedule keeps refreshing the current month and an Airflow backfill over
    # past dates is all a regressive month-by-month ingestion needs.
    target_month = datetime.strptime(load_end_date, "%Y-%m-%d").strftime(
        DATE_DIMENSION_FORMAT
    )

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

    _raise_unless_partition_overwrite_is_dynamic(spark_client.conn)

    s3_resource = boto3.resource("s3")
    staging_path = _staging_path(
        datalake_bucket=datalake_bucket,
        source=source,
        table_name=table_name,
        month=target_month,
    )

    _clear_staging(s3_resource, staging_path)
    row_count, exported_columns = _stage_export(
        odata_url=odata_url,
        table_api_path=table_api_path,
        access_token=access_token,
        target_month=target_month,
        staging_path=staging_path,
        storage_service=S3Service(s3_resource),
    )
    _raise_if_export_is_empty(row_count, target_month)
    _raise_if_schema_diverges(exported_columns, table_schema)

    # The schema is declared rather than inferred: inference would sample the
    # staged JSON and is free to read a column as long on one run and double on
    # the next, depending on the rows it happens to see. FAILFAST because the
    # default would turn a value that does not fit its column into a null, and
    # a financial measure that quietly becomes null is worse than a failed run.
    df = (
        spark_client.conn.read.schema(table_schema)
        .option("mode", "FAILFAST")
        .json(staging_path)
    )
    # Partitioned by the month the data belongs to, not by the day it was
    # loaded, so a month always lands in the same partition however many times
    # it is reloaded. Literals rather than values derived from the rows: every
    # row was just checked to carry target_month, so this writes exactly one
    # partition and the dynamic overwrite cannot reach another month.
    df = df.withColumn("year", lit(int(target_month[:4]))).withColumn(
        "month", lit(int(target_month[4:]))
    )

    IncrementalTableLoaderPipeline(
        database_name=write_database_name,
        table_name=write_table_name,
        database_location=write_location,
        layer=LayerEnum.RAW,
        query=None,
        partitions=partitions,
    ).load_and_register(df, format_options)

    # Only now that the table is written can the staged pages go: the read
    # above is lazy, so deleting any earlier would pull the input out from
    # under the write.
    _clear_staging(s3_resource, staging_path)

    logger.info(
        "m=load_raw, month=%s, rows=%s, msg=SAP Analytics Cloud raw monthly load "
        "completed successfully.",
        target_month,
        row_count,
    )
