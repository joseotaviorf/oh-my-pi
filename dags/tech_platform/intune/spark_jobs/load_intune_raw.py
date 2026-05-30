from __future__ import annotations

import argparse
import json
import os
from datetime import datetime
from typing import Any
from urllib.parse import urlparse

import requests
from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.jobs.common.helpers import insert_partitions, json_to_dataframe
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

LOGGER = QuintoAndarLogger(__name__)

DATABRICKS_SECRET_SCOPE = "quintoandar"

SECRET_KEY_GRAPH_API = "INTUNE_GRAPH_API"
SECRET_KEY_TENANT_ID = "INTUNE_AZURE_TENANT_ID"
SECRET_KEY_CLIENT_ID = "INTUNE_AZURE_CLIENT_ID"
SECRET_KEY_CLIENT_SECRET = "INTUNE_AZURE_CLIENT_SECRET"

GRAPH_SCOPE = "https://graph.microsoft.com/.default"
GRAPH_API_BASE = "https://graph.microsoft.com/v1.0"
GRAPH_ALLOWED_SCHEME = "https"
GRAPH_ALLOWED_HOST = "graph.microsoft.com"
GRAPH_ALLOWED_PATH_PREFIX = "/v1.0/"

ENDPOINT_KEY = "endpoint"


def _get_secret(dbutils, key: str, env_key: str | None = None) -> str:
    try:
        if dbutils is not None:
            return dbutils.secrets.get(scope=DATABRICKS_SECRET_SCOPE, key=key).strip()
    except Exception:
        pass
    env_key = env_key or key
    return os.environ.get(env_key, "").strip()


def _load_intune_graph_credentials(dbutils) -> tuple[str, str, str]:
    """Reads JSON from secret ``INTUNE_GRAPH_API`` (scope ``quintoandar`` or env ``INTUNE_GRAPH_API``)."""
    raw = _get_secret(dbutils, SECRET_KEY_GRAPH_API)
    if not raw.strip():
        return "", "", ""
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        LOGGER.error(
            "m=_load_intune_graph_credentials, msg=Invalid JSON for INTUNE_GRAPH_API",
            exc_info=e,
        )
        raise RuntimeError(
            f"Secret '{SECRET_KEY_GRAPH_API}' must contain valid JSON with keys "
            f"{SECRET_KEY_TENANT_ID}, {SECRET_KEY_CLIENT_ID}, {SECRET_KEY_CLIENT_SECRET}."
        ) from e
    if not isinstance(payload, dict):
        raise RuntimeError(
            f"Secret '{SECRET_KEY_GRAPH_API}' JSON must be an object with keys "
            f"{SECRET_KEY_TENANT_ID}, {SECRET_KEY_CLIENT_ID}, {SECRET_KEY_CLIENT_SECRET}."
        )
    tenant_id = str(payload.get(SECRET_KEY_TENANT_ID) or "").strip()
    client_id = str(payload.get(SECRET_KEY_CLIENT_ID) or "").strip()
    client_secret = str(payload.get(SECRET_KEY_CLIENT_SECRET) or "").strip()
    return tenant_id, client_id, client_secret


def _parse_graph_query_params(
    base_filters: dict[str, Any] | str | None,
) -> dict[str, Any]:
    if base_filters is None:
        return {}
    if isinstance(base_filters, str):
        try:
            base_filters = json.loads(base_filters)
        except json.JSONDecodeError as e:
            LOGGER.error(
                "m=_parse_graph_query_params, msg=Invalid JSON for base_filters",
                exc_info=e,
            )
            raise
    if not isinstance(base_filters, dict):
        raise TypeError("base_filters must be a dict or JSON object string")
    return base_filters


def _validate_graph_endpoint(endpoint: str) -> str:
    endpoint = (endpoint or "").strip()
    if not endpoint:
        raise ValueError("Graph endpoint must be a non-empty relative path")

    parsed = urlparse(endpoint)
    if parsed.scheme or parsed.netloc:
        raise ValueError("Graph endpoint must be relative (no scheme/host)")
    if endpoint.startswith("//"):
        raise ValueError("Graph endpoint cannot start with '//'")

    return endpoint


def _validate_graph_request_url(url: str) -> str:
    parsed = urlparse(url)
    normalized_path = parsed.path.rstrip("/") + "/"
    if (
        parsed.scheme != GRAPH_ALLOWED_SCHEME
        or parsed.netloc != GRAPH_ALLOWED_HOST
        or not normalized_path.startswith(GRAPH_ALLOWED_PATH_PREFIX)
    ):
        raise ValueError(
            "Refusing to call non-Graph or non-v1.0 URL while loading Intune data"
        )
    return url


class IntuneJobArgumentParser:
    """Parses CLI args from LoadCustomTaskCreator (degreed-compatible shape)."""

    @staticmethod
    def create_parser() -> argparse.ArgumentParser:
        parser = argparse.ArgumentParser(
            description="Intune / Microsoft Graph raw load"
        )
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
            "extra_details",
            nargs="?",
            default="{}",
            help="Extra details as JSON (endpoint, base_filters, …)",
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


def get_azure_access_token(dbutils) -> str:
    tenant_id, client_id, client_secret = _load_intune_graph_credentials(dbutils)
    if not tenant_id or not client_id or not client_secret:
        raise RuntimeError(
            "Azure credentials missing. Set Databricks secret "
            f"'{SECRET_KEY_GRAPH_API}' in scope '{DATABRICKS_SECRET_SCOPE}' to a JSON object "
            f"with keys {SECRET_KEY_TENANT_ID}, {SECRET_KEY_CLIENT_ID}, {SECRET_KEY_CLIENT_SECRET}. "
            f"Alternatively set env var '{SECRET_KEY_GRAPH_API}' to that JSON string."
        )
    token_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    body = {
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
        "scope": GRAPH_SCOPE,
    }
    response = requests.post(token_url, data=body, timeout=60)
    response.raise_for_status()
    token = response.json().get("access_token")
    if not token:
        raise RuntimeError("Azure token response did not include access_token")
    return token


def fetch_all_graph_pages(
    endpoint: str,
    base_filters: dict[str, Any] | str | None,
    access_token: str,
    timeout_seconds: int = 120,
) -> list[dict[str, Any]]:
    headers = {"Authorization": f"Bearer {access_token}"}
    query_params = _parse_graph_query_params(base_filters)
    safe_endpoint = _validate_graph_endpoint(endpoint)
    url = _validate_graph_request_url(f"{GRAPH_API_BASE}/{safe_endpoint.lstrip('/')}")
    results: list[dict[str, Any]] = []
    page = 1

    while url:
        log_url = url.split("?", maxsplit=1)[0]
        LOGGER.info(f"m=fetch_all_graph_pages, page={page}, url={log_url}")
        response = requests.get(
            _validate_graph_request_url(url),
            headers=headers,
            params=query_params if page == 1 else None,
            timeout=timeout_seconds,
        )
        response.raise_for_status()
        data = response.json()
        batch = data.get("value", [])
        results.extend(batch)
        next_url = data.get("@odata.nextLink") or ""
        url = _validate_graph_request_url(next_url) if next_url else ""
        query_params = None
        page += 1

    return results


def main() -> None:
    try:
        job_args = IntuneJobArgumentParser.parse_args()
        safe_keys = (
            "environment",
            "dag_name",
            "table_name",
            "extraction_type",
            ENDPOINT_KEY,
        )
        safe_log = {k: job_args.get(k) for k in safe_keys if k in job_args}
        LOGGER.info(f"m=main, msg=Running Intune raw load, summary={safe_log}")

        if not job_args.get(ENDPOINT_KEY):
            raise ValueError(
                "Job requires 'endpoint' in extra_details (e.g. "
                "deviceManagement/managedDevices)."
            )

        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()

        token = get_azure_access_token(dbutils)
        base_filters = job_args.get("base_filters")
        api_data_list = fetch_all_graph_pages(
            job_args[ENDPOINT_KEY], base_filters, token
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
                "m=main, msg=No data returned from Graph API; skipping raw write"
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
    spark_metastore_service = SparkMetastoreService(spark_client)
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


if __name__ == "__main__":
    main()
