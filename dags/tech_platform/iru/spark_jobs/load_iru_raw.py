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

SECRET_KEY_IRU_CREDENTIALS = "IRU_API_CREDENTIALS"
SECRET_KEY_API_TOKEN = "IRU_API_TOKEN"
SECRET_KEY_TENANT = "IRU_TENANT"

IRU_API_VERSION = "v1"
ENDPOINT_KEY = "endpoint"

IRU_ALLOWED_SCHEME = "https"
IRU_ALLOWED_HOST_PATTERN = re.compile(r"^[a-zA-Z0-9\-]+\.api\.kandji\.io$")
IRU_ALLOWED_PATH_PREFIX = f"/api/{IRU_API_VERSION}/"


def _validate_iru_tenant(tenant: str) -> str:
    """Validates that tenant matches expected Kandji domain pattern."""
    tenant = (tenant or "").strip()
    if not tenant:
        raise ValueError("IRU tenant must be a non-empty string")
    if not IRU_ALLOWED_HOST_PATTERN.match(tenant):
        raise ValueError(
            f"IRU tenant '{tenant}' does not match expected pattern "
            "(e.g. 'yourcompany.api.kandji.io')"
        )
    return tenant


def _validate_iru_endpoint(endpoint: str) -> str:
    """Validates that endpoint is a relative path (no scheme/host)."""
    endpoint = (endpoint or "").strip()
    if not endpoint:
        raise ValueError("IRU endpoint must be a non-empty relative path")

    parsed = urlparse(endpoint)
    if parsed.scheme or parsed.netloc:
        raise ValueError("IRU endpoint must be relative (no scheme/host)")
    if endpoint.startswith("//"):
        raise ValueError("IRU endpoint cannot start with '//'")

    return endpoint


def _validate_iru_request_url(url: str) -> str:
    """Validates that the request URL is a valid IRU/Kandji API URL."""
    parsed = urlparse(url)
    normalized_path = parsed.path.rstrip("/") + "/"

    if parsed.scheme != IRU_ALLOWED_SCHEME:
        raise ValueError(f"IRU URL must use HTTPS, got: {parsed.scheme}")
    if not IRU_ALLOWED_HOST_PATTERN.match(parsed.netloc):
        raise ValueError(f"IRU URL host '{parsed.netloc}' is not a valid Kandji domain")
    if not normalized_path.startswith(IRU_ALLOWED_PATH_PREFIX):
        raise ValueError(
            f"IRU URL path must start with '{IRU_ALLOWED_PATH_PREFIX}', "
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


def _load_iru_credentials(dbutils) -> tuple[str, str]:
    """Reads JSON from secret ``IRU_API_CREDENTIALS`` (scope ``quintoandar`` or env)."""
    raw = _get_secret(dbutils, SECRET_KEY_IRU_CREDENTIALS)
    if not raw.strip():
        return "", ""
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        LOGGER.error(
            "m=_load_iru_credentials, msg=Invalid JSON for IRU_API_CREDENTIALS",
            exc_info=e,
        )
        raise RuntimeError(
            f"Secret '{SECRET_KEY_IRU_CREDENTIALS}' must contain valid JSON with keys "
            f"{SECRET_KEY_API_TOKEN}, {SECRET_KEY_TENANT}."
        ) from e
    if not isinstance(payload, dict):
        raise RuntimeError(
            f"Secret '{SECRET_KEY_IRU_CREDENTIALS}' JSON must be an object with keys "
            f"{SECRET_KEY_API_TOKEN}, {SECRET_KEY_TENANT}."
        )
    api_token = str(payload.get(SECRET_KEY_API_TOKEN) or "").strip()
    tenant = str(payload.get(SECRET_KEY_TENANT) or "").strip()
    return api_token, tenant


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


class IruJobArgumentParser:
    """Parses CLI args from LoadCustomTaskCreator."""

    @staticmethod
    def create_parser() -> argparse.ArgumentParser:
        parser = argparse.ArgumentParser(description="IRU/Kandji raw load")
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
            help="Extra details as JSON (endpoint, base_filters, …)",
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


def fetch_all_iru_devices(
    api_token: str,
    tenant: str,
    endpoint: str,
    base_filters: dict[str, Any] | str | None,
    timeout_seconds: int = 120,
) -> list[dict[str, Any]]:
    """Fetch all devices from IRU/Kandji API with pagination."""
    safe_tenant = _validate_iru_tenant(tenant)
    safe_endpoint = _validate_iru_endpoint(endpoint)

    headers = {
        "Authorization": f"Bearer {api_token}",
        "Content-Type": "application/json",
    }
    query_params = _parse_query_params(base_filters)
    limit = int(query_params.get("limit", 300))

    base_url = (
        f"https://{safe_tenant}/api/{IRU_API_VERSION}/{safe_endpoint.lstrip('/')}"
    )
    _validate_iru_request_url(base_url)

    results: list[dict[str, Any]] = []
    offset = 0
    page = 1

    while True:
        LOGGER.info(f"m=fetch_all_iru_devices, page={page}, offset={offset}")
        params = {"limit": limit, "offset": offset}
        params.update({k: v for k, v in query_params.items() if k != "limit"})

        response = requests.get(
            _validate_iru_request_url(base_url),
            headers=headers,
            params=params,
            timeout=timeout_seconds,
        )
        response.raise_for_status()
        data = response.json()

        if isinstance(data, list):
            devices = data
        elif isinstance(data, dict):
            devices = data.get("data", data.get("results", []))
        else:
            devices = []

        if not devices:
            break

        results.extend(devices)

        if len(devices) < limit:
            break

        offset += limit
        page += 1

    return results


def main() -> None:
    try:
        job_args = IruJobArgumentParser.parse_args()
        safe_keys = (
            "environment",
            "dag_name",
            "table_name",
            "extraction_type",
            ENDPOINT_KEY,
        )
        safe_log = {k: job_args.get(k) for k in safe_keys if k in job_args}
        LOGGER.info(f"m=main, msg=Running IRU raw load, summary={safe_log}")

        if not job_args.get(ENDPOINT_KEY):
            raise ValueError("Job requires 'endpoint' in extra_details (e.g. devices).")

        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()

        api_token, tenant = _load_iru_credentials(dbutils)
        if not api_token or not tenant:
            raise RuntimeError(
                "IRU credentials missing. Set Databricks secret "
                f"'{SECRET_KEY_IRU_CREDENTIALS}' in scope '{DATABRICKS_SECRET_SCOPE}' "
                f"to a JSON object with keys {SECRET_KEY_API_TOKEN}, {SECRET_KEY_TENANT}."
            )

        base_filters = job_args.get("base_filters")
        api_data_list = fetch_all_iru_devices(
            api_token, tenant, job_args[ENDPOINT_KEY], base_filters
        )

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
                "m=main, msg=No data returned from IRU API; skipping raw write"
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
