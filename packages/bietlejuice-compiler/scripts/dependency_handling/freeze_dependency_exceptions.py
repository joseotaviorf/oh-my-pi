from collections import defaultdict
import yaml
import os
import sys

BI_ETL_EJUICE_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.append(BI_ETL_EJUICE_ROOT)

from dags import DAG_PACKAGES_ROOT
from bietlejuice.base.dependencies.file_dependency_generator import (
    FileDependencyGenerator,
)
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    DAGS_CROSS_DEPENDENCIES_FILE_NAME,
    BietlejuiceDependencyHelper,
)

DAGS_CROSS_DEPENDENCIES_FILE_PATH = os.path.join(
    DAG_PACKAGES_ROOT, DAGS_CROSS_DEPENDENCIES_FILE_NAME
)
DEPENDENCY_EXCEPTIONS_FOLDER_PATH = os.path.join(
    DAG_PACKAGES_ROOT, "dependency_exceptions"
)
UNSTANDARD_DAGS_PATH = os.path.join(
    DEPENDENCY_EXCEPTIONS_FOLDER_PATH, "unstandard_dags.yaml"
)
MANUAL_MODIFICATIONS_PATH = os.path.join(
    DEPENDENCY_EXCEPTIONS_FOLDER_PATH, "manual_modifications.yaml"
)


def main():
    new_dependencies = generate_new_dependencies()
    old_dependencies = BietlejuiceDependencyHelper.read_dependencies()
    manual_modifications = generate_manual_modifications(
        new_dependencies, old_dependencies
    )
    write_to_yml(manual_modifications)


def generate_new_dependencies() -> dict:
    unstandard_dags = get_unstandard_dags_file_content(UNSTANDARD_DAGS_PATH)
    dependency_generator = FileDependencyGenerator(unstandard_dags)
    return dependency_generator.generate_dependencies(
        dependencies_manual_modifications={}
    )


def generate_manual_modifications(
    new_dependencies: dict, old_dependencies: dict
) -> dict:
    manual_modifications = defaultdict(dict)
    _include_removes(manual_modifications, new_dependencies, old_dependencies)
    _include_adds(manual_modifications, new_dependencies, old_dependencies)
    return dict(manual_modifications)


def _include_adds(
    manual_modifications: dict, new_dependencies: dict, old_dependencies: dict
):
    for dag_name, old_dependency_list in old_dependencies.items():
        dependencies_to_add = sorted(
            [
                dependency
                for dependency in old_dependency_list
                if dependency not in new_dependencies.get(dag_name, [])
            ]
        )
        if dependencies_to_add:
            manual_modifications[dag_name]["add"] = dependencies_to_add


def _include_removes(
    manual_modifications: dict, new_dependencies: dict, old_dependencies: dict
):
    for dag_name, new_dependency_list in new_dependencies.items():
        if dag_name not in old_dependencies:
            manual_modifications[dag_name]["override"] = []
            continue

        dependencies_to_remove = sorted(
            [
                dependency
                for dependency in new_dependency_list
                if dependency not in old_dependencies.get(dag_name)
            ]
        )
        if dependencies_to_remove:
            manual_modifications[dag_name]["remove"] = dependencies_to_remove


def get_unstandard_dags_file_content(unstandard_dags_file_path: str):
    return read_from_yml(
        unstandard_dags_file_path,
        "msg=Unstandard dags file not found, no changes will be applied to task names or static dags. error={}",
    )


def read_from_yml(file_name: str, error_message_template: str) -> dict:
    try:
        with open(file_name) as file_stream:
            return yaml.safe_load(file_stream)
    except FileNotFoundError as e:
        print(error_message_template.format(e))
        return {}


def write_to_yml(manual_modifications: dict):
    with open(MANUAL_MODIFICATIONS_PATH, mode="w+") as file_stream:
        yaml.dump(manual_modifications, file_stream, explicit_start=True)


if __name__ == "__main__":
    main()
