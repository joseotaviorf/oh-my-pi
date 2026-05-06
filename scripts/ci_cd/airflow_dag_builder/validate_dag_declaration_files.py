import argparse
import logging
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from glob import glob

from quintoandar_logger import QuintoAndarLogger

BI_ETL_EJUICE_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.append(BI_ETL_EJUICE_ROOT)

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
    DAGDeclarationValidator,
)
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.file_service import FileService

from scripts.ci_cd.domain_cli import domain_arg_type

logger = QuintoAndarLogger("ValidateDAGDeclarationFiles")


def dag_python_file_exists(dag_declaration_file_path):
    dag_path = dag_declaration_file_path.rsplit("/", 1)[0]
    dag_files = FileService.list_files(dag_path)
    for dag_file in dag_files:
        if dag_file.endswith(".py"):
            raise Exception(
                "Validation failed",
                f"Unallowed Python file '{dag_path}/{dag_file}' in the same folder of "
                "a DAG declaration file.\n",
            )


def validate_one_dag(dag_declaration_file_path: str):
    """
    Validates a single DAG, by validating its DAG declaration YAML file structure
    and the absence of the Python DAG file. Used for multiple concurrent validations
    which share the same DAGDeclarationValidator object.

    :param dag_declaration_file_path: Local dir where the DAG Delcaration file is placed
    :type dag_declaration_file_path: str
    """
    logger.debug(f"Validating file '{dag_declaration_file_path}'")
    dag_declaration = FileService.get_dict_from_yaml_file(dag_declaration_file_path)
    # instantiate a fresh validator per file to ensure thread-safety
    DAGDeclarationValidator().validate(dag_declaration=dag_declaration)
    dag_python_file_exists(dag_declaration_file_path)
    logger.debug(f"Successfully validated file '{dag_declaration_file_path}'")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--level", "-l", required=False, default="error")
    parser.add_argument(
        "--domain",
        type=domain_arg_type,
        help="Restrict validation to a specific domain folder under dags/ (e.g. for_rent, fintech)",
        required=False,
        default=None,
    )
    args = parser.parse_args()
    level = logging.getLevelName(args.level.upper())
    logger.setLevel(level)

    dag_declaration_glob_path = DAGPackagesPathService.generate_artifact_file_path(
        artifact_type="dag_declaration", dag_name="**"
    )
    dag_declaration_files = glob(pathname=dag_declaration_glob_path, recursive=True)

    if args.domain:
        dag_declaration_files = [
            f for f in dag_declaration_files if f"/{args.domain}/" in f
        ]

    dag_declaration_fails_msg = ""

    if dag_declaration_files:
        logger.info(
            f"Validating DAG declaration files (count={len(dag_declaration_files)})"
        )
        with ThreadPoolExecutor(max_workers=64) as executor:
            futures = {
                executor.submit(validate_one_dag, dag_declaration_file): dag_declaration_file
                for dag_declaration_file in dag_declaration_files
            }
            processed = 0
            for future in as_completed(futures):
                if future.exception():
                    exc = future.exception()
                    error_msg = exc.args[1] if len(exc.args) > 1 else str(exc)
                    dag_declaration_fails_msg += "\n- Path: {}\n- Validation errors:\n{}".format(
                        futures[future], error_msg
                    )
                processed += 1
                if processed % 50 == 0 or processed == len(dag_declaration_files):
                    logger.info(
                        f"Validated {processed}/{len(dag_declaration_files)} files"
                    )
        if dag_declaration_fails_msg:
            sys.tracebacklimit = 0
            raise AssertionError(
                "DAG declaration validation failed for the following files:\n"
                + dag_declaration_fails_msg
            )
    else:
        logger.warning("No DAG declaration files were found!")
