from __future__ import annotations

from typing import List, Optional

import boto3
from airflow.models import Variable
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
    DAGYamlParser,
)
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.services.reverse_bpo_export_summary import (
    build_summary_marker_prefix,
    format_dag_summary_message,
    order_saved_files_by_declaration,
)

LOGGER = QuintoAndarLogger("reverse_bpo_summary_callback")


def _extract_dag_name(dag_id: str) -> str:
    prefix = "bietlejuice."
    if dag_id.startswith(prefix):
        return dag_id[len(prefix) :]
    return dag_id


def _get_declaration_tables(dag_name: str) -> List[str]:
    declaration = DAGYamlParser(dag_name).dag_declaration()
    tables_customization = declaration.get("workflow", {}).get(
        "tables_customization", {}
    )
    return sorted(tables_customization.keys())


def _list_saved_files_from_markers(
    bucket: str, dag_name: str, dag_run_id: str
) -> List[str]:
    prefix = build_summary_marker_prefix(dag_name, dag_run_id)
    s3_client = boto3.client("s3")
    paginator = s3_client.get_paginator("list_objects_v2")

    saved_files: List[str] = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            key = item["Key"]
            file_name = key.rsplit("/", 1)[-1]
            if file_name.endswith(".marker"):
                saved_files.append(file_name[: -len(".marker")])

    return saved_files


def _delete_summary_markers(bucket: str, dag_name: str, dag_run_id: str) -> None:
    prefix = build_summary_marker_prefix(dag_name, dag_run_id)
    s3_client = boto3.client("s3")
    paginator = s3_client.get_paginator("list_objects_v2")

    keys_to_delete = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        keys_to_delete.extend({"Key": item["Key"]} for item in page.get("Contents", []))

    if not keys_to_delete:
        return

    for index in range(0, len(keys_to_delete), 1000):
        s3_client.delete_objects(
            Bucket=bucket,
            Delete={"Objects": keys_to_delete[index : index + 1000]},
        )


def _resolve_webhook_url() -> Optional[str]:
    try:
        config_service = ConfigurationService()
        webhook_keys = config_service.get_config("notification_webhooks_keys")
        webhook_variable_key = webhook_keys.get("bpo_reverse_alerts")
        if not webhook_variable_key:
            return None
        return Variable.get(webhook_variable_key, default_var=None)
    except Exception as exc:
        LOGGER.warning(
            f"m=_resolve_webhook_url, msg=Could not resolve GChat webhook, error={exc}"
        )
        return None


def reverse_bpo_export_summary_alert(context) -> None:
    """
    Send a compiled Google Chat summary when a reverse BPO export DAG succeeds.

    Reads per-file markers written during export tasks and lists the saved files
    in declaration order. Never raises.
    """
    try:
        dag = context["dag"]
        dag_run = context["dag_run"]
        dag_name = _extract_dag_name(dag.dag_id)
        dag_run_id = dag_run.run_id

        declaration = DAGYamlParser(dag_name).dag_declaration()
        workflow_args = declaration.get("workflow", {})
        if not workflow_args.get("gchat_export_summary"):
            return

        bucket_config_name = workflow_args.get(
            "bucket_config_name", "planning_and_performance_bucket"
        )
        config_service = ConfigurationService(dag_name)
        bucket = config_service.get_config(bucket_config_name)

        saved_files = _list_saved_files_from_markers(bucket, dag_name, dag_run_id)
        declaration_tables = _get_declaration_tables(dag_name)
        ordered_files = order_saved_files_by_declaration(
            saved_files, declaration_tables
        )
        message_content = format_dag_summary_message(dag_name, ordered_files)

        webhook_url = _resolve_webhook_url()
        if not webhook_url:
            LOGGER.warning(
                f"m=reverse_bpo_export_summary_alert, dag_name={dag_name}, "
                "msg=Skipping summary notification because webhook is unavailable"
            )
            return

        sent = GChatService.send_message(
            Message(content=message_content, destination=webhook_url)
        )
        if sent:
            _delete_summary_markers(bucket, dag_name, dag_run_id)
            LOGGER.info(
                f"m=reverse_bpo_export_summary_alert, dag_name={dag_name}, "
                f"saved_files_count={len(ordered_files)}, msg=Summary notification sent"
            )
        else:
            LOGGER.warning(
                f"m=reverse_bpo_export_summary_alert, dag_name={dag_name}, "
                "msg=Summary notification was not delivered"
            )
    except Exception as exc:
        LOGGER.warning(
            f"m=reverse_bpo_export_summary_alert, msg=Failed to send summary notification, "
            f"error={exc}"
        )
