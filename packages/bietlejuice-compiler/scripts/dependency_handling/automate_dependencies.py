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


class DependencyFileDumper(yaml.Dumper):
    """
    A custom dumper that indents lists. Many people have black configured to indent lists with 2 spaces, but the default
    yaml dumper does not indent lists. This is to change that, avoiding conflicts.
    """
    def increase_indent(self, flow=False, indentless=False):
        return super(DependencyFileDumper, self).increase_indent(flow, False)


def main():
    dependencies = generate_dependencies()
    write_to_yml(dependencies)


def generate_dependencies():
    unstandard_dags = get_unstandard_dags_file_content(UNSTANDARD_DAGS_PATH)
    dependency_generator = FileDependencyGenerator(unstandard_dags)
    manual_modifications = get_manual_modifications_file_content(MANUAL_MODIFICATIONS_PATH)

    dependencies = dependency_generator.generate_dependencies(manual_modifications)

    return dependencies


def write_to_yml(table_dependencies: dict):
    with open(DAGS_CROSS_DEPENDENCIES_FILE_PATH, mode="w+") as file_stream:
        yaml.dump(
            data=table_dependencies,
            stream=file_stream,
            Dumper=DependencyFileDumper,
            explicit_start=True,
            default_flow_style=False
        )

def get_unstandard_dags_file_content(unstandard_dags_file_path: str):
    return read_from_yml(
        unstandard_dags_file_path,
        "msg=Unstandard dags file not found, no changes will be applied to task names or static dags. error={}",
    )


def get_manual_modifications_file_content(exceptions_file_path: str):
    return read_from_yml(
        exceptions_file_path,
        "msg=Manual modifications file not found, no manual changes will be applied to the output. error={}",
    )


def read_from_yml(file_name: str, error_message_template: str) -> dict:
    try:
        with open(file_name) as file_stream:
            return yaml.safe_load(file_stream)
    except FileNotFoundError as e:
        print(error_message_template.format(e))
        return {}


if __name__ == "__main__":
    main()
