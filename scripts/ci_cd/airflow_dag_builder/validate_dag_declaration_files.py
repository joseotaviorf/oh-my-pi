import argparse
import logging
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial
from tqdm import tqdm
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

parser = argparse.ArgumentParser()
parser.add_argument("--level", "-l", required=False, default="error")
args = parser.parse_args()
level = logging.getLevelName(args.level.upper())

logger = QuintoAndarLogger("ValidateDAGDeclarationFiles")
logger.setLevel(level)


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


def validate_one_dag(
    validator: DAGDeclarationValidator, dag_declaration_file_path: str
):
    """
    Validates a single DAG, by validating its DAG declaration YAML file structure
    and the absence of the Python DAG file. Used for multiple concurrent validations
    which share the same DAGDeclarationValidator object.

    :param validator: DAG Declaration validator object
    :type validator: DAGDeclarationValidator
    :param dag_declaration_file_path: Local dir where the DAG Delcaration file is placed
    :type dag_declaration_file_path: str
    """
    logger.debug(f"Validating file '{dag_declaration_file_path}'")
    dag_declaration = FileService.get_dict_from_yaml_file(dag_declaration_file_path)
    validator.validate(dag_declaration=dag_declaration)
    dag_python_file_exists(dag_declaration_file_path)
    logger.debug(f"Successfully validated file '{dag_declaration_file_path}'")


validator = DAGDeclarationValidator()
func = partial(validate_one_dag, validator)

dag_declaration_glob_path = DAGPackagesPathService.generate_artifact_file_path(
    artifact_type="dag_declaration", dag_name="**"
)
dag_declaration_files = glob(pathname=dag_declaration_glob_path, recursive=True)

dag_declaration_fails_msg = ""

if dag_declaration_files:
    with tqdm(
        desc=f"Validating DAG declaration files", total=len(dag_declaration_files)
    ) as progress_bar:
        with ThreadPoolExecutor(max_workers=64) as executor:
            futures = {
                executor.submit(func, dag_declaration_file): dag_declaration_file
                for dag_declaration_file in dag_declaration_files
            }
            for future in as_completed(futures):
                if future.exception():
                    exc = future.exception()
                    error_msg = exc.args[1] if len(exc.args) > 1 else str(exc)
                    dag_declaration_fails_msg += "\n- Path: {}\n- Validation errors:\n{}".format(
                        futures[future], error_msg
                    )
                progress_bar.update(1)
    if dag_declaration_fails_msg:
        sys.tracebacklimit = 0
        raise AssertionError(
            "DAG declaration validation failed for the following files:\n"
            + dag_declaration_fails_msg
        )
else:
    logger.warning("No DAG declaration files were found!")
