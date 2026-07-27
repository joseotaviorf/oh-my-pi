"""Generated Astro Python DAG bundle. Do not edit.

Exec-passthrough for standalone (non-declaration) DAG modules such as
emr-migration twin/emr/compare DAGs. Each source file is exec'd in an
isolated namespace with a correct ``__file__`` so Path(__file__)-relative
lookups and worker re-imports keep working.

The literal tokens ``airflow`` and ``dag`` must remain in this module so
Airflow DagBag safe-mode still discovers it.
"""

import logging
from pathlib import Path
from types import ModuleType

from airflow.models.dag import DAG  # noqa: F401 — DagBag safe-mode + isinstance

_LOG = logging.getLogger(__name__)

# dags/_astro_bundles/<group>/_*.py → parents[2] == dags/
_DAGS_ROOT = Path(__file__).resolve().parents[2]

_DAG_RELPATHS = __DAG_RELPATHS__  # noqa: F821 — replaced by codegen


def _load_dag_module(relpath: str) -> ModuleType:
    abs_path = _DAGS_ROOT / relpath
    source = abs_path.read_text()
    module_name = f"_astro_py_bundle_{abs_path.stem}"
    module = ModuleType(module_name)
    module.__file__ = str(abs_path)
    module.__name__ = module_name
    exec(compile(source, str(abs_path), "exec"), module.__dict__)  # noqa: S102
    return module


_errors = []
_dag_index = 0
for _relpath in _DAG_RELPATHS:
    try:
        _module = _load_dag_module(_relpath)
        for _attr_name, _attr_value in _module.__dict__.items():
            if isinstance(_attr_value, DAG):
                globals()[f"dag_{_dag_index:03d}"] = _attr_value
                _dag_index += 1
    except Exception as _exc:  # noqa: BLE001 — report every broken DAG in the batch
        _LOG.exception("Bundled Python DAG build failed: %s", _relpath)
        _errors.append(f"{_relpath}: {type(_exc).__name__}: {_exc}")

if _errors:
    raise ImportError(
        "Bundled Python DAG module failed to build "
        f"{len(_errors)} DAG(s): {'; '.join(_errors)}"
    )
