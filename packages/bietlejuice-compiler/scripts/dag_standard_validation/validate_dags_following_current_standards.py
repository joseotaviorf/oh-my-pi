import argparse
import os
import re
import sys
from collections import defaultdict
from glob import glob
from typing import Dict, List, Set

import yaml

BI_ETL_EJUICE_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.append(BI_ETL_EJUICE_ROOT)

from quintoandar_logger import QuintoAndarLogger

from dags import DAG_PACKAGES_ROOT
from scripts.ci_cd.domain_cli import domain_arg_type
from scripts.dag_standard_validation.dag_builder import (
    BaseDagBuilderStandardValidationRule,
    CDCValidationRule,
)

DAG_BUILDER_VALIDATION_RULES = [CDCValidationRule]

SKIP_LIST_PATH_REGEX = re.compile(r"(?:.*/)?dags/(?P<path>.*)")

logger = QuintoAndarLogger("ValidateDagStandardRules")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--domain",
        type=domain_arg_type,
        help="Restrict validation to a specific domain folder under dags/ (e.g. for_rent, fintech)",
        required=False,
        default=None,
    )
    args = parser.parse_args()
    domain = args.domain

    skip_list = read_skip_list()

    logger.info("Identifying DAGs not using the DAG Builder...")
    dags_not_using_builder = find_dags_not_using_builder(
        skip_list["dags_not_using_builder"], domain=domain
    )

    logger.info(
        "Identifying DAGs using the DAG Builder but not up to standard. Using the following validation rules:"
    )
    for rule in DAG_BUILDER_VALIDATION_RULES:
        logger.info(f"  - {rule.get_validation_name()}")
    invalid_dags = find_unstandard_dags_in_builder(skip_list, domain=domain)

    format_output(dags_not_using_builder, invalid_dags)

    if dags_not_using_builder or invalid_dags:
        exit(1)


def read_skip_list() -> Dict[str, List[str]]:
    """
    Read the skip list, which contains categories and their respective list of DAGs to ignore
    """
    parent_directory = os.path.dirname(os.path.abspath(__file__))
    skip_list_path = os.path.join(parent_directory, "skip_list.yml")

    with open(skip_list_path) as file:
        skip_list = yaml.safe_load(file)
    return skip_list


def remove_prefix(input_string):
    return re.match(SKIP_LIST_PATH_REGEX, input_string).groupdict()["path"]


def find_dags_not_using_builder(skip_list: list, domain: str = None) -> list:
    """
    The DAG Builder is our standard way of creating DAGs. We shouldn't be creating anything outside of it.
    Here is the documentation about it:
    https://docs.google.com/document/d/1zq5_S0M9FuExHKsujpow6HqZxkzgSubQlDLaSOiwXCQ/edit?tab=t.0
    """
    glob_pattern = (
        f"{DAG_PACKAGES_ROOT}/{domain}/**/*.py"
        if domain
        else f"{DAG_PACKAGES_ROOT}/*/**/*.py"
    )
    python_files = glob(glob_pattern, recursive=True)
    dag_python_files = [
        remove_prefix(file) for file in python_files if "/spark_jobs/" not in file
    ]
    return [file for file in dag_python_files if file not in skip_list]


def find_dag_declaration_file_paths(domain: str = None) -> List[str]:
    """
    Returns a list of all DAG declaration file paths, optionally scoped to a domain.
    """
    if domain:
        return glob(
            pathname=f"{DAG_PACKAGES_ROOT}/{domain}/**/*_declaration.yml",
            recursive=True,
        )
    return glob(pathname=f"{DAG_PACKAGES_ROOT}/**/*_declaration.yml", recursive=True)


def find_unstandard_dags_in_builder(
    skip_list: Dict[str, List[str]], domain: str = None
) -> Dict[str, Set[BaseDagBuilderStandardValidationRule]]:
    """
    Returns a dictionary with the DAG names and a set of reasons why they are not up to standard.
    """

    results = defaultdict(set)

    for dag_path in find_dag_declaration_file_paths(domain=domain):
        with open(dag_path) as file:
            dag_declaration = yaml.safe_load(file)
        dag_name = dag_declaration["dag"]["name"]

        for validation_rule in DAG_BUILDER_VALIDATION_RULES:
            if dag_name in skip_list.get(validation_rule.get_validation_name(), []):
                continue
            if not validation_rule.is_valid(dag_declaration):
                results[dag_name].add(validation_rule)

    return results


def format_output(
    dags_not_using_builder: list,
    invalid_dag_builder_dags: Dict[str, Set[BaseDagBuilderStandardValidationRule]],
) -> None:
    """
    Format the output of the validation.
    """
    logger.info(
        "\n\n===============================\nValidation Results\n===============================\n"
    )

    if dags_not_using_builder:
        logger.info("DAGs not using the DAG Builder:")
        for dag in dags_not_using_builder:
            logger.info(f"  - {dag}")
        logger.info(
            "If this should be an exception, add it to the skip_list.yml file under 'dags_not_using_builder'.\n"
        )

    if invalid_dag_builder_dags:
        logger.info("DAGs using the DAG Builder but not up to standard:")
        for dag_name, reasons in invalid_dag_builder_dags.items():
            logger.info(f"  - {dag_name}:")
            for reason in reasons:
                logger.info(
                    f"    - {reason.get_validation_description()}. If this should be an exception, add it to the skip_list.yml file under {reason.get_validation_name()}."
                )

    if not dags_not_using_builder and not invalid_dag_builder_dags:
        logger.info("All DAGs are using the DAG Builder and are up to standard.")


if __name__ == "__main__":
    main()
