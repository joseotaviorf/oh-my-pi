from __future__ import annotations

import argparse
import json
import re
import time
from typing import Any
from urllib.parse import urlparse

import requests
from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.jobs.common.helpers import insert_partitions, json_to_dataframe
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

LOGGER = QuintoAndarLogger(__name__)

DATABRICKS_SECRET_SCOPE = "quintoandar"

SECRET_KEY_ZSCALER_CREDENTIALS = "ZSCALER_API_CREDENTIALS"
SECRET_KEY_CLIENT_ID = "ZCC_CLIENT_ID"
SECRET_KEY_CLIENT_SECRET = "ZCC_CLIENT_SECRET"
SECRET_KEY_CLOUD = "ZCC_CLOUD"

ZSCALER_ALLOWED_SCHEME = "https"
ZSCALER_ALLOWED_HOST_PATTERN = re.compile(r"^api-mobile\.[a-z]+\.net$")
ZSCALER_DEFAULT_CLOUD = "zscalertwo"
ZSCALER_AUTH_ENDPOINT = "/auth/v1/login"
ZSCALER_DEVICES_ENDPOINT = "/public/v1/getDevices"

TOKEN_REFRESH_THRESHOLD_SECONDS = 40


def _get_zscaler_base_url(cloud: str) -> str:
    return f"https://api-mobile.{cloud}.net/papi"


def _validate_zscaler_request_url(url: str, cloud: str) -> str:
    parsed = urlparse(url)

    if parsed.scheme != ZSCALER_ALLOWED_SCHEME:
        raise ValueError(f"Zscaler URL must use HTTPS, got: {parsed.scheme}")

    expected_host = f"api-mobile.{cloud}.net"
    if parsed.netloc != expected_host:
        raise ValueError(
            f"Zscaler URL host '{parsed.netloc}' does not match expected '{expected_host}'"
        )

    return url


def _get_secret(dbutils, scope: str, key: str) -> str:
    try:
        return dbutils.secrets.get(scope=scope, key=key)
    except Exception as e:
        LOGGER.error(f"m=_get_secret, msg=Failed to get secret {key}", exc_info=e)
        raise


def _load_zscaler_credentials(dbutils) -> tuple[str, str, str]:
    raw_secret = _get_secret(
        dbutils, DATABRICKS_SECRET_SCOPE, SECRET_KEY_ZSCALER_CREDENTIALS
    )
    try:
        payload = json.loads(raw_secret)
    except json.JSONDecodeError as e:
        raise RuntimeError(
            f"Secret '{SECRET_KEY_ZSCALER_CREDENTIALS}' must contain valid JSON with keys "
            f"{SECRET_KEY_CLIENT_ID}, {SECRET_KEY_CLIENT_SECRET}, {SECRET_KEY_CLOUD}. "
            f"JSONDecodeError: {e}"
        ) from e

    client_id = str(payload.get(SECRET_KEY_CLIENT_ID) or "").strip()
    client_secret = str(payload.get(SECRET_KEY_CLIENT_SECRET) or "").strip()
    cloud = str(payload.get(SECRET_KEY_CLOUD) or ZSCALER_DEFAULT_CLOUD).strip()

    return client_id, client_secret, cloud


class ZscalerTokenManager:
    def __init__(self, client_id: str, client_secret: str, cloud: str):
        self.client_id = client_id
        self.client_secret = client_secret
        self.cloud = cloud
        self.base_url = _get_zscaler_base_url(cloud)
        self.token: str | None = None
        self.token_time: float = 0

    def authenticate(self, timeout_seconds: int = 60) -> str:
        token_url = f"{self.base_url}{ZSCALER_AUTH_ENDPOINT}"
        _validate_zscaler_request_url(token_url, self.cloud)

        payload = {
            "apiKey": self.client_id,
            "secretKey": self.client_secret,
        }

        LOGGER.info(f"m=authenticate, msg=Authenticating to Zscaler, url={token_url}")
        response = requests.post(token_url, json=payload, timeout=timeout_seconds)
        response.raise_for_status()

        data = response.json()
        self.token = data.get("jwtToken")
        self.token_time = time.time()

        if not self.token:
            raise RuntimeError("Zscaler authentication response missing jwtToken")

        LOGGER.info("m=authenticate, msg=Authentication successful")
        return self.token

    def ensure_token(self, timeout_seconds: int = 60) -> str:
        if (
            not self.token
            or (time.time() - self.token_time) > TOKEN_REFRESH_THRESHOLD_SECONDS
        ):
            LOGGER.info("m=ensure_token, msg=Token expired or missing, refreshing...")
            return self.authenticate(timeout_seconds)
        return self.token


def fetch_all_zscaler_devices(
    token_manager: ZscalerTokenManager,
    base_filters: dict[str, str] | None = None,
    timeout_seconds: int = 60,
) -> list[dict[str, Any]]:
    all_devices: list[dict[str, Any]] = []
    page = 1
    page_size = int((base_filters or {}).get("pageSize", "500"))

    while True:
        token = token_manager.ensure_token(timeout_seconds)

        devices_url = f"{token_manager.base_url}{ZSCALER_DEVICES_ENDPOINT}"
        _validate_zscaler_request_url(devices_url, token_manager.cloud)

        headers = {
            "Content-Type": "application/json",
            "auth-token": token,
        }
        params = {"page": page, "pageSize": page_size}

        LOGGER.info(f"m=fetch_all_zscaler_devices, msg=Fetching page {page}")
        response = requests.get(
            devices_url, headers=headers, params=params, timeout=timeout_seconds
        )

        if response.status_code == 401:
            LOGGER.info("m=fetch_all_zscaler_devices, msg=Token expired, refreshing...")
            token = token_manager.authenticate(timeout_seconds)
            headers["auth-token"] = token
            response = requests.get(
                devices_url, headers=headers, params=params, timeout=timeout_seconds
            )

        response.raise_for_status()
        devices = response.json()

        if not devices:
            break

        all_devices.extend(devices)
        LOGGER.info(
            f"m=fetch_all_zscaler_devices, msg=Page {page} fetched, "
            f"devices_in_page={len(devices)}, total={len(all_devices)}"
        )

        if len(devices) < page_size:
            break

        page += 1

    LOGGER.info(
        f"m=fetch_all_zscaler_devices, msg=Finished, total_devices={len(all_devices)}"
    )
    return all_devices


class ZscalerJobArgumentParser:
    @staticmethod
    def parse_args(args: list[str] | None = None) -> dict[str, Any]:
        parser = argparse.ArgumentParser(description="Zscaler raw data loader")
        parser.add_argument("environment", help="Environment (forno/prod)")
        parser.add_argument("bucket", help="S3 bucket for data storage")
        parser.add_argument("dag_name", help="DAG name")
        parser.add_argument("table_name", help="Target table name")
        parser.add_argument("ds", help="Execution date (YYYY-MM-DD)")
        parser.add_argument("partitions", help="Partition columns as JSON list")
        parser.add_argument(
            "extraction_type", help="Extraction type (full/incremental)"
        )
        parser.add_argument("load_start_date", help="Start date (YYYY-MM-DD)")
        parser.add_argument("load_end_date", help="End date (YYYY-MM-DD)")
        parser.add_argument(
            "table_privileges",
            nargs="?",
            default="null",
            help="Table privileges as JSON (group -> list of permissions)",
        )
        parser.add_argument(
            "extra_details",
            nargs="?",
            default="{}",
            help="Extra arguments as JSON",
        )

        parsed = parser.parse_args(args)

        try:
            partition_cols = json.loads(parsed.partitions)
        except json.JSONDecodeError:
            partition_cols = ["year", "month", "day"]

        try:
            extra_details = json.loads(parsed.extra_details)
        except json.JSONDecodeError:
            extra_details = {}

        base_filters = None
        if "base_filters" in extra_details:
            bf = extra_details["base_filters"]
            base_filters = json.loads(bf) if isinstance(bf, str) else bf

        return {
            "environment": parsed.environment,
            "bucket": parsed.bucket,
            "dag_name": parsed.dag_name,
            "table_name": parsed.table_name,
            "ds": parsed.ds,
            "partition_cols": partition_cols,
            "extraction_type": parsed.extraction_type,
            "load_start_date": parsed.load_start_date,
            "load_end_date": parsed.load_end_date,
            "table_privileges": parsed.table_privileges,
            "base_filters": base_filters,
        }


def main() -> None:
    try:
        job_args = ZscalerJobArgumentParser.parse_args()
        safe_log = {
            "environment": job_args.get("environment"),
            "dag_name": job_args.get("dag_name"),
            "table_name": job_args.get("table_name"),
            "extraction_type": job_args.get("extraction_type"),
        }
        LOGGER.info(f"m=main, msg=Running Zscaler raw load, summary={safe_log}")

        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()

        client_id, client_secret, cloud = _load_zscaler_credentials(dbutils)

        if not client_id or not client_secret:
            raise RuntimeError(
                "Zscaler credentials missing. Set Databricks secret "
                f"'{SECRET_KEY_ZSCALER_CREDENTIALS}' in scope '{DATABRICKS_SECRET_SCOPE}' "
                f"to a JSON object with keys {SECRET_KEY_CLIENT_ID}, {SECRET_KEY_CLIENT_SECRET}."
            )

        token_manager = ZscalerTokenManager(client_id, client_secret, cloud)
        token_manager.authenticate()

        base_filters = job_args.get("base_filters")
        api_data_list = fetch_all_zscaler_devices(token_manager, base_filters)

        spark = SparkSession.builder.getOrCreate()
        spark_client = SparkClient()

        if api_data_list:
            df = json_to_dataframe(spark, api_data_list)
            df = insert_partitions(df)
            _load_to_raw(spark_client, job_args, df)
            LOGGER.info(
                f"m=main, msg=Loaded records into raw, count={len(api_data_list)}, "
                f"table={job_args['table_name']}"
            )
        else:
            LOGGER.warning(
                "m=main, msg=No data returned from Zscaler API; skipping raw write"
            )

    except Exception:
        LOGGER.error("m=main, msg=Job failed", exc_info=True)
        raise


def _load_to_raw(spark_client: SparkClient, job_args: dict[str, Any], df) -> None:
    db_info = DatalakeMetastoreService.get_db_info(
        job_args["environment"], job_args["dag_name"], job_args["bucket"]
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    spark_metastore_service.create_database(database_name)

    mode = (
        "overwrite" if str(job_args["extraction_type"]).lower() == "full" else "append"
    )

    LOGGER.info(
        f"m=_load_to_raw, msg=Writing to raw, database={database_name}, "
        f"table={job_args['table_name']}, path={database_location}, rows={df.count()}, mode={mode}"
    )

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{job_args['table_name']}",
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        partitions=job_args["partition_cols"],
        write_mode=mode,
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=job_args["table_name"],
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=database_location,
        partitions=job_args["partition_cols"],
        force_recreate=True,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=database_name,
        table_name=job_args["table_name"],
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
    full_table_name = f"{database_name}.{job_args['table_name']}"
    TablePrivileges.from_input_dict(privileges_dict, full_table_name).apply()
    LOGGER.info(
        f"m=_apply_table_privileges, msg=Privileges applied, table={full_table_name}"
    )


if __name__ == "__main__":
    main()
