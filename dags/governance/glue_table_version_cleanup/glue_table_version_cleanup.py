"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta

import pendulum
from airflow import DAG
from airflow.models.param import Param
from airflow.operators.python import PythonOperator

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.glue.glue_table_version_cleanup import (
    GLUE_TABLE_VERSION_CLEANUP_DRY_RUN_ENV,
    GlueTableVersionCleanupService,
    create_glue_boto_client,
    parse_bool_flag,
    resolve_dry_run,
)

logger = logging.getLogger(__name__)

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
DEFAULT_REGION = "us-east-1"


def _conf_int(value, default: int | None = None) -> int | None:
    if value is None or value == "":
        return default
    return int(value)


def cleanup_glue_table_versions(**context):
    """Prune archived Glue TABLE_VERSION resources across the catalog."""
    dag_run = context.get("dag_run")
    run_conf = dag_run.conf if dag_run and dag_run.conf else {}
    params = context.get("params") or {}
    conf = {**params, **run_conf}

    dry_run = resolve_dry_run(
        conf_value=run_conf.get("dry_run"),
        conf_key_present="dry_run" in run_conf,
        param_value=params.get("dry_run"),
        param_key_present="dry_run" in params,
        default=False,
    )
    keep_count = _conf_int(conf.get("keep_count"), default=1) or 1
    database_prefix = conf.get("database_prefix") or None
    database_name = conf.get("database_name") or None
    table_name = conf.get("table_name") or None
    max_tables = _conf_int(conf.get("max_tables"))
    fail_on_error = parse_bool_flag(conf.get("fail_on_error"), default=True)
    region = conf.get("region") or DEFAULT_REGION

    logger.info(
        "Starting Glue table version cleanup: dry_run=%s keep_count=%s "
        "database_prefix=%s database_name=%s table_name=%s max_tables=%s "
        "region=%s",
        dry_run,
        keep_count,
        database_prefix,
        database_name,
        table_name,
        max_tables,
        region,
    )

    glue_client = create_glue_boto_client(region=region)
    service = GlueTableVersionCleanupService()
    summary = service.sweep(
        glue_client,
        keep_count=keep_count,
        database_prefix=database_prefix,
        database_name=database_name,
        table_name=table_name,
        dry_run=dry_run,
        max_tables=max_tables,
        fail_on_error=fail_on_error,
    )
    logger.info("Glue table version cleanup summary: %s", summary.as_dict())
    return summary.as_dict()


with DAG(
    dag_id="governance.glue_table_version_cleanup",
    default_args={
        "owner": DAGOwnerEnum.DATA_GOVERNANCE,
        "start_date": datetime(2026, 3, 1, 0, 0, 0, tzinfo=LOCAL_TZ),
    },
    description=(
        "Weekly sweep of the Glue Data Catalog that deletes archived TABLE_VERSION "
        "resources, keeping only the latest version per table. Trigger from the "
        "Airflow UI params form or dag_run.conf. It uses the Airflow worker's "
        "existing AWS credentials to call Glue directly. "
        f"Env {GLUE_TABLE_VERSION_CLEANUP_DRY_RUN_ENV} sets dry_run when not overridden."
    ),
    schedule="0 3 * * 0",
    catchup=False,
    tags=["governance", "glue", "maintenance"],
    params={
        "dry_run": Param(
            default=False,
            type="boolean",
            description=(
                "Count deletions without calling Glue delete APIs. "
                f"Precedence: dag_run.conf > {GLUE_TABLE_VERSION_CLEANUP_DRY_RUN_ENV} > "
                "this param."
            ),
        ),
        "keep_count": Param(
            default=1,
            type="integer",
            minimum=1,
            description="Number of latest TABLE_VERSION entries to retain per table.",
        ),
        "database_prefix": Param(
            default="",
            type="string",
            description="Optional Glue database name prefix filter.",
        ),
        "database_name": Param(
            default="",
            type="string",
            description="Optional single Glue database to sweep.",
        ),
        "table_name": Param(
            default="",
            type="string",
            description="Optional single table (requires database_name).",
        ),
        "max_tables": Param(
            default=None,
            type=["null", "integer"],
            minimum=1,
            description="Optional cap on tables processed (useful for staged rollouts).",
        ),
        "fail_on_error": Param(
            default=True,
            type="boolean",
            description="Fail the task when any table cleanup errors.",
        ),
        "region": Param(
            default=DEFAULT_REGION,
            type="string",
            description="AWS region for the Glue catalog.",
        ),
    },
) as dag:
    PythonOperator(
        task_id="cleanup_glue_table_versions",
        python_callable=cleanup_glue_table_versions,
        execution_timeout=timedelta(hours=6),
    )
