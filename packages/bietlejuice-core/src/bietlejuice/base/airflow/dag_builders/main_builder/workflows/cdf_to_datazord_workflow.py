"""Shared helpers for wiring Delta CDF → Kafka (Datazord) tasks in DAG workflows."""

from __future__ import annotations

from typing import List, Optional

from airflow.models.baseoperator import BaseOperator

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.datazord_config import (
    get_datazord_config,
)
from bietlejuice.base.airflow.enums.task_enum import TaskEnum
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.airflow.task_creators.task_creator_factory import (
    TaskCreatorFactory,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.services.configuration_service import ConfigurationService

__all__ = [
    "create_cdf_task_if_configured",
    "get_datazord_config",
    "initialize_cdf_task_creator",
    "wire_task_to_sink",
]


def initialize_cdf_task_creator(
    task_creator_factory: TaskCreatorFactory,
    config_service: ConfigurationService,
):
    return task_creator_factory.get_task_creator(
        TaskEnum.LOAD_CDF_TO_DATAZORD,
        config_service=config_service,
    )


def create_cdf_task_if_configured(
    load_cdf_task_creator,
    dag_args: dict,
    workflow_args: dict,
    layer: LayerEnum,
    cluster_table_names: Optional[List[str]] = None,
) -> Optional[BaseOperator]:
    """Create load-cdf-to-datazord when datazord_config targets a table in this cluster.

    v1: single-table CDF per DAG. When ``cluster_table_names`` is provided, the
    CDF task is created only if ``datazord_config.table`` is loaded in that cluster.
    """
    datazord_config = get_datazord_config(workflow_args)
    if not datazord_config:
        return None

    target_table = datazord_config["table"]
    if cluster_table_names is not None and target_table not in cluster_table_names:
        return None

    table_attributes = TableAttributes(dag_args, workflow_args, layer, target_table)
    return load_cdf_task_creator.create_task(
        table_attributes,
        key_columns=datazord_config.get("key_columns", []),
    )


def wire_task_to_sink(
    upstream_task: BaseOperator,
    cluster_completion_sink: BaseOperator,
) -> None:
    """Connect the last cluster work task to the job-cluster completion sink."""
    upstream_task >> cluster_completion_sink
