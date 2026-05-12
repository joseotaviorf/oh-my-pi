import os
from pathlib import Path

_PACKAGE_ROOT = Path(__file__).resolve().parent.parent  # bietlejuice/

BIETLEJUICE_PROJECT_ROOT = str(_PACKAGE_ROOT)
COMPOSER_FILES_ROOT = BIETLEJUICE_PROJECT_ROOT  # backward-compat alias
BIETLEJUICE_CONFIG_ROOT = str(_PACKAGE_ROOT / "config")

# TODO: create a constant inside db package and use here instead of the definition `../db`
DB_SQL_PATH = os.path.join(os.path.dirname(os.path.realpath(__file__)), "../db")

DATALAKE_METADATA_PATH = f"{DB_SQL_PATH}/datalake/metadata"
DATA_QUALITY_TESTS_PATH = f"{DB_SQL_PATH}/datalake/data_quality"
DATALAKE_SQL_DIR = f"{DB_SQL_PATH}/datalake"  # TODO: refactor to DATALAKE_SQL_PATH
QUERIES_DATALAKE_PATH = (
    DATALAKE_SQL_DIR + "/queries/"
)  # TODO: refactor to DATALAKE_QUERY_PATH
DDL_DATALAKE_PATH = DATALAKE_SQL_DIR + "/ddl/"  # TODO: refactor to DATALAKE_DDL_PATH

DW_QUERY_PATH = f"{DB_SQL_PATH}/dw/queries/"


def _find_dag_packages_root() -> "str | None":
    """Return the filesystem path to the deployed DAG packages tree.

    In Airflow/Composer the ``dags`` package is co-deployed at the root of
    the DAGs folder, so its ``__file__`` gives the correct absolute path.
    Returns None in Databricks and other environments where ``dags`` is not
    on sys.path, letting callers fall back to a Volume/S3 path.
    """
    try:
        import dags as _dags_pkg  # noqa: PLC0415
    except ImportError:
        return None
    from os.path import abspath, dirname

    return dirname(abspath(_dags_pkg.__file__))


DAG_PACKAGES_ROOT: "str | None" = _find_dag_packages_root()
