from __future__ import annotations

import argparse
import json
import os
import re
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

SECRET_KEY_IDN_CREDENTIALS = "IDN_API_CREDENTIALS"
SECRET_KEY_TENANT = "IDN_TENANT"
SECRET_KEY_CLIENT_ID = "IDN_CLIENT_ID"
SECRET_KEY_CLIENT_SECRET = "IDN_CLIENT_SECRET"

IDN_ALLOWED_SCHEME = "https"
IDN_TENANT_PATTERN = re.compile(r"^[a-zA-Z0-9\-]+$")
IDN_IDENTITY_ENDPOINTS = (
    ("beta/identities", "GET"),
    ("v3/public-identities", "GET"),
)


def _validate_idn_tenant(tenant: str) -> str:
    tenant = (tenant or "").strip()
    if not tenant:
        raise ValueError("IDN tenant must be a non-empty string")
    if not IDN_TENANT_PATTERN.match(tenant):
        raise ValueError(
            f"IDN tenant '{tenant}' must be alphanumeric with hyphens only "
            "(IdentityNow subdomain, e.g. 'yourcompany')"
        )
    return tenant


def _validate_idn_url(url: str, tenant: str) -> str:
    parsed = urlparse(url)
    expected_host = f"{tenant}.api.identitynow.com"
    if parsed.scheme != IDN_ALLOWED_SCHEME:
        raise ValueError(f"IDN URL must use HTTPS, got: {parsed.scheme}")
    if parsed.netloc != expected_host:
        raise ValueError(f"IDN URL host '{parsed.netloc}' must be '{expected_host}'")
    return url


def _get_secret(dbutils, key: str, env_key: str | None = None) -> str:
    try:
        if dbutils is not None:
            return dbutils.secrets.get(scope=DATABRICKS_SECRET_SCOPE, key=key).strip()
    except Exception:
        pass
    env_key = env_key or key
    return os.environ.get(env_key, "").strip()


def _load_idn_credentials(dbutils) -> tuple[str, str, str]:
    raw = _get_secret(dbutils, SECRET_KEY_IDN_CREDENTIALS)
    if not raw.strip():
        return "", "", ""
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        LOGGER.error(
            "m=_load_idn_credentials, msg=Invalid JSON for IDN_API_CREDENTIALS",
            exc_info=e,
        )
        raise RuntimeError(
            f"Secret '{SECRET_KEY_IDN_CREDENTIALS}' must contain valid JSON with keys "
            f"{SECRET_KEY_TENANT}, {SECRET_KEY_CLIENT_ID}, {SECRET_KEY_CLIENT_SECRET}."
        ) from e
    if not isinstance(payload, dict):
        raise RuntimeError(
            f"Secret '{SECRET_KEY_IDN_CREDENTIALS}' JSON must be an object."
        )
    tenant = str(payload.get(SECRET_KEY_TENANT) or "").strip()
    client_id = str(payload.get(SECRET_KEY_CLIENT_ID) or "").strip()
    client_secret = str(payload.get(SECRET_KEY_CLIENT_SECRET) or "").strip()
    return tenant, client_id, client_secret


def _normalize_attributes(raw_attributes: Any) -> dict[str, Any]:
    if isinstance(raw_attributes, dict):
        return raw_attributes
    if isinstance(raw_attributes, list):
        out: dict[str, Any] = {}
        for attr in raw_attributes:
            if isinstance(attr, dict):
                key = attr.get("key") or attr.get("name", "")
                if key:
                    out[str(key)] = attr.get("value")
        return out
    return {}


def _serialize_raw_attributes(raw_attributes: Any) -> str | None:
    if raw_attributes is None:
        return None
    try:
        return json.dumps(raw_attributes, ensure_ascii=False, default=str)
    except (TypeError, ValueError) as e:
        LOGGER.warning(
            "m=_serialize_raw_attributes, msg=Failed to serialize attributes, using str",
            exc_info=e,
        )
        return str(raw_attributes)


def extract_identity_row(identity: dict[str, Any]) -> dict[str, Any]:
    """Flatten SailPoint IdentityNow identity payloads (matches inventory idn_exporter)."""
    raw_attributes = identity.get("attributes")
    attributes = _normalize_attributes(raw_attributes)

    email = (
        identity.get("emailAddress")
        or attributes.get("sourceWorkEmail")
        or attributes.get("email")
        or attributes.get("workEmail")
    )

    lifecycle = identity.get("lifecycleState")
    if isinstance(lifecycle, dict):
        lifecycle_state = lifecycle.get("stateName") or lifecycle.get("state")
    else:
        lifecycle_state = (
            lifecycle
            or attributes.get("cloudLifecycleState")
            or attributes.get("lifecycleState")
        )

    manager_ref = identity.get("managerRef")
    if isinstance(manager_ref, dict):
        manager_name = manager_ref.get("name") or manager_ref.get("displayName")
    else:
        manager = identity.get("manager")
        if isinstance(manager, dict):
            manager_name = manager.get("name") or manager.get("displayName")
        else:
            manager_name = manager or attributes.get("manager")

    employee_number = (
        attributes.get("identificationNumber")
        or attributes.get("uid")
        or attributes.get("employeeNumber")
        or attributes.get("employeeId")
        or identity.get("alias")
    )

    return {
        "id_identity": identity.get("id"),
        "nm_identity": identity.get("name"),
        "nm_display": attributes.get("displayName") or identity.get("name"),
        "ds_work_email": email,
        "ds_lifecycle_state": lifecycle_state,
        "ds_identity_status": identity.get("identityStatus"),
        "ds_employee_number": employee_number,
        "ds_cost_center": attributes.get("costCenter") or attributes.get("cost_center"),
        "ds_last_login_sso": (
            attributes.get("lastLoginSsoDateType")
            or attributes.get("lastLoginSSODate")
            or attributes.get("lastLogin")
        ),
        "nm_manager": manager_name,
        "nm_department": attributes.get("departament") or attributes.get("department"),
        "ds_worker_type": attributes.get("type"),
        "nm_company": attributes.get("company"),
        "nm_job": attributes.get("jobName"),
        "ds_location": attributes.get("location"),
        "dt_start": attributes.get("startDate"),
        "dt_end": attributes.get("endDate"),
        "ts_created": identity.get("created"),
        "ts_modified": identity.get("modified"),
        "js_raw_attributes": _serialize_raw_attributes(raw_attributes),
    }


def get_access_token(tenant: str, client_id: str, client_secret: str) -> str:
    safe_tenant = _validate_idn_tenant(tenant)
    token_url = _validate_idn_url(
        f"https://{safe_tenant}.api.identitynow.com/oauth/token",
        safe_tenant,
    )
    body = {
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
    }
    response = requests.post(token_url, data=body, timeout=120)
    response.raise_for_status()
    token_data = response.json()
    access_token = token_data.get("access_token")
    if not access_token:
        raise RuntimeError("IdentityNow token response missing access_token")
    return str(access_token)


def get_all_identities(
    token: str,
    tenant: str,
    limit: int = 250,
    timeout_seconds: int = 120,
) -> list[dict[str, Any]]:
    safe_tenant = _validate_idn_tenant(tenant)
    base = f"https://{safe_tenant}.api.identitynow.com"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    working_path: str | None = None
    method: str | None = None

    for endpoint, http_method in IDN_IDENTITY_ENDPOINTS:
        test_url = f"{base}/{endpoint}"
        _validate_idn_url(test_url, safe_tenant)
        LOGGER.info(f"m=get_all_identities, msg=Trying endpoint={endpoint}")
        try:
            if http_method == "GET":
                response = requests.get(
                    test_url,
                    headers=headers,
                    params={"limit": 1},
                    timeout=timeout_seconds,
                )
            else:
                response = requests.post(
                    test_url,
                    headers=headers,
                    params={"limit": 1},
                    timeout=timeout_seconds,
                )
            if response.status_code == 200:
                working_path = endpoint
                method = http_method
                LOGGER.info(f"m=get_all_identities, msg=Using endpoint={endpoint}")
                break
            LOGGER.warning(
                f"m=get_all_identities, msg=Endpoint {endpoint} "
                f"returned {response.status_code}"
            )
        except requests.RequestException as e:
            LOGGER.warning(
                f"m=get_all_identities, msg=Endpoint {endpoint} failed",
                exc_info=e,
            )

    if not working_path or not method:
        raise RuntimeError(
            "No working IdentityNow identity endpoint; check API scopes."
        )

    all_identities: list[dict[str, Any]] = []
    offset = 0
    page = 1

    while True:
        url = f"{base}/{working_path}"
        params = {"limit": limit, "offset": offset}
        LOGGER.info(f"m=get_all_identities, msg=Fetching page={page}, offset={offset}")
        if method == "GET":
            response = requests.get(
                url, headers=headers, params=params, timeout=timeout_seconds
            )
        else:
            response = requests.post(
                url, headers=headers, params=params, timeout=timeout_seconds
            )
        response.raise_for_status()
        chunk = response.json()
        if isinstance(chunk, list):
            identities = chunk
        elif isinstance(chunk, dict):
            identities = (
                chunk.get("Results")
                or chunk.get("items")
                or chunk.get("data")
                or chunk.get("results")
                or chunk.get("resources")
                or []
            )
        else:
            identities = []

        if not identities:
            break

        all_identities.extend(identities)
        page += 1
        if len(identities) < limit:
            break
        offset += limit

    return all_identities


class IdnJobArgumentParser:
    @staticmethod
    def parse_args(args: list[str] | None = None) -> dict[str, Any]:
        parser = argparse.ArgumentParser(
            description="SailPoint IdentityNow (IDN) raw data loader"
        )
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
            help="Table privileges as JSON",
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

        api_page_limit = 250
        extra_raw = (parsed.extra_details or "").strip()
        if extra_raw and extra_raw != "{}":
            try:
                extra = json.loads(extra_raw)
                base_filters = extra.get("base_filters") or {}
                if isinstance(base_filters, str):
                    base_filters = json.loads(base_filters)
                if isinstance(base_filters, dict) and base_filters.get("limit"):
                    api_page_limit = int(str(base_filters["limit"]))
            except (json.JSONDecodeError, TypeError, ValueError) as e:
                LOGGER.warning(
                    "m=parse_args, msg=Could not parse extra_details for page limit, "
                    "using default 250",
                    exc_info=e,
                )

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
            "api_page_limit": api_page_limit,
        }


def main() -> None:
    try:
        job_args = IdnJobArgumentParser.parse_args()
        safe_log = {
            "environment": job_args.get("environment"),
            "dag_name": job_args.get("dag_name"),
            "table_name": job_args.get("table_name"),
            "extraction_type": job_args.get("extraction_type"),
        }
        LOGGER.info(f"m=main, msg=Running IDN raw load, summary={safe_log}")

        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()

        tenant, client_id, client_secret = _load_idn_credentials(dbutils)
        if not tenant or not client_id or not client_secret:
            raise RuntimeError(
                "IdentityNow credentials missing. Set Databricks secret "
                f"'{SECRET_KEY_IDN_CREDENTIALS}' in scope '{DATABRICKS_SECRET_SCOPE}' "
                f"to JSON with {SECRET_KEY_TENANT}, {SECRET_KEY_CLIENT_ID}, "
                f"{SECRET_KEY_CLIENT_SECRET}."
            )

        token = get_access_token(tenant, client_id, client_secret)
        page_limit = int(job_args.get("api_page_limit", 250))
        api_records = get_all_identities(token, tenant, limit=page_limit)
        rows = [extract_identity_row(rec) for rec in api_records]

        spark = SparkSession.builder.getOrCreate()
        spark_client = SparkClient()

        if rows:
            df = json_to_dataframe(spark, rows)
            df = insert_partitions(df)
            _load_to_raw(spark_client, job_args, df)
            LOGGER.info(
                f"m=main, msg=Loaded records into raw, count={len(rows)}, "
                f"table={job_args['table_name']}"
            )
        else:
            LOGGER.warning(
                "m=main, msg=No identities returned from IdentityNow; skipping raw write"
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
        f"table={job_args['table_name']}, mode={mode}"
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
