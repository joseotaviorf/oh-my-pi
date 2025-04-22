import re
from os.path import join
from typing import Tuple

from bietlejuice.services.file_service import FileService
from dags import DAG_PACKAGES_ROOT

DEPENDENCIES_PATTERN = "bietlejuice\.(\w*):(.*)"

DAGS_CROSS_DEPENDENCIES_FILE_NAME = "dependencies.yaml"
DAGS_CROSS_DEPENDENCIES_FILE_PATH = join(
    DAG_PACKAGES_ROOT, DAGS_CROSS_DEPENDENCIES_FILE_NAME
)


class BietlejuiceDependencyHelper:
    @staticmethod
    def read_dependencies() -> dict:
        """Reads the dependencies file from the DAGs"""

        return FileService.get_dict_from_yaml_file(DAGS_CROSS_DEPENDENCIES_FILE_PATH)

    @staticmethod
    def extract_dag_and_table_from_task_name(task_name: str) -> Tuple[str, str]:
        """
        Parses the DAG and table name from task name
        """
        if ("wonka" in task_name) or ("quintoml" in task_name):
            # Temporary workaround for bypassing this function
            # in case Wonka DAGs are used as dependencies
            dag_name, _ = task_name.split(":")
            return dag_name, None

        if ":load-into-redshift" in task_name:
            return BietlejuiceDependencyHelper._extract_dag_and_table_from_redshift_task(
                task_name
            )
        table_group_number = 4
        if ":create-external-table" in task_name:
            task_name_pattern = (
                "bietlejuice\.(.*):create-external-table-(enrich|raw|clean|dw)*-(.*)"
            )
            table_group_number = 3
        else:
            task_name_pattern = (
                "bietlejuice\.(.*):(load|done)-(enrich|raw|clean|dw|metric)*-(.*)"
            )

        match = re.search(task_name_pattern, task_name)
        if match is None:
            match_dag_name = re.search(DEPENDENCIES_PATTERN, task_name)
            dag_name = match_dag_name.group(1)
            return dag_name, None

        dag_name = match.group(1)

        match_layer = re.search("(dw|enrich|clean|raw|metric)", task_name)
        if match_layer is None:
            return dag_name, None

        layer = match.group(table_group_number - 1)
        if layer == "dw":
            table_name = BietlejuiceDependencyHelper._get_table_name_from_dw_task(
                dag_name, layer, match.group(table_group_number)
            )
        else:
            table_name = match.group(table_group_number).replace("-", "_")

        table_name = f"{layer}:{table_name}"
        return dag_name, table_name

    @staticmethod
    def _get_table_name_from_dw_task(dag_name: str, layer: str, task: str) -> str:
        """
        Clean the DW task in order to retrieve the table name being loaded
        """
        if "fact-" in task or "dim-" in task:
            match = re.search("(fact-|dim-)(.*)", task)
            return (match.group(1) + match.group(2)).replace("-", "_")

        dag_context = dag_name.replace(f"{layer}_", "")
        table_name = task.replace("-", "_").replace(f"{dag_context}_", "")
        return table_name

    @staticmethod
    def _extract_dag_and_table_from_redshift_task(task_name: str) -> Tuple[str, str]:
        """
        Parses the DAG and table name from load into redshift tasks
        """
        match = re.search("bietlejuice\.(.*):load-into-redshift-dw-(.*)", task_name)

        if not match:
            match_dag_name = re.search(DEPENDENCIES_PATTERN, task_name)
            dag_name = match_dag_name.group(1)
            return dag_name, None

        layer = "dw"
        dag_name = match.group(1)
        redshift_task = match.group(2)

        table_name = BietlejuiceDependencyHelper._get_table_name_from_dw_task(
            dag_name, layer, redshift_task
        )
        table_name = f"{layer}:{table_name}"

        return dag_name, table_name

    @staticmethod
    def subtract_dependencies(
        original_dependencies: dict, dependencies_to_subtract: dict
    ) -> dict:
        """Given two dependency dictionaries, returns a new dictionary consisting of the second one subtracted from the original one"""
        new_dependencies = {}
        for dag_name, dependency_list in original_dependencies.items():
            new_dependencies[dag_name] = sorted(
                list(
                    set(dependency_list)
                    - set(dependencies_to_subtract.get(dag_name, []))
                )
            )
            if len(new_dependencies[dag_name]) == 0:
                new_dependencies.pop(dag_name)
        return new_dependencies
