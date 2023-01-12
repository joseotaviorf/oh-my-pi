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

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration import (
    DAG_DECLARATION_FILE_SUFIX,
)
from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
    DAGDeclarationValidator,
)
from bietlejuice.services.file_service import FileService
from dags import DAG_PACKAGES_ROOT

parser = argparse.ArgumentParser()
parser.add_argument("--level", "-l", required=False, default="error")
args = parser.parse_args()
level = logging.getLevelName(args.level.upper())

logger = QuintoAndarLogger("ValidateDAGDeclarationFiles")
logger.setLevel(level)


def validate_one_file(
    validator: DAGDeclarationValidator, dag_declaration_file_path: str
):
    """
    Validates a single DAG declaration YAML file. Used for multiple concurrent validations which
    share the same DAGDeclarationValidator object.
    Args:
        validator (DAGDeclarationValidator): DAG Declaration validator object
        dag_declaration_file_path (str): Local dir where the DAG Delcaration file is placed
    """
    logger.debug(f"Validating file '{dag_declaration_file_path}'")
    dag_declaration = FileService.get_dict_from_yaml_file(dag_declaration_file_path)
    validator.validate(dag_declaration=dag_declaration)
    logger.debug(f"Successfully validated file '{dag_declaration_file_path}'")


validator = DAGDeclarationValidator()
func = partial(validate_one_file, validator)

dag_declaration_files = glob(
    pathname=f"{DAG_PACKAGES_ROOT}/**/*{DAG_DECLARATION_FILE_SUFIX}", recursive=True
)
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
                    dag_declaration_fails_msg += "\n- Path: {}\n- Validation errors:\n{}".format(
                        futures[future], future.exception().args[1]
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
