"""Shared datazord_config resolution helpers (no Airflow task imports)."""

from __future__ import annotations

from typing import Optional

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)

SCHEMA_VALIDATION_CASSANDRA = "cassandra"
SCHEMA_VALIDATION_NONE = "none"


def get_datazord_config(workflow_args: dict) -> Optional[dict]:
    """Return workflow datazord_config when present and non-empty."""
    config = workflow_args.get("datazord_config")
    if not config:
        return None
    return config


def resolve_kafka_topic(datazord_config: dict, environment: str) -> str:
    """Explicit kafka_topic wins; otherwise ``{env}_{namespace}.{entity}``.

    Wonka DAGs omit both and keep the legacy ``wonka`` namespace default.
    """
    kafka_topic = datazord_config.get("kafka_topic")
    if kafka_topic:
        return kafka_topic
    namespace = datazord_config.get("topic_namespace", "wonka")
    return f"{environment}_{namespace}.{datazord_config['entity']}"


def resolve_schema_validation(datazord_config: dict) -> str:
    return datazord_config.get("schema_validation", SCHEMA_VALIDATION_CASSANDRA)


def resolve_include_delete_events(datazord_config: dict) -> bool:
    return bool(datazord_config.get("include_delete_events", False))


def resolve_checkpoint_location(
    base_checkpoint_location: str,
    table: str,
    workflow_type: Optional[str] = None,
    dag_name: Optional[str] = None,
) -> str:
    """Resolve CDF streaming checkpoint path.

    Wonka and other legacy callers keep ``{base}/{table}`` so existing offsets
    are preserved. ``query_delta_datazord`` namespaces by DAG to avoid
    collisions when multiple DAGs export the same table name.
    """
    if workflow_type == WorkflowEnum.QUERY_DELTA_DATAZORD_WORKFLOW.value and dag_name:
        return f"{base_checkpoint_location}/{dag_name}/{table}"
    return f"{base_checkpoint_location}/{table}"
