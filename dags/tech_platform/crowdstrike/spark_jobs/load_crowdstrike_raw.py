from __future__ import annotations

import argparse
import json
import os
import re
from datetime import datetime
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

SECRET_KEY_CROWDSTRIKE_CREDENTIALS = "CROWDSTRIKE_API_CREDENTIALS"
SECRET_KEY_CLIENT_ID = "CROWDSTRIKE_CLIENT_ID"
SECRET_KEY_CLIENT_SECRET = "CROWDSTRIKE_CLIENT_SECRET"

CROWDSTRIKE_ALLOWED_SCHEME = "https"
CROWDSTRIKE_ALLOWED_HOST_PATTERN = re.compile(r"^api(\.us-2)?\.crowdstrike\.com$")
CROWDSTRIKE_BASE_URL = "https://api.us-2.crowdstrike.com"
CROWDSTRIKE_TOKEN_ENDPOINT = "/oauth2/token"
CROWDSTRIKE_QUERY_DEVICES_ENDPOINT = "/devices/queries/devices/v1"
CROWDSTRIKE_GET_DEVICES_ENDPOINT = "/devices/entities/devices/v2"


def _validate_crowdstrike_request_url(url: str) -> str:
    """Validates that the request URL is a valid CrowdStrike API URL."""
    parsed = urlparse(url)

    if parsed.scheme != CROWDSTRIKE_ALLOWED_SCHEME:
        raise ValueError(f"CrowdStrike URL must use HTTPS, got: {parsed.scheme}")
    if not CROWDSTRIKE_ALLOWED_HOST_PATTERN.match(parsed.netloc):
        raise ValueError(
            f"CrowdStrike URL host '{parsed.netloc}' is not a valid CrowdStrike domain"
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


def _load_crowdstrike_credentials(dbutils) -> tuple[str, str]:
    """Reads JSON from secret ``CROWDSTRIKE_API_CREDENTIALS``."""
    raw = _get_secret(dbutils, SECRET_KEY_CROWDSTRIKE_CREDENTIALS)
    if not raw.strip():
        return "", ""
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        LOGGER.error(
            "m=_load_crowdstrike_credentials, msg=Invalid JSON for CROWDSTRIKE_API_CREDENTIALS",
            exc_info=e,
        )
        raise RuntimeError(
            f"Secret '{SECRET_KEY_CROWDSTRIKE_CREDENTIALS}' must contain valid JSON with keys "
            f"{SECRET_KEY_CLIENT_ID}, {SECRET_KEY_CLIENT_SECRET}."
        ) from e
    if not isinstance(payload, dict):
        raise RuntimeError(
            f"Secret '{SECRET_KEY_CROWDSTRIKE_CREDENTIALS}' JSON must be an object with keys "
            f"{SECRET_KEY_CLIENT_ID}, {SECRET_KEY_CLIENT_SECRET}."
        )
    client_id = str(payload.get(SECRET_KEY_CLIENT_ID) or "").strip()
    client_secret = str(payload.get(SECRET_KEY_CLIENT_SECRET) or "").strip()
    return client_id, client_secret


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


class CrowdStrikeJobArgumentParser:
    """Parses CLI args from LoadCustomTaskCreator."""

    @staticmethod
    def create_parser() -> argparse.ArgumentParser:
        parser = argparse.ArgumentParser(description="CrowdStrike Falcon raw load")
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


def get_crowdstrike_access_token(
    client_id: str, client_secret: str, timeout_seconds: int = 60
) -> str:
    """Get OAuth2 access token from CrowdStrike."""
    token_url = _validate_crowdstrike_request_url(
        f"{CROWDSTRIKE_BASE_URL}{CROWDSTRIKE_TOKEN_ENDPOINT}"
    )
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    data = {"client_id": client_id, "client_secret": client_secret}

    response = requests.post(
        token_url, headers=headers, data=data, timeout=timeout_seconds
    )
    response.raise_for_status()

    token_data = response.json()
    access_token = token_data.get("access_token")
    if not access_token:
        raise RuntimeError("CrowdStrike token response did not include access_token")

    return access_token


def fetch_all_crowdstrike_devices(
    access_token: str,
    base_filters: dict[str, Any] | str | None,
    timeout_seconds: int = 120,
) -> list[dict[str, Any]]:
    """Fetch all devices from CrowdStrike Falcon API with pagination."""
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    query_params = _parse_query_params(base_filters)
    limit = int(query_params.get("limit", 500))

    query_url = _validate_crowdstrike_request_url(
        f"{CROWDSTRIKE_BASE_URL}{CROWDSTRIKE_QUERY_DEVICES_ENDPOINT}"
    )
    details_url = _validate_crowdstrike_request_url(
        f"{CROWDSTRIKE_BASE_URL}{CROWDSTRIKE_GET_DEVICES_ENDPOINT}"
    )

    all_devices: list[dict[str, Any]] = []
    offset = 0
    page = 1

    while True:
        LOGGER.info(f"m=fetch_all_crowdstrike_devices, page={page}, offset={offset}")

        params = {"limit": limit, "offset": offset}
        response = requests.get(
            query_url, headers=headers, params=params, timeout=timeout_seconds
        )
        response.raise_for_status()
        data = response.json()

        device_ids = data.get("resources", [])
        if not device_ids:
            break

        details_response = requests.post(
            details_url,
            headers=headers,
            json={"ids": device_ids},
            timeout=timeout_seconds,
        )
        details_response.raise_for_status()
        details_data = details_response.json()

        devices = details_data.get("resources", [])
        all_devices.extend(devices)

        LOGGER.info(
            f"m=fetch_all_crowdstrike_devices, page={page}, "
            f"device_ids={len(device_ids)}, devices_fetched={len(devices)}, "
            f"total_so_far={len(all_devices)}"
        )

        if len(device_ids) < limit:
            break

        offset += limit
        page += 1

    return all_devices


def main() -> None:
    try:
        job_args = CrowdStrikeJobArgumentParser.parse_args()
        safe_keys = (
            "environment",
            "dag_name",
            "table_name",
            "extraction_type",
        )
        safe_log = {k: job_args.get(k) for k in safe_keys if k in job_args}
        LOGGER.info(f"m=main, msg=Running CrowdStrike raw load, summary={safe_log}")

        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()

        client_id, client_secret = _load_crowdstrike_credentials(dbutils)
        if not client_id or not client_secret:
            raise RuntimeError(
                "CrowdStrike credentials missing. Set Databricks secret "
                f"'{SECRET_KEY_CROWDSTRIKE_CREDENTIALS}' in scope '{DATABRICKS_SECRET_SCOPE}' "
                f"to a JSON object with keys {SECRET_KEY_CLIENT_ID}, {SECRET_KEY_CLIENT_SECRET}."
            )

        access_token = get_crowdstrike_access_token(client_id, client_secret)
        base_filters = job_args.get("base_filters")
        api_data_list = fetch_all_crowdstrike_devices(access_token, base_filters)

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
                "m=main, msg=No data returned from CrowdStrike API; skipping raw write"
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

    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    spark_metastore_service.create_database(database_name)

    mode = (
        "overwrite" if str(job_args["extraction_type"]).lower() == "full" else "append"
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
