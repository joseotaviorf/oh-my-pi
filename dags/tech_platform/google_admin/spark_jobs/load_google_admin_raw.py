from __future__ import annotations

import argparse
import json
import os
import time
from datetime import datetime
from typing import Any
from urllib.parse import urlparse

import requests
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import service_account
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.base.validation.target_resolver import managed_table_fqn
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.jobs.common.helpers import insert_partitions, json_to_dataframe
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_google_admin_raw"
LOGGER = QuintoAndarLogger(__name__)

DATABRICKS_SECRET_SCOPE = "quintoandar"

SECRET_KEY_GOOGLE_ADMIN_CREDENTIALS = "GOOGLE_ADMIN_API_CREDENTIALS"
SECRET_KEY_ADMIN_SUBJECT = "GOOGLE_ADMIN_SUBJECT"
SECRET_KEY_CUSTOMER_ID = "GOOGLE_CUSTOMER_ID"
SECRET_KEY_SERVICE_ACCOUNT_KEY = "GOOGLE_SERVICE_ACCOUNT_KEY"

GOOGLE_ADMIN_SCOPES = [
    "https://www.googleapis.com/auth/admin.directory.device.mobile.readonly",
    "https://www.googleapis.com/auth/cloud-identity.devices.readonly",
]
GOOGLE_ADMIN_API_BASE = "https://admin.googleapis.com/admin/directory/v1"
GOOGLE_ADMIN_ALLOWED_SCHEME = "https"
GOOGLE_ADMIN_ALLOWED_HOST = "admin.googleapis.com"
GOOGLE_ADMIN_MOBILE_PATH_PREFIX = "/admin/directory/v1/customer/"

CLOUD_IDENTITY_API_BASE = "https://cloudidentity.googleapis.com/v1"
CLOUD_IDENTITY_ALLOWED_HOST = "cloudidentity.googleapis.com"
CLOUD_IDENTITY_DEVICES_PATH = "/v1/devices"

# Google recommends exponential backoff on these for Workspace / Cloud Identity APIs.
RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}
MAX_RETRIES = 5
INITIAL_BACKOFF_SECONDS = 2.0
MAX_BACKOFF_SECONDS = 60.0


def _validate_google_admin_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme != GOOGLE_ADMIN_ALLOWED_SCHEME:
        raise ValueError(f"Google Admin URL must use HTTPS, got: {parsed.scheme}")
    if parsed.netloc != GOOGLE_ADMIN_ALLOWED_HOST:
        raise ValueError(
            f"Google Admin URL host '{parsed.netloc}' must be '{GOOGLE_ADMIN_ALLOWED_HOST}'"
        )
    if not parsed.path.startswith(GOOGLE_ADMIN_MOBILE_PATH_PREFIX):
        raise ValueError(
            f"Google Admin URL path must start with '{GOOGLE_ADMIN_MOBILE_PATH_PREFIX}', "
            f"got: {parsed.path}"
        )
    return url


def _validate_cloud_identity_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme != GOOGLE_ADMIN_ALLOWED_SCHEME:
        raise ValueError(f"Cloud Identity URL must use HTTPS, got: {parsed.scheme}")
    if parsed.netloc != CLOUD_IDENTITY_ALLOWED_HOST:
        raise ValueError(
            f"Cloud Identity URL host '{parsed.netloc}' must be '{CLOUD_IDENTITY_ALLOWED_HOST}'"
        )
    if not parsed.path.startswith(CLOUD_IDENTITY_DEVICES_PATH):
        raise ValueError(
            f"Cloud Identity URL path must start with '{CLOUD_IDENTITY_DEVICES_PATH}', "
            f"got: {parsed.path}"
        )
    return url


def _get_secret(dbutils, key: str, env_key: str | None = None) -> str:
    try:
        if dbutils is not None:
            return dbutils.secrets.get(scope=DATABRICKS_SECRET_SCOPE, key=key).strip()
    except Exception:
        pass
    env_key = env_key or key
    return os.environ.get(env_key, "").strip()


def _load_google_admin_credentials(
    dbutils,
) -> tuple[str, str, dict[str, Any]]:
    """Reads JSON from Databricks secret ``GOOGLE_ADMIN_API_CREDENTIALS``.

    Expected JSON shape::

        {
            "GOOGLE_ADMIN_SUBJECT": "admin@quintoandar.com.br",
            "GOOGLE_CUSTOMER_ID": "my_customer",
            "GOOGLE_SERVICE_ACCOUNT_KEY": { ...service account key dict... }
        }

    To create/update the secret::

        databricks secrets put-secret quintoandar GOOGLE_ADMIN_API_CREDENTIALS \\
            --string-value '{"GOOGLE_ADMIN_SUBJECT": "...", "GOOGLE_CUSTOMER_ID": "...",
                             "GOOGLE_SERVICE_ACCOUNT_KEY": {...}}'
    """
    raw = _get_secret(dbutils, SECRET_KEY_GOOGLE_ADMIN_CREDENTIALS)
    if not raw.strip():
        return "", "", {}
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        LOGGER.error(
            "m=_load_google_admin_credentials, msg=Invalid JSON for GOOGLE_ADMIN_API_CREDENTIALS",
            exc_info=e,
        )
        raise RuntimeError(
            f"Secret '{SECRET_KEY_GOOGLE_ADMIN_CREDENTIALS}' must contain valid JSON with keys "
            f"{SECRET_KEY_ADMIN_SUBJECT}, {SECRET_KEY_CUSTOMER_ID}, {SECRET_KEY_SERVICE_ACCOUNT_KEY}."
        ) from e
    if not isinstance(payload, dict):
        raise RuntimeError(
            f"Secret '{SECRET_KEY_GOOGLE_ADMIN_CREDENTIALS}' JSON must be an object."
        )
    admin_subject = str(payload.get(SECRET_KEY_ADMIN_SUBJECT) or "").strip()
    customer_id = str(payload.get(SECRET_KEY_CUSTOMER_ID) or "my_customer").strip()
    sa_key = payload.get(SECRET_KEY_SERVICE_ACCOUNT_KEY)
    if not isinstance(sa_key, dict):
        raise RuntimeError(
            f"Secret '{SECRET_KEY_GOOGLE_ADMIN_CREDENTIALS}': key "
            f"'{SECRET_KEY_SERVICE_ACCOUNT_KEY}' must be a JSON object (service account key dict)."
        )
    return admin_subject, customer_id, sa_key


def _get_access_token(service_account_key: dict[str, Any], admin_subject: str) -> str:
    creds = service_account.Credentials.from_service_account_info(
        service_account_key,
        scopes=GOOGLE_ADMIN_SCOPES,
        subject=admin_subject,
    )
    creds.refresh(GoogleAuthRequest())
    return creds.token


def _retry_delay_seconds(response: requests.Response | None, attempt: int) -> float:
    if response is not None:
        retry_after = response.headers.get("Retry-After")
        if retry_after and retry_after.isdigit():
            return min(float(retry_after), MAX_BACKOFF_SECONDS)
    return min(INITIAL_BACKOFF_SECONDS * (2**attempt), MAX_BACKOFF_SECONDS)


def _get_with_retry(
    url: str,
    headers: dict[str, str],
    params: dict[str, Any],
    timeout_seconds: int,
    method_name: str,
) -> requests.Response:
    """GET with exponential backoff on transient errors (5xx, 429, network).

    Returns the response as-is for non-retryable status codes (e.g. 401) so the
    caller keeps control over auth refresh and ``raise_for_status``.
    """
    last_error: Exception | None = None
    for attempt in range(MAX_RETRIES + 1):
        response: requests.Response | None = None
        try:
            response = requests.get(
                url, headers=headers, params=params, timeout=timeout_seconds
            )
            if response.status_code not in RETRYABLE_STATUS_CODES:
                return response
            last_error = requests.HTTPError(
                f"{response.status_code} {response.reason}", response=response
            )
        except (requests.ConnectionError, requests.Timeout) as e:
            last_error = e

        if attempt == MAX_RETRIES:
            break
        delay = _retry_delay_seconds(response, attempt)
        LOGGER.warning(
            f"m={method_name}, msg=Transient error, retrying, "
            f"attempt={attempt + 1}/{MAX_RETRIES}, delay_seconds={delay:.1f}, "
            f"error={last_error}"
        )
        time.sleep(delay)

    LOGGER.error(
        f"m={method_name}, msg=Giving up after {MAX_RETRIES} retries, error={last_error}"
    )
    raise last_error  # type: ignore[misc]


def _parse_query_params(
    base_filters: dict[str, Any] | str | None,
) -> dict[str, Any]:
    if base_filters is None:
        return {}
    if isinstance(base_filters, str):
        try:
            base_filters = json.loads(base_filters)
        except json.JSONDecodeError as e:
            LOGGER.error(
                "m=_parse_query_params, msg=Invalid JSON for base_filters",
                exc_info=e,
            )
            raise
    if not isinstance(base_filters, dict):
        raise TypeError("base_filters must be a dict or JSON object string")
    return base_filters


class GoogleAdminJobArgumentParser:
    """Parses CLI args produced by LoadCustomTaskCreator."""

    @staticmethod
    def create_parser() -> argparse.ArgumentParser:
        parser = argparse.ArgumentParser(description="Google Admin raw load")
        parser.add_argument("environment", help="Environment (e.g., forno, prod)")
        parser.add_argument("datalake_bucket", help="Target S3 bucket")
        parser.add_argument("dag_name", help="DAG name / source schema")
        parser.add_argument("table_name", help="Table name to process")
        parser.add_argument("execution_date", help="Execution date (YYYY-MM-DD)")
        parser.add_argument(
            "partitions", help="Partition columns (comma-separated or JSON list)"
        )
        parser.add_argument(
            "extraction_type", help="Extraction type (full, incremental)"
        )
        parser.add_argument("load_start_date", help="Start date (YYYY-MM-DD)")
        parser.add_argument("load_end_date", help="End date (YYYY-MM-DD)")
        parser.add_argument(
            "table_privileges",
            nargs="?",
            default="null",
            help="Table privileges as JSON",
        )
        parser.add_argument(
            "extra_details",
            nargs="?",
            default="{}",
            help="Extra details as JSON (base_filters, …)",
        )
        add_validation_target_args(parser)
        return parser

    @classmethod
    def parse_args(cls) -> dict[str, Any]:
        parser = cls.create_parser()
        args = parser.parse_args()
        args_dict = vars(args)

        extra_details_str = args_dict.pop("extra_details", "{}")
        try:
            extra_details = json.loads(extra_details_str)
        except json.JSONDecodeError as e:
            LOGGER.error(
                "m=parse_args, msg=Invalid JSON for extra_details",
                exc_info=e,
            )
            raise
        args_dict.update(extra_details)

        if "base_filters" in args_dict and isinstance(args_dict["base_filters"], str):
            try:
                args_dict["base_filters"] = json.loads(args_dict["base_filters"])
            except json.JSONDecodeError as e:
                LOGGER.error(
                    "m=parse_args, msg=Failed to parse base_filters string",
                    exc_info=e,
                )
                raise

        for date_field in ("load_start_date", "load_end_date", "execution_date"):
            date_str = args_dict.get(date_field)
            if date_str:
                try:
                    args_dict[date_field] = datetime.strptime(
                        str(date_str), "%Y-%m-%d"
                    ).date()
                except ValueError as e:
                    LOGGER.error(
                        f"m=parse_args, msg=Invalid date, field={date_field}, value={date_str}",
                        exc_info=e,
                    )
                    raise

        raw_partitions = args_dict.get("partitions")
        partition_cols: list[str] = []
        if raw_partitions:
            raw_partitions = str(raw_partitions).strip()
            if raw_partitions and raw_partitions != "[]":
                try:
                    parsed = json.loads(raw_partitions)
                    if isinstance(parsed, list) and all(
                        isinstance(p, str) for p in parsed
                    ):
                        partition_cols = [col.strip() for col in parsed if col.strip()]
                    else:
                        LOGGER.warning(
                            "m=parse_args, msg=Partitions not a JSON list of strings; "
                            "falling back to comma-separated"
                        )
                        partition_cols = [
                            col.strip()
                            for col in raw_partitions.split(",")
                            if col.strip()
                        ]
                except json.JSONDecodeError:
                    partition_cols = [
                        col.strip() for col in raw_partitions.split(",") if col.strip()
                    ]

        args_dict["partition_cols"] = partition_cols
        return args_dict


def fetch_all_cloud_identity_devices(
    service_account_key: dict[str, Any],
    admin_subject: str,
    customer_id: str,
    base_filters: dict[str, Any] | str | None,
    timeout_seconds: int = 180,
) -> list[dict[str, Any]]:
    """Fetch all devices from Google Cloud Identity API (Windows, macOS, Linux, etc.)."""
    customer_resource = (
        f"customers/{customer_id}"
        if customer_id != "my_customer"
        else "customers/my_customer"
    )
    url = f"{CLOUD_IDENTITY_API_BASE}/devices"
    _validate_cloud_identity_url(url)

    token = _get_access_token(service_account_key, admin_subject)
    headers = {"Authorization": f"Bearer {token}"}

    query_params = _parse_query_params(base_filters)
    page_size = int(query_params.get("pageSize", 50))

    results: list[dict[str, Any]] = []
    page_token: str | None = None
    page = 1

    while True:
        LOGGER.info(f"m=fetch_all_cloud_identity_devices, page={page}")
        params: dict[str, Any] = {
            "customer": customer_resource,
            "pageSize": page_size,
        }
        if page_token:
            params["pageToken"] = page_token

        response = _get_with_retry(
            url, headers, params, timeout_seconds, "fetch_all_cloud_identity_devices"
        )

        if response.status_code == 401:
            LOGGER.info(
                "m=fetch_all_cloud_identity_devices, msg=Access token expired, refreshing"
            )
            token = _get_access_token(service_account_key, admin_subject)
            headers = {"Authorization": f"Bearer {token}"}
            response = _get_with_retry(
                url,
                headers,
                params,
                timeout_seconds,
                "fetch_all_cloud_identity_devices",
            )

        response.raise_for_status()
        data = response.json()

        devices: list[dict[str, Any]] = data.get("devices", [])
        results.extend(devices)

        page_token = data.get("nextPageToken")
        if not page_token:
            break
        page += 1

    return results


def fetch_all_cloud_identity_device_users(
    service_account_key: dict[str, Any],
    admin_subject: str,
    customer_id: str,
    base_filters: dict[str, Any] | str | None,
    timeout_seconds: int = 180,
) -> list[dict[str, Any]]:
    """Fetch all device-user assignments from Google Cloud Identity API.

    Uses the ``devices/-/deviceUsers`` wildcard list endpoint to retrieve, in a
    single paginated call, every device-to-user assignment across all endpoints
    (the same mapping the Admin console shows in its E-mail column).
    """
    customer_resource = (
        f"customers/{customer_id}"
        if customer_id != "my_customer"
        else "customers/my_customer"
    )
    url = f"{CLOUD_IDENTITY_API_BASE}/devices/-/deviceUsers"
    _validate_cloud_identity_url(url)

    token = _get_access_token(service_account_key, admin_subject)
    headers = {"Authorization": f"Bearer {token}"}

    query_params = _parse_query_params(base_filters)
    page_size = int(query_params.get("pageSize", 50))

    results: list[dict[str, Any]] = []
    page_token: str | None = None
    page = 1

    while True:
        LOGGER.info(f"m=fetch_all_cloud_identity_device_users, page={page}")
        params: dict[str, Any] = {
            "customer": customer_resource,
            "pageSize": page_size,
        }
        if page_token:
            params["pageToken"] = page_token

        response = _get_with_retry(
            url,
            headers,
            params,
            timeout_seconds,
            "fetch_all_cloud_identity_device_users",
        )

        if response.status_code == 401:
            LOGGER.info(
                "m=fetch_all_cloud_identity_device_users, msg=Access token expired, refreshing"
            )
            token = _get_access_token(service_account_key, admin_subject)
            headers = {"Authorization": f"Bearer {token}"}
            response = _get_with_retry(
                url,
                headers,
                params,
                timeout_seconds,
                "fetch_all_cloud_identity_device_users",
            )

        response.raise_for_status()
        data = response.json()

        device_users: list[dict[str, Any]] = data.get("deviceUsers", [])
        results.extend(device_users)

        page_token = data.get("nextPageToken")
        if not page_token:
            break
        page += 1

    return results


def fetch_all_mobile_devices(
    service_account_key: dict[str, Any],
    admin_subject: str,
    customer_id: str,
    base_filters: dict[str, Any] | str | None,
    timeout_seconds: int = 120,
) -> list[dict[str, Any]]:
    """Fetch all mobile devices from Google Admin Directory API with pagination."""
    query_params = _parse_query_params(base_filters)
    max_results = int(query_params.get("maxResults", 100))

    url = f"{GOOGLE_ADMIN_API_BASE}/customer/{customer_id}/devices/mobile"
    _validate_google_admin_url(url)

    token = _get_access_token(service_account_key, admin_subject)
    headers = {"Authorization": f"Bearer {token}"}

    results: list[dict[str, Any]] = []
    page_token: str | None = None
    page = 1

    while True:
        LOGGER.info(f"m=fetch_all_mobile_devices, page={page}")
        params: dict[str, Any] = {"maxResults": max_results, "projection": "FULL"}
        if page_token:
            params["pageToken"] = page_token

        response = _get_with_retry(
            url, headers, params, timeout_seconds, "fetch_all_mobile_devices"
        )

        if response.status_code == 401:
            LOGGER.info(
                "m=fetch_all_mobile_devices, msg=Access token expired, refreshing"
            )
            token = _get_access_token(service_account_key, admin_subject)
            headers = {"Authorization": f"Bearer {token}"}
            response = _get_with_retry(
                url, headers, params, timeout_seconds, "fetch_all_mobile_devices"
            )

        response.raise_for_status()
        data = response.json()

        devices: list[dict[str, Any]] = data.get("mobiledevices", [])
        results.extend(devices)

        page_token = data.get("nextPageToken")
        if not page_token:
            break
        page += 1

    return results


def main() -> None:
    try:
        job_args = GoogleAdminJobArgumentParser.parse_args()
        safe_log = {
            k: job_args.get(k)
            for k in ("environment", "dag_name", "table_name", "extraction_type")
            if k in job_args
        }
        LOGGER.info(f"m=main, msg=Running Google Admin raw load, summary={safe_log}")

        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()

        admin_subject, customer_id, sa_key = _load_google_admin_credentials(dbutils)
        if not admin_subject or not sa_key:
            raise RuntimeError(
                "Google Admin credentials missing. Set Databricks secret "
                f"'{SECRET_KEY_GOOGLE_ADMIN_CREDENTIALS}' in scope '{DATABRICKS_SECRET_SCOPE}' "
                f"to a JSON object with keys {SECRET_KEY_ADMIN_SUBJECT}, "
                f"{SECRET_KEY_CUSTOMER_ID}, {SECRET_KEY_SERVICE_ACCOUNT_KEY}."
            )

        base_filters = job_args.get("base_filters")
        table_name = job_args["table_name"]

        if table_name == "cloud_identity_devices":
            api_data_list = fetch_all_cloud_identity_devices(
                sa_key, admin_subject, customer_id, base_filters
            )
        elif table_name == "cloud_identity_device_users":
            api_data_list = fetch_all_cloud_identity_device_users(
                sa_key, admin_subject, customer_id, base_filters
            )
        else:
            api_data_list = fetch_all_mobile_devices(
                sa_key, admin_subject, customer_id, base_filters
            )

        LOGGER.info(
            f"m=main, msg=Fetched devices from Google Admin API, "
            f"count={len(api_data_list)}, table={table_name}"
        )

        spark_client = SparkClient(app_name=JOB_NAME)
        spark = spark_client.conn

        if api_data_list:
            df = json_to_dataframe(spark, api_data_list)
            exec_date_str = str(job_args["execution_date"])
            df = df.withColumn("_exec_dt", F.lit(exec_date_str))
            df = insert_partitions(
                df,
                date_column_to_partition="_exec_dt",
                datetime_format="yyyy-MM-dd",
            )
            df = df.drop("_exec_dt")
            _load_to_raw(spark_client, job_args, df)
            LOGGER.info(
                f"m=main, msg=Loaded records into raw, count={len(api_data_list)}, "
                f"table={job_args['table_name']}"
            )
        else:
            LOGGER.warning(
                "m=main, msg=No data returned from Google Admin API; skipping raw write"
            )

    except Exception:
        LOGGER.error("m=main, msg=Job failed", exc_info=True)
        raise


def _load_to_raw(spark_client: SparkClient, job_args: dict[str, Any], df) -> None:
    db_info = DatalakeMetastoreService.get_db_info(
        job_args["environment"], job_args["dag_name"], job_args["datalake_bucket"]
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=job_args["table_name"],
            prod_location=database_location,
            bucket=job_args["datalake_bucket"],
            target_database=job_args.get("target_database_name"),
            target_table=job_args.get("target_table_name"),
        )
    )

    s3_loader = S3Loader()
    spark_metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    )
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    spark_metastore_service.create_database(write_database_name)

    mode = (
        "overwrite" if str(job_args["extraction_type"]).lower() == "full" else "append"
    )
    s3_loader.load_df(
        df=df,
        s3_path=f"{write_location.rstrip('/')}/{write_table_name}",
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        partitions=job_args["partition_cols"],
        write_mode=mode,
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=write_database_name,
        table_name=write_table_name,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=write_location,
        partitions=job_args["partition_cols"],
        force_recreate=True,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=write_database_name,
        table_name=write_table_name,
        partition_cols=job_args["partition_cols"],
    )

    _apply_table_privileges(job_args, database_name)


def _apply_table_privileges(job_args: dict[str, Any], database_name: str) -> None:
    raw_privileges_json = job_args.get("table_privileges")
    if not raw_privileges_json or raw_privileges_json == "null":
        return
    try:
        privileges_dict = json.loads(raw_privileges_json)
    except json.JSONDecodeError as e:
        LOGGER.error(
            "m=_apply_table_privileges, msg=Invalid JSON for table_privileges",
            exc_info=e,
        )
        raise
    if not privileges_dict or not UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        return
    full_table_name = managed_table_fqn(
        database_name,
        job_args["table_name"],
        target_database=job_args.get("target_database_name"),
        target_table=job_args.get("target_table_name"),
    )
    TablePrivileges.from_input_dict(privileges_dict, full_table_name).apply()
    LOGGER.info(
        f"m=_apply_table_privileges, msg=Privileges applied, table={full_table_name}"
    )


if __name__ == "__main__":
    main()
