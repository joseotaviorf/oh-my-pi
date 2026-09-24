"""Generated Astro DAG bundle. Do not edit."""

import logging
import traceback
from datetime import datetime
from pathlib import Path

from airflow.datasets import Dataset  # noqa: F401 — referenced by generated specs
from airflow.models.dag import DAG
from airflow.operators.python import PythonOperator

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
    DAGYamlParser,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher import (
    FactoryDispatcher,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.validation.cluster_args import merge_validation_cluster_args

_LOG = logging.getLogger(__name__)

_IS_VALIDATION = __IS_VALIDATION__  # noqa: F821 — replaced by codegen
_DAG_SPECS = __DAG_SPECS__  # noqa: F821 — replaced by codegen

QUARANTINE_TAG = "broken-dag"
_DOMAIN = Path(__file__).resolve().parent.name


def _raise_build_error(error_text):
    raise RuntimeError(error_text)


def _quarantine_dag(dag_id, error_text):
    """Placeholder DAG so a failed build stays visible instead of vanishing from the UI."""
    dag = DAG(
        dag_id=dag_id,
        schedule=None,
        start_date=datetime(2023, 1, 1),
        catchup=False,
        is_paused_upon_creation=False,
        default_args={"owner": DAGOwnerEnum.DATA_PLATFORM},
        tags=[QUARANTINE_TAG, _DOMAIN],
        doc_md=f"**This DAG failed to build.**\n\n```\n{error_text}\n```",
    )
    PythonOperator(
        task_id="broken-dag",
        dag=dag,
        python_callable=_raise_build_error,
        op_kwargs={"error_text": error_text},
    )
    return dag


def _build_dag(dag_name, datasets, priority_tier):
    dag_declaration = DAGYamlParser(dag_name=dag_name).dag_declaration()
    factory_args = {
        "dag_args": dict(dag_declaration["dag"], priority_tier=priority_tier),
        "workflow_args": dag_declaration["workflow"],
        "cluster_args": dag_declaration["cluster"],
        "dataset_dependencies": datasets,
    }

    if _IS_VALIDATION:
        validation = dag_declaration.get("validation") or {}
        if not validation.get("cluster"):
            raise RuntimeError(
                f"Validation bundle includes {dag_name} but its declaration has no "
                "validation.cluster — regenerate with create-astro-dag-files"
            )
        factory_args["cluster_args"] = merge_validation_cluster_args(
            dag_declaration["cluster"], validation["cluster"]
        )
        factory_args["dataset_dependencies"] = None
        factory_args["is_validation"] = True
        factory_args["validation_config"] = validation

    factory = FactoryDispatcher(
        layer=LayerEnum(dag_declaration["workflow"]["layer"])
    ).get_factory(**factory_args)
    return factory.get_workflow().build_dag()


_suffix = BaseWorkflow.VALIDATION_DAG_SUFFIX if _IS_VALIDATION else ""
_prefix = "validation_dag" if _IS_VALIDATION else "dag"
for _index, (_dag_name, _datasets, _priority_tier) in enumerate(_DAG_SPECS):
    try:
        globals()[f"{_prefix}_{_index:03d}"] = _build_dag(
            _dag_name, _datasets, _priority_tier
        )
    except Exception as _exc:  # noqa: BLE001 — quarantine, never fail the batch
        _LOG.exception("Bundled DAG build failed: %s", _dag_name)
        globals()[f"{_prefix}_{_index:03d}"] = _quarantine_dag(
            f"bietlejuice.{_dag_name}{_suffix}",
            f"{_dag_name}: {type(_exc).__name__}: {_exc}\n\n{traceback.format_exc()}",
        )
