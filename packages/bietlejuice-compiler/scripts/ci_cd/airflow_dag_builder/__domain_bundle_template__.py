"""Generated Astro DAG bundle. Do not edit."""

import logging

from airflow.datasets import Dataset  # noqa: F401 — referenced by generated specs

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
    DAGYamlParser,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher import (
    FactoryDispatcher,
)
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.validation.cluster_args import merge_validation_cluster_args

_LOG = logging.getLogger(__name__)

_IS_VALIDATION = __IS_VALIDATION__  # noqa: F821 — replaced by codegen
_DAG_SPECS = __DAG_SPECS__  # noqa: F821 — replaced by codegen


def _build_dag(dag_name, datasets):
    dag_declaration = DAGYamlParser(dag_name=dag_name).dag_declaration()
    factory_args = {
        "dag_args": dag_declaration["dag"],
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


_errors = []
_prefix = "validation_dag" if _IS_VALIDATION else "dag"
for _index, (_dag_name, _datasets) in enumerate(_DAG_SPECS):
    try:
        globals()[f"{_prefix}_{_index:03d}"] = _build_dag(_dag_name, _datasets)
    except Exception as _exc:  # noqa: BLE001 — report every broken DAG in the batch
        _LOG.exception("Bundled DAG build failed: %s", _dag_name)
        _errors.append(f"{_dag_name}: {type(_exc).__name__}: {_exc}")

if _errors:
    raise ImportError(
        "Bundled DAG module failed to build "
        f"{len(_errors)} DAG(s): {'; '.join(_errors)}"
    )
