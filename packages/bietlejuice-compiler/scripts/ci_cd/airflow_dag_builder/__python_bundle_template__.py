"""Generated Astro Python DAG bundle. Do not edit.

Exec-passthrough for standalone (non-declaration) DAG modules such as
emr-migration twin/emr/compare DAGs. Each source file is exec'd in an
isolated namespace with a correct ``__file__`` so Path(__file__)-relative
lookups and worker re-imports keep working.

The literal tokens ``airflow`` and ``dag`` must remain in this module so
Airflow DagBag safe-mode still discovers it.
"""

import logging
import traceback
from datetime import datetime
from pathlib import Path
from types import ModuleType

from airflow.models.dag import DAG
from airflow.operators.python import PythonOperator

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

_LOG = logging.getLogger(__name__)

# dags/_astro_bundles/<group>/_*.py → parents[2] == dags/
_DAGS_ROOT = Path(__file__).resolve().parents[2]

_DAG_RELPATHS = __DAG_RELPATHS__  # noqa: F821 — replaced by codegen

QUARANTINE_TAG = "broken-dag"


def _raise_build_error(error_text):
    raise RuntimeError(error_text)


def _quarantine_dag(dag_id, error_text, domain):
    """Placeholder DAG so a failed build stays visible instead of vanishing from the UI."""
    dag = DAG(
        dag_id=dag_id,
        schedule=None,
        start_date=datetime(2023, 1, 1),
        catchup=False,
        is_paused_upon_creation=False,
        default_args={"owner": DAGOwnerEnum.DATA_PLATFORM},
        tags=[QUARANTINE_TAG, domain],
        doc_md=f"**This DAG failed to build.**\n\n```\n{error_text}\n```",
    )
    PythonOperator(
        task_id="broken-dag",
        dag=dag,
        python_callable=_raise_build_error,
        op_kwargs={"error_text": error_text},
    )
    return dag


def _load_dag_module(relpath: str) -> ModuleType:
    abs_path = _DAGS_ROOT / relpath
    source = abs_path.read_text()
    module_name = f"_astro_py_bundle_{abs_path.stem}"
    module = ModuleType(module_name)
    module.__file__ = str(abs_path)
    module.__name__ = module_name
    exec(compile(source, str(abs_path), "exec"), module.__dict__)  # noqa: S102
    return module


_dag_index = 0
for _relpath in _DAG_RELPATHS:
    try:
        _module = _load_dag_module(_relpath)
        for _attr_name, _attr_value in _module.__dict__.items():
            if isinstance(_attr_value, DAG):
                globals()[f"dag_{_dag_index:03d}"] = _attr_value
                _dag_index += 1
    except Exception as _exc:  # noqa: BLE001 — quarantine, never fail the batch
        _LOG.exception("Bundled Python DAG build failed: %s", _relpath)
        _quarantine_id = Path(_relpath).stem.removesuffix("_dag")
        _quarantine_domain = Path(_relpath).parts[0]
        globals()[f"dag_{_dag_index:03d}"] = _quarantine_dag(
            _quarantine_id,
            f"{_relpath}: {type(_exc).__name__}: {_exc}\n\n{traceback.format_exc()}",
            _quarantine_domain,
        )
        _dag_index += 1
