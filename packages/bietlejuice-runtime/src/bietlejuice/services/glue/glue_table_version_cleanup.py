"""Sweep the Glue Data Catalog and prune archived TABLE_VERSION resources."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Any, List, Optional, Sequence, Tuple, Union

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.clients.db_clients.glue_client import GlueClient

logger = QuintoAndarLogger("GlueTableVersionCleanup")

DEFAULT_REGION = "us-east-1"
GLUE_ASSUME_ROLE_ARN_ENV = "GLUE_ASSUME_ROLE_ARN"
AIRFLOW_GLUE_WORKER_ROLE_ENV = "AIRFLOW_GLUE_WORKER_ROLE_ARN"
# Airflow Variable: lake worker role (Astro pod → data-account worker).
AIRFLOW_GLUE_WORKER_ROLE_VARIABLE = "airflow_glue_worker_role"
GLUE_TABLE_VERSION_CLEANUP_DRY_RUN_ENV = "GLUE_TABLE_VERSION_CLEANUP_DRY_RUN"
ASSUME_ROLE_SESSION_NAME = "airflow-glue-table-version-cleanup"


def parse_bool_flag(value: Any, *, default: bool = False) -> bool:
    """Parse a boolean feature flag from conf, env, or CLI strings."""
    if value is None or value == "":
        return default
    if isinstance(value, bool):
        return value
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False
    return default


def resolve_dry_run(
    *,
    conf_value: Any = None,
    conf_key_present: bool = False,
    param_value: Any = None,
    param_key_present: bool = False,
    default: bool = False,
) -> bool:
    """Resolve dry-run mode: ``dag_run.conf`` > env > DAG params > default."""
    if conf_key_present:
        return parse_bool_flag(conf_value, default=default)
    env_value = os.environ.get(GLUE_TABLE_VERSION_CLEANUP_DRY_RUN_ENV)
    if env_value is not None and env_value != "":
        return parse_bool_flag(env_value, default=default)
    if param_key_present:
        return parse_bool_flag(param_value, default=default)
    return default


def _assume_role_session(
    role_arn: str,
    *,
    region: str = DEFAULT_REGION,
    session: Optional[boto3.Session] = None,
    session_name: str = ASSUME_ROLE_SESSION_NAME,
) -> boto3.Session:
    sts = (session or boto3.Session(region_name=region)).client("sts")
    response = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName=session_name,
        DurationSeconds=3600,
    )
    creds = response["Credentials"]
    return boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
        region_name=region,
    )


def create_glue_boto_client(
    *,
    role_arn: Optional[str] = None,
    worker_role_arn: Optional[str] = None,
    region: str = DEFAULT_REGION,
) -> Any:
    """Build a boto3 Glue client for the Airflow-worker cleanup DAG.

    On Astronomer, the pod identity assumes ``worker_role_arn`` (e.g.
    ``airflow-prod-role``) and calls Glue in the same account. An optional
    second ``role_arn`` hop is supported only when passed explicitly (CLI /
    notebook overrides), not via ``GLUE_ASSUME_ROLE_ARN`` env.
    """
    session = boto3.Session(region_name=region)

    if worker_role_arn:
        logger.info(
            f"m=create_glue_boto_client, worker_role_arn={worker_role_arn}, "
            "msg=assuming Airflow worker role before Glue API calls"
        )
        session = _assume_role_session(worker_role_arn, region=region, session=session)

    if role_arn and role_arn != worker_role_arn:
        logger.info(
            f"m=create_glue_boto_client, role_arn={role_arn}, "
            "msg=assuming explicit Glue role for table version cleanup"
        )
        session = _assume_role_session(role_arn, region=region, session=session)

    return session.client("glue")


def create_glue_client(
    *,
    role_arn: Optional[str] = None,
    worker_role_arn: Optional[str] = None,
    region: str = DEFAULT_REGION,
) -> Union[GlueClient, Any]:
    """Return a Glue client for catalog sweeps.

    Airflow DAG path: set ``worker_role_arn`` only; Glue runs in the worker
    account after the Astro → worker assume. CLI/notebook path: omit
    ``worker_role_arn`` and pass ``role_arn`` or rely on
    ``GLUE_ASSUME_ROLE_ARN`` for a single-hop ``GlueClient``.
    """
    if worker_role_arn:
        return create_glue_boto_client(
            role_arn=role_arn,
            worker_role_arn=worker_role_arn,
            region=region,
        )

    resolved_role_arn = role_arn or os.environ.get(GLUE_ASSUME_ROLE_ARN_ENV)
    if resolved_role_arn:
        logger.info(
            f"m=create_glue_client, role_arn={resolved_role_arn}, "
            "msg=using STS assume-role for Glue table version cleanup"
        )
    return GlueClient(role_arn=resolved_role_arn, region=region)


@dataclass
class GlueTableVersionCleanupSummary:
    databases_scanned: int = 0
    tables_scanned: int = 0
    tables_with_prunable_versions: int = 0
    versions_deleted: int = 0
    versions_would_delete: int = 0
    failures: List[Tuple[str, str]] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "databases_scanned": self.databases_scanned,
            "tables_scanned": self.tables_scanned,
            "tables_with_prunable_versions": self.tables_with_prunable_versions,
            "versions_deleted": self.versions_deleted,
            "versions_would_delete": self.versions_would_delete,
            "failure_count": len(self.failures),
            "failures": [
                {"table": table_fqn, "error": error}
                for table_fqn, error in self.failures
            ],
        }


def version_ids_to_prune(version_ids: Sequence[str], keep_count: int) -> List[str]:
    """Return version IDs to delete, keeping the newest ``keep_count`` versions."""
    if keep_count < 1:
        raise ValueError("keep_count must be at least 1")
    if len(version_ids) <= keep_count:
        return []
    sorted_ids = sorted(version_ids, key=lambda version_id: int(version_id))
    return list(sorted_ids[:-keep_count])


def _resolve_glue_client(
    glue: Union[GlueClient, Any],
) -> Union[GlueClient, Any]:
    """Accept a ``GlueClient`` or a raw boto3 Glue client."""
    if isinstance(glue, GlueClient):
        return glue
    if hasattr(glue, "get_paginator") and hasattr(glue, "batch_delete_table_version"):
        return glue
    raise TypeError(
        "glue must be a GlueClient or a boto3 Glue client with paginator support"
    )


def _list_table_version_ids_boto(
    glue: Any, database_name: str, table_name: str
) -> List[str]:
    version_ids: List[str] = []
    paginator = glue.get_paginator("get_table_versions")
    for page in paginator.paginate(DatabaseName=database_name, TableName=table_name):
        for version in page.get("TableVersions", []):
            version_ids.append(version["VersionId"])
    return sorted(version_ids, key=lambda version_id: int(version_id))


def _batch_delete_table_versions_boto(
    glue: Any,
    database_name: str,
    table_name: str,
    version_ids: List[str],
) -> int:
    if not version_ids:
        return 0

    batch_size = 100
    deleted_count = 0
    failures: List[dict] = []
    for i in range(0, len(version_ids), batch_size):
        batch = version_ids[i : i + batch_size]
        response = glue.batch_delete_table_version(
            DatabaseName=database_name,
            TableName=table_name,
            VersionIds=batch,
        )
        errors = response.get("Errors", [])
        for err in errors:
            error_detail = err.get("ErrorDetail", {})
            logger.error(
                f"m=batch_delete_table_versions, "
                f"table={database_name}.{table_name}, "
                f"version_id={err.get('VersionId')}, "
                f"error_code={error_detail.get('ErrorCode')}, "
                f"error_message={error_detail.get('ErrorMessage')}, "
                "msg=table version deletion failed in Glue"
            )
        failures.extend(errors)
        deleted_count += len(batch) - len(errors)

    if failures:
        raise RuntimeError(
            f"Glue batch_delete_table_version failed for "
            f"{len(failures)} version(s) in "
            f"{database_name}.{table_name} "
            f"({deleted_count} deleted)"
        )

    return deleted_count


def _list_database_names(
    glue: Union[GlueClient, Any],
    database_name: Optional[str],
    database_prefix: Optional[str],
) -> List[str]:
    if database_name:
        return [database_name]

    if isinstance(glue, GlueClient):
        names = glue.get_database_names()
    else:
        names = []
        paginator = glue.get_paginator("get_databases")
        for page in paginator.paginate():
            for database in page.get("DatabaseList", []):
                names.append(database["Name"])

    if database_prefix:
        names = [name for name in names if name.startswith(database_prefix)]
    return sorted(names)


def _list_table_names(
    glue: Union[GlueClient, Any],
    database_name: str,
    table_name: Optional[str],
) -> List[str]:
    if table_name:
        return [table_name]

    if isinstance(glue, GlueClient):
        return glue.get_table_names(database_name)

    names: List[str] = []
    paginator = glue.get_paginator("get_tables")
    for page in paginator.paginate(DatabaseName=database_name):
        for table in page.get("TableList", []):
            names.append(table["Name"])
    return names


def sweep_glue_table_versions(
    glue: Union[GlueClient, Any],
    *,
    keep_count: int = 1,
    database_prefix: Optional[str] = None,
    database_name: Optional[str] = None,
    table_name: Optional[str] = None,
    dry_run: bool = False,
    max_tables: Optional[int] = None,
) -> GlueTableVersionCleanupSummary:
    """Sweep Glue tables and delete archived versions, keeping the newest ones.

    Accepts a ``GlueClient`` or a raw boto3 ``glue`` client (notebook-friendly).
    """
    glue = _resolve_glue_client(glue)
    summary = GlueTableVersionCleanupSummary()
    databases = _list_database_names(glue, database_name, database_prefix)
    summary.databases_scanned = len(databases)

    for db_name in databases:
        for tbl_name in _list_table_names(glue, db_name, table_name):
            if max_tables is not None and summary.tables_scanned >= max_tables:
                logger.info(
                    f"m=sweep_glue_table_versions, max_tables={max_tables}, "
                    "msg=reached table limit, stopping sweep"
                )
                return summary

            summary.tables_scanned += 1
            table_fqn = f"{db_name}.{tbl_name}"
            try:
                if isinstance(glue, GlueClient):
                    version_ids = glue.list_table_version_ids(db_name, tbl_name)
                else:
                    version_ids = _list_table_version_ids_boto(glue, db_name, tbl_name)

                to_delete = version_ids_to_prune(version_ids, keep_count)
                if not to_delete:
                    continue

                summary.tables_with_prunable_versions += 1
                if dry_run:
                    summary.versions_would_delete += len(to_delete)
                    logger.info(
                        f"m=sweep_glue_table_versions, table={table_fqn}, "
                        f"versions_to_delete={len(to_delete)}, dry_run=True, "
                        "msg=would delete archived Glue table versions"
                    )
                    continue

                if isinstance(glue, GlueClient):
                    deleted = glue.batch_delete_table_versions(
                        db_name, tbl_name, to_delete
                    )
                else:
                    deleted = _batch_delete_table_versions_boto(
                        glue, db_name, tbl_name, to_delete
                    )
                summary.versions_deleted += deleted
                logger.info(
                    f"m=sweep_glue_table_versions, table={table_fqn}, "
                    f"versions_deleted={deleted}, msg=pruned archived Glue table versions"
                )
            except Exception as exc:
                logger.error(
                    f"m=sweep_glue_table_versions, table={table_fqn}, "
                    f"error={exc}, msg=failed to prune Glue table versions"
                )
                summary.failures.append((table_fqn, str(exc)))

    logger.info(
        "m=sweep_glue_table_versions, "
        f"databases_scanned={summary.databases_scanned}, "
        f"tables_scanned={summary.tables_scanned}, "
        f"tables_with_prunable_versions={summary.tables_with_prunable_versions}, "
        f"versions_deleted={summary.versions_deleted}, "
        f"versions_would_delete={summary.versions_would_delete}, "
        f"failure_count={len(summary.failures)}, "
        "msg=Glue table version sweep completed"
    )
    return summary


class GlueTableVersionCleanupService:
    """Service wrapper around :func:`sweep_glue_table_versions`."""

    def sweep(
        self,
        glue_client: Union[GlueClient, Any],
        *,
        keep_count: int = 1,
        database_prefix: Optional[str] = None,
        database_name: Optional[str] = None,
        table_name: Optional[str] = None,
        dry_run: bool = False,
        max_tables: Optional[int] = None,
        fail_on_error: bool = True,
    ) -> GlueTableVersionCleanupSummary:
        summary = sweep_glue_table_versions(
            glue_client,
            keep_count=keep_count,
            database_prefix=database_prefix,
            database_name=database_name,
            table_name=table_name,
            dry_run=dry_run,
            max_tables=max_tables,
        )
        if fail_on_error and summary.failures:
            failed_tables = ", ".join(name for name, _ in summary.failures)
            raise RuntimeError(
                f"Glue table version cleanup failed for {len(summary.failures)} "
                f"table(s): {failed_tables}"
            )
        return summary
